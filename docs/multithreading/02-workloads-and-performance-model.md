# Multi-threading in Maxima: workloads and a performance model

This document sets Maxima's internals aside. It asks which workloads might
benefit from parallelism, what limits them, and how to decide where effort
pays off. The mailing-list background is in
[01-mailing-list-discussion.md](01-mailing-list-discussion.md).

Most of this is analysis; the numbers in the examples are illustrations,
not results. The model's parameters for `wc_systematic` were later measured
by the process-pool benchmark: see "Measured parameters" at the end and
[07-process-pool-baseline.md](07-process-pool-baseline.md).

## Candidate workloads

The discussion named four kinds of workload. They parallelise differently.

| Workload | Example from the thread | Shape | Naturally parallel? |
|---|---|---|---|
| Parameter sweep | `wc_systematic` corners, Monte Carlo, Michel's `partfrac` over `i` | A map over N independent inputs, sometimes with a min/max reduction at the end | Yes. Textbook embarrassingly parallel. |
| Algorithm-internal | Poisson-series products (Fateman), truncated polynomial multiplication (Butler), modular GCD over several primes, matrix work | Fine-grained data parallelism inside one operation | Partly. Dense arrays parallelise; linked sparse lists don't. |
| Speculative / portfolio | Macrakis: try several algorithms, keep whichever finishes first | A few tasks racing for the lowest latency | Yes, but the gain depends on how much the algorithms' run times vary. Throughput doesn't improve. |
| Search | Breadth-first search over integration rewrites (Scherfgen), Rubi | Irregular task graph with a shared visited set | Only loosely. Synchronising the shared set and balancing the load dominate. |

Only the parameter sweep has a real user behind it (Gunter's `wrstcse`
worksheets). The others are research directions.

## Where the bottleneck sits

### Hidden serial fractions

A sweep's visible serial part (setup, then merging results) is tiny, so
Amdahl's law predicts near-linear speedup. The limits come from serial
fractions hidden in the runtime.

1. **Garbage collection.** Symbolic computation allocates constantly: every
   `subst` and simplification conses fresh list structure. SBCL's default
   collector stops every thread and then collects with one thread. More
   workers means more allocation per second and more frequent pauses, and
   during each pause one core works. For allocation-heavy work, GC time is
   the effective serial fraction. It may explain David's result, where the
   threaded `partfrac` ran more than 10× slower even with one thread, though
   he attributed it to merging result lists.
2. **Memory bandwidth and cache.** Pointer-chasing through cons cells is
   latency-bound. Several cores walking separate expression trees compete
   for the shared L3 cache and DRAM. Gunter's linear scaling on 4 cores
   suggests his working set fits in cache; that may not hold at 16 cores or
   on larger expressions.
3. **Load imbalance.** Symbolic cost varies enormously between inputs: one
   corner simplifies instantly while another triggers expression swell. With
   static chunking (`distribute_over_tranches` splits the range into fixed
   tranches), the slowest tranche sets the finish time. Dynamic scheduling
   (a work queue with small chunks) is the standard fix.
4. **Memory capacity.** N workers need N times the live working set.
   Expression swell usually ends a symbolic run by exhausting memory before
   CPU time matters, and parallelism brings that point closer.
5. **Serialised shared state.** Any lock around the fact database becomes a
   true Amdahl serial section on every `sign` call.

### Choice of law

