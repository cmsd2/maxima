## Context

See proposal.md for the motivation and scope assumptions, and
`specs/environment-write-observation/spec.md` for the requirements.
docs/multithreading/03 has the inventory of write sites.

Current state of the write paths:

- **`putprop`** (`src/globals.lisp`) is already a function. It handles
  symbols and the non-symbol database nodes `(x . plist)`. `mputprop`
  (`src/maxmac.lisp`), `meta-putprop` and `meta-mputprop` (`src/trprop.lisp`)
  all end in it, which accounts for about 270 of the run-time write sites.
- **`zl-remprop`** (`src/clmacs.lisp`) is a function that handles both node
  kinds. `remprop` is called directly in about 54 places.
- **Direct `(setf (get …))`**: 278 textual occurrences, about 40 of them
  inside function bodies. The rest are load-time top-level forms.
- **`(setf (symbol-plist …))`**: 9 sites, among them `kill` restoring
  built-in plists (`suprv1.lisp`), `ordervar` sharing plists (`nalgfa.lisp`),
  and `sublis` markers.
- **`mset`** (`src/mlisp.lisp`) is the single path for Maxima-level
  assignment. It ends in `(setf (symbol-value x) y)`. `mbind-doit` and
  `munbind` call `mset` (with `mbindp`/`munbindp` bound). Unbinding to
  "unbound" goes through `munbind-makunbound`, which calls `makunbound`
  directly.
- **Build order:** `globals` depends on `compatibility-macros1`, which
  contains `clmacs`, so `clmacs.lisp` compiles first. (The first draft of
  this design assumed the reverse; the stage B build caught it as
  undefined-variable warnings.) A special used by both files must be
  declared in `clmacs.lisp`.

Constraints from AGENTS.md: minimal diffs that match the surrounding style,
literal tabs preserved, no new `$` symbols, and a full suite run with share
tests before a change counts as finished.

## Goals / Non-Goals

**Goals:**

- One observation point per kind of write: property put, property remove,
  plist replacement, value assignment.
- Keep conversions mechanical and reviewable: each converted site becomes an
  equivalent call to an existing funnel function.
- Make the static check fail on new bypasses, so the funnel stays complete.

**Non-Goals:**

- Changing how or where state is stored. Plists and value cells remain the
  store.
- Thread safety of any kind. The hook runs in the writer's thread with no
  locking, and the hook variable itself is an ordinary special.
- Reads, `share/`, and `setq` of Lisp specials (see proposal).

## Decisions

### D1. Extend the existing funnels instead of introducing `env-put`/`env-get`

The hook goes into `putprop` and `zl-remprop`. Bypass sites are converted to
call them, plus one new function for plist replacement.

- *Why:* about 270 sites already call `putprop` indirectly. Adding a new
  `env-put` would mean rewriting those as well, with no behavioural gain and a
  diff several times larger, against the project's minimal-diff norm.
- *Alternative:* a new `env-*` API across all write sites, which docs/04
  sketched. It could be layered on later by renaming, once there is a reason
  such as a layered environment needing reads as well.

### D2. Hook shape: one special variable holding a function or nil

Declare `*environment-write-hook*` with `defvar` in `src/clmacs.lisp`,
default nil, since `clmacs.lisp` compiles before `globals.lisp` (see
Context). Funnels call
`(funcall *environment-write-hook* operation object indicator value)` before
performing the write, where operation is one of `:put`, `:remove`,
`:replace-plist`, `:assign`, `:unbind`.

- *Why before the write:* the spec requires that a refused write not take
  effect. Calling first and writing only if the hook returns normally
  satisfies that without any rollback.
- *Why a special:* binding it with `let` scopes observation to one dynamic
  extent. In SBCL that binding is also thread-local, which suits later
  per-worker measurement.
- *Alternative:* a list of hooks (`run-hooks` style). Rejected: composition
  can be done inside one function, and a single `funcall` keeps the unused
  path to one test.

### D3. Refusal is an ordinary Maxima error

An observer refuses by calling `merror`. That signals the same condition
`errcatch` handles, so `errcatch(g(x) := x)` returns `[]` as the spec
requires. The facility itself doesn't decide what to refuse; that is policy
for later barrier work.

- *Alternative:* return a flag and have the funnel skip the write silently.
  Rejected, because silent skips produce wrong results.

### D4. Value assignment is observed in `mset` and `munbind-makunbound`

`mset` calls the hook with operation `:assign`, or `:unbind` when `munbindp`
is true. The call sits after the `assign`-property check (which may itself
refuse) but before the `setter-method` branch and the `add2lnc`
bookkeeping on `$values`/`$myoptions`. A refused assignment therefore
changes nothing, and assignments handled by a setter method are observed
too.
`munbind-makunbound` calls the hook with `:unbind` and the value `munbound`
before `makunbound`.

