# Threaded prototype, stage A: the runner and the guard

Gate A of `add-threaded-prototype`. Stage A builds the thread runner and
proves the confinement it rests on, without running any Maxima algebra.

Tools: `tools/threads.lisp`, `tools/threads-test.lisp`,
`tools/threads-test.sh`, `tools/symbolset.lisp`.
Log: `logs/threads-test.log`.

## Task 1.1: the symbol set, from a fresh trace

Traced `wc_item` over 80 iterations with the write hook, one warm-up item
skipped:

| Class | Symbols |
|---|---|
| Assigned or unbound (confined by thread-entry binding) | `$WC_NUM`, `$WC_TOL`, `$WC_TOLNUM` |
| Plist writes (**not** confined by binding) | `|$U_In|` with `+LABS` |

This matches doc 05's stored trace exactly. The plist writes are the T2
fact-database labels that stage B removes; until then the runner tolerates
them explicitly, and the tolerance appears in each run record rather than
hiding in the code.

The full thread-entry set is those three plus the T1-category specials from
`research/multithreading/oracle-churn.tsv` and the binding stack
(`bindlist`, `mspeclist`): **46 symbols**, every name resolving.

## Tasks 1.2 and 1.3: runner and guard

Each worker enters through `progv` over the set, then evaluates its items.
`mbind`, `munbind` and `mset` are untouched: their
`(setf (symbol-value x) y)` lands in the worker's binding.

The guard is an `*environment-write-hook*` installed inside workers only. It
refuses an assignment to any symbol not bound at entry, naming the symbol,
and refuses a property write unless the run tolerates that indicator.

**Unbound symbols stay in the set.** The first version dropped them, on the
grounds that `progv` would bind them to `nil`, a value they never had. That
was wrong and would have leaked writes in silence. Eleven symbols in the
set are unbound in a fresh image, `ANS` among them, and the region trace
shows `ANS` written once per iteration. Worse, `ANS` is SETQ'd by Lisp code
rather than through `mset`, so the hook never sees it and the guard cannot
catch it. The fix uses `progv`'s own semantics: symbols past the end of the
value list are bound **as unbound**, which is exactly the state they should
start in. A worker's write then lands in its own binding, and the parent's
symbol stays unbound.

## Tasks 1.3 and 1.4: what was verified

| Check | Result |
|---|---|
| Symbol set resolves, 46 symbols, none unresolved | pass |
| Unbound specials kept rather than dropped (`ANS`) | pass |
| `bindlist` and `mspeclist` in the set | pass |
| Each worker reads back its own write | pass, `(0 1 2 3 4 5 6 7)` |
| Parent's value survives the region | pass |
| **Negative control:** same work, symbol left out, guard off | pass, `(6 4 2 4 5 5 5 5)` |
| **Negative control:** the write reached the parent | pass, parent holds 5 |
| Unbound symbol confined, parent still unbound | pass |
| Guard refuses an unconfined assignment, naming the symbol | pass |
| The refused write never reached the parent | pass |
| Guard refuses an untolerated property write | pass |
| Guard allows a tolerated property write | pass |

The negative control is the point. Without the binding, four workers
writing the same variable read back whichever write landed last, and the
value escapes to the parent. There is no error and no warning: the run
completes and the answers are wrong. That is what this design prevents, and
what the guard turns into a refusal for the cases binding cannot cover.

## Gate A verdict

The confinement mechanism works, its failure mode is reproduced on demand,
and the guard catches what binding cannot. Stage B can proceed.

Two limits to carry forward:

- **The guard sees `mset`, not Lisp.** A special SETQ'd outside `mset`
  passes it unseen. Such symbols reach the set only because the oracle's
  snapshot diff found them in the earlier change, so the set is only as
  complete as that trace. `ANS` is the proof that this class is real.
- **No Maxima algebra has run on threads yet.** Stage C is the first time,
  and a guard firing there is the designed way to find a symbol the trace
  missed.
