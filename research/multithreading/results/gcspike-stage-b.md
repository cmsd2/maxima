# GC spike, stage B: threads against processes

Gate B of `add-thread-feasibility-spikes`. Spike A asks whether
stop-the-world collection scales when several workers allocate at
`wc_systematic`'s measured rate. Both arms run the identical calibrated
loop (stage A) with the identical per-worker iteration count, so they
differ only in the mechanism.

Data: `gcspike.jsonl` (main sweep), `gcspike-sens.jsonl` (sensitivity).
Reports: `gcspike-report.md`, `gcspike-sens-report.md`.
Tools: `tools/gcspike.lisp`, `tools/gcspike-bench.sh`,
`tools/gcspike_report.py`.

32 measurements, 8 warm-up rounds dropped, 0 failures. Every run's checksum
matched the single-threaded calibration value (5184002592000001), so no
worker silently did less work than it was asked for. The machine stayed
between 12% and 117% of one core busy throughout, battery 96–97%, no run
forced past the quiet check.

Work is fixed per worker, so this measures throughput: perfect scaling holds
wall time constant as workers are added. Throughput is
C(p) = p × wall(1) / wall(p) against each arm's own one-worker time.

## Result

| Workers | Threads | Processes | Ratio |
|---|---|---|---|
| 1 | 1.00× | 1.00× | 1.00 |
| 2 | 1.93× (96%) | 1.96× (98%) | 0.99 |
| **4** | **3.63× (91%)** | **3.85× (96%)** | **0.94** |
| 8 | 4.98× (62%) | 5.76× (72%) | 0.86 |

Run-to-run spread is 0.01–0.20 s on runs of 10–16 s.

**Gate B threshold (design D4, fixed before the data): pass needs ratio ≥
0.90 at *p* = 4 and thread efficiency ≥ 70%. Measured 0.94 and 91%.
Spike A passes.**

The sensitivity run with the survival-matched allocator config
(`:retain-every 32768 :ring-size 64`, stage A's alternative) gives 3.64×
against 3.86×, ratio 0.94, efficiency 91%. The calibration compromise does
not move the verdict.

## What the collector actually does

| Arm | Workers | MB consed per collection | Promoted | Stopped share |
|---|---|---|---|---|
| threads | 1 | 51.0 | 16 MB | 1.3% |
| threads | 2 | 48.7 | 51 MB | 2.9% |
| threads | 4 | 43.7 | 124 MB | 6.8% |
| threads | 8 | 33.9 | 407 MB | 11.4% |
| processes | 1 | 51.0 | 21 MB | 1.2% |
| processes | 2 | 51.0 | 42 MB | 1.2% |
| processes | 4 | 51.4 | 85 MB | 1.5% |
| processes | 8 | 51.0 | 170 MB | 2.0% |

Threads pay twice, and both costs grow with the worker count:

- **They collect more often for the same bytes.** Processes collect every 51
  MB whatever *p* is, because each has its own heap. Threads share one
  nursery trigger, and the interval falls from 51 MB at one thread to 33.9
  MB at eight: 1,981 collections against the process arm's 1,320 for the
  same 65.6 GB.
- **More survives each collection.** Promotion grows faster than linearly
  for threads (124 MB at *p* = 4 against the process arm's 85 MB, 407 MB
  against 170 MB at *p* = 8), because more workers have live structures in
  flight when the collector stops them.

A thread at *p* = 4 spends 6.8% of its time halted, against 1.5% for a
process worker. That is the cost the ratio of 0.94 is made of.

## Where the time goes

| Arm | Workers | Ideal | Measured | Excess | GC stall | Residual | GC share |
|---|---|---|---|---|---|---|---|
| threads | 2 | 10.24 s | 10.62 s | 0.37 s | 0.31 s | 0.06 s | 84% |
| threads | 4 | 10.24 s | 11.30 s | 1.06 s | 0.76 s | 0.29 s | 72% |
| threads | 8 | 10.24 s | 16.46 s | 6.21 s | 1.87 s | 4.34 s | 30% |
| processes | 2 | 10.23 s | 10.45 s | 0.22 s | 0.13 s | 0.09 s | 59% |
| processes | 4 | 10.23 s | 10.66 s | 0.42 s | 0.16 s | 0.27 s | 37% |
| processes | 8 | 10.23 s | 14.24 s | 4.00 s | 0.28 s | 3.72 s | 7% |

On the performance cores, collection is what separates the arms: it
accounts for 72% of the thread arm's excess at *p* = 4, and the residual
(0.29 s) is the same size as the process arm's (0.27 s), which is memory
bandwidth both arms pay alike.

Past four workers the picture changes. Both arms lose far more to the
residual than to collection, because workers 5–8 run on efficiency cores
that are simply slower. At *p* = 8 the thread arm's GC stall is 1.87 s of a
6.21 s excess. Adding threads beyond the performance cores is not a GC
problem.

## What this means for the decision

- **Collection does not serialise these threads.** The thread arm reaches
  91% efficiency on four cores while collecting 770 times, stopping every
  thread each time. Stop-the-world gencgc with no parallel marking is not a
  barrier at this allocation rate.
- **The margin is intact.** Threads give up 6% against processes at four
  workers. Doc 07 measured processes paying about 8% in fork and result
  transfer on the real workload at ten workers, and 2% at one. Threads
  remain able to beat a process pool for this workload, though not by much.
- **The gap widens with workers.** The ratio falls from 0.99 at two workers
  to 0.94 at four and 0.86 at eight. Extrapolating the collection interval
  (51 → 43.7 → 33.9 MB) suggests thread GC cost keeps climbing, so a
  many-core machine would read differently from this one.

## Limits

- A synthetic allocator matched on rate, collection frequency and GC share.
  It cannot reproduce the real expression graph's locality.
- Survival is 5× the workload's (stage A explains why it cannot be matched
  alongside the pause). The sensitivity run at 1.4× survival gives the same
  verdict.
- One machine, one collector, one SBCL version. A newer SBCL with the
  mark-region collector and parallel marking would need its own measurement,
  and would only improve the thread arm.
- Pause durations are recorded only in the thread arm; the process arm
  reports collection counts and GC time per child. The stopped share, which
  the comparison turns on, is measured in both.