- *Why distinguish `:unbind`:* restoring a saved binding at exit is not a new
  definition. A barrier that refused restorations would break `block` exit
  and leave the save stacks inconsistent. Observers need to be able to tell
  the two apart.
- **Documented rule:** observers must not refuse `:unbind`.
- *Alternative:* observe `mbind-doit` separately. Unnecessary, because it
  already goes through `mset`.

### D5. Plist replacement gets its own funnel function

Add a small function in `src/clmacs.lisp`, next to `zl-remprop`, that calls
the hook with `:replace-plist` and then does `(setf (symbol-plist sym) new)`.
Only the run-time `symbol-plist` sites are converted to it.

- *Why:* `kill` and plist sharing change many indicators at once, and
  reporting them as one operation is both accurate and cheap.

### D6. Classify sites as load-time or run-time by enclosing form

A write counts as run-time when it appears inside the body of a `defun`,
`defmfun`, `defmspec`, `lambda` or `flet`/`labels`. It is left alone when it
sits in a top-level form or in `defprop`. Macro bodies (`defmacro`,
`def-simplifier`) are reviewed case by case: an expansion that runs at load
time stays, and one that expands into a function body is converted.

### D7. The static check is a standalone script, allowlist in the repo

The check reads `src/*.lisp` with a small reader-level scanner, not grep, so
that `#|…|#`, `#+nil` and strings are handled correctly. It reports direct
`(setf (get`, `(setf (symbol-plist`, `(remprop` and `(setf (getf (cdr` on
node plists inside run-time bodies that aren't on the allowlist. It lives on
this branch (for example under `tests/` next to `depcheck.sh.in`, or under
`admin/`). Each allowlist entry names file, enclosing function and reason.

- *Alternative:* SBCL xref, like `check-dependencies.lisp`. Rejected: xref
  records calls, not `setf` expansions of `get`, and it is SBCL-only in any
  case.

### D8. Tests are a Lisp-level script loaded into the built image

The test installs a recording hook with `let`, evaluates Maxima forms with
`meval*`, and checks the recorded operations for each scenario in the spec.
It runs like `tests/depcheck.sh`: it loads into the built image and exits
nonzero on failure.

- *Why not an `rtest_*.mac` file:* the rtest format can't install a Lisp
  closure without adding a user-visible function, which the proposal rules
  out.

### D9. The oracle is a deep fingerprint diff, attributed per test problem

The oracle captures a snapshot before an evaluation and another after it,
then subtracts what the observer log explains.

**What a snapshot holds:** a map from `(object indicator)` to a structural
hash of the stored value. It covers:

- every symbol in the `maxima` package: each plist entry, plus the value
  cell as a pseudo-indicator;
- the gensyms in `genvar`;
- the non-symbol nodes in `dobjects` and `*nobjects*`;
- every context in `$contexts` and `context`.

**How values are hashed:** a recursive walk that uses `eq` identity for
symbols and structure for conses, with a cycle guard (the fact database
holds cyclic lists).

**How differences are explained:**

- A changed or new `(object indicator)` pair is explained when the log
  contains a put, remove, replace-plist, assign or unbind for that pair.
- A pair whose *slot* was never written but whose *hash* changed is in-place
  mutation. It is reported as unexplained unless it falls in a documented
  unobserved class. For example, `data` lists mutated by `fdel` are
  expected, and are labelled rather than hidden.

**Granularity:** per test problem. The runner wraps each problem of
`run_testsuite`, so every difference can be attributed to a file and problem
number. The oracle is opt-in and slow, and never runs in normal suites.

- *Alternative:* hash the whole image with SBCL's heap walker. Rejected:
  far more noise (compiler caches, streams) and no way to attribute
  differences to indicators.

### D10. The profile report aggregates by kind, never by generated name

Reports are grouped by operation, object kind and indicator.

| Object kind | Rule |
|---|---|
| Interned `maxima` symbol | user symbol |
| Uninterned symbol (CRE gensyms, context gensyms) | Maxima-created |
| `(x . plist)` cell | database node |
| Member of `$contexts` or the internal context chain | context |

Counts are per workload and, when the workload marks a region, per region
iteration. Generated names never appear in grouping keys, which makes the
profiles repeatable by construction.

### D11. The differential corpus runner compares normalised 1-D output

**Corpus:**

- every `rtest` input, core and share;
- every `.dem` file under `demo/` and `share/`;
- a seeded generator of random expressions over common operators (`+`, `*`,
  `^`, `sin`, `log`, `abs`, `sqrt`, `integrate`, `limit`), with a fixed seed
  so that runs are reproducible.

**Method:** each corpus *file* runs in its own process under `timeout`,
following the AGENTS.md sec. 3 traps, under `display2d:false`. rtest and demo
files are read with `batch`, so every input and its result are printed.

