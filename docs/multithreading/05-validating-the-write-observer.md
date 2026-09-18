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

### Decision criteria (level 6)

*Revised after stage E, before any workload was profiled.* The first
version classified only what the hook sees (plist slot writes). Stage C
showed that most environment change is in-place mutation (oracle class B)
and special-variable assignment (class C). The **oracle** is therefore the
primary instrument, with the hook adding attribution. The criteria cover
all classes.

**Steady state only.** Profile at least three iterations of the loop body
with a snapshot per iteration. Writes that happen only in the first
iteration (autoload, memo tables, bigfloat constants, first-use caches) can
be handled by a warm-up iteration before a parallel region, which is itself
a contained fix. Only writes that recur in **every** iteration after the
first count against threads.

**Fix tiers.** Every steady-state write is placed in one tier, using doc
03's classification:

| Tier | Meaning | Oracle classes and categories |
|---|---|---|
| **T1: bind per thread** | a Lisp binding at thread entry confines it | C: driver-io, repl-labels, eval-trace, algorithm-scratch, result-vars, bigfloat-cache, cre-pool (`varlist`, `genvar`); `:assign`/`:unbind` of `block`/function locals (needs `mbind` rebuilt on `progv`, doc 03) |
| **T2: per-query or per-thread structure** | a contained redesign already sized in doc 03 | C: factdb-scratch (per-query label table); factdb-contexts (per-thread context). A: `+labs`/`-labs`/`ulabs` label writes. B: fact `DATA` mutation by a temporary `assume`/`forget` inside one computation. CRE gensym `DISREP`/value-cell writes on gensyms created in the iteration |
| **T3: shared structure, needs a lock or per-thread copy** | correct only with synchronisation; cost depends on frequency | C: info-lists (`$values`, `$props`, `$functions`), factdb-nodes (`*nobjects*`, `dobjects`), rules (`*rule-symbol-pool*`), lisp-runtime (`*gensym-counter*`, needs to be atomic). B: `DATA` mutation of built-in constants and number nodes (`dintnum` rewiring the number chain). M: symbols interned in the iteration (package table; thread safety of SBCL `intern` **unverified**) |
| **T4: breaks the frozen environment** | the loop body changes shared definitions; threads can't host it | A: definition indicators (`mprops`, `mexpr`, `operators`, `oldrules`, `opers`, parser properties). B: `MPROPS` mutation outside the funnel. C: parser tables (`macsyma-operators`). Persistent user facts: `assume`/`declare` not undone within the iteration |
| **Unknown** | not yet categorised | C: uncategorised variables; anything else |

**Conclusions:**

| Steady-state profile of the loop body | Conclusion |
|---|---|
| Only T1 and T2 | Frozen-environment threads are **plausible** with contained fixes; the next step is prototyping those fixes |
| T1–T3, with T3 at a low rate per iteration (T3 writes are a small share of the iteration's writes) | **Possible with locks**; the next step is measuring lock contention, since the write count is only a stand-in for time spent holding a lock |
| Any T4, or T3 at a high rate | **Threads ruled out** for this workload; use processes |
| Unknown writes above 5% of the steady-state total | **No conclusion** until they are categorised |

The four mailing-list failure cases are a sanity check at this level. Each
must show steady-state writes that explain its known failure (see the
validation ladder below). A case that shows none means the instrument is
blind there, and no conclusion is drawn until that is explained.

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
  | `ratdisrep(rat(x+y))` | `disrep` put on a CRE gensym (`rat` alone only renumbers gensym value cells) |
  | `sign(x)` after `assume(x>0)` | `+labs` puts on the node |
  | `limit(…)` via the series path | `internal` put on the limit variable |
  | `integrate(…)` | Context switch (`subc` put on a new context symbol) |
  | `rectform(x^a)` | Fact assume, then forget (`absarg1`); `(-1)^a` makes a redundant assumption and writes nothing |
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

## Result of the level-6 measurement (stage F)

Measured with the oracle's region mode: a snapshot per iteration plus every
hook-observed write, classified by `tools/region_report.py`. The steady
state is iterations 2 to second-to-last. The last iteration also carries the
region's exit (the enclosing `makelist` and `block` restoring their
bindings), a measurement artefact found while reading the first result and
corrected before drawing conclusions. Per-region reports are in
`research/multithreading/results/region-*.md`.

