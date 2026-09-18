# Multi-threading in Maxima: the immutability option

This document assesses one route to in-image concurrency: rebuilding
Maxima's environment on immutable (persistent) data. It doesn't recommend
doing that. It sets out what the change would involve, which parts are
mechanical, which aren't, and what would be worth doing whatever is decided.

It builds on [03-codebase-concurrency-analysis.md](03-codebase-concurrency-analysis.md).
Counts are grep-level estimates against `sourceforge/master` at `9b545c065`.

## Why immutability matters

A data race needs two conditions at once: two threads can reach the same data,
and at least one of them writes it. Removing either condition makes the data
safe:

|  | Immutable | Mutable |
|---|---|---|
| **Shared** | Safe, no coordination needed | The hazard: locks, atomics or a redesign |
| **Thread-local** | Safe | Safe |

There are three standard remedies:

- **Immutability:** make shared data read-only.
- **Confinement:** give each thread its own copy.
- **Synchronisation:** keep the data shared and serialise access. This fixes
  correctness but gives up parallelism on that data.

Doc 03 found that Maxima's *values* (expressions) are mostly immutable by
convention. Its *environment* (everything reached through a symbol) is shared
and mutable. Immutability is the principled fix for the environment.

## Lisp permits immutability but doesn't enforce it

Lisp's reputation for functional programming comes mostly from Scheme, ML and
Clojure. Common Lisp, and Maclisp before it, is imperative:

| Feature | Mutable? |
|---|---|
| Cons cells | Yes: `rplaca`, `rplacd`, `nconc` |
| Symbols | Yes: value cell, function cell and property list, writable by anyone who can name the symbol |
| Property lists | A global mutable key-value store on every symbol |
| Special variables | Global unless bound; Maclisp scoped variables dynamically by default |
| Literal constants | Modifying them is undefined behaviour in the standard, but mostly not prevented |

Macsyma was written from the late 1960s onward on PDP-10s with at most 256K
words of memory. Its style follows from that:

- **Consing was expensive**, so reusing cells (`rplacd`, `nconc`) was an
  optimisation.
- **Property lists were the cheapest associative store.** Data hangs off a
  name the code already holds, one pointer chase away. Facts, rules,
  definitions and query scratch all ended up there.
- **Dynamic scope turned globals into implicit parameters.** Option variables
  are read deep in the call stack instead of being passed down.
- **There was one thread,** so shared mutation cost nothing to reason about.

These were good choices for their time. The result is that a symbol's
*identity* and its *state* are the same object: `$x` *is* the variable's
current state.

Two Lisp features do suit concurrency, but Maxima's environment uses neither:

1. **Persistent structure by convention.** Cons trees that nobody mutates can
   share structure freely. Maxima's expressions mostly work this way, which is
   why the value layer came out nearly clean in doc 03.
2. **Thread-local dynamic binding.** In SBCL a `let` of a special gives each
   thread its own binding. This makes the ~1340 specials a mechanical problem.
   Maxima's interpreted binding (`mbind` → `mset`) bypasses the mechanism.

## What an immutable environment would look like

The model is Clojure's split between **values** and **identities**:

- **Values** are immutable persistent data structures.
- **Identities** are references that point at successive values and are
  updated atomically.

Applied to Maxima:

- **Environment as a persistent map.** Symbol → properties, value and
  definitions. This could use a hash array mapped trie, such as the one in the
  FSet library. A special variable holds the current version. A definition
  (`:=`, `tellsimp`, `declare`, `assume`) produces a new version and swaps the
  reference.
- **Snapshots are O(1).** A thread captures the current version and works
  against it undisturbed. That's the snapshot contract from the strategy
  discussion, provided in memory instead of by `fork`.
- **Fact database.** Facts become persistent data, and query marks move to a
  per-query table.
- **CRE.** Each CRE carries its own immutable variable order and kernel map.
  The header already holds `varlist` and `genvar`, so this means trusting the
  header instead of mutable gensym state.

## Scale

| Scope | Plist operations (`get`, `putprop`, `remprop`, `setf get`, `mget`, …) | Files | Lines |
|---|---|---|---|
| `src/` (excluding SLATEC) | 1342 | 202 | ~141k |
| `share/` | 576 | 805 | ~326k |

