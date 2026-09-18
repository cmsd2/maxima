## 1. Baseline and pre-registration

- [ ] 1.1 Bootstrap, configure (`--enable-sbcl`) and build the worktree.
  Verify that `./maxima-local --version` runs, and that no `src/*.lisp` file
  is newer than `src/binary-sbcl/maxima.core`.
- [ ] 1.2 Run `run_testsuite(share_tests=true)` on the unmodified build and
  save the full log as the baseline. Verify that it contains
  `No unexpected errors`, or record the baseline failures.
- [ ] 1.3 Time the core suite three times on the unmodified build,
  discarding the first run, and save the timings. Verify that three usable
  timings are recorded with their spread.
- [ ] 1.4 Write the level-6 decision criteria in docs/multithreading/05
  (which profile leads to which conclusion for `wc_systematic`) before any
  workload is profiled. Verify that the criteria are in the document.

## 2. Differential corpus (baseline side)

- [ ] 2.1 Write the corpus runner (design D11):
  - rtest inputs, `.dem` files, and a seeded random-expression generator;
  - one process per input under `timeout`, with `display2d:false`;
  - normalised output (gensym placeholders, timing lines stripped).

  Verify that two runs on the baseline build give identical output files.
- [ ] 2.2 Build the exclusion list from inputs that differ between two
  baseline runs, with a reason for each. Verify that two baseline runs agree
  exactly once the exclusions apply.
- [ ] 2.3 Save the baseline corpus output. Verify that the output file
  exists and records the generator seed and corpus size.

## 3. Static check (written first, so it drives the conversions)

- [ ] 3.1 Write the reader-level scanner that reports run-time direct plist
  writes in `src/*.lisp`: `(setf (get`, `(setf (symbol-plist`, `(remprop`,
  `(setf (getf (cdr` on node plists, and `(funcall #'(setf get)`. Report
  file, enclosing top-level form and line. Verify on the unmodified tree
  that it reports roughly the ~100 run-time sites estimated in
  docs/multithreading/03, and flags no top-level `defprop` or top-level
  `(setf (get …))`.
- [ ] 3.2 Add allowlist support (file, enclosing function, reason) and exit
  status (0 only when there are no unlisted sites). Verify that it exits
  nonzero on the unmodified tree and exits 0 on a fixture containing only
  load-time writes.
- [ ] 3.3 Save the scanner's report on the unmodified tree as the conversion
  worklist. Verify that the worklist count matches 3.1.

## 4. Hook and funnels

- [ ] 4.1 Declare `*environment-write-hook*` (default nil) in
  `src/globals.lisp` before `putprop`, with a docstring giving the calling
  convention, the operation kinds and the rule that `:unbind` must not be
  refused. Verify after rebuilding that `:lisp (boundp
  'maxima::*environment-write-hook*)` returns T.
- [ ] 4.2 Call the hook with `:put` in `putprop` before the write, for both
  symbols and non-symbol nodes. Verify with an ad hoc hook in a
  `--batch-string` session that `f(x):=x^2` records a `:put` for `$f`.
- [ ] 4.3 Call the hook with `:remove` in `zl-remprop` before the removal.
  Verify ad hoc that `kill(f)` after a definition records a `:remove` or
  `:replace-plist` for `$f`.
- [ ] 4.4 Add the plist-replacement funnel function next to `zl-remprop` in
  `src/clmacs.lisp`, calling the hook with `:replace-plist`. Verify that it
  compiles cleanly (no `caught WARNING` in the build log).
- [ ] 4.5 Call the hook in `mset` before the final
  `(setf (symbol-value x) y)`, with `:assign`, or `:unbind` when `munbindp`
  is true. Call it in `munbind-makunbound` with `:unbind` and `munbound`.
  Verify ad hoc that `y:5` records `:assign`, and that `block([z:1],z+1)`
  records `:assign` then `:unbind` for `$z`.

## 5. Convert bypass sites

- [ ] 5.1 Convert run-time `(setf (get …))` sites on the worklist to
  `putprop`, one commit per file, checking each site's use of the return
  value. Verify that the scanner no longer reports those sites and that each
  touched file compiles without new warnings.
- [ ] 5.2 Convert run-time `remprop` sites to `zl-remprop`, checking return
  value use, one commit per file. Verify with the scanner and a clean
  compile.
- [ ] 5.3 Convert run-time `(setf (symbol-plist …))` sites (`kill` in
  `suprv1.lisp`, `ordervar` in `nalgfa.lisp`, `sublis`, `hayat`) to the
  replacement funnel. Verify with the scanner and a clean compile.
- [ ] 5.4 Review the macro bodies the scanner flags (`defmacro`,
  `def-simplifier`). Convert expansions that land in function bodies, and
  allowlist load-time ones with a reason. Verify that the scanner exits 0.
