# GC scaling spike: threads against processes

Machine: Apple M4, 4P+6E cores; SBCL 2.6.5-85913ede1; commit 02d55a6a8.
Collector: gencgc yes, mark-region no, parallel marking no, nursery 51.2 MiB.

Records: 32 total, 8 warm-up (dropped), 24 timed, 0 failed.

Checksums: all 24 runs agree on 5184002592000001
Cross-check against the single-threaded calibration value 5184002592000001: match

Machine state during the sweep: CPU in use 12-117% of one core, battery 96-97%, 0 runs forced past the quiet check.


## Threads

| Workers | Median wall | Spread | Throughput | Efficiency | Rate | Collections | GC wall | Stopped | Mean pause |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10.24 s | 0.03 | 1.00× | 100% | 0.80 GB/s | 165 | 0.13 s | 1.3% | 0.79 ms |
| 2 | 10.62 s | 0.02 | 1.93× | 96% | 1.55 GB/s | 346 | 0.31 s | 2.9% | 0.91 ms |
| 4 | 11.30 s | 0.04 | 3.63× | 91% | 2.91 GB/s | 770 | 0.76 s | 6.8% | 1.01 ms |
| 8* | 16.46 s | 0.20 | 4.98× | 62% | 3.98 GB/s | 1981 | 1.87 s | 11.4% | 0.95 ms |

\* above the 4 performance cores.

## Processes

| Workers | Median wall | Spread | Throughput | Efficiency | Rate | Collections | GC wall | Stopped | Mean pause |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10.25 s | 0.03 | 1.00× | 100% | 0.80 GB/s | 165 | 0.12 s | 1.2% | n/a |
| 2 | 10.45 s | 0.04 | 1.96× | 98% | 1.57 GB/s | 330 | 0.26 s | 1.2% | n/a |
| 4 | 10.66 s | 0.06 | 3.85× | 96% | 3.09 GB/s | 656 | 0.63 s | 1.5% | n/a |
| 8* | 14.24 s | 0.09 | 5.76× | 72% | 4.62 GB/s | 1320 | 2.25 s | 2.0% | n/a |

\* above the 4 performance cores.

Pause times are not collected in the process arm: each child reports its collection count and GC time, not its individual pauses. The stopped share is what the comparison turns on, and that is measured in both arms.

## Where the time goes

| Arm | Workers | Ideal wall | Measured | Excess | GC stall | Residual | GC share of excess |
|---|---|---|---|---|---|---|---|
| threads | 1 | 10.24 s | 10.24 s | 0.00 s | 0.13 s | n/a | n/a |
| threads | 2 | 10.24 s | 10.62 s | 0.37 s | 0.31 s | 0.06 s | 84% |
| threads | 4 | 10.24 s | 11.30 s | 1.06 s | 0.76 s | 0.29 s | 72% |
| threads | 8 | 10.24 s | 16.46 s | 6.21 s | 1.87 s | 4.34 s | 30% |
| processes | 1 | 10.23 s | 10.25 s | 0.02 s | 0.12 s | n/a | n/a |
| processes | 2 | 10.23 s | 10.45 s | 0.22 s | 0.13 s | 0.09 s | 59% |
| processes | 4 | 10.23 s | 10.66 s | 0.42 s | 0.16 s | 0.27 s | 37% |
| processes | 8 | 10.23 s | 14.24 s | 4.00 s | 0.28 s | 3.72 s | 7% |

Rows whose excess is under 0.1 s are left blank: run-to-run spread is 0.03-0.06 s, so at that size the excess is the measurement floor and a ratio against it means nothing.

Ideal wall is the one-worker loop time: with perfect scaling, p workers finish in the same wall time as one. GC stall is the time each worker spent halted for collection. The residual is what collection does not explain: memory bandwidth, scheduling, and cores that are not all equal.

## Verdict against design D4

At p = 4: threads 3.63×, processes 3.85×, ratio 0.94, thread efficiency 91%.

Thresholds (design D4, fixed before the data): pass needs ratio >= 0.90 and efficiency >= 70%; 0.70-0.90 is redesign; below 0.70, or under 2.0x absolute, is fail.

**Spike A: PASS**

