# Multi-threading in Maxima: the process-pool baseline

This document reports the OpenSpec change `add-process-pool-benchmark`:
how `wc_systematic` scales when its corners are spread over forked worker
processes. Any future thread mode has to beat this, not a sequential run
(doc 02). **There is no thread arm.** The symbolic loop body can't run
correctly on threads until the stage F fixes from doc 05 (binding rebuilt
on `progv`, per-query fact labels) exist.

Data: `research/multithreading/results/pool-quiet.jsonl` (the quiet sweep
these numbers come from), `results/pool-final.jsonl` and
`results/pool-sweep-original.jsonl` (earlier, noisier sweeps, kept as the
record), full report `results/pool-report.md`, stage notes
`results/pool-stage-*.md`.
Tools: `tools/pool.lisp`, `tools/pool-bench.sh`, `tools/pool_report.py`.

## Setup

- **Machine:** Apple M4, 4 performance and 6 efficiency cores, 32 GB; SBCL
  2.6.5; on battery at 90–98% throughout (matching the earlier runs). The
  headline numbers come from a sweep run on a quiet machine: about 1.5 of 10
  cores busy with the desktop session before it started, nothing else
  running. Earlier sweeps were disturbed (see Reliability).
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

| Tolerances | Corners | Median (spread) | Per item | GC share | Peak RSS |
|---|---|---|---|---|---|
| 10 | 59,049 | 4.97 s (0.01 s) | 84 µs | 1.6% | 129 MB |
| 12 | 531,441 | 63.19 s (1.06 s) | 119 µs | 1.5% | 181 MB |

Items are fine-grained, about 0.1 ms. Per-item times vary (CV about 0.5),
which comes from GC pauses landing on single items rather than from the
work. On the noisy sweeps this CV reached 3.7.

**Speedup over sequential (median of three rounds, quiet machine):**

| Workers | 10 tol., static | 10 tol., dynamic | 12 tol., static | 12 tol., dynamic |
|---|---|---|---|---|
| 1 | 0.96× | 0.92× | 0.98× | 0.93× |
| 2 | 1.76× | 1.65× | 1.82× | 1.72× |
| 3 | 2.36× | 2.36× | 2.61× | 2.59× |
| **4** | **3.42×** | **2.99×** | **3.35×** | **3.20×** |
| 6 | 3.35× | 3.35× | 3.86× | 3.88× |
| 8 | 3.77× | 3.82× | 4.40× | 4.51× |
| 10 | 4.18× | 4.11× | **4.99×** | 4.95× |

Run-to-run spreads are 0 to 9% of the median, so the curve is now monotone
in the worker count; on the noisy sweeps spreads reached 51% and the curve
was not.

Efficiency at 4 workers is 80–85%, falling to about 50% at 10 workers as
the extra workers run on the slower efficiency cores.

**Overheads** (12 tolerances, 10 workers):

| Overhead | Time |
|---|---|
| Forking all workers (serialised) | 0.26 s |
| Parent reading 531,441 results | 0.55 s |
| Each worker printing its results | 0.22 s |
| **Total** | **about 1.0 s of a 12.7 s run (≈ 8%)** |

At one worker the pool costs about 1.5 s (2%) over sequential, for printing
and reading results.

**Memory:** each worker's peak RSS is 156 MB (12 tolerances) or 83 MB (10
tolerances). The sum over 10 workers plus the parent is 1.8 GB. That sum is
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

**Universal Scalability Law, 12 tolerances.** Capacity is measured against
the pool's own one-worker time, since the law assumes C(1) = 1; the speedup
table above stays relative to the sequential run.

| Range | Mode | σ | κ | Residual |
|---|---|---|---|---|
| *p* ≤ 4 | static | 0.059 | 0 (constrained) | 0.022 |
| *p* ≤ 4 | dynamic | 0.053 | 0 (constrained) | 0.046 |
| all *p* | dynamic | 0.049 | 0.0052 | 0.090, peak near 13.5 workers |
| all *p* | static | 0.065 | 0.0047 | 0.130 — not usable |

Two notes on the fits. An unconstrained fit put κ slightly **below zero** on
the performance cores, which is physically meaningless: there is no
measurable cross-worker cost in that range. Constraining κ to 0 reduces the
model to Amdahl's law and fits well, giving a serial fraction of about 5–6%.
Over the full curve the model fits only loosely, because the machine has two
kinds of core: one σ cannot describe 4 fast and 6 slow workers at once.

## Reliability

- **The headline numbers come from a quiet machine** (about 1.5 of 10 cores
  busy with the desktop session, nothing else running, on battery). Spreads
  are 0–9% of the median and the curve is monotone.
- **Earlier sweeps were disturbed and read differently.** With a load average
  of 6–11 (Steam, backup software, cloud file sync), the same configurations
  gave 3.04× at 4 workers and 4.27× at 10 (12 tolerances, static), against
  3.35× and 4.99× when quiet, and the 10-tolerance curve was not even
  monotone. The sequential baseline itself was 13% slower (71.6 s against
  63.2 s).
- **Reproducibility on the disturbed machine was poor:** a rerun of
  sequential, *p* = 4 and *p* = 10 agreed within spread only on the second
  attempt, and the *p* = 10 median moved by about ±8% between measurements.
  Those runs are kept in `results/pool-repro-{1,2}.jsonl` and the disturbed
  sweeps in `results/pool-final.jsonl` and
  `results/pool-sweep-original.jsonl`.
- **Lesson for later benchmarks:** the machine's load average is not a usable
  idleness test here (it sits near 4 while only 1.5 of 10 cores are busy).
  Total CPU across all processes is. Every measurement now records the load
  average, power source and battery level.

## What this means for the thread decision

A thread mode for this workload has to beat about **3.4× on the 4
performance cores** and about **5× on all 10 cores**, at a memory cost of
about 156 MB per worker. The following
bear on whether it can:

- **GC won't stop threads:** at a 1.5% GC share, doc 02's GC-only ceiling
  is about 65×. For this workload, contention on shared structure and
  memory bandwidth decide, not GC.
- **Processes pay about 8% overhead at 10 workers** (fork plus result
  transfer), and about 2% at one worker. Threads would avoid most of it, since results need no
  serialization and no fork is needed. That is the margin threads could
  gain, and it would be eaten by any locking the T2/T3 fixes add.
- **The process pool needed no changes to Maxima,** and it already works
  with `wrstcse` as shipped (the corner-counter change isn't needed for
  processes). For this workload, processes are the practical answer today.
- **The mailing list's 3.8× on 4 cores** is consistent with these
  measurements. We get 3.4× on this machine's 4 performance cores, with
  fine-grained items and fork overhead included, and the Amdahl fit puts the
  serial fraction at about 5–6%.