Gustafson's law describes sweeps better than Amdahl's: users grow the problem
to fill the machine rather than finishing a fixed problem faster. For search,
the usual model is work and span (Brent's theorem). There, speedup is limited
by the critical-path length and by contention on the shared visited set.

### Exponential work against linear speedup

`wc_systematic` evaluates `k^t` corners: `k` values per tolerance over `t`
tolerances, with `k = 3` by default. A p-fold speedup buys only `log_k(p)`
extra tolerances:

| Workers | Speedup (ideal) | Extra tolerances at k = 3 |
|---|---|---|
| 4 | 4× | 1.26 |
| 8 | 8× | 1.89 |
| 16 | 16× | 2.52 |

Adding one tolerance triples the run time. Parallelism is a constant-factor
patch on an algorithmic problem.

## The classic approach, in order

1. **Profile first.** Find where time actually goes: simplification, `sign`,
   GC, or printing. Unintended symbolic evaluation is a common cause (Chris
   D.'s example in the June thread).
2. **Fix the algorithm.** Worst-case analysis has standard techniques that
   avoid enumerating corners:
   - **Monotonicity.** If the expression is monotone in each tolerance (the
     sign of the partial derivative), the extremes need 2 evaluations, not
     `k^t`.
   - **Interval arithmetic.** Bound the result in one pass.
   - **Sensitivity analysis**, as a first-order approximation.

   `wrstcse` already has `wc_ewc_optimize` in this spirit, and Gunter reports
   it cutting hours to minutes.
3. **Move invariant symbolic work out of the loop (staging, or partial
   evaluation).** Each corner runs `subst` and simplifies the same
   expression with different numbers. When the substituted result is
   numeric, compile the expression once (`compile`, `translate`,
   `coerce_float_fun`) and evaluate it as plain floats. This is often 100×
   to 1000× faster than repeated simplification. The resulting loop body
   never touches the simplifier, so it is thread-safe and allocates little.
4. **Coarse-grained process farm** for whatever remains independent: a task
   queue with dynamic scheduling and a cheap reduction (keep the min/max,
   not every result).
5. **Shared-memory threads last**, and only for algorithm-internal
   parallelism. There the standard answer is native code built for the job:
   FLINT for multi-threaded polynomial arithmetic and modular methods, BLAS
   and LAPACK for dense linear algebra. Those threads never see Lisp
   objects.

### Processes may beat threads

Independent processes collect garbage independently and in parallel, while a
threaded SBCL image stops every thread for each collection. For
allocation-heavy work that is the main scaling limit, and processes remove it
without changing Maxima.

Gunter's objection is memory: several heaps won't fit in 8 GB. This needs
measuring before it is accepted:

- **The heap cap isn't resident memory.** SBCL's `--dynamic-space-size`
  reserves address space; resident memory grows with what the worker uses.
- **`fork` shares the loaded image.** Workers share the core image's pages
  copy-on-write, so each doesn't pay the full cost.

Peak RSS of a real process farm on `wc_systematic` would settle it.

## Performance model

A first-order model with about five measured numbers is enough to rank the
options. All but one come from a single-threaded run.

### Model

For a sweep of N independent items on p workers:

```
T(p) ≈ T_setup + (N · w) / p + G(p) + I(p) + T_merge
```

`G(p)` is GC time and `I(p)` is time lost to load imbalance.

| Parameter | Meaning | How to measure (p = 1) |
|---|---|---|
| N | Number of items (`k^t` corners for `wc_systematic`) | Known in advance |
| w | Time per item excluding GC | (total run time − GC time) / N |
| f_gc | 1.5-1.6% | the GC-only ceiling 1/f_gc ≈ 65× is an overestimate: see below |
| CV | Per-item cost variation (standard deviation / mean) | Time each item inside the loop body |
| r | Speedup from compiling once and evaluating numerically | Time one item symbolically and compiled |

**Threads.** With a stop-the-world collector that runs on one core, GC does
not shrink as p grows, so it is the serial fraction. Amdahl gives the
ceiling directly:

```
S_threads(p) ≤ 1 / (f_gc + (1 − f_gc) / p)
```

| f_gc | Ceiling at p = 4 | Ceiling at p = 16 |
|---|---|---|
| 0.1 | 3.1× | 6.4× |
| 0.3 | 2.1× | 2.9× |
| 0.5 | 1.6× | 1.9× |

This is an upper bound: collections also get more frequent as more threads
allocate at once. A single-threaded run with 30% GC means threads can't do
much better than about 2× to 3×, whatever happens to Maxima's global state.

**Processes.** Each process collects its own heap, so GC runs in parallel
too:

```
T_proc(p) ≈ p · T_start + N · w_total / p + I(p) + T_serialise
```

`w_total` includes GC. The costs move to process start-up (small with
`fork`) and serialising results back to the parent.

**Load imbalance.** With dynamic scheduling, the finish time is roughly the
ideal time plus the slowest single item. With static tranches it is the
slowest tranche. Below a CV of about 0.5 imbalance can be ignored; above
about 2 it dominates at high p.

### Levers compared

| Lever | Term it reduces | Typical reach |
|---|---|---|
| Algorithm (monotonicity, intervals) | N: `k^t` becomes something like `2t` | Orders of magnitude for exponential N |
| Staging (compile once) | w divided by r; f_gc falls because numeric evaluation barely allocates | 10× to 1000× |
| Processes | Divides by p, losing start-up and imbalance | About p |
| Threads | Divides by p, capped by f_gc | 1 / f_gc at most |

Rank them by gain per unit of effort. Threads come last unless f_gc is small
and N and w can't be reduced another way.

### Refinement: Universal Scalability Law

The first-order model leaves out memory-bandwidth and cache contention.
Gunther's Universal Scalability Law captures both:

```
C(p) = p / (1 + σ(p − 1) + κ·p(p − 1))
```

σ is contention (serialisation) and κ is coherency cost (cross-core
traffic). Fit both from throughput at p = 1, 2, 4 and 8. A nonzero κ means
throughput peaks and then falls as p grows. Report this curve instead of a
single speedup ratio.

## Measurement plan

1. Build this worktree with SBCL.
2. Pick `wc_systematic` inputs with t = 6, 8 and 10 tolerances, so run times
   span seconds to minutes.
3. At p = 1, record wall time, GC time, bytes consed and per-item times.
   That gives w, f_gc and CV.
4. Time one item symbolically and compiled. That gives r.
5. Run a process farm (`distribute_over_tranches`) at p = 1, 2, 4 and 8.
   Record wall time and peak RSS per worker, and fit the USL.
6. Compare the predicted thread ceiling (from f_gc) with the process-farm
   curve. If the process farm already beats the thread ceiling, the
   threading question is closed for this workload.

## Measured parameters (added after the process-pool benchmark)

The process-pool benchmark (doc 07) measured the model's parameters for
`wc_systematic` on a voltage-divider chain (10 and 12 tolerances, Apple M4
with 4 performance and 6 efficiency cores, quiet machine, on battery).
Data: `research/multithreading/results/pool-quiet.jsonl`.

| Parameter | Measured | Note |
|---|---|---|
| w (per item, excluding GC) | 84–119 µs | grows with expression size; items are fine-grained |
| f_gc | 1.5–1.6% | GC-only thread ceiling 1/f_gc ≈ 65×: GC does not limit this workload |
| CV of item time | about 0.5 | GC pauses on single items, not work variation (it read up to 3.7 on a disturbed machine) |
| r (staging gain) | not measured | outside this benchmark's scope |
| Fork cost | 20–26 ms per worker, serialised | 0.26 s for 10 workers |
| Result transfer | 0.55 s read by the parent, 0.22 s written per worker, for 531,441 results | about 1 µs per result each way |
| Memory per worker | 83–156 MB peak RSS (upper bound, includes shared pages) | the 8 GB concern does not arise at this size |
| Serial fraction σ (Amdahl, *p* ≤ 4) | 0.053–0.059 | κ constrained to 0: no measurable coherency cost on the performance cores |
| USL over all *p* (dynamic) | σ = 0.049, κ = 0.0052 | fits only loosely: the machine has two kinds of core |

**The thread ceiling above is too generous.** `S_threads(p) ≤ 1 / (f_gc +
(1 − f_gc) / p)` assumes GC cost per byte does not change as threads are
added. Spike A
([08-thread-feasibility-spikes.md](08-thread-feasibility-spikes.md))
measured threads collecting more often than processes for the same bytes
(the nursery trigger is image-wide, so the interval falls from 51 MB at one
thread to 34 MB at eight) and promoting more each time. A thread at four
workers spends 6.8% of its wall time halted where a process worker spends
1.5%, against the 1.5% this table's f_gc would predict for both. Threads
still scaled to 91% efficiency on four cores, so the conclusion holds and
the bound does not.

Measured process speedup is **3.35× at 4 workers** and **4.99× at 10** (12
tolerances, static). Efficiency is 80–85% on the performance cores and about
50% once the efficiency cores are in use. The exponential-work argument
above still dominates: on this curve, 10 workers buy log₃(5.0) ≈ 1.5 extra
tolerances.
