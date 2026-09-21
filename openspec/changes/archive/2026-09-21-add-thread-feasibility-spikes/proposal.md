## Why

Doc 05 stage F found a frozen-environment thread mode *plausible* for
`wc_systematic`, and doc 07 measured what it would have to beat: a forked
process pool reaching 3.35× on 4 performance cores and 4.99× on 10, needing
no changes to Maxima. Getting threads that far means two substantial changes
to Maxima's hottest code (binding rebuilt on `progv`, the fact database's
query state made per-query). Two risks could make that work pointless, and
both can be measured **without touching Maxima**:

- **Garbage collection may not scale with threads.** SBCL 2.6.5 here uses
  `gencgc`: stop-the-world, collected by one thread, with no parallel
  marking (`:mark-region-gc` absent). Allocation is per thread, and the
  12-tolerance workload conses 48 GB in 63 s, which is 0.76 GB/s from one
  worker. If GC serialises at 4 threads, threads cannot beat processes,
  which collect in parallel by construction.
- **`progv` may be too expensive** to put on the evaluator's hot path, where
  every `block` and function call would pay it.

This change measures both, and decides whether steps 1–4 of the threading
path are worth starting.

## What Changes

- **Spike A, GC scaling under threads.** A Lisp benchmark, run inside a
  built Maxima image, that allocates at a rate matched to `wc_systematic`
  (0.76 GB/s per worker) in *p* = 1, 2, 4, 8 threads, and the same work
  in *p* forked processes. Measures wall time, speedup, GC time and pause
  counts, and the share of wall time each thread spends stopped.
- **Spike B, cost of `progv`.** A microbenchmark of `progv` against the
  save-assign-restore pattern `mbind`/`munbind` use today, over the variable
  counts Maxima actually binds (1, 2, 5, 10), plus a count of how often
  `mbind` runs during the test suite, so the microbenchmark converts into an
  estimated whole-suite cost.
- **A decision record** in `docs/multithreading/`, stating for each spike
  whether it passes, and a single recommendation: proceed to step 1, or stop
  and ship a process-based `parallel_makelist`.

Scope decisions (recorded; change them before applying if wrong):

- **No changes to `src/` or `share/`.** Both spikes are standalone benchmarks
  that load into the existing image.
- **Allocation rate is matched, not the workload.** Spike A mimics
  `wc_systematic`'s allocation and lifetime profile; it does not run Maxima
  code, because Maxima code is not thread-safe yet. That is the point: it
  isolates GC from every other thread hazard.
- **Staging (compiling the expression once) is not measured here.** Doc 02
  estimates 10–1000× for it, far more than threads offer, but it is a
  separate question and belongs in its own change.
- **This machine only:** Apple M4, 4 performance and 6 efficiency cores.
  Thresholds are stated relative to the measured process baseline, not in
  absolute times.

## Capabilities

### New Capabilities

- `thread-feasibility-evidence`: reproducible measurements of the two risks
  that would make a threaded Maxima pointless, with pass/fail thresholds
  fixed before the measurements are taken.

### Modified Capabilities

(none)

## Impact

- **Code:** new files under `research/multithreading/` (a Lisp benchmark, a
  driver, a report script). No Maxima source changes.
- **Machine time:** under an hour in total; both spikes are short.
- **Docs:** a decision record in `docs/multithreading/`, referenced from
  doc 07.
- **Risk to the project:** this change exists to produce a "stop" answer
  cheaply if that is the truth.
