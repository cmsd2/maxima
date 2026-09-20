# Process-pool baseline for wc_systematic

Machine: Apple M4, 4P+6E cores, 32 GB; SBCL 2.6.5-85913ede1; commit ad792d6f8.

Records: 120 total, 30 warm-up (ignored), 90 timed, 0 failed correctness.

There is no thread arm: the symbolic loop body can't run correctly on threads until the stage F fixes (binding on progv, per-query fact labels) exist.


## 10 tolerances (59049 corners)

**Sequential:** median 5.56 s (spread 1.10 s over 3 runs); GC 1.7%; per item mean 94 µs, CV 0.84; peak RSS 129 MB.

### Dynamic scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5.83 s | 1.01 | 0.95× | 95% | 0.06 s | 0.06 s | 0.14 s | 0.00 s | 85 MB | 208 MB |
| 2 | 3.36 s | 0.26 | 1.65× | 83% | 0.05 s | 0.05 s | 0.09 s | 0.00 s | 83 MB | 291 MB |
| 3 | 2.39 s | 0.11 | 2.32× | 77% | 0.08 s | 0.05 s | 0.06 s | 0.00 s | 83 MB | 374 MB |
| 4 | 1.84 s | 0.23 | 3.02× | 76% | 0.13 s | 0.06 s | 0.05 s | 0.00 s | 83 MB | 458 MB |
| 6* | 2.02 s | 1.03 | 2.75× | 46% | 0.16 s | 0.08 s | 0.06 s | 0.00 s | 83 MB | 625 MB |
| 8* | 2.22 s | 0.81 | 2.50× | 31% | 0.21 s | 0.06 s | 0.07 s | 0.00 s | 83 MB | 792 MB |
| 10* | 1.66 s | 0.65 | 3.35× | 34% | 0.25 s | 0.06 s | 0.05 s | 0.00 s | 84 MB | 964 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.2872, κ = -0.04508, rms residual 0.027 — **not a usable fit** (negative parameter or residual > 0.1)

USL over all p: σ = 0.1979, κ = 0.00533, rms residual 0.324 — **not a usable fit** (negative parameter or residual > 0.1)

### Static scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5.62 s | 0.62 | 0.99× | 99% | 0.02 s | 0.07 s | 0.14 s | 0.00 s | 83 MB | 207 MB |
| 2 | 2.94 s | 1.17 | 1.89× | 94% | 0.05 s | 0.06 s | 0.08 s | 0.01 s | 83 MB | 290 MB |
| 3 | 2.19 s | 0.13 | 2.54× | 85% | 0.12 s | 0.05 s | 0.05 s | 0.02 s | 83 MB | 374 MB |
| 4 | 1.84 s | 0.30 | 3.03× | 76% | 0.11 s | 0.05 s | 0.05 s | 0.01 s | 83 MB | 457 MB |
| 6* | 2.38 s | 0.95 | 2.33× | 39% | 0.19 s | 0.06 s | 0.07 s | 0.06 s | 83 MB | 625 MB |
| 8* | 1.72 s | 0.33 | 3.23× | 40% | 0.20 s | 0.06 s | 0.06 s | 0.09 s | 84 MB | 800 MB |
| 10* | 1.92 s | 0.89 | 2.90× | 29% | 0.33 s | 0.07 s | 0.06 s | 0.26 s | 83 MB | 959 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0266, κ = 0.02031, rms residual 0.013, throughput peaks at p ≈ 6.9

USL over all p: σ = 0.1256, κ = 0.01453, rms residual 0.318 — **not a usable fit** (negative parameter or residual > 0.1)


## 12 tolerances (531441 corners)

**Sequential:** median 71.55 s (spread 3.92 s over 3 runs); GC 1.8%; per item mean 135 µs, CV 3.70; peak RSS 138 MB.

### Dynamic scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 74.68 s | 7.90 | 0.96× | 96% | 0.06 s | 0.61 s | 1.57 s | 0.00 s | 156 MB | 358 MB |
| 2 | 40.17 s | 8.38 | 1.78× | 89% | 0.14 s | 0.62 s | 0.85 s | 0.00 s | 156 MB | 513 MB |
| 3 | 28.36 s | 1.29 | 2.52× | 84% | 0.20 s | 0.63 s | 0.60 s | 0.00 s | 156 MB | 664 MB |
| 4 | 25.68 s | 8.38 | 2.79× | 70% | 0.33 s | 0.64 s | 0.60 s | 0.00 s | 156 MB | 818 MB |
| 6* | 20.61 s | 1.61 | 3.47× | 58% | 0.44 s | 0.64 s | 0.53 s | 0.00 s | 156 MB | 1162 MB |
| 8* | 21.11 s | 3.33 | 3.39× | 42% | 0.55 s | 0.73 s | 0.55 s | 0.00 s | 156 MB | 1441 MB |
| 10* | 19.52 s | 2.06 | 3.67× | 37% | 0.66 s | 0.61 s | 0.56 s | 0.01 s | 156 MB | 1756 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0296, κ = 0.02789, rms residual 0.055, throughput peaks at p ≈ 5.9

USL over all p: σ = 0.0973, κ = 0.01005, rms residual 0.100 — **not a usable fit** (negative parameter or residual > 0.1)

### Static scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 71.61 s | 1.11 | 1.00× | 100% | 0.03 s | 0.61 s | 1.38 s | 0.00 s | 156 MB | 356 MB |
| 2 | 37.41 s | 1.59 | 1.91× | 96% | 0.13 s | 0.59 s | 0.74 s | 0.00 s | 156 MB | 513 MB |
| 3 | 28.14 s | 1.66 | 2.54× | 85% | 0.24 s | 0.61 s | 0.64 s | 0.13 s | 156 MB | 663 MB |
| 4 | 23.51 s | 1.70 | 3.04× | 76% | 0.32 s | 0.60 s | 0.55 s | 0.10 s | 156 MB | 818 MB |
| 6* | 19.70 s | 4.34 | 3.63× | 61% | 0.37 s | 0.63 s | 0.50 s | 0.27 s | 156 MB | 1168 MB |
| 8* | 17.68 s | 3.72 | 4.05× | 51% | 0.62 s | 0.61 s | 0.46 s | 0.23 s | 156 MB | 1441 MB |
| 10* | 16.76 s | 4.92 | 4.27× | 43% | 0.82 s | 0.62 s | 0.45 s | 0.72 s | 156 MB | 1754 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0129, κ = 0.02339, rms residual 0.020, throughput peaks at p ≈ 6.5

USL over all p: σ = 0.0810, κ = 0.00703, rms residual 0.053, throughput peaks at p ≈ 11.4

