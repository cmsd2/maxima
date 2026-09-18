# Multi-threading in Maxima: codebase concurrency analysis

This document looks at how Maxima stores and moves state, to judge how hard
true shared-memory concurrency would be: several SBCL threads running Maxima
computations in one image. It follows
[01-mailing-list-discussion.md](01-mailing-list-discussion.md) and
[02-workloads-and-performance-model.md](02-workloads-and-performance-model.md).

The tree is `sourceforge/master` at `9b545c065` (2026-09-18). The work was a
static survey of `src/`, split into four parts:

- evaluator and binding;
- global state and destructive mutation;
- property lists and the CRE system;
- the fact database.

I re-checked the central claims directly against the source (marked
**verified** below). Counts come from grep or small s-expression scripts, and
the method is noted where it matters. Nothing was built for this document.
One behavioural observation (CRE gensym reuse) came from running the installed
Maxima 5.49.0.

## Classification used

Every finding is placed in one of four classes:

| Class | Meaning | Typical fix |
|---|---|---|
| **a** | Read-only after startup | Nothing |
| **b** | Isolatable per thread by a Lisp binding | Bind the special at thread entry |
| **c** | Shared and mutable, needs synchronisation | Lock, atomic, synchronized hash table |
| **d** | Architectural: the data model shares it | Change the representation |

Background: in SBCL a `let`/`progv` binding of a special variable is
thread-local. A `setq` of a special that the current thread hasn't bound
writes the global value, which every thread sees. Symbol property lists are
always global.

## The shape of Maxima's state

### The interned symbol is the hub

Almost all state hangs off interned symbols, reached through the reader's
global package. A symbol such as `$f` or `$x` carries several independent
stores:

```
                       ┌───────────────────────────────────────────┐
  user symbol $x ──────┤ value cell   ← mset, and every Maxima bind │
                       │ plist:                                     │
                       │   mprops (mexpr, hashar, array)  ← :=      │
                       │   operators, oldrules, rules     ← tellsimp│
                       │   opers, $commutative, …         ← declare │
                       │   data  ──────────► facts (fact database)  │
                       │   +labs, -labs   ← every sign query        │
                       │   internal       ← limit, integrate        │
                       │   msublis marker ← sublis                  │
                       └───────────────────────────────────────────┘
  global info lists   $values, $functions, $arrays, $props, $myoptions
                       ← add2lnc: destructive nconc / delete

  CRE gensym G123 ─────  value cell = variable order (pointergp)
                         plist: disrep (which kernel it stands for),
                                tellrat, algord, diff, …
  global pool          genvar, varlist  ← $rat extends and renumbers

  context symbol ──────  plist: data (facts), subc (parents), cmark
  globals              context, $context, $contexts, current
```

Expressions (`((mplus simp) …)`) are mostly treated as values: the
simplifier builds new structure. They refer to symbols, though, and what a
symbol *means* (its value, its simplifier, its facts, its CRE ordering) lives
in the mutable stores above. So values are shareable but meaning isn't.

### What a single evaluation writes

Here is what one ordinary computation touches, such as calling a user
function that simplifies a product of powers and converts to CRE form. Each
step is a write to state other threads can see.

1. **Binding the parameters.** `mbind-doit` stores each argument with `mset`,
   which does `(setf (symbol-value x) y)` on the global value cell. It pushes
   the old value onto the global stacks `bindlist` and `mspeclist`. `munbind`
   restores it by `mset` from `mspeclist`. **Verified.** An unbound
   parameter is appended to `$values` by `add2lnc` (`nconc`) on entry and
   deleted on exit.
2. **Evaluating.** `meval1` does `(setq *last-meval1-form* form)` on every
   function-call form. `mlambda` pushes 5 entries per frame onto the global
   `*mlambda-call-stack*`. Memo functions (`a[n]:=`) `nconc` into shared
   hash buckets on a miss (`harrfind`).
3. **Simplifying.** `simplifya` dispatches through plists (`operators`,
   `opers`, `distribute_over`, `oldrules`). Those are reads, but
   `tellsimp`/`declare`/`kill` in another thread can change them mid-flight.
   `eqtest` stamps a `simp` header onto its input with `rplaca`.
