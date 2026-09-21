# Binding cost: PROGV against MBIND

SBCL 2.6.5-85913ede1, commit b20ec9b1e. 51 microbenchmark records over 3 rounds, 0 with a checksum mismatch.

MBIND assigns the symbol's value cell, which is global: one thread's block variable would be every thread's. PROGV binds dynamically, which SBCL makes per thread. This is what the substitution costs.

## Cost per call

| Arm | 1 var | 2 vars | 5 vars | 10 vars | Per binding | Bytes |
|---|---|---|---|---|---|---|
| mbind | 144 ns | 260 ns | 644 ns | 1267 ns | 129 ns | 80 B |
| mbind-doit | 126 ns | 236 ns | 620 ns | 1250 ns | 124 ns | 80 B |
| progv | 17 ns | 25 ns | 53 ns | 104 ns | 12 ns | 0 B |
| raw | 36 ns | 73 ns | 162 ns | 299 ns | 34 ns | 16 B |

Cost scales with the variable count in every arm (a flat row would mean the compiler elided the binding). Fitted per call as a + b*n:

- mbind: 15 ns fixed + 125 ns per variable (worst residual 2%)
- mbind-doit: -7 ns fixed + 126 ns per variable (worst residual 6%)
- progv: 6 ns fixed + 10 ns per variable (worst residual 7%)
- raw: 13 ns fixed + 29 ns per variable (worst residual 15%)

Reading a special costs 3.81 ns when it is only globally bound and 3.75 ns inside a PROGV binding (-2%). SBCL reads a special through its thread-local slot whether or not anything bound it, so moving to dynamic binding does not make the evaluator's reads dearer.


`raw` is save, assign, restore with no MSET checks and no BINDLIST: the floor for a hand-written per-thread binding stack.

## How often binding happens

| Workload | MBIND calls | Vars per call | Wall (plain) | Calls/s |
|---|---|---|---|---|
| wc10 | 1,299,078 | 1.00 | 4.7 s | 279,341 |
| suite | 2,352,130 | 1.65 | 42.5 s | 55,384 |

Wall time is from a separate run without the counting wrapper.

## Estimated whole-workload cost

| Workload | Binding today | With PROGV | Change | Upper bound |
|---|---|---|---|---|
| wc10 | 0.18 s (3.9%) | 0.02 s (0.5%) | -3.5% | -0.7% |
| suite | 0.52 s (1.2%) | 0.05 s (0.1%) | -1.1% | -0.2% |

*Binding today* is MBIND plus MUNBIND at the measured call rate. *With PROGV* replaces them outright, which is the lower bound: it drops the ASSIGN checks and the $VALUES bookkeeping that MBIND also does. *Upper bound* keeps all of that and swaps only the value-cell assignment.

## Verdict against design D4

Worst estimated cost across workloads and bounds: -0.2% of run time.

Thresholds (design D4, fixed before the data): pass at or under 5%, 5-15% is redesign, over 15% is fail.

**Spike B: PASS**

