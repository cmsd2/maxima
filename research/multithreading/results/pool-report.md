# Process-pool baseline for wc_systematic

Machine: Apple M4, 4P+6E cores, 32 GB; SBCL 2.6.5-85913ede1; commit 4678082a9.

Records: 120 total, 30 warm-up (ignored), 90 timed, 0 failed correctness.

There is no thread arm: the symbolic loop body can't run correctly on threads until the stage F fixes (binding on progv, per-query fact labels) exist.


## 10 tolerances (59049 corners)

**Sequential:** median 4.97 s (spread 0.01 s over 3 runs); GC 1.6%; per item mean 84 µs, CV 0.46; peak RSS 129 MB.

### Dynamic scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5.43 s | 0.01 | 0.92× | 92% | 0.02 s | 0.05 s | 0.13 s | 0.00 s | 83 MB | 206 MB |
| 2 | 3.02 s | 0.09 | 1.65× | 82% | 0.03 s | 0.05 s | 0.07 s | 0.00 s | 83 MB | 290 MB |
| 3 | 2.10 s | 0.01 | 2.36× | 79% | 0.05 s | 0.05 s | 0.05 s | 0.00 s | 83 MB | 373 MB |
| 4 | 1.66 s | 0.04 | 2.99× | 75% | 0.06 s | 0.05 s | 0.04 s | 0.00 s | 83 MB | 457 MB |
| 6* | 1.49 s | 0.05 | 3.35× | 56% | 0.10 s | 0.05 s | 0.03 s | 0.00 s | 83 MB | 624 MB |
| 8* | 1.30 s | 0.05 | 3.82× | 48% | 0.14 s | 0.05 s | 0.03 s | 0.00 s | 83 MB | 791 MB |
| 10* | 1.21 s | 0.07 | 4.11× | 41% | 0.16 s | 0.05 s | 0.02 s | 0.00 s | 83 MB | 958 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0792, κ = 0.00000 (κ constrained to 0: Amdahl), rms residual 0.034

USL over all p: σ = 0.0779, κ = 0.00615, rms residual 0.108 — **not a usable fit** (negative parameter or residual > 0.1)

### Static scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5.17 s | 0.01 | 0.96× | 96% | 0.02 s | 0.05 s | 0.12 s | 0.00 s | 83 MB | 206 MB |
| 2 | 2.83 s | 0.05 | 1.76× | 88% | 0.03 s | 0.05 s | 0.07 s | 0.08 s | 83 MB | 289 MB |
| 3 | 2.11 s | 0.11 | 2.36× | 79% | 0.05 s | 0.05 s | 0.05 s | 0.12 s | 84 MB | 377 MB |
| 4 | 1.45 s | 0.13 | 3.42× | 85% | 0.07 s | 0.05 s | 0.03 s | 0.04 s | 83 MB | 457 MB |
| 6* | 1.48 s | 0.09 | 3.35× | 56% | 0.12 s | 0.05 s | 0.03 s | 0.09 s | 83 MB | 623 MB |
| 8* | 1.32 s | 0.04 | 3.77× | 47% | 0.16 s | 0.05 s | 0.03 s | 0.06 s | 83 MB | 790 MB |
| 10* | 1.19 s | 0.03 | 4.18× | 42% | 0.20 s | 0.05 s | 0.02 s | 0.11 s | 83 MB | 957 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0652, κ = 0.00000 (κ constrained to 0: Amdahl), rms residual 0.147 — **not a usable fit** (negative parameter or residual > 0.1)

USL over all p: σ = 0.0793, κ = 0.00716, rms residual 0.233 — **not a usable fit** (negative parameter or residual > 0.1)


## 12 tolerances (531441 corners)

**Sequential:** median 63.19 s (spread 1.06 s over 3 runs); GC 1.5%; per item mean 119 µs, CV 0.51; peak RSS 181 MB.

### Dynamic scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 67.61 s | 0.04 | 0.93× | 93% | 0.02 s | 0.54 s | 1.11 s | 0.00 s | 167 MB | 419 MB |
| 2 | 36.78 s | 1.95 | 1.72× | 86% | 0.04 s | 0.54 s | 0.62 s | 0.00 s | 165 MB | 582 MB |
| 3 | 24.35 s | 0.55 | 2.59× | 86% | 0.06 s | 0.54 s | 0.41 s | 0.00 s | 156 MB | 716 MB |
| 4 | 19.71 s | 0.38 | 3.20× | 80% | 0.08 s | 0.54 s | 0.31 s | 0.00 s | 156 MB | 869 MB |
| 6* | 16.30 s | 1.43 | 3.88× | 65% | 0.12 s | 0.58 s | 0.28 s | 0.00 s | 156 MB | 1213 MB |
| 8* | 14.00 s | 0.39 | 4.51× | 56% | 0.16 s | 0.55 s | 0.24 s | 0.00 s | 156 MB | 1489 MB |
| 10* | 12.77 s | 0.50 | 4.95× | 49% | 0.22 s | 0.55 s | 0.23 s | 0.00 s | 156 MB | 1800 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0534, κ = 0.00000 (κ constrained to 0: Amdahl), rms residual 0.046

USL over all p: σ = 0.0488, κ = 0.00523, rms residual 0.090, throughput peaks at p ≈ 13.5

### Static scheduling

| Workers | Median wall | Spread | Speedup | Efficiency | Fork | Read | Write/worker | Busy spread | Peak RSS/worker | Sum RSS (upper bound) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 64.66 s | 0.17 | 0.98× | 98% | 0.02 s | 0.54 s | 1.10 s | 0.00 s | 164 MB | 416 MB |
| 2 | 34.75 s | 0.36 | 1.82× | 91% | 0.04 s | 0.55 s | 0.58 s | 0.04 s | 165 MB | 582 MB |
| 3 | 24.25 s | 0.84 | 2.61× | 87% | 0.07 s | 0.54 s | 0.41 s | 0.38 s | 156 MB | 716 MB |
| 4 | 18.85 s | 0.76 | 3.35× | 84% | 0.08 s | 0.54 s | 0.31 s | 0.38 s | 156 MB | 868 MB |
| 6* | 16.37 s | 0.63 | 3.86× | 64% | 0.15 s | 0.57 s | 0.27 s | 0.41 s | 156 MB | 1213 MB |
| 8* | 14.35 s | 0.28 | 4.40× | 55% | 0.20 s | 0.54 s | 0.24 s | 0.43 s | 156 MB | 1489 MB |
| 10* | 12.67 s | 0.37 | 4.99× | 50% | 0.26 s | 0.55 s | 0.22 s | 0.32 s | 156 MB | 1800 MB |

\* above the 4 performance cores. Fork: time to fork all workers, serialised in the parent. Read: parent reading and parsing results. Write: median per-worker time printing results. Sum RSS counts pages shared with the parent after fork in every worker, so it is an upper bound.

USL over p ≤ 4: σ = 0.0589, κ = 0.00000 (κ constrained to 0: Amdahl), rms residual 0.022

USL over all p: σ = 0.0648, κ = 0.00465, rms residual 0.130 — **not a usable fit** (negative parameter or residual > 0.1)

