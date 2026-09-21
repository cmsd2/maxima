# Threaded prototype, stage B: per-query fact labels

Gate B of `add-threaded-prototype`. The one stage that changes `src/`: sign
query labels move from properties written onto shared fact-database nodes
to a per-query hash table, so that queries in different threads on the same
node never see each other's marks.

Diff: `src/db.lisp`, `src/compar.lisp`; 50 insertions, 33 deletions.
Artefacts: `suite-stage-b.txt`, `depcheck-stage-b.log`, `corpus-stage-b.txt`,
`timing-stage-b.tsv`. Tools: `tools/timing-ab.sh`, `tools/symbolset.lisp`.

## What the lifecycle read found (task 2.1)

- **The marks were already transient.** `clear` runs at the start of every
  query (`truep` calls it) and sweeps the nodes recorded on the `+labs`,
  `-labs` and `ulabs` lists. What escaped to threads was only the storage:
  a `putprop` onto a node every other thread can see.
- **`+labs` is overloaded, and both users moved.** `db.lisp`'s `queue+p`
  stores a bit cell under it; `compar.lisp`'s `dmark` stores a sign symbol
  under the same key, and each checks for the other's leftovers ("a stale
  sign symbol left by DMARK"). One table per indicator keeps that
  behaviour exactly as it was.
- **`ulabs` is overloaded differently, and stays put.** `local()` in
  `mlisp.lisp` writes `ulabs` *persistently* (`(putprop fact -1 'ulabs)`)
  to hide a fact for the extent of a block, and `munlocal` removes it.
  That is not query scratch. Moving it is a separate change with its own
  risk, so `ulabs` stays on the plist and the thread guard refuses any run
  that writes it. `wc_systematic` does not.
- **The label numbering stays.** `*labindex*`, `+lab-high-bit+` and
  `unlab` invalidate stale marks cheaply; with the marks still living
  until the next `clear`, they are still needed. The diff moves only where
  the marks live.

## The change (tasks 2.2, 2.3)

Two `defvar`s holding `eq` hash tables, two accessor macros `+labs-of` and
`-labs-of`, and every read and write site switched to them: 22 sites in
`db.lisp`, 7 in `compar.lisp`. `clear` sweeps by `remhash` over the same
lists it always walked. `killframe` uses `remhash` where it used
`zl-remprop`. The `defmode`-generated `+labs`/`-labs` accessor macros are
left defined and unused, since removing the selectors would change the
generated mode's shape.

Task 2.3 turned out not to need a `src/` change. A nested query is handled
by `clear` as before. Per-thread isolation comes from the runner: a
`progv` copy of a table would hand every thread the same table, so
`threads.lisp` gained `+thread-fresh-bindings+`, binding both tables to a
fresh hash table at thread entry. The fact database's own per-query
specials (`+s`, `-s`, `*labs*`, `*lprs*`, `*labindex*`, `*marks*`, `*db*`,
`current`, the lists, and so on: 18 names) joined the thread symbol set,
taking it to 64.

Leftover marks behave as they always did: after a query, the table holds
exactly the nodes on the `+labs` list (checked: 3 and 3, every key on the
list), and the next `clear` empties both.

## Task 2.4: the labels are gone

Fresh trace of `wc_item` over 80 iterations, one warm-up skipped:

| | Before | After |
|---|---|---|
| Assigned or unbound | `$WC_NUM` `$WC_TOL` `$WC_TOLNUM` | same |
| Plist writes | `|$U_In|` (`+LABS`) | **none** |

The workload's only T2 write class is gone. The runner no longer needs to
tolerate `+LABS`.

## Gate B (task 2.5)

| Gate | Result |
|---|---|
| Full suite with share tests | **21,498 tests, no unexpected errors**; no Lisp errors; no expected-to-fail-but-passed, so the registry is unchanged |
| `make check` dependency check | **clean**: no undeclared compile-time dependencies |
| Differential corpus vs the pre-change baseline | **443 files, 0 differ** (5 excluded per the documented list) |
| Single-thread timing, alternating A/B, 3 timed rounds after a warm-up | `wc_systematic` 10 tol.: **4.92 s vs 5.07 s** baseline; core suite **44.39 s vs 44.39 s** |

Timing detail (seconds; A = baseline, B = this tree):

| Round | A wc10 | B wc10 | A core | B core |
|---|---|---|---|---|
| 1 | 5.246 | 5.201 | 46.48 | 47.55 |
| 2 | 5.065 | 4.922 | 44.38 | 44.39 |
| 3 | 5.024 | 4.880 | 44.39 | 43.18 |

The new tree is faster on `wc_systematic` in every paired round, by about
3%, which is a hash lookup replacing a plist scan and a `putprop` per mark.
The suite is a tie. The change may not slow sequential Maxima, and it does
not. Stage C can proceed.

## Carried forward

- `ulabs` writes are refused, not confined. A workload whose queries call
  `cancel` (a contradicting fact during a query) will stop at the guard.
  That is the intended behaviour until `ulabs`'s two lifetimes are
  separated, which is its own change.
- The stage A limit stands: the guard sees `mset` and plist writes, not
  Lisp `setq`. The 18 fact-database specials reached the symbol set from
  the oracle's classification, not from the hook.
