# Process-pool benchmark, stage A: workload and sequential baseline

Change: `add-process-pool-benchmark`, tasks 1.1–1.4. Machine: Apple M4 (4
performance and 6 efficiency cores), 32 GB, SBCL 2.6.5.

## Workload

`workloads/wc_pool.mac`: a voltage-divider chain with *n* resistor
tolerances (*n*/2 stages), symbolic `U_In` under `assume(U_In>0)`.

- `wc_setup(n)` does `wc_systematic`'s per-call setup;
- `wc_item(i)` computes corner *i* exactly as its outer `makelist` body does.

`makelist(wc_item(i), …)` equals `wc_systematic(wc_chain(n))` at 4
tolerances (81 corners) and 6 (729). Each result is a constant times `U_In`.

## Sequential cost

| Tolerances | Corners | Wall | Per item (mean) | CV | GC | Allocated | Peak RSS |
|---|---|---|---|---|---|---|---|
| 4 | 81 | 0.002 s | 24 µs | | 0% | 1.4 MB | 119 MB |
| 6 | 729 | 0.03 s | 39 µs | 0.17 | 0% | 22 MB | 118 MB |
| 8 | 6,561 | 0.46 s | 70 µs | 2.33 | 2.7% | 317 MB | 120 MB |
| **10** | **59,049** | **6.7 s** | **113 µs** | 3.55 | 1.5% | 4.1 GB | 121 MB |
| **12** | **531,441** | **91.9 s** | **173 µs** | 5.43 | 1.4% | 48 GB | 127 MB |

**Chosen sizes (gate A): 10 and 12 tolerances.** The planned 6 and 8 were far
too short to time.

## Findings

- **Items are fine-grained**, about 0.1–0.2 ms each and growing with the
  expression size. Fork and result-transfer overhead will be a real part of
  the pool's cost for this workload; the design assumed coarser items.
- **The high CV comes from GC pauses landing on single items** (worst items
  9 ms at 8 tolerances, 67 ms at 10), not from real variation in item cost.
- **GC is 1.4–3% of sequential time.** By doc 02's model, GC alone would cap
  a thread mode's speedup only mildly for this workload.
- **Memory is small despite heavy allocation:** 48 GB is consed over the
  12-tolerance run, but peak RSS is 127 MB, because almost everything is
  garbage at once. Gunter's concern about heap size doesn't arise at this
  workload size.
