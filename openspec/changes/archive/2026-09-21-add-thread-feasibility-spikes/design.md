## Context

See `proposal.md` for motivation and `specs/thread-feasibility-evidence/spec.md`
for the requirements. Doc 05 (stage F) found the thread hazards contained
and fixable; doc 07 measured what threads would have to beat. This change
tests the two assumptions those documents left untested.

Facts that shape the design:

- **The collector on this machine is stop-the-world gencgc.**
  `(:gc-parallel nil :gencgc :gencgc :mark-region nil)` under SBCL
  2.6.5-85913ede1. One thread collects while every other thread is stopped.
  Newer SBCL builds can use a mark-region collector with parallel marking;
  this one cannot.
- **The workload allocates hard.** `wc_systematic` at 12 tolerances conses
  48 GB in 63 s: 0.76 GB/s from a single worker. Four workers would ask for
  3 GB/s.
- **GC share is small in one thread (1.5%),** which is why doc 07 put the
  GC-only Amdahl ceiling at 65×. That ceiling assumes GC cost per byte
  stays constant as threads are added. Collection frequency rises with
  aggregate allocation rate, and each collection now stops *p* threads
  instead of one, so the assumption is exactly what needs testing.
- **Processes already give 3.35× at 4 workers and 4.99× at 10,** with about
  8% overhead at 10 workers and 2% at one. That 8% is the entire margin
  threads can win.
- **`sb-posix:fork` needs a single-threaded image,** so the process arm must
  fork before any benchmark thread exists.
- **`mbind` is a plain `defun`,** not inlined, so it can be counted by
  redefinition at run time (AGENTS.md sec. 4) with no rebuild.

## Goals / Non-Goals

**Goals:**

- Decide, for under an hour of machine time, whether the threading path is
  worth starting.
- Produce numbers a later reader can re-derive: recorded machine state,
  recorded collector features, committed thresholds.

**Non-Goals:**

- Running any Maxima algebra on threads. It isn't safe yet; that is what
  steps 1–4 would fix.
- Changing `src/` or `share/`.
- Measuring staging (compile-once), which doc 02 ranks far above threads
  and which belongs in its own change.
- Portability beyond SBCL on this machine.

## Decisions

### D1. The GC spike allocates Maxima-shaped garbage, calibrated to a measured rate

The loop builds and drops small list structures resembling simplified
expressions (a header cons plus two to four argument conses, nested two to
three deep), rather than allocating one large vector. Pointer-rich garbage
is what a symbolic run produces, and it is what makes marking expensive.

Calibration: size the per-iteration work so a single thread reaches 0.76
GB/s ± 20%, measured with `sb-ext:get-bytes-consed`. The report states the
rate achieved.

Survival: a fraction of objects is retained in a per-thread ring buffer so
that some promote out of the nursery. The fraction is set from the Maxima
run's observed collections per generation (`sb-ext:generation-number-of-gcs`
for generations 0–2, sampled before and after a `wc_systematic` run), not
chosen by taste.

*Alternative rejected:* replaying an allocation trace from the real run.
More faithful, far more work, and the trace itself perturbs what it
measures.

### D2. One fresh process per measurement; arms differ only in mechanism

Each measurement starts a new Maxima image, runs one configuration (arm,
*p*, round), writes a JSON record and exits. Rounds rotate across
configurations rather than running in blocks, and the first round is
discarded, matching the process-pool harness. This keeps the process arm's
fork legal (no thread has been created in that image) and stops one arm's
heap state from shaping the other's.

### D3. GC is measured directly, not inferred from speedup

Each run records:

- `sb-ext:*gc-run-time*` delta: total time the collector ran;
- collection count and per-collection duration, accumulated in an
  `sb-ext:*after-gc-hooks*` hook;
- per-thread useful work: each thread counts iterations and its own elapsed
  time, so throughput per thread is known;
- stopped share per thread: GC run time over wall time, which under a
  stop-the-world collector is the time every non-collecting thread spent
  halted.

A gap between measured and ideal speedup that GC time does not account for
is memory bandwidth. The report must say which.

### D4. Thresholds, fixed now

