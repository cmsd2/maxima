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

(filled from the sweep: thread runs at four workers with the guard on and
off)

## Task 4.4: the measurement

(filled from the sweep)

## Gate D verdict

(filled from the sweep, against design D4)
