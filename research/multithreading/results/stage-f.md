# Stage F results: level-6 measurement

Change: `add-environment-accessor-layer`, tasks 11.1–11.4. The conclusion
and its limits are in docs/multithreading/05, "Result of the level-6
measurement".

## Tooling (task 11.2)

- **`oracle.lisp` region mode:** `oracle-region-begin`/`-step`/`-end`.
  Each iteration records every hook-observed write, transient ones included,
  plus the net differences the hook didn't explain.
- **`region_report.py`:** separates warm-up from the steady state and places
  every steady-state key in a tier (doc 05). It reports the criterion
  matched.
- **Toy-loop check:** a `block` local gave T1, a fresh global T3, `f(x):=…`
  T4, and an autoload appeared in iteration 1 only; 0% Unknown.

## Three measurement errors caught before concluding

1. **The last iteration carries the region's exit.** The enclosing `block`
   and `makelist` restore their bindings there, which made the shared
   counter look like a paired local in that one iteration, so it dropped out
   of the steady state. The first reading of `wc_systematic` was
   "Plausible", which contradicted the predicted T3. **Fix:** the steady
   state excludes the last iteration.
2. **Fact writes on shared objects were counted as T2.** Doc 05 places fact
   mutation of shared objects (constants, number nodes, `$INITIAL`, interned
   symbols) in T3. **Fix:** only facts on per-computation gensyms are T2.
   This raised the `limit` case's T3 share from 1% to 25%.
3. **`ANS` was uncategorised.** It is a Lisp special written without a
   binding somewhere on the evaluation path; the writer was not identified.
   **Fix:** categorised as algorithm-scratch (T1).

None of these changed a criterion; they corrected the instrument, which the
sanity check (a prediction that disagreed with the first reading) exposed.

## Numbers

| Region | Iterations | T1 | T2 | T3 | T4 | Unknown | Criterion |
|---|---|---|---|---|---|---|---|
| `wc_systematic` | 81 | 36.2% | 55.2% | 8.6% | 0 | 0 | possible with locks |
| `wc_systematic`, `wc_tolnum` local | 81 | 45.8% | 54.2% | 0 | 0 | 0 | **plausible** (results identical, 81 of 81) |
| fresh globals `::` | 20 | 62.5% | 0 | 37.5% | 0 | 0 | possible with locks (high T3) |
| parallel `limit` | 20 | 4.9% | 69.9% | 25.2% | 0 | 0 | possible with locks |
| Newton, `block` locals | 20 | 100% | 0 | 0 | 0 | 0 | plausible |