**Spike A (GC scaling), at *p* = 4:**

| Outcome | Condition |
|---|---|
| **Pass** | thread speedup ≥ 0.90 × process speedup in this benchmark, and thread efficiency ≥ 70% |
| **Redesign** | thread speedup 0.70–0.90 × process speedup |
| **Fail** | thread speedup < 0.70 × process speedup, or < 2.0× absolute |

Threads' whole advantage over processes is the 8% overhead processes pay
(doc 07). Losing more than 10% to collection spends that margin before any
Maxima code runs. A *redesign* verdict means threads stay possible only
with a collector change (a newer SBCL with mark-region parallel marking),
which would become its own spike.

**Spike B (`progv` cost):**

| Outcome | Condition |
|---|---|
| **Pass** | estimated whole-workload cost ≤ 5% of run time |
| **Redesign** | 5–15% |
| **Fail** | > 15% |

A thread mode starting 15% down cannot recover it from an 8% margin. A
*redesign* verdict points at binding only the variables that a call can
actually reach, or at a per-thread binding stack instead of `progv`.

Both spikes must pass for the recommendation to be "proceed to step 1". A
single fail is a stop.

### D5. The `progv` baseline mimics `mbind-doit`, not a textbook `let`

Today's per-variable cost in `mbind-doit` is: read the old value
(`symbol-values-in`), `mset` it, then push the variable onto `bindlist` and
the old value onto `mspeclist`; `munbind` pops both. The microbenchmark's
baseline arm reproduces that shape, including the two conses per variable,
so the comparison is against what Maxima pays now rather than against an
idealised binding.

The `progv` arm pays SBCL's binding-stack cost and a value list, but not the
two conses. It also forces a control-flow change in `mbind`: `progv` wraps a
body, while `mbind-doit` binds incrementally in a `do` loop and returns.
That restructuring is step 1's work, not this spike's, but its cost is noted
in the decision record.

To stop the compiler eliding the work, the symbol list is built at run time,
the body reads the bound special and accumulates into a returned sum, and
the harness checks that sum.

### D6. `mbind` frequency comes from a real run, by redefinition

A counting wrapper is loaded with `:lisp (load ...)` into a built image and
counts calls and variables bound, printing to `*debug-io*` (AGENTS.md sec.
4: `run_testsuite` swallows `*standard-output*`). It runs over the core test
suite and over `wc_systematic` at 10 tolerances. Calls per second times
measured per-binding cost gives the percentage estimate.

*Alternative rejected:* a statistical profiler. It answers where time goes
today, not what a changed binding mechanism would cost.

### D7. Recorded conditions, carried over from the last benchmark

Every record carries total CPU busy, load average, power source, battery
level, SBCL version, collector features and commit. The quiet test is total
CPU below 250% of one core; the load average misreads this machine (doc 07,
Reliability).

## Risks / Trade-offs

- **A synthetic allocator is not Maxima.** Matching rate and pointer density
  gets the collector's behaviour approximately right; it cannot capture
  locality effects of the real expression graph. This overstates neither
  arm, since both arms run the same loop. Mitigation: state the limit in the
  decision record, and treat a borderline pass as a redesign.
- **Eight threads on four performance cores measures the scheduler as much
  as the collector.** Mitigation: the pass/fail threshold sits at *p* = 4;
  *p* = 8 is reported for shape only.
- **Spike B's estimate is an estimate.** A per-binding microbenchmark
  ignores cache effects of a real evaluator. Mitigation: the thresholds have
  a wide middle band, and a redesign verdict does not kill the path.
- **A stop verdict wastes the work already done.** It does not: doc 07's
  process pool is the shippable outcome, and this change is what stops us
  spending weeks to learn the same thing.

## Migration Plan

None. New files under `research/multithreading/` and one document under
`docs/multithreading/`. Nothing depends on them.

## Open Questions

- If spike A returns *redesign*, is a newer SBCL with the mark-region
  collector worth building and re-measuring? Cheap to answer, but out of
  scope here.
- Does the survival fraction measured from `wc_systematic` generalise to
  other symbolic workloads? Not tested; the decision record states the
  workload it holds for.
