Tasks run in six stages (A–F). Each stage ends with a gate; stop and review
before starting the next. The baseline build lives in a separate worktree
(`maxima-mt-baseline`, detached at `9b545c065`), so it stays runnable while
this worktree changes.

## 1. Stage A: baseline builds and timings

- [x] 1.1 Create the baseline worktree `../maxima-mt-baseline`, detached at
  `9b545c065`. Bootstrap, configure (`--enable-sbcl`) and build it, and
  record the wall time of each step. Verify that `./maxima-local --version`
  runs there and that no `src/*.lisp` is newer than
  `src/binary-sbcl/maxima.core`.
- [x] 1.2 Bootstrap, configure (`--enable-sbcl`) and build this worktree,
  still unmodified. Verify the same two checks as 1.1.
- [x] 1.3 In the baseline worktree, run `run_testsuite(share_tests=true)`
  and save the full log and its wall time. Verify that the log contains
  `No unexpected errors`, or record the baseline failures.
- [x] 1.4 Time the core suite three times in the baseline worktree,
  discarding the first run, and save the timings. Verify that three usable
  timings are recorded with their spread.

## 2. Stage A: differential corpus (baseline side)

- [x] 2.1 Write the corpus runner (design D11):
  - rtest inputs, `.dem` files, and a seeded random-expression generator;
  - one process per input under `timeout`, with `display2d:false`;
  - normalised output (gensym placeholders, timing lines stripped).

  It takes the Maxima build directory as a parameter. Verify that two runs on
  the baseline build give identical output files, apart from inputs later
  excluded in 2.2.
- [x] 2.2 Build the exclusion list from inputs that differ between two
  baseline runs, with a reason for each. Verify that two baseline runs agree
  exactly once the exclusions apply.
- [x] 2.3 Save the baseline corpus output and the corpus wall time. Verify
  that the output file exists and records the generator seed and corpus
  size.

## 3. Stage A: static check

- [x] 3.1 Write the reader-level scanner that reports run-time direct plist
  writes in `src/*.lisp`: `(setf (get`, `(setf (symbol-plist`, `(remprop`,
  `(setf (getf (cdr` on node plists, and `(funcall #'(setf get)`. Report
  file, enclosing top-level form and line. Verify on the unmodified tree
  that it reports roughly the ~100 run-time sites estimated in
  docs/multithreading/03, and flags no top-level `defprop` or top-level
  `(setf (get …))`.
- [x] 3.2 Add allowlist support (file, enclosing function, reason) and exit
  status (0 only when there are no unlisted sites). Verify that it exits
  nonzero on the unmodified tree and exits 0 on a fixture containing only
  load-time writes.
- [x] 3.3 Save the scanner's report on the unmodified tree as the conversion
  worklist. Verify that the worklist count matches 3.1.
- [x] 3.4 **Gate A.** Summarise the build, suite and corpus wall times, the
  corpus size and exclusions, and the worklist size by operation and file.
  Stop for review.

## 4. Stage B: hook and funnels

- [x] 4.1 Declare `*environment-write-hook*` (default nil) in
  `src/clmacs.lisp` (compiled before `globals.lisp`, which uses it in
  `putprop`), with a docstring giving the calling
  convention, the operation kinds and the rule that `:unbind` must not be
  refused. Verify after rebuilding that `:lisp (boundp
  'maxima::*environment-write-hook*)` returns T.
- [x] 4.2 Call the hook with `:put` in `putprop` before the write, for both
  symbols and non-symbol nodes. Verify with an ad hoc hook in a
  `--batch-string` session that `f(x):=x^2` records a `:put` for `$f`.
- [x] 4.3 Call the hook with `:remove` in `zl-remprop` before the removal.
  Verify ad hoc that `sign(x)` after `assume(x>0)` records `:remove` of
  `+labs` (a `zl-remprop` caller in `db.lisp`). *Revised in stage B:*
  `kill(f)` records nothing yet, because `kill` calls `remprop` directly in
  `suprv1.lisp`; that check moves to task 6.2's per-file gate for
  `suprv1.lisp`.
- [x] 4.4 Add the plist-replacement funnel function next to `zl-remprop` in
  `src/clmacs.lisp`, calling the hook with `:replace-plist`. Verify that it
  compiles cleanly (no `caught WARNING` in the build log).
- [x] 4.5 Call the hook in `mset` before the final
  `(setf (symbol-value x) y)`, with `:assign`, or `:unbind` when `munbindp`
  is true. Call it in `munbind-makunbound` with `:unbind` and `munbound`.
  Verify ad hoc that `y:5` records `:assign`, and that `block([z:1],z+1)`
  records `:assign` then `:unbind` for `$z`.
