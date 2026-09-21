# Multi-threading in Maxima: the feasibility spikes

Doc 05 found a frozen-environment thread mode **plausible** for
`wc_systematic`, given four contained fixes. Doc 07 measured what threads
would have to beat: a forked process pool reaching 3.35× on four
performance cores and 4.99× on ten, needing no changes to Maxima at all.

Two assumptions sat under the decision to start building, and neither had
been measured. This document reports the two spikes that measured them, and
the recommendation that follows. Neither spike changed a line of `src/`.

OpenSpec change: `add-thread-feasibility-spikes`. Stage reports:
`research/multithreading/results/gcspike-stage-a.md`, `gcspike-stage-b.md`,
`progv-stage-c.md`.

## The two questions

**Does garbage collection scale with threads?** SBCL 2.6.5 on this machine
uses `gencgc`: one thread collects while every other thread stops, with no
parallel marking (`:mark-region-gc` absent, `:gc-parallel` absent).
`wc_systematic` conses 48 GB in 63 s. If four threads allocating at that
rate serialise on collection, threads cannot beat processes, which collect
in parallel by construction.

Doc 07 said GC would not stop threads, reasoning from a 1.5% GC share to a
GC-only ceiling of 65×. That reasoning assumed the cost of collection per
byte stays constant as threads are added. It does not (see below), so the
question needed measuring rather than deriving.

**What does `progv` cost?** Step 1 of the threading path replaces `mbind`'s
global value-cell assignment with `progv`'s dynamic binding, on the
evaluator's hottest path. If that were 20% slower, step 1 would need a
different design.

## Spike A: garbage collection under threads

A synthetic allocator, calibrated against `wc_systematic`, runs in *p*
threads and in *p* forked processes from the same image. It builds small
tree structures shaped like simplified expressions, walks them and drops
them; pointer-rich garbage is what a symbolic run produces and what makes
marking expensive.

Calibration matched the measured workload on rate (0.78 GB/s against 0.74),
collection frequency (20 collections per GB in both) and GC share (1.17%
against 1.33%). It could not match survival as well: promotion has a floor
of about 31 KB per collection from page granularity, already above the
workload's 24 KB. GC cost was matched in preference, since pause length is
what stops threads, and the survival-matched configuration was kept as a
sensitivity check.

Work is fixed per worker, so this measures throughput: perfect scaling holds
wall time constant as workers are added.

| Workers | Threads | Processes | Ratio |
|---|---|---|---|
| 2 | 1.93× (96%) | 1.96× (98%) | 0.99 |
| **4** | **3.63× (91%)** | **3.85× (96%)** | **0.94** |
| 8 | 4.98× (62%) | 5.76× (72%) | 0.86 |

**Threads pay the collector twice, and both costs grow with the worker
count.** Processes collect every 51 MB consed whatever *p* is, because each
owns its heap. Threads share one nursery trigger, and the interval falls to
43.7 MB at four threads and 33.9 MB at eight: 1,981 collections against the
process arm's 1,320 for the same 65.6 GB. Promotion grows faster than
linearly too, 407 MB against 170 MB at eight workers, because more workers
have live structures in flight when the collector stops them. A thread at
four workers spends 6.8% of its time halted; a process worker spends 1.5%.

On the performance cores that is what separates the arms: collection
accounts for 72% of the thread arm's excess over ideal, and the residual
(0.29 s) matches the process arm's (0.27 s), which is memory bandwidth both
pay alike. Past four workers both arms lose far more to the efficiency cores
than to collection.

**Doc 07's claim was right in direction and wrong in mechanism.** GC does
not serialise these threads, but not because its cost per byte is fixed. It
rises with thread count, and the 65× ceiling derived from a single-threaded
GC share overstates the headroom.

## Spike B: the cost of `progv`

Four arms, binding the same symbols to the same values and running the same
body, at 1, 2, 5 and 10 variables per binding.

| Arm | Per binding | Bytes per binding |
|---|---|---|
| `mbind` + `munbind` (today) | 129 ns | 80 B |
| `mbind-doit` + `munbind` (no error wrapper) | 124 ns | 80 B |
| **`progv`** | **12 ns** | **0 B** |
| `raw` save-assign-restore | 34 ns | 16 B |

`progv` is about ten times cheaper than what Maxima does today and allocates
nothing. It beats even the bare save-assign-restore floor, because SBCL's
binding stack needs no list to record what to undo, where `mbind` conses two
cells per variable onto `bindlist` and `mspeclist`.

Reads do not get dearer: 3.81 ns for a globally bound special, 3.75 ns for
one bound by `progv`. SBCL reads a special through its thread-local slot
whether or not anything bound it, so the evaluator's reads, far more
frequent than its bindings, are unaffected.

Counting `mbind` over real workloads (by redefining it at run time; it is a
plain `defun`): 1,299,078 calls at 1.00 variables per call for
`wc_systematic`, 2,352,130 at 1.65 for the core test suite, which passed
under the wrapper.

| Workload | Binding today | With `progv` | Change | Upper bound |
|---|---|---|---|---|
| `wc_systematic` | 0.18 s (3.9%) | 0.02 s (0.5%) | −3.5% | −0.7% |
| Core test suite | 0.52 s (1.2%) | 0.05 s (0.1%) | −1.1% | −0.2% |

`progv` is not a drop-in replacement: `mbind` also runs the `assign` checks,
the `$values` bookkeeping and an error wrapper, and a correct replacement
keeps them. The upper-bound column keeps all of that and swaps only the
value-cell assignment. Both bounds are savings.

## Verdicts

Thresholds were fixed in the change's design before any measurement, and
are quoted here unchanged.

