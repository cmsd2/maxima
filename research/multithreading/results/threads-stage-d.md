# Threaded prototype, stage D: the measurement, and what it took to get one

Gate D of `add-threaded-prototype`. Threads against doc 07's process pool
on the same workload, machine and methodology. The sweep's first attempt
failed, and what it found matters more than the timing.

Data: `bench-d.jsonl` (the sweep), `bench-d-values-race.jsonl` (the first
attempt, kept as evidence), `threads-wc-10-loclist-race.jsonl`,
`threads-wc-10-fixed.jsonl`, `threads-wc-10-audited.jsonl` (the
10-tolerance repeats before and after each fix),
`threads-observe-stage-d.jsonl` (the write trace under threads). Report:
`bench-d-report.md`. Tools: `tools/bench-d.sh`, `tools/threads-bench.lisp`,
`tools/threads_report.py`.

## Task 4.2: the write trace under threads

Observe mode records every write per worker instead of refusing any.
`wc_systematic` at 6 tolerances, four threads, static and dynamic: 6
distinct writes, none flagged, on the three symbols the single-threaded
trace found, with per-worker counts summing to exactly one run (729
items, 5,103 counter bindings, 8,748 tolerance bindings). At 10 tolerances
on one thread over all 59,049 items: the same 6 writes, none flagged.

So the trace under threads matched the trace without them. It was still
wrong, in the sense that mattered.

## What the first sweep found

Stage C had passed 20 of 20 at 6 tolerances. The sweep's first attempt at
10 tolerances failed **every** threaded run with four or more workers,
static and dynamic, guard on and guard off, while one and two workers
passed. The errors were list-structure corruption (`NIL is not of type
CONS`, `MPLUS is not of type LIST`) and, once, the guard catching
`REMOVE of MPROPS` on a node. Two causes, found one after the other:

**`$values`.** `wc_systematic`'s three locals are unbound between calls,
so each `mset` of one runs `add2lnc`, which is
`(nconc $values (ncons item))`, and each `munbind` restoring "unbound"
runs `(delete var $values ...)`. Both are destructive on the list's own
conses. `$values` was not in the symbol set (doc 05 classed the info
lists T3), and a `progv` binding would not have helped: it copies a
reference, so every thread would have spliced the same conses. The fix
is a third binding class beside "copied by reference" and "fresh":
lists **copied** at thread entry with `copy-list`, for `$values` and the
other info lists. After it, 13 of 15 runs passed at 10 tolerances.

**`loclist`.** The two remaining failures both went through `munlocal`,
called from `$ev`, called from the inner `makelist`. `loclist` is the
`local()` frame stack, a global that **every** `mlambda` call, `block` and
`ev` pushes a frame onto at entry and `munlocal` pops at exit, with
`mproplist` and `factlist` alongside. Shared across threads, lost-update
pushes and pops let `munlocal` walk past a thread's own frames into
something else and "restore" what it found there: a `tol[k]` expression,
in both captured backtraces, which the guard reported as a property
removal on a node. Bound per thread with `bindlist` and `mspeclist`, plus
`$%%`, which `block` sets with a raw `setq` on every statement: 15 of 15.

**Why neither was in the set.** Both are Lisp-level writes: a `push`,
an `nconc`, a `setq`. The write hook sees `mset` and property writes, so
the guard could not refuse them, and the observe trace could not show
them. The oracle's snapshot diff should have caught `loclist` and did not,
because every iteration restores it before the snapshot, doc 05's stated
"transient special-variable writes" blind spot. `$values` the oracle did
see and classify; the classification was right and the runner did not act
on it.

**The audit.** Two such symbols found one at a time is a pattern, so the
evaluator files (`mlisp`, `suprv1`, `comm`, `simp`, `float`) were searched
for every global written with `push`, `setq`, `setf` or `incf`. 33 were
not in the set. Most are specials the caller `let`-binds before the
`setq`, already thread-local when written; the rest are option lists only
`kill`, `reset`, `declare` or `tellrat` change, which the frozen
environment forbids. All 33 were bound anyway, since case-by-case
reasoning is what had missed the first two and a binding nothing writes
costs nothing. The set is 101 symbols in three classes:

| Class | Count | Mechanism |
|---|---|---|
| Copied by reference | 90 | `progv` over the parent's values; unbound symbols bound as unbound |
| Copied by value | 8 info lists | `copy-list` at entry, because `add2lnc` and `delete` splice them |
| Fresh | 3 | a constructor at entry: the two label tables, the `mlambda` call stack |