Doc 03 adds these figures:
- 105 indicators are written at run time; about 90 write sites run during
  ordinary computation.
- 1241 destructive list operations.
- About 1340 special variables.

`share/` is largely third-party and partly unmaintained. Any change to how
the environment is stored needs a compatibility path for it.

## A staged migration

A strangler-fig approach puts an indirection layer in front of the old store
and then replaces what is behind it:

1. **Accessor layer.** Replace direct `get`/`putprop`/`remprop` on
   environment indicators with `env-get`/`env-put`/`env-rem`, which at first
   still use plists. Behaviour doesn't change, and the existing test suite
   verifies the step.
2. **Classify every indicator** by lifecycle: load-time (read-only), user
   definition, query scratch, cache, or a real effect of computation. Doc 03
   has most of this for `src/`.
3. **Layered environment.**
   - *Base:* the ~655 load-time `defprop`s stay as read-only plists, so the
     hot path stays fast for built-ins.
   - *Overlay:* a persistent map holds only what users change.
   - *Snapshot:* a thread's snapshot is the current overlay version.
4. **Move scratch and caches out of the environment.** Fact database marks go
   to a per-query table, recursion stacks and `sublis` markers to specials,
   and memo tables get a lock or become per-thread.
5. **CRE ordering.** CREs carry their own order, or every operation gets fresh
   variables in place of the shared, renumbered pool.
6. **Binding.** `mbind` is rebuilt on `progv`, and every special is bound at
   thread entry.

## How mechanical is it?

| Step | Nature | AI speed-up |
|---|---|---|
| 1. Accessor layer | Mechanical and local; the existing tests verify it | Very large |
| 6. `progv` binding, specials bound at entry | Mechanical, with a few irregular sites (debugger frame swapping, `errlfun1`) | Large |
| 4. Fact database scratch | Contained: selector macros concentrate access (~55 functions, est. 100–200 lines) | Large |
| 2. Indicator classification | Judgment about intended behaviour, not syntax | Moderate: AI builds the inventory, people decide |
| 3. Environment layering | Design decisions (below) | Small |
| 5. CRE ordering | `pointergp` sits in the inner loop of polynomial arithmetic; order context must be carried through the `rat3*` call graph | Moderate for editing, small for performance validation |
| Destructive list operations | Aliasing analysis: does this `nconc` touch fresh or shared structure? The answer depends on every caller | Poor: whole-program reasoning, and mistakes are silent |

The hard parts have one thing in common: **their correctness can't be
checked locally.** Step 1 is mechanical because each edit can be checked
against the line it changes. Aliasing depends on data flow across the whole
program. Semantic questions depend on what the original authors meant, which
is often unrecorded. For example: is `ask-integer` declaring a fact scratch
state or a user-visible effect?

### Design decisions that no transformation makes

- **Visibility.** When does a definition in one thread become visible to
  others: immediately, at the end of the parallel region, or never?
- **`kill`.** Does `kill` inside a snapshot affect only that snapshot?
- **Read-your-writes.** Code that makes a definition during a computation
  must still see it. Examples are `ask-integer` → `$declare` and
  `factor(e, minpoly)` → `tellrat`. The thread's current version has to
  update, while other threads keep theirs.
- **Merging.** What happens to `$values`, `$functions` and labels created
  inside a parallel region?
- **Share compatibility.** `share/` code that calls `putprop` directly either
  goes through a shim or runs only outside parallel regions.

## Verification is the bottleneck

AI shortens editing. It doesn't shorten the evidence that the result is
correct under concurrency:

- **The existing suite can't see a race.** It runs single-threaded. The
  doc 03 failures (wrong sign, wrong bigfloat precision, renumbered CRE
  variables) all pass it.
- **Races are silent and depend on timing.** Catching them needs new
  infrastructure:
  - running the whole suite in N threads at once and comparing against
    sequential output;
  - stress tests that force threads to collide;
  - ideally a race detector. SBCL has nothing like ThreadSanitizer, so that
    would be a project in itself.
