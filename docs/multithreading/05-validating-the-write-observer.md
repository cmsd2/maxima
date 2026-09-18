# Multi-threading in Maxima: validating the environment write observer

Doc 04 recommends an accessor layer with a write hook as a no-regret first
step. The OpenSpec change `add-environment-accessor-layer` plans it. This
document covers what we want from building it, and how to tell a working
facility from a broken one. Silent breakage is the main concern.

## The outcome sought

The facility is useful only as a trustworthy measurement. For a candidate
workload (the `wc_systematic` loop body first), it should produce a profile
of the environment writes made inside the region we would parallelise:

| Dimension | Values |
|---|---|
| Operation | put, remove, replace-plist, assign, unbind (restoring a binding at exit) |
| Object | user symbol, Maxima-created gensym, fact-database node, context |
| Indicator | `disrep`, `+labs`, `mexpr`, `internal`, … |
| Count | per iteration |

The profile feeds one decision. **The criteria below must be recorded before
any measurement is taken**, so that the result can't be read to suit a
preferred answer.

| Profile inside the region | Conclusion |
|---|---|
| Every write falls in a class doc 03 has a contained fix for: sign scratch, CRE gensyms, `block` bind/restore, caches | A frozen-environment thread mode is plausible for this workload |
| Writes to user-symbol definitions or facts, or context switches, on common paths | Threads are ruled out for this workload; use processes |
| Writes in many unrelated classes | Threads are ruled out, and the mailing-list question is settled with data |

A clear negative result counts as success. The facility has failed only if
its answer can't be trusted.

## Failure modes

### Loud failures

Loud failures are a failed build, a test-suite regression, a crash, a hook
that recurses forever, or a large slowdown. The planned baseline
comparisons catch them: the suite log, the stale-image and build-log checks
from AGENTS.md sec. 4, and alternating timing runs. They cost time, not
correctness.

### Silent failure 1: behaviour changes but tests pass

A converted site behaves differently on a path no test covers, through a
different return value or a different order of events.

- **Detection: differential testing.** A green suite is not enough. Run a
  large corpus through the baseline and changed builds and compare printed
  results exactly: every share test, every demo, and randomly generated
  expressions. Repeat with a passive hook installed against no hook.

### Silent failure 2: under-reporting

The facility reports no write where one happened. This is the worst
failure, because the facility's purpose is to certify that a workload does
not write. A missed write becomes a race that ships.

The planned design has these known blind spots:

| Blind spot | Example | Why the hook misses it |
|---|---|---|
| Mutation of values stored in properties | `fdel` does `rplacd` on the list held in `data` | The hook sees slot writes, not changes to the structure a slot holds |
| Writes the scanner's patterns miss | `(funcall #'(setf get) …)`, `nconc` onto a plist obtained by `symbol-plist`, macro-generated writes | They don't match the textual forms the scanner looks for |
| Destructive edits of info lists | `add2lnc` `nconc`ing onto `$values` (the mailing list's 9544/10000 case) | Not a property write |
| `setq` of specials | `bcons` header cache, `*last-meval1-form*` | Not a property write, and not `mset` |
| Hash tables and arrays | memo tables, `*bigprimes*`, `*lambda-expr-funs*` | Not a property write |
| `share/` | any add-on package | Out of scope |

These gaps need an **independent oracle** that checks the facility's answers
without relying on its reports:

- **Snapshot diffing.** Before and after each test problem, take a deep
  structural fingerprint of every symbol's plist and value in the `maxima`
  package, plus the gensyms reachable from `genvar` and the database lists
  (`dobjects`, `*nobjects*`, context `data`). Any difference the hook log
  doesn't explain is a missed write. Because the fingerprint is deep, it
  also catches in-place mutation of stored values, which the hook can't
  see. It is slow, so it is for validation runs only.
- **An expected-write table.** Doc 03 names specific hidden writers, and
  each must be reported when its trigger runs. A row that never fires marks
  a blind spot.

  | Trigger | Expected report |
  |---|---|
  | `rat(x+y)` | `disrep` put on a CRE gensym |
  | `sign(x)` after `assume(x>0)` | `+labs` puts on the node |
  | `limit(…)` via the series path | `internal` put on the limit variable |
  | `integrate(…)` | Context switch (`subc` put on a new context symbol) |
  | `rectform((-1)^a)` | Fact assume, then forget (`absarg1`) |
  | `f(x):=…`, `tellsimp`, `declare`, `kill` | `mexpr`/`mprops`, `operators`, `opers`, remove or replace-plist |
  | `block([z:1], …)` | `:assign`, then `:unbind` for `$z` |

- **Seeded bypasses.** Plant known unobserved writes and confirm the scanner
  or the snapshot diff catches each one:
  - a direct `setf get`;
  - `funcall #'(setf get)`;
  - `rplacd` on a stored value;
  - `nconc` onto an info list.

  This checks the checkers.