- [x] 4.6 **Gate B.**
  - Run the full suite with no hook, and verify it matches the 1.3 baseline.
  - Run the differential corpus with no hook and with a passive hook, and
    verify both match the 2.3 baseline.
  - Time the core suite in alternating baseline and changed runs, and verify
    the difference is within noise.

  Stop for review.

## 5. Stage C: oracle and seeded bypasses, before any conversion

- [x] 5.1 Write the snapshot-diff oracle (design D9): a deep structural hash
  with a cycle guard over package symbols, `genvar` gensyms, database nodes
  and contexts, attributed per test problem. Verify on a hand-written case
  that an in-place `rplacd` on a stored property value is reported as
  unexplained.
- [x] 5.2 Write the seeded-bypass tests:
  - a direct `setf get` in a function body;
  - `funcall #'(setf get)`;
  - `rplacd` on a stored value;
  - `nconc` onto `$values`.

  Verify that each is caught by the scanner, the oracle, or both, and that
  the test names any bypass neither caught.
- [x] 5.3 Draft the benign-churn list (labels, `$linenum`,
  `*last-meval1-form*`, …) and the expected unobserved classes (such as
  `data` lists mutated by `fdel`), each with a reason. Verify that each
  entry maps to benign churn or a documented unobserved class.
- [x] 5.4 Run the full suite with the oracle on, still with no conversions.
  Save the unexplained differences grouped by indicator and file as the
  **gap report**. Verify that the report exists and gives the total
  unexplained count as the starting point for stage D.
- [x] 5.5 **Gate C.** Compare the gap report with the scanner worklist and
  with doc 03. Decide whether stage D is worth doing, given the size and
  spread of the gap. Stop for review.

## 6. Stage D: convert bypass sites, one file per commit

For each file, the gate is: its scanner entries are gone; it compiles
without new warnings; the core suite still matches the baseline; and the
oracle's unexplained count falls. A file whose count doesn't fall points to
a pattern the scanner missed, and is investigated before going on.

*Revised at gate C (agreed):* the full per-file gate (scanner, clean build,
core suite, oracle class A count) applies to the large or sensitive files:
`suprv1.lisp`, `transl.lisp`, `mlisp.lisp`, `mdebug.lisp`, `db.lisp` and
`compar.lisp`. The remaining small files are converted one commit per file
with the cheap checks (scanner, clean compile) per file, and the core suite
and oracle run once per batch of about 10 files. If a batch's class A count
doesn't fall as expected, bisect within the batch. The full gate would cost
about 7 minutes of machine time per file, 4–5 hours in total.

- [x] 6.1 Convert run-time `(setf (get …))` sites on the worklist to
  `putprop`, checking each site's use of the return value. Verify each file
  against the per-file gate.
- [x] 6.2 Convert run-time `remprop` sites to `zl-remprop`, checking return
  value use. Verify each file against the per-file gate; for `suprv1.lisp`,
  also verify that `kill(f)` after a definition records `:remove` or
  `:replace-plist` for `$f`.
- [x] 6.3 Convert run-time `(setf (symbol-plist …))` sites (`kill` in
  `suprv1.lisp`, `ordervar` in `nalgfa.lisp`, `sublis`, `hayat`) to the
  replacement funnel. Verify each file against the per-file gate.
- [x] 6.4 Review the macro bodies the scanner flags (`defmacro`,
  `def-simplifier`). Convert expansions that land in function bodies, and
  allowlist load-time ones with a reason. Verify that the scanner exits 0.
- [x] 6.5 Rebuild. Run the stale-image check from AGENTS.md sec. 4 and grep
  the build log for `caught ERROR`, `caught WARNING` and
  `undefined function:`. Verify that all three are clean.
- [x] 6.6 **Gate D.** Rerun the oracle over the full suite and record the
  unexplained count against the 5.4 starting point. Stop for review.

## 7. Stage E: functional tests (validation levels 1 and 2)

- [x] 7.1 Write the Lisp-level test script (loaded into the built image, like
  `tests/depcheck.sh`) with a recording hook and one check per scenario for:
  - definition, `tellsimp` and `kill` removal;
  - hidden writes during `sign` after `assume`;
  - plain assignment;
  - `block` bind and restore.

  Verify that the script exits 0.
- [x] 7.2 Add the refusal scenario: a hook that `merror`s on writes to `$g`,
  where `errcatch(g(x):=x)` returns `[]` and `g` has no `mexpr`. Verify that
  the script exits 0.