- **Review is its own limit.** The project's culture is minimal diffs that
  cherry-pick between release branches (AGENTS.md sec. 10 and 15). A change
  to over 1300 core sites is a large review load for a small volunteer team,
  several of whom have said they don't want the feature. David Scherfgen
  warned on the list that AI makes serious mistakes in Maxima code; review is
  where that risk would have to be met.

AI shrinks the mechanical fraction of the project towards zero. What remains
(design, aliasing checks, the concurrent test harness, review and acceptance)
is most of the original project. This is Amdahl's law applied to the project
itself.

## Arguments for and against

**For:**

- It is the principled fix. It removes the hazard instead of guarding it.
- The value layer already follows this discipline, so the change is confined
  to the environment.
- Snapshots in memory are cheaper than `fork` and work on Windows.
- Environment versions have uses beyond threads: undo, cheap "what if"
  evaluation, and reproducible sessions.
- Steps 1, 4 and 6 fix latent single-thread bugs as they go: specials leaking
  between call sites, and query state that survives an error.

**Against:**

- **Hot-path cost.** A plist lookup on a hot indicator is one or two pointer
  hops. A persistent map lookup is several hops plus hashing, and the
  simplifier and evaluator do these constantly. The layered design limits the
  cost to user-defined symbols, but that still needs measuring.
- **The CRE change reaches the fastest code in the system.** Polynomial
  arithmetic performance is sensitive to how variable order is looked up.
- **Semantic changes.** Code that relies on global side effects during
  computation would behave differently.
- **Share compatibility** is a permanent tax.
- **Adoption.** Upstream acceptance is uncertain at best.
- **Processes give the same snapshot semantics today** on macOS and Linux,
  with no code changes.

## Hard or easy, in summary

| Part | Difficulty | Why |
|---|---|---|
| Accessor layer | Easy | Mechanical; existing tests verify it |
| Binding specials, `progv` for `mbind` | Easy to moderate | Mechanical, a few irregular sites |
| Fact database scratch | Moderate | Contained, but central to correctness |
| Context switching per thread | Moderate | Visibility model (`cmark`) must change |
| Layered environment | Moderate to hard | Design decisions and hot-path performance |
| CRE ordering | Hard | Deep representation change in performance-critical code |
| Destructive-mutation audit | Hard | Whole-program aliasing; silent failures |
| Verification harness | Moderate, and essential | New infrastructure; SBCL has no race detector |
| Upstream acceptance | Hard | Review load and maintainer scepticism |

## Worth doing regardless

Two steps are cheap, useful whatever is decided later, and don't commit the
project to a rewrite.

1. **The accessor layer (step 1).** It's mechanical, verified by the existing
   suite, and useful for reasons that have nothing to do with threads: one
   place to instrument, audit or cache environment access. Most importantly,
   it enables a **write barrier**. `env-put` can trap any environment write
   during a parallel region. That gives complete coverage for dynamic
   detection of tame workloads (strategy discussion) and turns doc 03's
   static inventory into a runtime measurement.
2. **A concurrent test harness.** Run the suite and the known failure cases
   in N threads or processes and compare with sequential output. Any
   concurrency work needs it, and it gives an objective check on claims such
   as "nearly finished".

With both in place, measure how many writes the barrier catches on real
workloads such as `wc_systematic`. How to tell whether that measurement can
be trusted is covered in
[05-validating-the-write-observer.md](05-validating-the-write-observer.md). That number shows whether a
frozen-environment thread mode is close (few writes, mostly scratch) or far
away (writes throughout the simplifier). Only then does the case for or
against the rest of the migration rest on evidence.

## Decision points

1. After the accessor layer and harness: does the write barrier show
   tractable write traffic on target workloads?
2. After the doc 02 measurements: does a process pool already beat the
   thread ceiling set by the GC fraction? If so, the thread case weakens
   whatever the barrier shows.
3. Before step 3: can the hot-path cost of a layered environment be kept
   within an acceptable single-thread slowdown? This needs a prototype
   benchmark.
4. Before step 5: is a CRE representation change acceptable to the people
   who maintain `rat3*`?
