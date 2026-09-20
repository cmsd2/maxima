# Multi-threading in Maxima: the process-pool baseline

This document reports the OpenSpec change `add-process-pool-benchmark`:
how `wc_systematic` scales when its corners are spread over forked worker
processes. Any future thread mode has to beat this, not a sequential run
(doc 02). **There is no thread arm.** The symbolic loop body can't run
correctly on threads until the stage F fixes from doc 05 (binding rebuilt
on `progv`, per-query fact labels) exist.

Data: `research/multithreading/results/pool-final.jsonl` (compact records),
full report `results/pool-report.md`, stage notes `results/pool-stage-*.md`.
Tools: `tools/pool.lisp`, `tools/pool-bench.sh`, `tools/pool_report.py`.

## Setup

- **Machine:** Apple M4, 4 performance and 6 efficiency cores, 32 GB; SBCL
  2.6.5. The machine **wasn't idle**: the load average was 6–11 throughout,
  from the desktop session (WindowServer, `syspolicyd`, other applications).
- **Workload:** `wc_systematic` on a voltage-divider chain with 10 and 12
  resistor tolerances (59,049 and 531,441 corners), symbolic `U_In`.
  `wc_item(i)` computes corner *i* exactly as `wc_systematic`'s outer
  `makelist` does; results match `wc_systematic` exactly.
- **Pool:** forks workers from the loaded image. Scheduling is dynamic (a
  shared pipe of index tokens, written after all workers are forked) or
  static (worker *k* takes indices ≡ *k* mod *p*). Results come back as
  re-readable forms in one file per worker and are checked element by
  element against the sequential results.
- **Method:** one fresh Maxima process per measurement; a discarded warm-up
  round, then three rounds with the configuration order rotated.

## Results

**Correctness:** 168 of 168 pooled runs matched the sequential results
exactly (112 in the sweep, 56 in the 10-tolerance rerun), plus 18 of 18 in
the two reproducibility reruns. A planted wrong value was caught at the right
index. Side effects in workers (a global, a function definition) never
reached the parent.

**Sequential baseline:**

| Tolerances | Corners | Median | Per item | GC share | Peak RSS |
|---|---|---|---|---|---|
| 10 | 59,049 | 5.56 s | 94 µs | 1.7% | 129 MB |
| 12 | 531,441 | 71.55 s | 135 µs | 1.8% | 138 MB |

Items are fine-grained, about 0.1 ms. Per-item times vary a lot (CV up to
3.7), but that comes from GC pauses landing on single items, not from the
work.

**Speedup over sequential (median of three rounds):**

| Workers | 10 tol., static | 10 tol., dynamic | 12 tol., static | 12 tol., dynamic |
|---|---|---|---|---|
| 1 | 0.99× | 0.95× | 1.00× | 0.96× |
| 2 | 1.89× | 1.65× | 1.91× | 1.78× |
| 3 | 2.54× | 2.32× | 2.54× | 2.52× |
| **4** | **3.03×** | **3.02×** | **3.04×** | **2.79×** |
| 6 | 2.33× | 2.75× | 3.63× | 3.47× |
| 8 | 3.23× | 2.50× | 4.05× | 3.39× |
| 10 | 2.90× | 3.35× | **4.27×** | 3.67× |

Efficiency at 4 workers is 70–76%. Beyond the 4 performance cores, extra
workers run on efficiency cores and compete with the background load.

**Overheads** (12 tolerances, 10 workers):

| Overhead | Time |
|---|---|
| Forking all workers (serialised) | 0.66 s |
| Parent reading 531,441 results | 0.61 s |
| Each worker printing its results | 0.56 s |
| **Total** | **about 1.8 s of a 19.5 s run (≈ 9%)** |

At one worker, the pool costs about 3 s (4%) over sequential for result
printing and reading.

**Memory:** each worker's peak RSS is 156 MB (12 tolerances) or 83 MB (10
tolerances). The sum over 10 workers plus the parent is 1.75 GB. That sum is
an **upper bound**, because pages shared with the parent after fork are
counted in every worker. Heap growth measured with `dynamic-usage` is not a
usable estimate of private memory: a GC in a worker can make it negative.
Even the upper bound is far below the 8 GB machine the mailing list worried
about.

**Scheduling:** static beats dynamic here. Static workers start computing
as they are forked. Dynamic workers wait until the parent has forked them
all and written the tokens, so dynamic loses the overlap with fork time
(0.3–0.8 s). Item costs are uniform enough that dynamic balancing buys
nothing.

**Universal Scalability Law, 12 tolerances:**

| Range | Mode | σ | κ | Residual | Peak |
|---|---|---|---|---|---|
| *p* ≤ 4 | static | 0.013 | 0.023 | 0.020 | about 6.5 workers |
| *p* ≤ 4 | dynamic | 0.030 | 0.028 | 0.055 | about 5.9 workers |
| all *p* | static | 0.081 | 0.007 | 0.053 | about 11.4 workers |

The 10-tolerance fits over the full curve are not usable (residual about
0.32): runs of about 2 s don't average out the background load.

## Reliability

- **Up to 4 workers the numbers are consistent.** Both workload sizes give
  about 3.0× at 4 workers, and the static spreads are small.
- **Above 4 workers they reproduce only loosely.** Two reruns of
  sequential, *p* = 4 and *p* = 10 (dynamic, 12 tolerances) were made:

  | Configuration | Sweep | Rerun 1 (load 8–10) | Rerun 2 (load 4 at start) |
  |---|---|---|---|
  | Sequential | 71.55 s | 70.49 s | 69.90 s |
  | *p* = 4 | 25.68 s | 23.62 s | 23.90 s |
  | *p* = 10 | 19.52 s | 16.85 s | 18.64 s |

  Rerun 1 failed the spec's criterion at *p* = 10 (outside the 2.06 s
  spread); rerun 2 met it for all three. The pass partly reflects wide
  spreads (one 78.3 s sequential run gave a 9.1 s spread). Across the three
  measurements the *p* = 10 median varies by about ±8%, and the dynamic
  *p* = 4 spreads reached 8–10 s.
- **The disturbed first 10-tolerance sweep is kept** in
  `results/pool-sweep-original.jsonl`. One round was 60–160% slower
  throughout; the 10-tolerance numbers above come from a full rerun.

Treat the curve above 4 workers as indicative, roughly 3.5–4.3× (±8%). A
quieter machine would narrow it.

## What this means for the thread decision

A thread mode for this workload has to beat about **3× on the 4
performance cores**, and about **4× on all 10 cores** where that is
measurable, at a memory cost of 150 MB or less per worker. The following
bear on whether it can:

- **GC won't stop threads:** at a 1.8% GC share, doc 02's GC-only ceiling
  is about 55×. For this workload, contention on shared structure and
  memory bandwidth decide, not GC.
- **Processes pay about 9% overhead at 10 workers** (fork plus result
  transfer). Threads would avoid most of it, since results need no
  serialization and no fork is needed. That is the margin threads could
  gain, and it would be eaten by any locking the T2/T3 fixes add.
- **The process pool needed no changes to Maxima,** and it already works
  with `wrstcse` as shipped (the corner-counter change isn't needed for
  processes). For this workload, processes are the practical answer today.
- **The mailing list's 3.8× on 4 cores** is consistent with these
  measurements. We get 3.0× on this machine's 4 performance cores, with
  fine-grained items and fork overhead included.
