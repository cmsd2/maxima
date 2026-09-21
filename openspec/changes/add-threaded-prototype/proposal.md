## Why

Doc 08 recommended proceeding: spike A measured threads reaching 0.94 of
the process arm's throughput on four cores, and spike B measured `progv`
costing a tenth of what `mbind` costs today. Nothing cheap stands in the
way.

What stands in the way is not cheap, and it is specific. Doc 05 measured
`wc_systematic`'s writes and found three classes that break under threads:
sign queries writing `+labs`/`-labs` labels onto shared fact-database nodes
during ordinary simplification, first-iteration writes from autoload and
caches, and one shared counter in `wrstcse.mac`. Doc 07 measured what any
of this has to beat: a process pool at 3.35× on four cores, needing no
changes to Maxima at all.

This change fixes those three, runs Maxima on threads for the first time,
and makes the measurement that decides whether the threading path continues.

## What Changes

- **Per-query fact labels** (`src/db.lisp`, `src/compar.lisp`). Sign query
  labels move from properties written onto shared nodes to a per-query
  table, doc 03's option (ii). The largest piece, and the only one that
  changes core Maxima.
- **Per-iteration corner counter** (`share/contrib/wrstcse.mac`). One line,
  making `wc_tolnum` local to each iteration instead of shared across them.
- **A thread runner** (research tooling): a pool that binds the specials
  each thread writes at thread entry, so `mset`'s assignment lands in the
  thread's own binding rather than the global value cell, with a guard that
  refuses a write to any symbol not bound that way.
- **A warm-up iteration** before the parallel region, absorbing
  first-iteration writes.
- **The measurement**: threads against doc 07's process pool on the same
  workload, same machine, same methodology.

Scope decisions (change them before applying if wrong):

- **`mbind` is not rebuilt on `progv`.** Binding the symbols at thread entry
  gives the same confinement without restructuring the evaluator: a `setf`
  of a symbol bound in this thread writes the thread's binding, which was
  verified on this build. The rebuild is what a *general* threaded Maxima
  needs, for user code binding symbols nobody enumerated in advance. It is
  not what the verdict needs, and it is deferred until the verdict justifies
  it.
- **One workload.** `wc_systematic` on the voltage-divider chain, so the
  result compares directly with doc 07. Doc 05's limits on generalising from
  one input still stand and are restated in the decision record.
- **The runner stays research tooling.** A user-facing parallel map is a
  product decision that this change's measurement should inform, not
  precede.
- **Threads run a frozen environment.** No `:=`, `tellsimp`, `declare`,
  `kill`, `load` or `assume` from inside the parallel region. The guard
  enforces what it can; the rest is a stated rule (doc 03).

## Capabilities

### New Capabilities

- `frozen-environment-threads`: running independent Maxima computations on
  native threads in one image, with the environment frozen for the duration,
  writes confined per thread, and any escape refused rather than silently
  corrupting.

### Modified Capabilities

- `environment-write-observation`: the observer gains a thread-mode
  assertion, so the write trace can be taken while threads run rather than
  only single-threaded.

## Impact

- **Code:** `src/db.lisp` and `src/compar.lisp` (per-query labels);
  `share/contrib/wrstcse.mac` (one line); new files under
  `research/multithreading/`.
- **Risk:** the fact-database change is in code every `sign` call reaches.
  It gates on the full suite with share tests, the differential corpus, and
  a single-thread timing comparison: it may not slow sequential Maxima.
- **Machine time:** the measurement is comparable to doc 07's sweep, under
  an hour on a quiet machine.
- **Outcome:** either threads beat the process pool on this workload, or
  they do not and the process pool is the answer. Both are publishable
  results; only one continues the path.
