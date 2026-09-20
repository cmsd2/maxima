## Why

Stage F of `add-environment-accessor-layer` found that a frozen-environment
thread mode is *plausible* for `wc_systematic`, but plausible isn't the same
as worthwhile. Doc 02 argued that processes, not a single thread, are the
baseline any thread mode must beat: separate processes collect garbage in
parallel, share nothing, and `fork` shares the loaded image cheaply. Nobody
has measured that baseline. On the mailing list, the case against processes
was memory ("several heaps won't fit in 8 GB"), and the only speedup quoted
(3.8× on 4 cores) was an unreproducible anecdote. This change measures the
process-pool curve for `wc_systematic` so a later threads decision rests on
numbers.

## What Changes

- Add a fork-based process pool for Maxima computations as research
  tooling. The parent forks worker processes from the loaded image (copy on
  write), hands out work items, and collects results as re-readable
  strings. Both static chunking and dynamic scheduling are supported.
- Add a benchmark driver for `wc_systematic`:
  - scalable workloads (the voltage-divider chain with 6 and 8 tolerances,
    729 and 6561 corners);
  - a sequential baseline;
  - pool runs at 1, 2, 3, 4, 6, 8 and 10 workers, repeated and alternated.
- Measure:
  - wall time, speedup and efficiency;
  - peak memory per worker and in total;
  - GC share of the sequential run (doc 02's f_gc);
  - per-item cost distribution (coefficient of variation) and load
    imbalance;
  - fork start-up and result-transfer overhead.

  Fit the Universal Scalability Law to the throughput curve.
- Check that every pooled result list equals the sequential result list
  exactly.
- Record the results, with the machine's core layout, in
  `docs/multithreading/`, alongside doc 02's model.

Scope decisions (recorded; change them before applying if wrong):

- **Sequential and process pool only.** There is no thread arm: the symbolic
  loop body can't run correctly on threads until the stage F fixes (binding
  rebuilt on `progv`, per-query fact labels) exist. A staged or compiled
  numeric kernel arm and a predicted thread ceiling were considered and left
  out.
- **One workload family** (`wc_systematic` on the voltage-divider chain).
  Other workloads come later.
- **Research tooling only.** Nothing in `src/` or `share/` changes, and
  `wrstcse.mac` is used as shipped.
- **This machine only:** Apple M4, 4 performance and 6 efficiency cores,
  32 GB. Results are reported per core type, not generalised.

## Capabilities

### New Capabilities

- `process-pool-benchmark`: a reproducible measurement of how Maxima
  computations scale across forked worker processes (speed, memory, GC and
  load balance), with a correctness check against sequential results.

### Modified Capabilities

(none)

## Impact

- **Code:** new files under `research/multithreading/`: the pool, the driver,
  workloads and a report script. No Maxima source changes.
- **Dependencies:** SBCL's `sb-posix` contrib (`fork`, `pipe`, `waitpid`),
  already available in the built image. `fork` requires a single-threaded
  image; that was checked on this machine.
- **Machine time:** roughly 1–2 hours of benchmark runs, depending on the
  per-item cost measured in the first task.
- **Docs:** a new results document in `docs/multithreading/`, and doc 02's
  model updated with measured parameters.
