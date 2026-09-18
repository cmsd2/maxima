## Context

See proposal.md for the motivation and scope, and
`specs/process-pool-benchmark/spec.md` for the requirements. Doc 02 has the
performance model this benchmark fills in; doc 05 has the stage F result it
follows.

Facts that shape the design:

- **SBCL forks only a single-threaded image.** A built Maxima image runs one
  thread, and `sb-posix:fork` from a Maxima session was checked on this
  machine: the child ran and exited cleanly. This rules out helper threads
  in the parent (for dispatch or memory sampling) while workers are forked.
- **The machine is heterogeneous:** Apple M4 with 4 performance and 6
  efficiency cores, 32 GB RAM. Scaling past 4 workers moves work onto slower
  cores.
- **`wc_systematic`'s outer `makelist` is the parallel loop.** Each item
  substitutes one corner of the tolerance space into the expression and
  simplifies it. Items are independent once the per-call setup
  (`%wc_merge_ewc_subtols`, `%wc_tols`) is done.
- **Results are ordinary Maxima expressions:** numbers, or small
  expressions in a symbol such as `U_In`. There are no CRE forms or gensyms,
  so the printed internal form reads back to an equal structure.

## Goals / Non-Goals

**Goals:**

- A pool generic enough for other workloads later: a work item is
  "evaluate a Maxima function of an index".
- Minimal measurement disturbance: no threads, no sampling process, and
  timing taken only around the parts being measured.

**Non-Goals:**

- Threads of any kind (see proposal).
- A user-facing `parallel_makelist`. This is research tooling.
- Windows, or any Lisp other than SBCL.

## Decisions

### D1. Fork the loaded image, don't spawn fresh processes

The parent loads `wrstcse`, builds the expression and does the per-call
setup, then forks. Workers inherit everything copy-on-write and start
computing at once.

- *Alternative:* spawn new Maxima processes (Robert Dodier's
  `distribute_over_tranches`). Each worker would pay Maxima start-up, load
  the package and receive the expression. Rejected as the baseline because
  fork is the cheapest process model available. If fork doesn't beat
  threads, nothing heavier will.

### D2. Dynamic scheduling through a shared pipe of index tokens

Before forking, the parent writes every item index into one pipe as a
fixed-size 4-byte token, then closes its write end. Each worker repeatedly
reads one token and computes that item, until it reads end-of-file. POSIX
guarantees that pipe reads and writes of at most `PIPE_BUF` bytes are
atomic, so no two workers get the same index, and there is no dispatch loop
in the parent.

Static chunking assigns worker *k* the items with index ≡ *k* (mod *p*),
computed after the fork with no pipe.

- *Alternative:* a parent dispatch loop over per-worker pipes. Rejected: it
  needs `select`/serve-event plumbing, and the shared pipe does the same
  job.
- *Risk:* the index pipe's capacity (64 KiB on macOS) limits prewritten
  tokens to 16,384. The largest workload has 6,561 items. **Mitigation:**
  assert the limit, and fall back to having the parent feed the pipe for
  larger runs.

### D3. Results return through per-worker files as re-readable Lisp forms

Each worker writes `(index . result)` pairs, printed with
`with-standard-io-syntax` in the `maxima` package, to its own temporary
file. The parent reads the files after `waitpid`. Floats print round-trip
exactly in SBCL, and symbols intern into `maxima` again.

- *Why files, not pipes:* a worker blocked writing to a full result pipe
  while the parent waits for it would deadlock. Files avoid that, and the
  transfer cost is still measured: writing time in the worker, reading and
  parsing time in the parent.
- *Correctness:* the parent compares the reassembled list with the
  sequential list using `alike1` element by element. Any mismatch fails the
  run and names the first differing index.

### D4. Memory from inside each process

Each worker, at exit, records:

- its peak resident set from `getrusage` (`ru_maxrss`, bytes on macOS);
- its heap growth since fork (`sb-kernel:dynamic-usage` at exit minus at
  fork).

It writes both into its result file. The parent records its own values.

- `ru_maxrss` counts shared copy-on-write pages the process has touched, so
  the sum over workers is an **upper bound** on real memory.
- Heap growth approximates the pages each worker made private. Both are
  reported, labelled as such.
- *Alternative:* an external `ps` sampler. Rejected: sampling misses short
  peaks and adds a process competing for cores.

### D5. One fresh Maxima process per measurement, alternated

Each timed measurement (a configuration and a repeat) runs in a new
`maxima-local` process, so heap state and GC history can't carry over from
one measurement to the next. The driver runs a discarded warm-up round,
then three rounds. Each round visits every configuration: sequential, then
the pool at each worker count in both scheduling modes. The order rotates
between rounds.

The parent times fork-to-collect with `get-internal-real-time`. Workers
report busy time (from their first item to their last), and GC time from
`sb-ext:*gc-run-time*`.

### D6. Workload sizes are set from a measured per-item cost

The voltage-divider chain is extended to 6 and 8 tolerances (729 and 6,561
corners). The first task measures per-item cost. If a sequential run falls
outside roughly 10–120 s, the sizes are adjusted before the full sweep, so
that runs are long enough to time and short enough to repeat.

### D7. Analysis in a separate Python script

The driver writes one JSON record per measurement. `pool_report.py`
computes medians, spreads, speedup and efficiency, fits the USL by
Gauss–Newton (pure Python, since scipy isn't assumed), and writes the
markdown report.

## Risks / Trade-offs

- **[Fork preconditions]** A future image, or a loaded package, that starts
  a thread would make `fork` fail. → The pool checks the thread count
  before forking and fails with a clear message.
- **[GC dirties shared pages]** A garbage collection in a child copies pages
  it touches, so memory grows with GC activity. → Report GC time and heap
  growth per worker. This is a real cost of the process model, not an
  artefact.
- **[Thermal throttling and background load]** A laptop slows under
  sustained load, and stage E showed that stray load inflates the spread.
  → Alternate configurations and repeat, report the spread, and record the
  wall-clock start time of each run.
- **[Efficiency cores]** Throughput per core drops past 4 workers. → Fit the
  USL separately on the performance-core range, and mark the worker counts
  above 4.
- **[Result serialization]** An expression that doesn't read back equal
  would show up as a false mismatch. → The correctness check fails loudly.
  If it happens, print results as Maxima strings and `parse_string` them.

## Open Questions

- Whether 6 and 8 tolerances are the right sizes. Settled by D6's first
  measurement without changing the approach.