| Spike | Threshold | Measured | Verdict |
|---|---|---|---|
| A, GC scaling at *p* = 4 | thread throughput ≥ 0.90 × processes, efficiency ≥ 70% | 0.94, 91% | **Pass** |
| B, `progv` cost | ≤ 5% of run time | −0.2% (a saving) | **Pass** |

The sensitivity configuration for spike A gives the same 0.94.

## Recommendation

**Proceed to step 1.** Neither cheap failure happened. Stop-the-world
`gencgc` does not serialise threads at Maxima's allocation rate, and the
binding mechanism the threading path needs is cheaper than the one it
replaces.

The four fixes from doc 05, in the order to attempt them:

1. **Maxima-level binding rebuilt on `progv`** (doc 03), so block and lambda
   locals are per thread. The largest change, and the one that touches the
   evaluator.
2. **A warm-up iteration** before the parallel region, absorbing
   first-iteration writes (autoload, caches). Cheap, and it needs no change
   to `src/`.
3. **The fact database's query labels moved to a per-query table** (doc 03,
   option ii), so sign queries stop writing labels onto shared objects.
4. **The one-line change to `wrstcse.mac`** making `wc_tolnum` local to each
   iteration.

Doing the cheap warm-up before the fact-database work means the first
prototype needs only one invasive change. Every step that touches `src/`
gates on the full test suite with share tests, and on the differential
corpus from the environment-observation change. Steps 1 and 3 additionally
gate on a single-thread timing comparison: neither may slow sequential
Maxima.

**What would reverse this.** Threads give up 6% to processes at four
workers, and the process pool needs no changes to Maxima at all. Doc 07
measured processes paying about 8% in fork and result transfer, so the
margin threads can win is that 8%, less this 6%, less whatever
synchronisation the T2 fixes add. If step 1 or step 3 needs a lock on a hot
path, that margin is gone and processes remain the answer for this
workload.

## What followed

The prototype these spikes recommended is
[09-threaded-prototype.md](09-threaded-prototype.md). Maxima ran on
threads, correctly, and beat the process pool at four workers by 5–8%;
spike A's prediction that the advantage erodes with thread count held on
the real workload. The restructuring cost this document could not price
was deferred again: the prototype confined binding by a thread-entry
`progv` over a traced symbol set and left `mbind` untouched.

## What these spikes do not settle

- **The restructuring cost.** `progv` wraps a body; `mbind-doit` binds
  incrementally and returns, leaving the caller to unbind later. Turning
  `meval`'s call path into a body-wrapping form is step 1's real work, and
  no microbenchmark prices it. The spike rules out the cheaper failure, that
  the mechanism itself is too slow.
- **Contention.** Everything here is single-threaded Maxima or
  non-Maxima threads. Whether the T2 and T3 structures contend at scale is
  step 3's question.
- **Locality.** A synthetic allocator matched on rate and collection
  frequency cannot reproduce the real expression graph's cache behaviour.
- **This machine, this collector.** Apple M4 with 4 performance and 6
  efficiency cores, SBCL 2.6.5. The thread-to-process ratio falls from 0.99
  at two workers to 0.86 at eight, so a many-core machine would read
  differently. A newer SBCL with the mark-region collector and parallel
  marking would need its own measurement, and could only improve the thread
  arm.
- **One workload.** `wc_systematic` on a voltage-divider chain. Doc 05's
  limits on generalising still hold.

## Reproducing

From the worktree root, with the tree built (`./configure --enable-sbcl &&
make`). Every harness refuses to start when total CPU across all processes
exceeds 250% of one core; the load average is not a usable idleness test on
this machine (doc 07).

```sh
R=research/multithreading
# Spike A: reference profile, calibration, sweep, report
SIZE=12 LABEL=wc12 OUT=$PWD/$R/results/gcref.jsonl   $R/tools/gcref.sh
ITERS=8000000 LABEL=cal OUT=$PWD/$R/results/gccal.jsonl $R/tools/gccal.sh
ARMS="threads processes" WORKERS="1 2 4 8" ROUNDS=3 ITERS=8000000 \
  OUT=$PWD/$R/results/gcspike.jsonl $R/tools/gcspike-bench.sh
python3 $R/tools/gcspike_report.py $R/results/gcspike.jsonl \
  --expect-checksum 5184002592000001

# Spike B: microbenchmark, call counts, report
ITERS=200000 ROUNDS=3 OUT=$PWD/$R/results/progv.jsonl $R/tools/progv-bench.sh
WHAT=wc10 COUNT=1 OUT=$PWD/$R/results/mbind-count.jsonl $R/tools/count-mbind.sh
WHAT=wc10 COUNT=0 OUT=$PWD/$R/results/mbind-count.jsonl $R/tools/count-mbind.sh
WHAT=suite COUNT=1 OUT=$PWD/$R/results/mbind-count.jsonl $R/tools/count-mbind.sh
WHAT=suite COUNT=0 OUT=$PWD/$R/results/mbind-count.jsonl $R/tools/count-mbind.sh
python3 $R/tools/progv_report.py $R/results/progv.jsonl \
  $R/results/mbind-count.jsonl
```

Which file each number comes from:

| Number | File |
|---|---|
| Workload allocation profile | `results/gcref.jsonl` |
| Allocator calibration and sensitivity config | `results/gccal.jsonl` |
| Thread and process scaling | `results/gcspike.jsonl` |
| Sensitivity sweep | `results/gcspike-sens.jsonl` |
| Binding cost and read cost | `results/progv.jsonl` |
| `mbind` call counts and plain wall times | `results/mbind-count.jsonl` |

Each record carries the commit, SBCL version, collector features and the
machine state at the time of the run.
