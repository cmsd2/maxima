# GC scaling spike: threads against processes

Machine: Apple M4, 4P+6E cores; SBCL 2.6.5-85913ede1; commit 02d55a6a8.
Collector: gencgc yes, mark-region no, parallel marking no, nursery 51.2 MiB.

Records: 16 total, 4 warm-up (dropped), 12 timed, 0 failed.

Checksums: all 12 runs agree on 5184002592000001
Machine state during the sweep: CPU in use 12-181% of one core, battery 94-95%, 0 runs forced past the quiet check.


## Threads

| Workers | Median wall | Spread | Throughput | Efficiency | Rate | Collections | GC wall | Stopped | Mean pause |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10.21 s | 0.01 | 1.00× | 100% | 0.81 GB/s | 165 | 0.12 s | 1.1% | 0.70 ms |
| 4 | 11.22 s | 0.05 | 3.64× | 91% | 2.93 GB/s | 730 | 0.67 s | 6.0% | 0.92 ms |

\* above the 4 performance cores.

## Processes

| Workers | Median wall | Spread | Throughput | Efficiency | Rate | Collections | GC wall | Stopped | Mean pause |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10.24 s | 0.05 | 1.00× | 100% | 0.80 GB/s | 164 | 0.10 s | 1.0% | n/a |
| 4 | 10.60 s | 0.06 | 3.86× | 97% | 3.11 GB/s | 660 | 0.53 s | 1.3% | n/a |

\* above the 4 performance cores.

Pause times are not collected in the process arm: each child reports its collection count and GC time, not its individual pauses. The stopped share is what the comparison turns on, and that is measured in both arms.

## Where the time goes

| Arm | Workers | Ideal wall | Measured | Excess | GC stall | Residual | GC share of excess |
|---|---|---|---|---|---|---|---|
| threads | 1 | 10.21 s | 10.21 s | 0.00 s | 0.12 s | n/a | n/a |
| threads | 4 | 10.21 s | 11.22 s | 1.02 s | 0.67 s | 0.34 s | 66% |
| processes | 1 | 10.22 s | 10.24 s | 0.02 s | 0.10 s | n/a | n/a |
| processes | 4 | 10.22 s | 10.60 s | 0.38 s | 0.13 s | 0.24 s | 35% |

Rows whose excess is under 0.1 s are left blank: run-to-run spread is 0.03-0.06 s, so at that size the excess is the measurement floor and a ratio against it means nothing.

Ideal wall is the one-worker loop time: with perfect scaling, p workers finish in the same wall time as one. GC stall is the time each worker spent halted for collection. The residual is what collection does not explain: memory bandwidth, scheduling, and cores that are not all equal.

## Verdict against design D4

At p = 4: threads 3.64×, processes 3.86×, ratio 0.94, thread efficiency 91%.

Thresholds (design D4, fixed before the data): pass needs ratio >= 0.90 and efficiency >= 70%; 0.70-0.90 is redesign; below 0.70, or under 2.0x absolute, is fail.

**Spike A: PASS**