- [ ] 5.5 Rebuild. Run the stale-image check from AGENTS.md sec. 4 and grep
  the build log for `caught ERROR`, `caught WARNING` and
  `undefined function:`. Verify that all three are clean.

## 6. Functional tests (validation levels 1 and 2)

- [ ] 6.1 Write the Lisp-level test script (loaded into the built image, like
  `tests/depcheck.sh`) with a recording hook and one check per scenario for:
  - definition, `tellsimp` and `kill` removal;
  - hidden writes during `sign` after `assume`;
  - plain assignment;
  - `block` bind and restore.

  Verify that the script exits 0.
- [ ] 6.2 Add the refusal scenario: a hook that `merror`s on writes to `$g`,
  where `errcatch(g(x):=x)` returns `[]` and `g` has no `mexpr`. Verify that
  the script exits 0.
- [ ] 6.3 Add the expected-writer table (spec "Known hidden writers are
  reported"): `rat`, `sign` after `assume`, series `limit`, `integrate`
  context, `rectform((-1)^a)`, `block`. Each runs in a fresh session. Verify
  that every row fires and the script names any row that doesn't.

## 7. Profile report (validation level 5)

- [ ] 7.1 Write the aggregated profile report (design D10): operation ×
  object kind × indicator, with optional region marking and per-iteration
  counts. Verify that a CRE-heavy workload groups gensym writes under
  Maxima-created, with no gensym names in the output.
- [ ] 7.2 Profile three fixed workloads (a slice of the suite, a `rat` loop,
  an `integrate` loop) three times each in fresh sessions. Verify that the
  profiles are identical across runs.

## 8. Oracle and seeded bypasses (validation levels 3 and 4)

- [ ] 8.1 Write the snapshot-diff oracle (design D9): a deep structural hash
  with a cycle guard over package symbols, `genvar` gensyms, database nodes
  and contexts, attributed per test problem. Verify on a hand-written case
  that an in-place `rplacd` on a stored property value is reported as
  unexplained.
- [ ] 8.2 Build the reviewed benign-churn list (labels, `$linenum`,
  `*last-meval1-form*`, …) and the expected unobserved classes (such as
  `data` lists mutated by `fdel`). Verify that each entry has a reason and
  maps to a documented unobserved class or to benign churn.
- [ ] 8.3 Run the full suite, share tests included, with the oracle on.
  Verify that there are no unexplained differences. Each remaining one is
  fixed by conversion or added to the unobserved list with a reason, and the
  final run lists none.
- [ ] 8.4 Write the seeded-bypass tests:
  - a direct `setf get` in a function body;
  - `funcall #'(setf get)`;
  - `rplacd` on a stored value;
  - `nconc` onto `$values`.

  Verify that each is caught by the scanner, the oracle, or both, and that
  the test names any bypass neither caught.

## 9. Behaviour and performance verification (validation level 0)

- [ ] 9.1 Run `run_testsuite(share_tests=true)` with no hook installed.
  Verify that the results match the 1.2 baseline exactly: same failures,
  `No unexpected errors`, no newly unexpected passes.
- [ ] 9.2 Run the core suite with a passive counting hook. Verify that the
  results match the 1.2 baseline, and record the total write count.
- [ ] 9.3 Run the differential corpus on the changed build with no hook and
  with a passive hook. Verify that both outputs match the 2.3 baseline
  exactly after the 2.2 exclusions.
- [ ] 9.4 Time the core suite in alternating baseline and changed runs, three
  each after a discarded first run, with no hook installed. Verify that the
  difference in mean time is smaller than the larger run-to-run spread, and
  record the numbers.

## 10. Documentation

- [ ] 10.1 Document the facility in `docs/multithreading/`:
  - the hook's calling convention and observer rules (reentrancy, never
    refuse `:unbind`, refuse at the first write);
  - how to run the scanner, tests, oracle, corpus and profile report;
  - the observed/unobserved scope statement (spec "Observed scope is stated
    precisely").

  Verify that every allowlist entry and every oracle unobserved-class entry
  appears in the unobserved list.
- [ ] 10.2 Record the passive-hook write count (9.2), the timings (9.4), the
  corpus size and the oracle results (8.3) in the document. Verify that the
  numbers are present.

## 11. First measurement (validation level 6)

- [ ] 11.1 With levels 0–5 cleared, profile the `wc_systematic` loop body
  and the four mailing-list failure cases, with the region marked. Verify
  that each failure case shows writes that explain its known failure, and
  treat any case that shows none as a blind spot to investigate before
  going further.
- [ ] 11.2 Read the `wc_systematic` profile against the criteria written in
  1.4 and record the conclusion in docs/multithreading/05. Verify that the
  conclusion cites the criterion it matched.