4. **Asking sign.** `timesin` calls `$csign` when merging powers in every
   product, and `simpexpt` calls `maxima-integerp`/`kindp`. Any query that
   reaches a node with facts runs `clear`: it resets `+labs`/`-labs` on the
   plists of every node the previous query touched and `setq`s about 15
   queue and label globals. The walk then writes new labels onto shared
   plists with `dmark`. **Verified.**
5. **Changing assumption context.** `$integrate`, `risch`, `defint`,
   `laplace`, `sum` and limit series steps use `with-new-context`, which calls
   `$supcontext`. That does `(setq context … $context …)` with no binding,
   so it switches the context for the whole image. **Verified.**
6. **Converting to CRE.** `$rat` binds neither `varlist` (unless variables are
   given) nor `genvar`. `orderpointer` extends the global `genvar` pool and
   `prenumber` renumbers every gensym's value cell. Variable order is
   `(> (symbol-value a) (symbol-value b))`. **Verified.** Converting back
   (`ratdisrepd`) writes each kernel onto its gensym's `disrep` property,
   then reads it back.
7. **Making bigfloats.** `bcons` caches the header in two unbound globals,
   `*bfloat-header*` and `*bfloat-header-prec*`. Two threads at different
   `fpprec` can produce a number stamped with the wrong precision.
   **Verified.**
8. **Reporting an error.** `merror` does `setq $error`.
9. **Returning to the top level.** It writes `$%`, `$_`, `$__`, `$linenum`,
   `$labels` and the values of `%iN`/`%oN`, and `clearsign` retracts asked
   facts from the shared `$initial` context.

Even a computation the user thinks of as a pure function of its inputs writes
shared state at nearly every step. This matches the failures seen on the
mailing list: the 9544 of 10000 variables (step 1), corrupted `limit` state
(steps 4 and 5), and the crashing `block`-local Newton loop (step 1).

## Findings by subsystem

### Evaluator and binding

| Finding | Evidence | Class |
|---|---|---|
| Maxima binding is shallow: save, overwrite the global value, restore | `mbind-doit`, `munbind`, `mset` in `mlisp.lisp` | d |
| Save stacks are single global lists, never rebound | `bindlist`, `mspeclist`, `loclist`, `mproplist`, `factlist` in `globals.lisp`; only `setq` sites | b |
| Every `block`, `for`, interpreted function call and `ev` flag goes through that path | `mbinding` (maxmac), `mprog`, `mdo`, `mdoin`, `mlambda`; 22 call lines, all lexically scoped apart from `errlfun1` and the debugger | d |
| **Translated** code binds its variables with `(declare (special …))`, which is thread-local in SBCL | `vanilla-lambda` (transq.lisp), `transl.lisp` `do` codegen | a/b |
| `$local` localises by saving and editing plists (`mprops`, `data`) | `$local`, `munlocal` | d |
| Assignment updates `$values`/`$myoptions` destructively | `add2lnc` (61 call sites) | c |
| Memo function calls write buckets, counters and resize | `harrfind`, `arrfind` | c |
| Compiled-lambda cache with random eviction | `*lambda-expr-funs*` in `mapply1` | c |
| Autoload marks a file loaded *before* loading it | `generic-autoload` pushes onto `*autoloaded-files*` first | c |
| Top-level labels are global symbols | `%iN`/`%oN` values set in `continue` | d |
| Already per-thread: catch tags, handlers, `errcatch`, `$%%`, `$load_pathname`, `*mread-prompt*` | `let` bindings in place | a/b |

The shallow binding is the one that matters most. It also explains why
translated code behaves differently from interpreted code. Since every normal
call site has lexical extent, `mbind` could in principle be rebuilt on
`progv`. That would keep the `assign`/`setter-method` hooks and `$values`
bookkeeping but make the value cell per thread. It hasn't been prototyped.

### Global specials, caches and destructive mutation

Counts in `src/` (excluding `numerical/slatec`):

| Kind | Count |
|---|---|
| Top-level `defmvar` / `defvar` / `defparameter` / `defconstant` | 467 / 526 / 11 / 44 |
| Distinct special names, including `declare-top (special …)` | about 1340 |
| Specials assigned by `setq`/`setf` outside any binding in the same function | 459 names, 1508 sites |
| … and **bound nowhere in `src/`** | 216 names, 476 sites (29 names on hot paths) |
| Destructive list operations (`nconc`, `rplaca`, `rplacd`, `delete`, `sort`, `nreverse`, …) | 1241 sites, 250 in hot files |
| `make-hash-table` calls / tables created `:synchronized` | 31 / 0 |