What caught all of this was the correctness check against the sequential
results, and Lisp type errors. Had the corruption been silent, the check
was the only net. That is the finding of this stage: **the guard and the
trace bound the `mset`-visible hazard; the correctness check is what
bounds the rest, and it has to run at the scale that opens the race
windows.** 6 tolerances never showed either bug in 20 runs; 10 tolerances
showed both in every run.

## Task 4.3: the guard's cost

Thread runs at four workers with the guard on and off, same rounds:

| Tolerances | Mode | Guard on | Guard off | Difference |
|---|---|---|---|---|
| 10 | static | 1.35 s | 1.35 s | −0.1% |
| 10 | dynamic | 1.35 s | 1.32 s | +2.3% |
| 12 | static | 16.91 s | 17.90 s | −5.5% |
| 12 | dynamic | 17.30 s | 17.64 s | −1.9% |

The guard is one hash lookup per assignment, unbind or property write.
Its cost is not measurable above the run-to-run noise: three of the four
comparisons have the guarded run faster. Nothing in the thread mode takes
a lock.

## Task 4.4: the measurement

184 measurements, 46 warm-up round dropped, **0 incorrect**. CPU in use
before each run 2–219% of one core, none forced past the quiet check,
on battery throughout. Speedups are against the sequential run; the ratio
is thread speedup over process speedup.

**10 tolerances (59,049 corners), sequential 4.89 s:**

| Workers | Threads, static | Processes, static | Ratio | Threads, dynamic | Processes, dynamic | Ratio |
|---|---|---|---|---|---|---|
| 1 | 1.00× | 0.96× | 1.04 | 0.99× | 0.90× | 1.10 |
| 2 | 1.93× | 1.77× | 1.09 | 1.93× | 1.66× | 1.16 |
| **4** | **3.62× (91%)** | **3.36× (84%)** | **1.08** | 3.63× | 3.01× | 1.21 |
| 8 | 4.62× | 3.88× | 1.19 | 4.68× | 3.84× | 1.22 |
| 10 | 4.92× | 4.15× | 1.19 | 5.10× | 3.99× | 1.28 |

**12 tolerances (531,441 corners), sequential 61.89 s:**

| Workers | Threads, static | Processes, static | Ratio | Threads, dynamic | Processes, dynamic | Ratio |
|---|---|---|---|---|---|---|
| 1 | 1.00× | 0.97× | 1.03 | 0.98× | 0.93× | 1.06 |
| 2 | 1.93× | 1.84× | 1.05 | 1.91× | 1.72× | 1.11 |
| **4** | **3.66× (92%)** | **3.47× (87%)** | **1.05** | 3.58× | 3.24× | 1.11 |
| 8 | 4.55× | 4.53× | 1.01 | 4.59× | 4.50× | 1.02 |
| 10 | 4.78× | 5.05× | 0.95 | 4.87× | 4.99× | 0.97 |

Paired by round (processes minus threads, static, guard on): threads
ahead in **3 of 3 rounds at every worker count up to 4**, both sizes,
both modes. Beyond the performance cores on the larger workload the lead
goes: 1 of 3 rounds at 8 and 10 workers, mean −0.38 s at 10.

Three readings:

- **Threads win by about the process overhead, and no more.** 5–8% at
  four workers, static. Doc 07 measured processes paying about 2% at one
  worker and 8% at ten in fork and result transfer. Threads avoid that and
  gain nothing else; the loop body is the same code.
- **Dynamic scheduling favours threads more** (ratio 1.11–1.21 at four
  workers), because the process pool's dynamic mode waits for every fork
  before handing out tokens and threads have no fork to wait for.
- **Past four workers the advantage erodes, then reverses.** On the
  larger workload the ratio falls from 1.05 at 4 to 1.01 at 8 and 0.95 at
  10. Spike A's synthetic run gave 0.94 at 4 and 0.86 at 8 for the
  collector alone; the real workload does better than that because the
  process pool's own overhead offsets it, but the direction is the same:
  more threads collect more often and promote more, and processes do not.

## Gate D verdict

Design D4: a win needs threads ahead of processes at four workers, static,
by more than the run-to-run spread, with no lock on a hot path and the
guard active.

| Size | Threads | Processes | Threads ahead by | Spread | Verdict |
|---|---|---|---|---|---|
| 10 tolerances | 1.35 s (3.62×) | 1.45 s (3.36×) | 0.11 s | 0.05 s | **Win** |
| 12 tolerances | 16.91 s (3.66×) | 17.83 s (3.47×) | 0.92 s | 0.71 s | **Win** |

No lock was added; the guard was active in every scored run. **Win, on
both sizes**, by a margin about the size of the overhead processes pay.
