# Stage C results: oracle and gap measurement

Change: `add-environment-accessor-layer`, tasks 5.1–5.5. No conversions
yet: this measures the gap left by the stage B hook alone.

## The oracle (task 5.1)

`tools/oracle.lisp` snapshots every plist slot and bound value cell of the
symbols accessible in `:maxima`, plus the `genvar` gensyms, the
fact-database nodes and any temporary context. Each slot is stored as
`(value . deep-hash)`, with a cycle guard.

Comparing two snapshots gives one of these kinds per slot or object:

| Kind | Meaning |
|---|---|
| `:added` / `:removed` / `:replaced` | a slot write |
| `:mutated` | the same value object, with a changed deep hash: in-place mutation |
| `:appeared` / `:vanished` | a whole object joined or left the tracked set |

A slot write is **explained** when the hook log (keyed by object identity)
recorded a matching write.

Cost: a snapshot takes about 4 ms (7,632 plist slots on 13,046 symbols),
and the full suite with one snapshot per problem runs in 275 s.

Hand checks:

| Case | Result |
|---|---|
| `rplacd` inside `f`'s stored `mexpr` | `:MUTATED $F MPROPS`, unexplained |
| Direct `(setf (get …))` | `:ADDED`, unexplained |
| `putprop` | `:REPLACED`, explained by `:PUT` |
| `mset` of a fresh variable | value explained by `:ASSIGN`; `:MUTATED $VALUES` unexplained (`add2lnc`'s `nconc`) |

## Seeded bypasses (task 5.2)

`tools/seeded-test.sh` passes. Every planted bypass is caught:

| Bypass | Scanner | Oracle |
|---|---|---|
| `(setf (get …))` in a function | ✓ | ✓ `:added` |
| `(funcall #'(setf get) …)` | ✓ | n/a: `#'(setf get)` is undefined in SBCL, so this can't occur in working SBCL code |
| `(setf (getf (symbol-plist …) …))` | ✓ | ✓ `:added` |
| `rplacd` on a stored value | n/a | ✓ `:mutated` |
| `nconc` onto `$values` | n/a | ✓ `:mutated $VALUES` |

## The gap (tasks 5.3, 5.4)

Full suite with share tests under the oracle: **no unexpected errors out of
21,498 tests**. The hook observed **97.5 million writes**. The oracle
found 235,222 slot/object differences, of which 197,962 are unexplained.
Two runs give identical counts. Full breakdown: `gap-report-stageC.md`.

| Class | Unexplained | Scope |
|---|---|---|
| **A. Plist slot writes outside the funnel** | **19,033** (70 indicators) | **Stage D conversion targets** |
| M. Objects appearing or vanishing | 8,612 | fresh symbols (6,626), CRE gensyms (531 in and out), DB nodes (462 in and out) |
| B. In-place mutation of stored values | 27,046 | unobserved class: `DATA` fact lists (25,965), `MPROPS` (1,078) |
| C. Value-cell changes of specials | 143,271 (1,802 variables) | unobserved class; 96% categorised in `oracle-churn.tsv` |

### Class A by source

These were matched to scanner worklist sites by literal indicator:

| Source | Writes | What |
|---|---|---|
| `suprv1.lisp` (with `mlisp`, `mdebug`) | about 16,500 | `kill` removing `MPROPS`, `NOUN`/`VERB`, operator properties; `LINEINFO` |
| `transl.lisp` | 1,003 | `MODE`, `TRANSLATED` |
| `fortra.lisp`, `rat3e.lisp`, `mactex.lisp`, `nset.lisp`, … | under 250 | |
| No literal match (variable indicator, macro or `share/`) | 807 | |

By write count, the funnel already covers about 99.98% of plist slot writes
(97.5M observed against 19k unobserved). The unobserved writes are
concentrated in a few files, `kill` above all.

### Class C categories

| Category | Differences | Notes |
|---|---|---|
| driver-io | 64,353 | test driver and reader streams |
| eval-trace | 24,198 | `*LAST-MEVAL1-FORM*`, `*MLAMBDA-CALL-STACK*`, `$ERROR` |
| repl-labels | 19,144 | `$%`, `%iN`/`%oN`, `$LINENUM` |
| lisp-runtime | 8,582 | `*GENSYM-COUNTER*` |
| factdb-scratch | 7,142 | `+LABS`, queue pointers |
| uncategorised | 5,321 | long tail: `gf` package state, `cpoly` arrays, test variables unbound by `kill` |
| info-lists | 4,113 | `$VALUES`, `$PROPS`, `$FUNCTIONS` |
| algorithm-scratch | 3,585 | unbound working arrays (`*COL*`, `*ROW*`, `*MAT*`, …) |
| factdb-nodes | 2,016 | |
| cre-pool | 1,560 | `VARLIST`, `GENVAR` |
| result-vars | 1,186 | |
| bigfloat-cache | 827 | `*BFLOAT-HEADER*`: the `bcons` cache from doc 03 |
| name-counters | 647 | |
| rules | 159 | `*RULE-SYMBOL-POOL*` |
| parser | 154 | |
| factdb-contexts | 124 | `CONTEXT`/`$CONTEXT` switched by `$supcontext` |
| oracle-artefact | 160 | |

## Oracle bugs found and fixed while measuring

1. **The wrapper dropped `test-batch`'s extra return values.** `prog1` kept
   only one of the four, so every file reported an "error break" even though
   all problems passed. This was an observer changing results, caught by the
   suite summary. **Fix:** `multiple-value-prog1`.
2. **Object names containing newlines broke TSV rows.** **Fix:** sanitise
   names.
3. **Nodes joining or leaving the tracked set looked like slot writes.**
   **Fix:** report them as `:appeared`/`:vanished`.
4. **The explanation log was keyed with `equal`.** A fact-database node is a
   cons whose contents change, so its log entry could not be found again,
   and its funnelled writes looked like bypasses. **Fix:** key by `eq`
   identity.
5. **Indicators printed under a test's changed readtable case** (`:|VALUE|`).
   **Fix:** `with-standard-io-syntax`.

After each fix, the seeded test still passes and the suite still passes
under the oracle.

## Gate C assessment

**Is stage D worth doing?** Yes, and it's cheaper than the worklist
suggests. Class A is concentrated: converting `suprv1.lisp` alone should
remove about 85% of it, and `transl.lisp` most of the rest. The per-file
gate has a real metric: the class A count must fall by the amount that
file's indicators contributed.

**The more important finding for the research question:** the hook's
scope (plist slots and `mset`) is the *smaller* part of what changes in
the environment. After full conversion, class A goes towards zero, but
classes B and C remain. Those are about 170,000 unexplained differences per
suite run: fact-list mutation, info lists, fact-database scratch,
bigfloat caches, CRE pool, algorithm scratch arrays, REPL state. That
matches doc 03: most concurrency hazards are specials and in-place
mutation, not plist slot writes. It has two consequences:

1. For stage F, the **oracle**, not the hook, is the primary instrument
   for profiling `wc_systematic`. The hook's value is attribution (which
   indicator, and refusal), not completeness.
2. Class C categories map directly onto doc 03's fixes: specials that a
   thread-entry binding would confine (driver-io, repl-labels, eval-trace,
   cre-pool, bigfloat-cache, algorithm-scratch) versus shared structures
   that need a lock or a redesign (info-lists, factdb-*, rules, parser).
