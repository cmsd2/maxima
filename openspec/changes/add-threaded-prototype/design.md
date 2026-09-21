## Context

See `proposal.md` for motivation, `specs/` for the requirements, doc 05 for
the write measurement this change acts on, doc 07 for the process baseline
it must beat, and doc 08 for the spikes that recommended starting.

Facts that shape the design, each checked against the tree or measured:

- **A thread-entry binding confines `mset`.** Probed on this build: a
  symbol bound by `progv` in a thread, then assigned with
  `(setf (symbol-value s) v)`, keeps the write inside that thread; the same
  assignment with no binding in force writes the global cell and every
  thread sees it. `mset` ends in exactly that `setf`, so binding at thread
  entry is enough to confine it, with no change to `mbind`.
- **The unconfined case is silent.** There is no error, no warning, and the
  wrong answer appears somewhere else entirely. This is why the guard is a
  requirement and not a convenience.
- **Labels are written onto nodes.** `db.lisp`'s `+labs`, `-labs` and
  `ulabs` are specials holding lists of marked nodes, and the marks
  themselves go on the nodes with `putprop nd ... '+labs`. `clear` resets
  the lists at the start of each query (`truep` calls it), so the query
  state is already per query in intent; what escapes is the property write
  on structure other threads share.
- **The selector macros contain it.** `(selector +labs)`, `unlab` and the
  `+labs`/`-labs`/`ulabs` accessor macros are the only readers, so the
  representation can change behind them. Doc 03 estimated 100–200 lines.
- **`mset` already has a hook.** `*environment-write-hook*` is called on
  every assignment and unbind, so the guard needs no new call site.
- **Binding at thread entry removes a write.** `mset` calls
  `add2lnc x $values` only when the symbol is not `boundp`. Bound at thread
  entry, they are, so the shared info-list write doc 05 classed T3 does not
  happen.
- **`sb-posix:fork` needs a single-threaded image**, so the thread arm and
  the process arm cannot share one process. Each measurement runs in its
  own image, as in doc 07.

## Goals / Non-Goals

**Goals:**

- Run `wc_systematic` on threads, correctly, and measure it against the
  process pool.
- Make the fact-database change good enough to keep whatever the
  measurement says, since it is a correctness improvement in its own right.
- Fail loudly on anything the design cannot confine.

**Non-Goals:**

- Rebuilding `mbind` on `progv` (proposal; deferred until the verdict).
- A user-facing parallel map.
- Workloads beyond `wc_systematic` (proposal).
- Context switching, CRE gensym state, or the other items doc 03 listed
  beyond the fact database. `wc_systematic` does not reach them; another
  workload would.

## Decisions

### D1. Confinement by thread-entry binding, with a guard

Each worker thread starts with `progv` over the symbol set, binding each to
its current global value, then runs items. `mbind`, `munbind` and `mset`
are untouched and land in the thread's bindings.

The symbol set comes from the workload's recorded write trace (the
observation facility of the archived `environment-write-observation`
change), not from reading the code. `bindlist` and `mspeclist` are in it, as
are the specials doc 05 listed under T1.

The guard is a `*environment-write-hook*` function that checks each
assigned symbol against a per-thread table and signals an error naming any
symbol not in it. Cost is one hash lookup per write, on the order of 1% at
this workload's write rate by a rough estimate, and it is measured rather
than assumed (task 4.3). It runs in thread mode only.

*Alternative rejected:* rebuilding `mbind` on `progv`. It is the general
answer and it is step 1 of the roadmap, but it inverts control flow through
`mlambda`, `mevalatoms` and the `mprog` handler, and the verdict does not
need it.

### D2. Per-query label table

`+labs`/`-labs`/`ulabs` become a hash table held in a per-query special,
bound per thread, keyed by node. The selector macros change to read the
table; `clear` binds a fresh one. Node plists stop being written.

Two things to get right:

- **The label numbering stays.** `*labindex*`, `+lab-high-bit+` and the
  `unlab` indirection exist to invalidate stale marks cheaply. The table
  removes the need for that only if it is fresh per query; if the table is
  reused, the numbering still does the invalidating.
- **`compar.lisp` re-entry.** `$sign` and `$asksign` rebind the four sign
  specials plus `factored`; the label state has to be bound at the same
  point or a nested query will see an outer query's table.

*Alternative rejected:* a lock around the fact database. It would make
every `sign` call a serial section, which is the one thing doc 02 named as
turning into a true Amdahl fraction.

### D3. One item per task, static scheduling

Doc 07 found static scheduling beat dynamic for this workload, because item
costs are uniform and dynamic loses the overlap with worker start-up.
Threads have no fork to overlap, so both are worth measuring, but static is
the default.

### D4. What counts as a win

The thread arm must beat the process arm's measured 3.35× at four workers
on the same machine, with no lock on a hot path and the guard active.

| Outcome | Condition |
|---|---|
| **Win** | threads beat processes at four workers, and the gap is not inside the run-to-run spread |
| **Tie** | within spread of each other |
| **Loss** | processes beat threads, or the run needs a lock on the `sign` path |

A tie is a loss in practice: processes need no changes to Maxima and work
with `wrstcse` as shipped, so parity does not justify the difference.

### D5. Gates on the `src/` change

The fact-database change gates on all of:

- the full test suite with share tests, green, with the registry unchanged;
- `make check`'s dependency check, since `db.lisp` and `compar.lisp` sit
  under `:dependencies-complete` modules;
- the differential corpus from the observation change, no new diffs;
- a single-thread timing comparison on `wc_systematic` and the suite: the
  change may not slow sequential Maxima outside the noise floor;
- the write observer re-run, showing the label writes gone.

## Risks / Trade-offs

- **The symbol set may be incomplete.** A data-dependent branch, a gensym,
  a symbol interned during the run: any of these escapes the trace. The
  guard turns corruption into a refusal, which is the whole reason it is a
  requirement. It also means the mode refuses workloads it cannot prove
  safe, which is the intended behaviour rather than a limitation to fix.
- **The fact-database change touches everything.** Every `sign` call reaches
  it. Mitigation is D5's gate list, and keeping the change behind the
  selector macros so the diff stays small.
- **Threads may lose.** That is a result, and doc 07's pool is the fallback.
  The fact-database change is worth keeping either way.
- **One machine, four performance cores.** Spike A found the
  thread-to-process ratio sliding from 0.99 at two workers to 0.86 at
  eight, so this verdict will be specific to this machine.

## Migration Plan

The fact-database change is internal: no user-visible behaviour changes, no
option variable, no documentation beyond a `ChangeLog` entry. The
`wrstcse.mac` line changes a local's scope and is covered by that package's
own tests. The runner is research tooling and ships to nobody.

## Open Questions

- Does `clear` need to keep the label numbering once the table is per
  query, or does a fresh table make it redundant? Decided during task 2.1,
  from what the selector macros actually need.
- Is SBCL's `intern` thread-safe enough for items that create symbols? Doc
  05 recorded this as unverified. `wc_systematic` does not intern, so this
  change can leave it unverified, and a note in the decision record says so.
