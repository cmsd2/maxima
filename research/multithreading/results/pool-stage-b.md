# Process-pool benchmark, stage B: the pool

Change: `add-process-pool-benchmark`, tasks 2.1–2.4.

## The pool (`tools/pool.lisp`, `pool-run`)

- **Refuses to fork unless the image runs exactly one thread.**
- **Forks *p* workers from the loaded image,** one after another. In
  dynamic mode the parent then writes every item index into a shared pipe as
  4-byte tokens, 64 tokens per write (256 bytes, within `PIPE_BUF`), and
  closes it. Workers read tokens until end of file. In static mode worker
  *k* takes the indices ≡ *k* (mod *p*).
- **Each worker** writes `(index . result)` forms and a summary (items, busy
  time, GC time, `ru_maxrss`, heap growth, write time) to its own file, then
  exits with `sb-ext:exit :abort t`.
- **The parent** waits for every worker, reads and reassembles the results,
  and compares them with the sequential results using `alike1`.

## Checks

| Check | Result |
|---|---|
| 81 results at *p* = 3, both modes | ✓ |
| Planted fault at index 40 | reported as failed, first mismatch 40, in both modes |
| Isolation: items assign `iso_global` and define `iso_f` in workers | parent has neither afterwards, and `$values` is unchanged. Control: one call in the parent defines both |
| Gate B matrix: both modes, *p* = 1, 2, 4, 10, 4 and 6 tolerances | 16 of 16 correct |

## First observations (small workloads, not the benchmark)

- **Forking costs about 20–45 ms per worker,** serialised in the parent.
  10 workers take 0.24–0.44 s to start, against a sequential time of 0.03 s
  at 6 tolerances. For the 10-tolerance workload (6.7 s sequential, about
  0.67 s per worker at *p* = 10), fork cost is a large share of the ideal
  per-worker time.
- **Dynamic mode spreads items unevenly** on small workloads, because the
  first-forked workers start earlier and take more tokens. Static mode
  splits evenly by construction.
- **Result transfer is cheap:** reading and parsing 729 results takes about
  1 ms.