- [x] 7.3 Add the expected-writer table (spec "Known hidden writers are
  reported"): `ratdisrep(rat(x+y))`, `sign` after `assume`, `gruntz`
  series path, `integrate` context, `rectform(x^a)`, `block`. *Revised in
  stage E:* `rat(x+y)` alone writes no `DISREP` (only gensym value cells), and
  `rectform((-1)^a)` makes a redundant assumption that writes nothing. Each runs in a fresh session. Verify
  that every row fires and the script names any row that doesn't.

## 8. Stage E: profile report (validation level 5)

- [x] 8.1 Write the aggregated profile report (design D10): operation ×
  object kind × indicator, with optional region marking and per-iteration
  counts. Verify that a CRE-heavy workload groups gensym writes under
  Maxima-created, with no gensym names in the output.
- [x] 8.2 Profile three fixed workloads (a slice of the suite, a `rat` loop,
  an `integrate` loop) three times each in fresh sessions. Verify that the
  profiles are identical across runs.

## 9. Stage E: full validation (validation levels 0, 3 and 4)

- [x] 9.1 Run the full suite, share tests included, with the oracle on.
  Verify that there are no unexplained differences. Each remaining one is
  fixed by conversion or added to the unobserved list with a reason, and the
  final run lists none.
- [x] 9.2 Rerun the seeded-bypass tests (5.2) on the converted build. Verify
  that all are still caught.
- [x] 9.3 Run `run_testsuite(share_tests=true)` with no hook installed.
  Verify that the results match the 1.3 baseline exactly: same failures,
  `No unexpected errors`, no newly unexpected passes.
- [x] 9.4 Run the core suite with a passive counting hook. Verify that the
  results match the 1.3 baseline, and record the total write count.
- [x] 9.5 Run the differential corpus on the converted build with no hook and
  with a passive hook. Verify that both outputs match the 2.3 baseline
  exactly after the 2.2 exclusions.
- [x] 9.6 Time the core suite in alternating baseline and changed runs, three
  each after a discarded first run, with no hook installed. Verify that the
  difference in mean time is smaller than the larger run-to-run spread, and
  record the numbers.

## 10. Stage E: documentation

- [x] 10.1 Document the facility in `docs/multithreading/`:
  - the hook's calling convention and observer rules (reentrancy, never
    refuse `:unbind`, refuse at the first write);
  - how to run the scanner, tests, oracle, corpus and profile report;
  - the observed/unobserved scope statement (spec "Observed scope is stated
    precisely").

  Verify that every allowlist entry and every oracle unobserved-class entry
  appears in the unobserved list.
- [x] 10.2 Record the passive-hook write count (9.4), the timings (9.6), the
  corpus size, the gap report's starting and final counts (5.4, 9.1), and
  the oracle results in the document. Verify that the numbers are present.
- [x] 10.3 **Gate E.** Confirm that validation levels 0–5 in doc 05 have all
  passed. Stop for review.

## 11. Stage F: first measurement (validation level 6)

- [x] 11.1 Write the level-6 decision criteria in docs/multithreading/05
  (which profile leads to which conclusion for `wc_systematic`) before
  profiling any workload. Verify that the criteria are in the document.
  *Revised after stage E:* the criteria cover oracle classes B and C and
  group M, use only steady-state writes (every iteration after the first),
  and place each write in a fix tier (T1 bind per thread, T2 per-query or
  per-thread structure, T3 lock, T4 breaks the frozen environment).
- [x] 11.2 Extend the oracle with a region mode (design D13): snapshot at
  region entry and after each iteration of a marked loop, report
  differences per iteration with the hook's attribution, and have
  `gap_report.py` split the first iteration from the steady state and
  assign each steady-state write to a tier using `oracle-churn.tsv` and the
  tier table in doc 05. Verify on a toy loop with known writes: a
  `block`-local assignment gives T1; `y::i` of a fresh global gives T3
  (`$values` info list); `f(x):=…` inside the loop gives T4; an autoload
  happens in iteration 1 only.
- [x] 11.3 Profile the `wc_systematic` loop body and the four mailing-list
  failure cases, with the region marked. Verify that each failure case shows
  writes that explain its known failure, and treat any case that shows none
  as a blind spot to investigate before going further.
- [x] 11.4 Read the `wc_systematic` profile against the criteria from 11.1
  and record the conclusion in docs/multithreading/05. Verify that the
  conclusion cites the criterion it matched.