The binding-versus-assignment count comes from an s-expression scanner that
doesn't macroexpand. It misses `bind-fpprec`, `with-new-context` and
`mbinding`, so "bound somewhere" overstates safety. The "bound nowhere"
figure is the more reliable one.

The patterns:

- **Caller binds, callee assigns (safe once entry points bind).** The sign
  quartet `sign`/`minus`/`odds`/`evens` is bound by `$sign`, `$asksign`,
  `sign*` and `meqp`. `*plusflag*` is bound by `simplus`, `varlist` by
  `$factor`, and `fpprec` plus its constants by `bind-fpprec`.
- **Nobody binds (a global write on every call).** Examples: the `bcons`
  header cache; `*last-meval1-form*`; `newprime` `nconc`ing onto
  `*bigprimes*`; `$integration_constant_counter`; the `cpoly` working arrays
  `*nn*` and `*pr-sl*`, which two concurrent `allroots` would share; and the
  display scratch array `linearray`.
- **Assign hooks spread writes.** `fpprec:` runs `fpprec1`, which sets
  `fpprec` and four bigfloat constants. `numer:` sets `float`. `context:`
  runs `asscontext`. `stardisp:` writes the `dissym` plist of `mtimes`.
  Because `mbind` goes through `mset`, `block([fpprec:50], …)` fires these
  hooks against global state.
- **Lazy caches without locks.** These include `*lambda-expr-funs*`, the
  per-precision `%pi`/`%e`/`%gamma` memo tables in `float.lisp`,
  `*bigprimes*`, the Bernoulli/Euler arrays (`adjust-array` with the limit on
  a plist), `*prime-diffs*`, and the gettext domain tables. Concurrent writes
  can corrupt an unsynchronized SBCL hash table.
- **SLATEC.** 76 of 122 translated Fortran files keep SAVE/DATA state in
  top-level `let` closures, for example the `j4save` error state and
  `dgamma`'s lazy init.
- **The simplifier mostly mutates fresh structure.** `plusin`/`timesin`
  edit accumulators built by their caller. The exception is `eqtest`, which
  `rplaca`s a `simp` header onto its input (reached from `simpargs` for
  `mlist`/`mequal`, and from compiled rules). That write is idempotent and
  probably a benign race, but it hasn't been proven.
- **`$gensym` interns its result**, so a counter race could hand two threads
  the same interned symbol.

### Property lists and the CRE system

Plist writes in `src/` (regex scan, literal indicators only):

| Writer | Load time | Run time |
|---|---|---|
| `putprop` / `mputprop` / `zl-put` | 49 | 175 sites, 84 indicators |
| `(setf (get …))` | 226 | 40 sites, 26 indicators |
| `remprop` / `zl-remprop` | 0 | 88 sites, 64 indicators |
| `defprop` | 655 | n/a |

105 distinct indicators are written at run time. They fall into three
lifecycles:

- **Load only (a).** The `defprop` table: simplifier dispatch for built-ins,
  `grad`, `alias`, and so on.
- **User definitions.** Written by `:=`, `tellsimp`, `declare`,
  `matchdeclare`, `put`, `depends`, `gradef` and `kill`. These are the
  indicators the hot path reads: `simplifya` reads `operators`, `opers`,
  `distribute_over` and `oldrules`, and `meval1` reads `mexpr`, `hashar`,
  `noun`, `mfexpr*` and others. `init-cl.lisp` `optimize-symbol-plist`
  moves them to the front of built-in plists, which confirms they are hot.
  `kill` replaces whole plists. A definition in one thread changes the
  behaviour of simplification already under way in another thread (c).
- **Ordinary computation (the critical group).** About 60 write sites
  outside the fact database, and 28 inside it:

| Indicator | Writer | Reached from | Class |
|---|---|---|---|
| `disrep`, `tellrat`, `algord`, `unhacked`, value cell | `newsym`, `orderpointer`/`prenumber`, `ratdisrepd` (rat3e) | every `rat`, `ratsimp`, `factor`, `integrate`, `limit`, `solve` | b if `genvar` bound, else d |
| `leadop`, `rischexpr`, `rischdiff`, `rischarg` | `intset1` (risch) | `integrate` | b |
| `varorder` | `putorder`/`remorder` (algsys, no unwind-protect) | `solve`, `algsys` | b |
| `internal` | `calculate-series` (on the **user's** limit variable); defint on interned `yx`, never removed | `limit`, `integrate`; read by `has-int-symbols` to suppress questions | c |
| `current-recursion-args` | `call-with-safe-recursion`, on one interned symbol used as a stack | `meqp-by-csign` (`is(a=b)`, sign) | c |
| msublis marker | `msublis-setup` prepends to **user** symbol plists | `sublis` | c |
| `lim` | `bern`, `euler` caches | Bernoulli/Euler evaluation | c |

**The CRE variable pool** is the deepest part of this subsystem:

- CRE variables are uninterned gensyms kept in the global pool `genvar`.
  `orderpointer` reuses the pool and creates only the extra gensyms it needs,
  and `prenumber` renumbers all of them. **Verified.**
- Variable order is the gensym's value cell (`pointergp`, 35 call sites).
- `$rat`, `$divide`, `$content` and, by a first-level scan, about 14 other
  user functions (including `ratexpand`, `allroots`, `ev` and `nthroot`)
  don't bind `genvar`. `$factor`, `ratsimp`, `taylor`, `risch`, `algsys`,
  `solve` and `nalgfa` do.
- Running Maxima 5.49.0 showed the same gensym standing for `b3` in one input
  and `x` in the next, with a different order value each time.
- Converting a CRE back writes its kernels onto the gensyms' `disrep`
  property, then reads them back. A CRE stored in a Maxima variable shares its
  gensyms with every other holder of that CRE.

Binding `genvar` per thread fixes the pool (b). It doesn't fix CREs held in
shared variables, because their meaning lives in mutable symbol state rather
than in the CRE itself (d). The fix is to carry the kernel mapping in the CRE
header and pass it explicitly.

### The fact database and sign

Structure:

- A **node** is a symbol, or a cons `(x . plist)` for non-symbol objects,
  kept in the global lists `dobjects` and `*nobjects*`. The number chain is
  rewired with `rplacd` when a new number is assumed, and rebuilt by
  `db-gc`.
- A **fact** is a cell whose plist holds `con` (its context) and `ulabs`. It
  is pushed onto the `data` property of every node it mentions.
- A **context** is a symbol with `data`, `subc` (parents) and `cmark` (a
  visibility counter). `cntp` decides visibility from `cmark`.
- **Query scratch** lives in the `+labs`/`-labs`/`ulabs` plist entries and
  about 15 global queue and index specials. None of them is bound anywhere.

The query algorithm clears on entry, not on exit. `init-cl.lisp` notes that
marks persist until the next `clear`. A concurrent query's `clear` erases
another thread's labels mid-walk and produces a **wrong sign with no error**.
The only read-only fast path is for nodes with no facts. Anything involving
`%pi`, `%e`, declared or assumed symbols, or function kinds writes labels.
(`sign` on any function call checks `kind-any-of` for `$posfun`/`$oddfun`.)

**How often simplification reaches sign** (grep counts of call sites):

| File | Call sites |
|---|---|
| `simp.lisp` | 54 (`$csign` 25) |
| `csimp2.lisp` | 37 |
| `trigi.lisp` | 16 |
| `rpart.lisp` | 14 |
| `src/` total | `$sign` 213, `$asksign` 88, `$csign` 77, `maxima-integerp` 79 |

By function: `simpexpt` 15, `timesin` 7, `simpln` about 7, `simpabs` 5.

**Facts written by ordinary computation.** `rectform` of a power
(`absarg1`: assume, then forget `notequal`). `limit`'s assumes on the shared
`prin-inf`. `ask-integer` running a real `$declare`. `asksign` answers filed
in `$initial` and pushed onto the unbound `*local-signs*`. The internal
`assume` callers:

- `defint` (10)
- `limit` (5)
- `laplace` (5)
- `sin` (4)
- `hypgeo` (2)
- `asum` (2, plus a `declare`)
- `irinte` (1, never forgotten)

**Options for making queries safe:**

1. **Global lock.** It has to be recursive and span a whole top-level query,
   since sign recurses through `limit`, `rectform` and user predicates. With
   `timesin` and `simpexpt` on the path, much non-polynomial simplification
   would serialise.
2. **Per-query side table.** Every label access goes through the selector
   macros for `+labs`/`-labs`/`ulabs`, so redirecting them to a thread-bound
   `eq` hash table and binding the queue specials is contained. The estimate
   is about 55 functions and 100–200 lines. `$local`'s persistent
   `ulabs -1` flag has to move to its own key first. This fixes the scratch
   state only; facts and contexts still need a reader/writer lock, and
   writers are frequent (above).
3. **Per-thread contexts.** Replace the shared `cmark` counters with a
   thread-local active set, and bind `context`/`$context` per thread. That
   includes making `with-new-context` bind instead of `setq`.

## Size and difficulty

| Class | What falls in it | Scale | Effort |
|---|---|---|---|
| a | Load-time plists, built-in tables, catch/handler machinery | Most of the 655 `defprop`s and the load-time `setf get`s | None |
| b | Option variables, unbound specials, save stacks, `genvar`/`varlist`, `*local-signs*`, display and REPL state | ~1340 specials; bind them all with `progv` at thread entry | Mechanical, but every assign hook's side effects must be enumerated |
| c | Info lists, memo tables, lazy caches, autoload, `$gensym`, SLATEC closures, plist-as-scratch indicators | Dozens of sites | Moderate; each needs a lock or a move to a special |
| d | Shallow Maxima binding, fact database scratch on plists, context switching, CRE gensym state, hot-path plists mutable by user definitions | Five mechanisms | Large; each is a data-model change |

The five class-d mechanisms, from most to least contained:

1. **Shallow binding** (`mbind` → `progv`). Contained, because call sites are
   lexically scoped. The debugger's frame swapping and `errlfun1` need
   rework.
2. **Fact database scratch** (per-query table). Contained by the selector
   macros. An estimated 100–200 lines.
3. **Context switching** (`with-new-context`, `asscontext`, `learn-*`).
   Contained in `compar.lisp`, but the visibility model (`cmark`) has to
   become per thread.
4. **CRE gensym state.** Binding `genvar` is easy. Making stored CREs
   self-describing is a change to a core representation used throughout
   `rat3*`, `ratout`, `hayat` and `nalgfa`.
5. **User definitions visible mid-computation.** This can't be engineered
   away in a shared image; it has to be a rule. The environment must be
   frozen (no `:=`, `tellsimp`, `declare`, `kill`, `load` or `assume` from
   user code) while threads run.

## Assessment

- **David Scherfgen's objection is correct.** The problem is the data model:
  symbol plists and the global value cell, and it isn't solved by checking
  variables one at a time. Two of his specific claims are confirmed in the
  source: that `sign` writes during read-only queries, and that function
  calls mutate `$values`. The survey adds three more hidden-write mechanisms
  he didn't mention:
  - `$rat` renumbering the shared gensym pool;
  - `$integrate` switching the global assumption context;
  - `bcons` caching the bigfloat header.
- **Gunter Königsmann's model is incomplete.** "Most variables already
  declared the Right Way" holds for Lisp specials bound by callers. It
  doesn't hold for Maxima-level variables, which never get a Lisp binding
  in interpreted code, or for any plist state. His list of exceptions (load,
  memoization, hash tables, gensym) is correct as far as it goes, but it
  covers only the class-c items.
- **"Impossible short of a redesign" (Robert Dodier) overstates it for a
  restricted mode.** Four of the five class-d mechanisms have contained
  fixes, and the fifth becomes a usage rule. A thread mode that freezes the
  environment and confines everything else per thread looks like a bounded
  engineering project. It still means touching the evaluator, the fact
  database, the context machinery and the CRE layer: the core of the system,
  with correctness risk in each.
- **Processes need none of this.** A forked worker confines every store
  above at once. The comparison for any thread work is therefore the
  process-farm baseline from doc 02, not a sequential run.

## Unverified points

- SBCL atomicity of `gensym`, `intern` and plist updates (`(setf get)`,
  `remprop`) under concurrent writers.
- Whether every `testp`/`plusin` term edit touches only fresh structure.
- The list of about 14 user functions that don't bind `genvar`. It's a
  first-level scan and misses indirect calls.
- Line-count estimates for the fact-database and `mbind` changes. Neither is
  prototyped.
- Contention on a global sign lock. This needs profiling.