### Silent failure 3: over-reporting or misattribution

The log fills with writes that don't matter, such as restoration on `block`
exit or scratch state that is cleared again at once, and the useful signal
is lost.

- **Mitigation:** report by operation, object kind and indicator, not a raw
  total. Gensym names change between runs, so aggregate by kind, not name.
- **Check:** repeated runs of the same workload give **identical profiles**.
  Profiles that drift mean something depends on timing or order, and that
  has to be explained before the data is used.

### Silent failure 4: measurement disturbs the result

A recording hook allocates, which shifts GC and timing. Write counts aren't
affected; timings taken with a hook installed are. Take timings with no hook
and counts with the hook, never both from the same run.

## What "no write" means

A clean report must have a precise meaning. As planned, the facility
observes:

- property **slot** writes in `src/` made through the funnel: put, remove,
  replace-plist;
- Maxima-level value assignment through `mset`, including binding and
  restoration.

It does **not** observe:

- mutation of structures stored in properties;
- destructive edits of info lists (`$values`, `$functions`, …);
- `setq`/`setf` of Lisp specials;
- hash tables and arrays;
- anything in `share/`;
- writes made before a hook is installed.

"No write observed" means "no write in the observed classes". Only the
snapshot oracle can back a claim that nothing was written at all.

## Validation ladder

Workload profiles are read only after the facility clears each level in
order:

| Level | Check | Catches |
|---|---|---|
| 0 | Clean build; suite identical to baseline; timing within noise | Loud failures |
| 1 | Spec scenarios pass | Basic function |
| 2 | Every expected-write row fires | Blind spots on known writers |
| 3 | Snapshot diff: no unexplained differences across the suite, within declared scope | Unknown bypasses; value mutation |
| 4 | Every seeded bypass is caught | Whether the checkers work |
| 5 | Profiles repeat exactly across runs | Nondeterminism; misattribution |
| 6 | Profile `wc_systematic` against the pre-recorded criteria | The answer we want |

At level 6 the four mailing-list failures serve as a sanity check. Each
should show writes that explain its known failure:

| Case | Expected explanation |
|---|---|
| `::` loop (9544/10000) | `:assign` of fresh globals inside the region |
| Parallel `limit` | Fact and context writes |
| `block`-local Newton loop | `:assign`/`:unbind` of the locals |
| `wc_systematic` | `:assign` of the shared counter `wc_tolnum` |

A case that shows nothing means the facility is blind there.

## Changes made to the OpenSpec proposal

The first draft of `add-environment-accessor-layer` covered levels 0 and 1
and part of 2. The change now also includes:

1. A snapshot-diff oracle requirement (level 3) with scenarios.
2. The expected-write table as tests (level 2).
3. Seeded-bypass tests for both the scanner and the oracle (level 4).
4. An explicit statement of observed and unobserved classes (the section
   above), so that under-reporting is a stated limit, not a hidden property
   of the design.
5. A repeatability requirement (level 5).
6. The level-6 decision criteria written in `docs/multithreading/` before
   any workload is measured.
