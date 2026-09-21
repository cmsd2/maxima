# Threaded prototype, stage C: the remaining fixes, and Maxima on threads

Gate C of `add-threaded-prototype`. The `wrstcse` counter, the warm-up
iteration, and the first time Maxima algebra runs on threads.

Data: `threads-wc-stage-c.jsonl`. Tools: `tools/threads.lisp`,
`tools/threads-wc.lisp`, `tools/threads-wc.sh`. Logs:
`logs/threads-wc-*.log` (the failing runs' backtraces are in
`logs/threads-wc-bt*-p4.log`).

## Task 3.1: `wrstcse.mac`

`wc_tolnum` was a local of `wc_systematic`'s outer `block`, shared by every
corner of the outer `makelist`. It is now bound by a `block` inside the
per-corner `subst`, so each corner has its own. Three insertions, four
deletions (the outer local and its comment go).

Checked against the unchanged package loaded from the baseline tree, in the
same image: `wc_systematic(wc_chain(4))` and `wc_chain(6)` are
syntactically identical before and after (81 and 729 corners), and
`wc_tolnum` no longer holds a value after the call. `rtest_wrstcse`: 97/97.

## Task 3.2: warm-up

`thread-run` evaluates item 0 once in the parent before any worker
starts, so autoload, cache population and other first-use writes happen
single-threaded, outside the region. Workers then compute every item,
item 0 included; the warm-up's value is discarded. Each record says
`warmup: true`.

## Task 3.3: the first threaded run, and what it found

`wc_systematic` at 6 tolerances (729 corners), every result compared with
the sequential list by `alike1`:

| Threads | First attempt |
|---|---|
| 1 | correct |
| 2 | correct |
| 4 | **incorrect**: a worker died at item 727 |
| 8 | incorrect (repeats: items 170, 66) |

Not a guard firing. The error was a Lisp type error,
`-4 is not of type (UNSIGNED-BYTE 62)`, and the captured backtrace put it
in `SB-KERNEL:%SET-FILL-POINTER`, called from `MLAMBDA`'s unwind cleanup.
`*mlambda-call-stack*` is an adjustable vector with a fill pointer:
`mlambda` pushes a call frame onto it and pops it in a cleanup form. It
was in the thread symbol set, and `progv` bound it in every thread — **to
the parent's vector, by reference**. Four threads pushing and popping one
vector drove its fill pointer below zero.

This is the same class of bug stage B met with the label tables, and the
fix is the same: `+thread-fresh-bindings+` now gives each thread its own
`(make-array 30 :fill-pointer 0 :adjustable t)`, the constructor from
`globals.lisp`. After the fix, five runs at each of 1, 2, 4 and 8 threads:
**20 of 20 correct.**

One of the failing repeats also **hung**: ten minutes at 0% CPU. An error
signalled inside an unwind cleanup can escape the worker's `handler-case`,
and the thread then sat in the interactive debugger reading `*debug-io*`.
The runner now binds the debugger hooks in every worker to abort the
thread, and the parent joins with a timeout, so a stuck worker is reported
rather than waited on.

## What this stage says about the symbol set

"Bound at thread entry" is not enough for a mutable object. A `progv`
binding copies a reference, so a hash table, an adjustable vector, or any
array written in place is still one object shared by every thread. The
symbol set now has two classes:

| Class | Members | Mechanism |
|---|---|---|
| Copied by reference | 61 symbols: values, lists that Maxima grows with fresh conses | `progv` over the parent's values |
| Fresh per thread | `*+labs-table*`, `*-labs-table*`, `*mlambda-call-stack*` | constructor run at thread entry |

Lists are safe in the first class only because Maxima grows them with
fresh conses on the thread's own binding (`bindlist`, `mspeclist`,
`varlist`, the fact database's queue lists after `clear`).

**The guard could not have caught this.** It sees `mset` and property
writes; a `vector-push` on a shared vector is neither. What caught it was
a Lisp error, and had the corruption been silent the result comparison was
the only remaining net. That is why stage D re-runs the write observer
under threads, and why the correctness check is a requirement rather than
a test.

Two more shared objects were checked directly rather than trusted to the
trace, since the oracle never fingerprinted arrays outside plists:

- `contextmark` writes `cmark` counts onto the context symbol's plist only
  when the current context changes, which no worker does; the warm-up
  leaves `current` equal to `context` before any thread starts, and if
  that ever failed the write is a `putprop`, which the guard refuses.
  `conmark`/`conunmrk` are written only when contexts are created or
  killed.
- `*lambda-expr-funs*`, the compiled-lambda memo table: 0 entries before
  and after 728 items. The workload does not touch it.

## Gate C verdict

| Check | Result |
|---|---|
| `wrstcse` results unchanged at 4 and 6 tolerances | identical |
| `rtest_wrstcse` | 97/97 |
| Warm-up runs item 0 in the parent, recorded | verified (stage A checks) |
| Threaded `wc_systematic`, 6 tolerances, 1/2/4/8 threads × 5 | 20/20 correct |
| Guard firings | none; the escape was below the guard's reach |

Stage D can proceed: the measurement, with the write observer re-run under
threads first.