### Sanity check: the four mailing-list failures

Each case shows steady-state writes that explain its known failure, so the
instrument is not blind to any of them.

| Case | Steady state | Explanation |
|---|---|---|
| `concat('v,i)::i` (9544 of 10000) | T3 37.5%: fresh global assigned, symbol interned, `$VALUES` mutated | lost updates to the shared info list |
| Parallel `limit(abs(x-i)/(x-i), x, i)` | T3 25%: facts filed on `$INITIAL`, `PRIN-INF` and number nodes; T2 70% | shared fact-database structure |
| `block`-local Newton loop | T1 100%: bind/restore of `x_n`, `x_next`, `i` | shallow binding through the global value cell |
| `wc_systematic` | T3 8.6%: `$WC_TOLNUM` assigned 5 times per iteration | a counter shared across iterations |

### `wc_systematic`

Workload: a two-stage voltage divider with 4 resistor tolerances (81
corners), symbolic `U_In` under `assume(U_In>0)`. The region is the outer
`makelist`, the loop a parallel makelist would distribute.

| Tier | Steady writes per iteration | What they are |
|---|---|---|
| T1 | 21 | bind/restore of `wc_tol` and `wc_num`; specials such as `*last-meval1-form*`, `ans` |
| T2 | 32 | fact-database query labels (`+LABS`) on `U_In`, from sign queries during simplification |
| T3 | 5 | `wc_tolnum`, a local of `wc_systematic`'s outer `block` that every iteration increments |
| T4 | 0 | |
| Unknown | 0 | |

**Criterion matched: "possible with locks"** (T1–T3, with T3 at 8.6% of
steady writes). The criteria distinguish "low" from "high" T3 rates without
giving a number. That gap doesn't affect the conclusion below, because the
variant removes T3 entirely, but a future measurement with real T3 writes
needs a threshold, ideally one based on lock hold time rather than write
counts.

The one T3 write is not Maxima's: it comes from how `wrstcse.mac` shares its
corner counter across iterations. A one-line change that binds `wc_tolnum`
inside each iteration returns **identical results** (81 of 81) and profiles
as **T1 and T2 only**. That meets the **"plausible"** criterion.

**Conclusion.** For this workload, a frozen-environment thread mode is
**plausible**, given:

1. **Maxima-level binding rebuilt on `progv`** (doc 03), so that `wc_tol`,
   `wc_num` and other locals are per thread, plus thread-entry binding of
   the specials the loop writes.
2. **The fact database's query labels moved to a per-query table** (doc 03,
   option ii), so sign queries during simplification stop writing labels
   onto the shared `U_In`.
3. **A warm-up iteration** before the parallel region, which absorbs the
   first-iteration writes (autoload, caches).
4. **The one-line change to `wrstcse.mac`** that makes `wc_tolnum` local to
   each iteration.

No steady-state write required a lock, and nothing changed a definition.

### Limits of this result

- **One input.** Other `wrstcse` inputs (`wc_mintypmax2tol`, `abs`,
  functions whose sign needs facts) may reach code paths that file facts on
  shared objects, which is T3, as the `limit` case shows.
- **Unfingerprinted state.** The oracle doesn't fingerprint hash tables or
  arrays held outside plists (memo tables, `*lambda-expr-funs*`), and it
  misses transient special-variable writes that are restored to the same
  value within an iteration. The fact database's query queue pointers are
  of this kind; they are covered by the same T2 fix as the labels.
- **Plausibility is not speedup.** Each iteration here is a small `subst`
  and simplification. Whether threads beat a process pool for this workload
  is the separate measurement planned in doc 02, and it has not been made.
