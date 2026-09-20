Tasks run in four stages. Each stage ends with a gate; stop and review
before starting the next.

## 1. Stage A: workload and sequential baseline

- [x] 1.1 Write the workload file (`research/multithreading/workloads/`):
  the voltage-divider chain with a configurable number of tolerances,
  `wc_setup(n)` doing `wc_systematic`'s per-call setup, and `wc_item(i)`
  computing corner `i` exactly as `wc_systematic`'s outer `makelist` body
  does. Verify that `makelist(wc_item(i), i, 0, N-1)` equals
  `wc_systematic(expr)` for 4 and 6 tolerances.
- [x] 1.2 Write the sequential runner. It records wall time, GC time
  (`sb-ext:*gc-run-time*`), bytes consed and per-item times, and writes a
  JSON record. Verify that a 4-tolerance run produces a record with 81
  per-item times.
- [x] 1.3 Measure per-item cost at 6 tolerances and choose the two workload
  sizes (design D6: sequential runs roughly 10–120 s). Record the choice and
  the measured mean and coefficient of variation. Verify that the sizes are
  written into the workload file's header comment. *Result:* 10 and 12
  tolerances (59,049 and 531,441 corners; 6.7 s and 91.9 s sequential).
  The planned 6 and 8 took 0.03 s and 0.46 s.
- [x] 1.4 **Gate A.** Report per-item mean, CV, GC share and sequential
  times for both sizes. Stop for review.

## 2. Stage B: the process pool

- [x] 2.1 Write the pool (`research/multithreading/tools/pool.lisp`):
  - check that the image runs one thread;
  - static and dynamic scheduling (design D2, including the `PIPE_BUF`
    token limit check);
  - fork *p* workers; each worker evaluates the item function per index and
    writes `(index . result)` pairs to its own file (D3);
  - each worker records busy time, GC time, `ru_maxrss` and heap growth
    (D4);
  - the parent waits, reads and reassembles the results, and records fork,
    wait and read times.

  Verify that a 4-tolerance run at *p* = 3 in both modes returns 81 results.
- [x] 2.2 Add the correctness check: compare the pooled list with the
  sequential list by `alike1`, element by element, and fail naming the
  first differing index. Verify with a planted fault (one worker returning
  a wrong value for one index) that the run is reported failed, naming that
  index.
- [x] 2.3 Add the isolation test (spec "Workers share nothing"): a work item
  that assigns a global and defines a function. Verify that the parent has
  neither afterwards and the results are correct.
- [x] 2.4 **Gate B.** Pool correct in both modes at *p* = 1, 2, 4, 10 on the
  4- and 6-tolerance workloads; planted fault caught; isolation holds.
  Stop for review.

## 3. Stage C: the sweep

- [x] 3.1 Write the driver (`research/multithreading/tools/pool-bench.sh`),
  following design D5:
  - one fresh Maxima process per measurement;
  - a discarded warm-up round, then three timed rounds, rotating the order
    of configurations between rounds;
  - configurations: sequential, and *p* = 1, 2, 3, 4, 6, 8, 10 in both
    modes, for both workload sizes;
  - one JSON record per measurement, including the start time, core layout,
    SBCL version and Maxima commit.

  Verify that a dry run with one repeat and two worker counts produces the
  expected records.
- [x] 3.2 Run the full sweep. Verify that every record is marked correct and
  that the number of records matches the configuration count.
- [x] 3.3 **Gate C.** Report any failed or outlying runs, and total machine
  time. Stop for review.

## 4. Stage D: analysis and documentation

- [x] 4.1 Write `pool_report.py`:
  - per-configuration medians and spreads, speedup and efficiency;
  - memory per worker and total;
  - worker busy-time spread (imbalance) for both modes;
  - fork and transfer overheads;
  - USL fit (σ, κ, residual, peak worker count) over *p* ≤ 4 and over the
    full curve.

  Verify on synthetic records with known σ and κ that the fit recovers them
  to within 5%.
- [x] 4.2 Generate the report from the sweep. Verify that it contains every
  section the spec requires, and states that there is no thread arm and
  why.
- [x] 4.3 Rerun a subset (sequential, *p* = 4 and *p* = 10, dynamic, larger
  workload) as a reproducibility check. Verify that the medians agree
  within the reported spread (spec "Rerun on the same machine").
  *Result:* first rerun (load average 8–10) not met for *p* = 10 (16.85 s
  against 19.52 s, spread 2.06 s). Second rerun (load average 4 at start)
  met for all three: sequential 69.90 s, *p* = 4 23.90 s, *p* = 10 18.64 s.
  The pass partly reflects wide spreads (sequential 9.1 s, *p* = 10 4.6 s);
  across the three measurements the *p* = 10 median varies by about ±8%.
- [x] 4.4 Write `docs/multithreading/07-process-pool-baseline.md` with the
  results and the machine description. Update doc 02's model with the
  measured parameters (f_gc, per-item CV, fork and transfer overheads, USL
  σ and κ). Verify that both documents cite the result files.
- [x] 4.5 **Gate D.** Summarise what the process curve means for the thread
  decision: the speedup and memory a thread mode would have to beat.
