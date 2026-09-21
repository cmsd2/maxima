# Binding cost spike, stage C

Gate C of `add-thread-feasibility-spikes`. Spike B asks what it costs to
move Maxima's block and lambda binding from `mbind`'s mechanism to `progv`.

`mbind` binds by assigning the symbol's value cell, saving the old value on
`bindlist`/`mspeclist` for `munbind` to restore. That cell is global: on
threads, one thread's block variable would be every thread's. `progv` binds
dynamically, which SBCL makes per thread. Step 1 of the threading path is
that substitution, and it lands on the evaluator's hottest path.

Data: `progv.jsonl` (microbenchmark), `mbind-count.jsonl` (call counts).
Report: `progv-report.md`.
Tools: `tools/progv-bench.lisp`, `tools/progv-bench.sh`,
`tools/count-mbind.lisp`, `tools/count-mbind.sh`, `tools/progv_report.py`.

## Result

**`progv` is about ten times cheaper per binding than what Maxima does
today, and allocates nothing.**

| Arm | Per binding | Bytes per binding |
|---|---|---|
| `mbind` + `munbind` (today) | 129 ns | 80 B |
| `mbind-doit` + `munbind` (no error wrapper) | 124 ns | 80 B |
| **`progv`** | **12 ns** | **0 B** |
| `raw` save-assign-restore | 34 ns | 16 B |

Cost rises with the variable count in every arm (`mbind` 144 → 1267 ns from
1 to 10 variables), so nothing was optimised away. Four arms ran at 1, 2, 5
and 10 variables over three rounds, 48 records, no checksum mismatch.

`raw` is the floor: assign the cell and restore it, with none of `mset`'s
checks and no `bindlist`. `progv` beats even that, because SBCL's binding
stack needs no list to record what to undo.

**Reads do not get dearer.** 3.81 ns for a globally bound special, 3.75 ns
for one bound by `progv`. SBCL reads a special through its thread-local slot
whether or not anything bound it, so the evaluator's reads — far more
frequent than its bindings — are unaffected. The measurement checks its own
sums, so a read that found the wrong value would show up.

## How often binding happens

| Workload | `mbind` calls | Variables per call | Wall | Calls/s |
|---|---|---|---|---|
| `wc_systematic`, 10 tolerances | 1,299,078 | 1.00 | 4.7 s | 279,341 |
| Core test suite | 2,352,130 | 1.65 | 42.5 s | 55,384 |

Counted by redefining `mbind` at run time — it is a plain `defun`, not
declaimed inline, so no rebuild is needed. Wall times come from separate
runs without the wrapper; counting cost 0.2% (4.64 s against 4.65 s). The
suite passed under the wrapper, 16,409 tests with no unexpected errors,
which is a free check that the redefinition is transparent.

`wc_systematic` binds one variable per call, 22 times per corner.

## Estimated whole-workload cost

| Workload | Binding today | With `progv` | Change | Upper bound |
|---|---|---|---|---|
| `wc_systematic` | 0.18 s (3.9%) | 0.02 s (0.5%) | −3.5% | −0.7% |
| Core test suite | 0.52 s (1.2%) | 0.05 s (0.1%) | −1.1% | −0.2% |

Two bounds, because `progv` is not a drop-in replacement. `mbind` also runs
the `assign` property checks, the `$values` bookkeeping and an error
wrapper, and a correct replacement keeps them. The *change* column replaces
`mbind` outright (the lower bound, and unrealistic); the *upper bound*
column keeps every check and swaps only the value-cell assignment.

Both are savings. The substitution does not cost run time on either
workload.

**Gate C threshold (design D4, fixed before the data): pass at or under 5%
of run time, 5–15% redesign, over 15% fail. Worst case measured: −0.2%.
Spike B passes.**

## What this does not measure

- **The restructuring.** `progv` wraps a body; `mbind-doit` binds
  incrementally in a loop and returns, leaving the caller to unbind later.
  Turning `meval`'s call path into a body-wrapping form is step 1's real
  work, and no microbenchmark can price it. What this rules out is the
  cheaper failure: that the mechanism itself is too slow.
- **Correctness of the substitution.** `mbind` handles `munbound` values,
  destructuring lists, `$errormsg`'s special case and the argument-count
  error. A `progv`-based binding has to keep all of it.
- **Contention.** Single-threaded throughout. Whether per-thread binding
  stacks contend at scale is a question for step 1 itself.
