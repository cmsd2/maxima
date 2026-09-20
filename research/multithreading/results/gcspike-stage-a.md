# GC spike, stage A: calibration

Gate A of `add-thread-feasibility-spikes`. The spike measures whether
stop-the-world collection scales when several threads allocate at the
workload's rate. Stage A establishes what that rate is, and tunes a
synthetic allocator to reproduce it.

Data: `gcref.jsonl` (reference), `gccal.jsonl` (calibration).
Tools: `tools/gcspike.lisp`, `tools/gcref.sh`, `tools/gccal.sh`.
Machine: Apple M4, 4P+6E cores, 32 GB; SBCL 2.6.5-85913ede1; on battery at
80–75%; total CPU below 130% of one core before each run.

## Collector in force

```
gencgc, mark-region nil, gc-parallel nil, sb-thread present
nursery 53,687,091 bytes; gcs-before-promotion (1 1 1)
```

One thread collects while the others stop, and there is no parallel
marking. This is the configuration the spike exists to test.

## Task 1.1: the reference profile

`wc_systematic`'s loop body over the voltage-divider chain, two sizes, two
runs each:

| Run | Wall | Consed | Rate | Collections | GC share | Mean pause | Max pause | Survival |
|---|---|---|---|---|---|---|---|---|
| wc10-r1 | 5.08 s | 4.0 GB | 0.781 GB/s | 80 | 1.24% | 0.79 ms | 0.90 ms | 0.038% |
| wc10-r2 | 5.10 s | 4.0 GB | 0.778 GB/s | 80 | 1.23% | 0.79 ms | 0.88 ms | 0.038% |
| wc12-r1 | 64.65 s | 48.1 GB | 0.744 GB/s | 960 | 1.32% | 0.89 ms | 2.28 ms | 0.047% |
| wc12-r2 | 64.89 s | 48.1 GB | 0.741 GB/s | 959 | 1.34% | 0.91 ms | 2.58 ms | 0.047% |

Repeats agree to within 1%. Three findings shape the allocator:

- **Collection is nursery-bound.** 20 collections per GB consed, which is
  the 53.7 MB nursery. Aggregate allocation rate therefore sets collection
  frequency directly: four threads at this rate would collect four times as
  often.
- **Almost nothing survives.** 0.04% of consed bytes promote out of the
  nursery, and the live heap is flat across the run (61.47 MB before and
  after). The workload's garbage is ephemeral.
- **Pauses are short and uniform.** 0.8–0.9 ms mean, 2.6 ms worst. At *p* =
  1 they cost 1.2–1.3% of run time.

`sb-ext:generation-number-of-gcs` resets when its generation is collected,
so it under-counts badly (it reported 1 collection for a run that had 960).
Collections are counted in an `sb-ext:*after-gc-hooks*` hook instead, which
also samples `sb-ext:generation-bytes-allocated`; rises in generation 1 are
the promoted bytes.

## Tasks 1.2 and 1.3: the allocator and its calibration

The loop builds a small tree shaped like a simplified Maxima expression (a
header list, then 3 arguments, nested 2 deep: 896 bytes, 13 nodes), walks
it, and drops it. One node in 512 is held in a 4096-entry ring, so it is
live at the next collection.

```
:depth 2 :width 3 :walks 9 :retain-every 512 :ring-size 4096
```

| | Reference (wc12) | Calibrated | Ratio |
|---|---|---|---|
| Allocation rate | 0.74 GB/s | 0.78 GB/s | 1.05 |
| Collections per GB | 20 | 20 | 1.00 |
| GC share at *p* = 1 | 1.33% | 1.17% | 0.88 |
| Mean pause | 0.90 ms | 0.75 ms | 0.83 |
| Max pause | 2.6 ms | 3.5 ms | 1.3 |
| Survival | 0.047% | 0.25% | 5.4 |

Rate, collection frequency and GC share match. Survival does not, and the
two cannot be matched at once:

- Promotion has a floor of about 31 KB per collection from page
  granularity. Measured with retention switched off entirely, the allocator
  still promoted 1.32 MB over 42 collections, above the workload's 24 KB per
  collection. Survival cannot be tuned below the workload's value.
- Reaching the workload's 0.9 ms pause needs a multi-megabyte live ring. The
  workload gets its pause length from a 61 MB live heap with few survivors;
  the allocator has to buy the same tracing cost with survivors.

Matching GC cost was preferred over matching survival, because pause length
is what stops threads. The survival-matched alternative
(`:retain-every 32768 :ring-size 64`: survival 0.069%, pause 0.64 ms, GC
0.99%) is recorded as `cal-sensitivity` and runs in stage B as a
sensitivity check.

Repeats: 0.781 and 0.783 GB/s, GC 1.17% both, identical checksum
(5184002592000001 at 8,000,000 iterations), so the arms in stage B can
cross-check their results against a single expected value.

## Gate A verdict

Calibration target was the measured rate within 20%. Achieved 5%, with
collection frequency and GC share matching too. Stage B can proceed.

Two limits to carry into the decision record:

- Survival is 5× the workload's, which makes each collection slightly more
  expensive than the real thing. Both arms run the same loop, so neither is
  favoured, but the thread arm's stalls are marginally overstated. A pass
  under this bias is a real pass; a borderline fail should be re-checked
  against the sensitivity config.
- A synthetic allocator cannot reproduce the locality of the real
  expression graph.
