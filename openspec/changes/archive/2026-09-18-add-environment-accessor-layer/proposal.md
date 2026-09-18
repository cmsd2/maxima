## Why

Maxima keeps its environment (definitions, rules, declarations, facts, CRE
ordering, query scratch) on symbol property lists and value cells, and code
writes that state at run time from about 300 places through several
different Lisp operations. Nobody can observe, audit or restrict those writes, so every claim
about which workloads are "safe to parallelise" rests on static reading
(docs/multithreading/03). An accessor layer is the no-regret first step
identified in docs/multithreading/04. It leaves behaviour unchanged, the
existing suite verifies it, and it enables a write barrier that measures real
environment write traffic on workloads such as `wc_systematic`.

## What Changes

- Make `putprop` and `zl-remprop` the single funnel for **run-time** symbol
  property writes in `src/`. `mputprop` and `meta-putprop` already call
  `putprop`. Convert the run-time bypasses to the funnel:
  - direct `(setf (get …))` inside function bodies;
  - `remprop`;
  - `(setf (symbol-plist …))`.
- Add a whole-plist replacement function to the funnel for the few sites that
  swap plists (`kill` restoring built-in properties, `nalgfa` plist sharing,
  `sublis` markers, `hayat` clearing).
- Add an environment write hook: a special variable, nil by default, called on
  every funnelled write. It receives the object, indicator, new value and kind
  of operation (put, remove, replace-plist, value assignment).
- Call the hook from `mset` for Maxima-level value assignment, which also
  covers `mbind`/`munbind`.
- Add a static coverage check that lists any remaining run-time property
  writes in `src/` that bypass the funnel, against an explicit allowlist.
- Add a Lisp-level test that installs a recording hook and checks that
  representative operations report their writes: `:=`, `tellsimp`,
  `declare`, `assume`, `kill`, `rat`, `sign`.
- Add validation machinery, so that a clean report can be trusted
  (docs/multithreading/05):
  - **Snapshot-diff oracle:** a deep fingerprint of environment state taken
    before and after each test problem. Any difference the hook log doesn't
    explain is reported as a missed write.
  - **Expected-write tests:** each hidden writer found in
    docs/multithreading/03 must be reported when its trigger runs.
  - **Seeded-bypass tests:** planted unobserved writes that the scanner or
    the oracle must catch.
  - **Differential testing:** a corpus (share tests, demos, generated
    expressions) run through the baseline and changed builds, and with and
    without a passive hook, with results compared exactly.
  - **Aggregated, repeatable profiles:** reports grouped by operation,
    object kind and indicator, identical across repeated runs.
- State precisely which classes of write are observed and which are not, so
  that "no write observed" has a defined meaning.
- Write the decision criteria for reading a workload profile in
  `docs/multithreading/` before any workload is measured.

Scope decisions (assumptions recorded here; change them before applying if
wrong):

- **Writes only.** Reads (~1000 `get`/`zl-get`/`mget` sites) are unchanged.
  The barrier and measurement need writes. A layered environment would need
  reads as well, in a later change.
- **`src/` only.** `share/` is not converted. Its direct writes are a
  documented coverage gap.
- **Load-time writes are left alone.** `defprop` and top-level
  `(setf (get …))` run before any hook exists.
- **Value-cell writes are covered through `mset` only.** Direct
  `(setf (symbol-value …))` and `setq` of specials are out of scope. Doc 03
  covers those with thread-entry binding, a separate mechanism.
- **No user-visible Maxima function** is added. The hook is a Lisp-level
  developer facility.

## Capabilities

### New Capabilities

- `environment-write-observation`: every run-time write to symbol property
  lists in `src/`, and every Maxima-level value assignment, passes through a
  funnel that can report it to an optional hook. A static check keeps the
  funnel complete, an independent oracle and seeded tests check that it
  under-reports nothing within its declared scope, and aggregated profiles
  are repeatable.

### Modified Capabilities

(none: there are no existing specs, and computation behaviour doesn't change)

## Impact

- **Code:**
  - `src/globals.lisp` (`putprop`);
  - `src/clmacs.lisp` (`zl-remprop`, new replace-plist function);
  - `src/mlisp.lisp` (`mset`);
  - about 100 converted run-time sites across `src/`. Doc 03 lists about 40
    `setf get`, about 54 `remprop` and 9 `setf symbol-plist` sites, before
    load-time sites are excluded.
- **Build:** a possible new special declared early enough in
  `src/maxima.system` for all users. If a new file is added, `maxima.system`
  and `maxima.asd` need entries.
- **Performance:** one special-variable read and null test per property write
  and per `mset` when no hook is installed. Must stay within noise on the
  test suite. The snapshot oracle is slow and runs only in validation runs,
  never by default.
- **Validation tooling:** new branch-local scripts for the oracle, the
  differential corpus runner and the profile report, alongside the scanner
  and the test script.
- **Upstream:** the conversions are small, behaviour-preserving diffs that
  could stand as a cleanup. The hook is research infrastructure and may stay
  on this branch.
- **Dependencies:** none.