*Revised during stage A:* one process per file, not per input. The corpus has
thousands of inputs, and at about 0.5 s of Maxima start-up each, one process
per input would take hours. Running a whole file keeps the order of inputs
deterministic across builds (an input that poisons later ones does so the
same way in both), and `timeout` still isolates hangs. Demo files that open
viewers or read the terminal are skipped by pattern and listed in the
manifest. Output is normalised by
rewriting gensym names to positional placeholders and stripping timing lines.
It runs on the baseline build, the changed build with no observer, and the
changed build with a passive observer. All three outputs must match.

### D12. Decision criteria are a document, written before measurement

The level-6 criteria in docs/multithreading/05 are written before any
workload profile is produced, so the profile is read against criteria
fixed in advance. This is process, not code, but it is a task, so that it
isn't skipped.

### D13. Region mode for the oracle (added after stage E)

Stage C showed that the hook's scope is the smaller part of environment
change, so the level-6 measurement uses the oracle as the primary
instrument. Per-test-problem snapshots are too coarse for a loop body, so
the oracle gains a region mode:

- `oracle-region-begin` takes a snapshot; each call to
  `oracle-region-step` (one per iteration) diffs against the previous
  snapshot and records the differences with the iteration number;
  `oracle-region-end` stops.
- The hook log keeps working as the explainer, as in D9, so each difference
  is still attributed (explained by a funnelled write, or unobserved class
  B/C/M).
- `gap_report.py` separates iteration 1 from the steady state (iterations
  2 and later, which must repeat) and assigns steady-state writes to the
  fix tiers in doc 05.

*Alternative:* profile with the hook alone. Rejected: the hook doesn't see
classes B and C, which carry most of the concurrency hazard.

## Risks / Trade-offs

- **[A converted site changes behaviour]**
  - `(setf (get s i) v)` returns `v`, and `putprop` returns `v` as well.
  - `remprop` returns a generalized boolean, but `zl-remprop` returns what
    `remprop`/`remf` return, which matches.
  - → Check each conversion's return value use. Run the full suite with
    share tests against a recorded baseline.
- **[Hook runs during recursive or partial states]** The hook sees the world
  before the write, possibly mid-way through a multi-step update (for
  example `mputprop` creating the `mprops` cell, then writing into it). →
  Document that observers must be reentrancy-safe and must not evaluate
  Maxima code that writes the environment. A recording hook only pushes
  onto a list.
- **[Observer refuses a write mid-update]** Refusing the second step of a
  two-step update leaves the first step applied, so the state is partial but
  consistent with single-writer semantics. → Accept. Barrier policy should
  refuse at the first write of an operation. Document it.
- **[Performance]** `putprop` and `mset` are hot. The unused cost is one
  special read and a null test. → Measure per the spec: alternating runs,
  first run discarded. If this is ever measurable, declare the hook check
  `(optimize speed)` locally, or make `putprop` inline.
- **[Incompleteness hidden by the allowlist]** → Allowlist entries require a
  written reason, and the gap list in the documentation must mirror them.
- **[Stale image after build]** A failed compile of `globals.lisp` can leave
  the old core in place (AGENTS.md sec. 4). → The test checks
  `(boundp '*environment-write-hook*)`, which is decisive for a newly added
  variable.
- **[Upstream divergence]** Converting about 100 sites touches many files that
  upstream is actively changing (for example David Scherfgen's `compar.lisp`
  work). → Keep conversions in small per-file commits so they rebase and
  cherry-pick cleanly.

- **[Silent under-reporting]** This is the most serious failure: a clean
  report that misses a write. → The oracle (D9) and the seeded bypasses
  (spec) provide independent evidence. The observed/unobserved statement
  makes the limits explicit. Don't read workload profiles until the
  validation ladder in docs/multithreading/05 is cleared.
- **[Oracle blind spots]** The fingerprint covers package symbols, `genvar`
  and database structures only. Hash tables, arrays and specials outside the
  package are not fingerprinted. → Those are listed as unobserved in the
  scope statement. Extend the fingerprint if a seeded bypass slips through.
- **[Oracle noise]** Legitimate churn, such as top-level labels, `$linenum`
  and `*last-meval1-form*`, appears as differences. → Attribute each class to
  a named benign category in a reviewed list, so that noise is labelled
  rather than hidden.
- **[Differential corpus flakiness]** Some inputs depend on randomness,
  timing or the environment. → Fix the random seed, strip timing lines, and
  keep a reviewed exclusion list for inputs that differ between two runs of
  the *baseline* build.

## Migration Plan

This is a branch-local research facility and nothing needs deploying.

- **Rollback:** revert the commits. With no observer installed, the only
  difference is the funnel calls.
- **Rebasing:** rebase onto `sourceforge/master` per file. The static check
  reveals any bypass that upstream reintroduces.

## Open Questions

- Where the check, test, oracle, corpus and profile scripts should live
  (`tests/` next to `depcheck`, or `admin/`). Any location satisfies the
  spec.
- The size of the generated-expression corpus. Start with a few thousand
  expressions and grow it if runtime allows.
- Whether to extend the check later to `share/`. That is out of scope here,
  but the same scanner would work.
