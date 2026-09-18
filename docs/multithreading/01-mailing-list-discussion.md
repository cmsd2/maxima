# Multi-threading in Maxima: the 2026 mailing list discussion

Analysis of the maxima-discuss threads on thread safety, June to September 2026.
Source claims checked against `sourceforge/master` at `9b545c065` (2026-09-18).
Workload analysis and a performance model follow in
[02-workloads-and-performance-model.md](02-workloads-and-performance-model.md).

## Threads covered

| Dates | Subject | Messages |
|---|---|---|
| 5–7 Jun | A fix for SBCL error "thread local storage exhausted" when creating too many rules | 7 |
| 7–12 Jun | Maxima and thread safety | 20 |
| 14–15 Sep | Maxima and thread safety (recent efforts) | 18 |
| 15–18 Sep | goals and uses of thread safety review | 7 |

A side thread, "Race condition on loading packages from 2 maxima processes in
parallel?" (14–18 Jun), covers concurrent builds and loads across *processes*,
not threads. This document leaves it out.

Participants: David Scherfgen, Gunter Königsmann, Stavros Macrakis, Richard
Fateman, Raymond Toy, Robert Dodier, Michel Talon, Leo Butler, Andrew Wolven,
Chris D.

## Timeline

### 1. TLS exhaustion fix (5–7 Jun)

David fixed bug #4517: SBCL crashes after rules are created and destroyed
repeatedly (running `rtest_rules` a few times triggers it). The pattern
compiler in `matcom.lisp` generates fresh symbols and binds them dynamically.
SBCL gives each newly bound special its own TLS index from a counter that
only goes up, so it never reclaims those slots. The fix keeps a
`*rule-symbol-pool*` and recycles symbols when a rule is overwritten or
killed. TLS use then depends on the number of live rules, not on every rule
ever created.

Gunter asked what this means for multi-threading. David replied that the pool
would need a mutex, and that rule creation already mutates `$rules` and symbol
plists, so creating rules from two threads fails with or without the pool.
Running existing rules in parallel is fine, since their specials get bound per
thread.

### 2. Experiments with threads (7–12 Jun)

David tested Michel Talon's `distribute_over_tranches_thread.lisp` (SBCL
threads in one image):

- `distribute_over_tranches('(concat('v, i) :: i), i, 10000, 16)` leaves
  `length(values)` at 9544, and the count varies between runs. Each thread
  creates a different variable, but they all append to the shared `$values`.
- Parallel `limit(abs(x-i)/(x-i), x, i)` leaves the session corrupted, so
  later non-parallel limits also fail. The likely cause is fact-database
  writes. Integrals fail the same way.
- A Newton iteration using only `block`-local variables crashes with more
  than one thread. Stavros explained why: every Maxima variable is dynamic,
  and `block` saves and restores one value cell. It does not give the thread
  its own variable.

Michel's `partfrac` example, with a distinct main variable per thread,
produced correct results. At 150000 iterations David found the threaded
version more than 10× slower than the sequential one, even with one thread.
He suspected the cost of building and merging per-thread result lists.

Michel updated his README to say that special variables with global extent are
shared across threads and have no mutex.

Stavros asked which problems are CPU-bound in practice. The answers:

- **Richard:** celestial mechanics (multiplying Poisson series), matrix work,
  modular or multi-field methods, and FFT polynomial multiplication. He
  thinks random user-level parallelism is "not yet convincing".
- **Leo:** normal-form computations, where truncated polynomial
  multiplication is the bottleneck.
- **Chris:** unintended symbolic growth usually runs out of memory before it
  runs out of CPU.

### 3. Gunter's survey (14–15 Sep)

Gunter is running an AI-assisted thread-safety survey at
<https://github.com/gunterkoenigsmann/maxima-multithreading>, with CI across
five Lisps and a test for each change. His goal is `makelist_parallel` and
parallel `for`/`in` loops on an OpenMP model. His use case is `wc_systematic`
in the `wrstcse` package, which runs for hours and is essentially a
`makelist`. He reports a 3.8× speedup on 4 cores.

David opened the thread by arguing that the goal is unrealistic, because all
user-visible state lives on symbols shared by the whole image:

- `y : 5` does a global `setq` on `$Y`.
- `f(x) := x^2` writes to the plist of `$F`.
- `a[1] : 3` and `put(a, 1, k)` write to the plist of `$A`.
- 467 option variables change for every thread, and some have assign hooks
  that touch further globals (`fpprec` recomputes `*bigfloatone*`).
- Simplifier dispatch (`operators`), the fact database (`data`),
  `matchdeclare`, noun/verb/alias and `autoload` all live on plists, and
  `kill` strips them.

David proposed an inventory of shared mutable state, checked against the
source, as the deliverable. Raymond and Gunter agreed that the inventory is
more valuable than threading itself.

The objections:

- **Raymond:** "we can get incorrect results faster". He asked whether the
  makelist dominates Gunter's total run time. Gunter said it does: minutes to
  hours inside `wc_systematic`, seconds outside.
- **David:** asked for real examples, and warned that people will put
  anything inside a parallel `makelist` and blame Maxima when it fails. He
  said the survey report misses the plist problem entirely.
- **Richard:** asked whether a relocating GC in one thread breaks another
  thread's pointers. Gunter and Stavros answered that threaded Lisps stop the
  world, which makes this the Lisp's problem.
- **Stavros:** a big calculation can tolerate process start-up costs. He
  suggested a process-pool `makelist` package and named speculative execution
  as the best use for threads.

### 4. "Goals and uses" (15–18 Sep)

- **Robert:** thread safety is "impossible, short of redesigning and
  reimplementing the whole system". Keep the side benefits and frame the work
  around them.
- **Andrew:** use `fork()`. Gunter said multiple Lisp heaps are too big for
  his 8 GB machine.
- **Gunter:** described the work as nearly finished. His model: `let`
  bindings are thread-local; most globals "already are declared The Right
  Way"; the remaining exceptions are load/autoload, memoization, a few hash
  tables, atomic gensym counters, and temp file names. ECL builds get one
  thread, because older ECL releases did not stop all threads before GC. He
  then said he would stop, since the work isn't welcome, and offered to port
  Rubi instead. He also said the AI found several thread-compatible designs
  for `db.lisp` and measured them.
- **David:** replied that Gunter's model misses the data model. State lives
  on plists that no binding reaches. `sign`/`is` writes labels into the plists
  of every node it visits, so two concurrent `sign(x)` calls corrupt each
  other with no `assume` involved. The simplifier calls `sign` for `abs` and
  `^`, and `cabs` adds and removes a temporary `notequal` fact. A lock around
  the database serializes exactly the work threads were meant to spread. The
  places to search are `putprop`, `get`, `set` and `nconc` on shared
  structure, and there are thousands of them.
- **Stavros (18 Sep, unanswered):** define the user-facing API first. His
  questions:
  - Does each thread get its own global and `assume` context?
  - How does a user create thread-local arrays?
  - How do threads communicate (queues?), and how does one thread kill
    another?
  - Can threads be named? How do `break` and control-C work, and how does a
    user inspect another thread's variables?

  He also wants worked examples of real use cases. He isn't worried about GC,
  or about user-level shared lists, which users can already copy.

## Where the two models differ

**Gunter's model:** state lives in special variables. Binding one per thread
isolates it, so the work is a per-variable audit with a short list of
exceptions.

**David's model:** state lives on symbol property lists and in
destructively-modified shared lists. Bindings don't reach either, so the audit
has to look at plist and list mutation sites.

## Source verification

The source supports David's model.

**The fact database writes during read-only queries.** `db.lisp`:

- `mark` (line 87) is `(putprop x t 'mark)`.
- `clear` (line 348) resets `+labs`/`-labs` on every node the previous
  traversal touched, removes `ulabs` properties, and `setq`s the global queues
  `+s`, `+sm`, `+sl`, `-s`, `-sm`, `-sl`, `*labs*` and `*lprs*`.

`compar.lisp:2763` calls `(clear)` from the sign code. Two threads in `sign`
share both the plist labels and the queue globals.

**Registering a variable is a destructive append.** `add2lnc`
(`mlisp.lisp:2523`) finishes with `(nconc llist (ncons item))` on `$values`
and the other info lists. This explains the 9544/10000 result.

**The scale of shared state in `src/*.lisp`:**

| Construct | Count |
|---|---|
| `defmvar` | 468 |
| `(get …)` | 480 |
| `(zl-get …)` | 58 |
| `(putprop …)` | 230 |
| `(mputprop …)` | 42 |
| `(setf (get …) …)` | 278 |
| `(remprop …)` | 56 |
| `(nconc …)` | 238 |

These are raw textual counts. Many sites touch local or freshly consed
structure, so they set an upper bound on the audit. They are not a bug count.

**What upstream contains.** Recent upstream commits by Gunter cover build
dependencies, optimize proclamations and unused bindings (9 Sep). None of the
threading work is in `master`. David's recent `sign` commits (such as
`9b545c065`, "Bind all sign specials in MEQP") bind specials inside
`meqp`. This helps re-entrancy within one thread, and it would also be a
prerequisite for per-thread isolation.

## Assessment

- **Consensus.** Five core developers (David, Raymond, Stavros, Robert,
  Richard) think general thread safety is either impractical or not worth the
  risk. They favour process-level parallelism: Robert's and Michel's
  `distribute_over_tranches`, `fork`, or a process-pool `makelist`.
- **GC is a non-issue.** Threaded SBCL and CCL stop all threads before GC.
- **Gunter's objection to processes is about memory.** Several heaps don't
  fit in 8 GB. His workload has independent iterations, which suits processes.
  Nobody has measured whether his `wc_systematic` runs actually need a full
  heap per worker.
- **The blocker for any parallel `makelist`** is the simplifier's dependence
  on `sign` and the fact database. Almost any non-trivial loop body reaches
  them. A per-variable binding audit doesn't address this.
- **Useful regardless of outcome:**
  - an inventory of shared mutable state;
  - tests that expose hidden global coupling;
  - fixes to specials that leak between call sites (the ccl64 rebuild
    failures, David's MEQP bindings).

## Measure of success: none defined

Nobody in the discussion named a benchmark, a standard workload, or a
speedup target. The only numbers anyone gave:

| Claim | Source | Reproducible? |
|---|---|---|
| 3.8× on 4 cores | Gunter, `wc_systematic` worksheets | No: the worksheets are unpublished and no input size was given |
| More than 10× *slower* than sequential | David, Michel's `partfrac` example at 150000 iterations | Yes: the code is in the thread |
| 9544 of 10000 variables registered | David, `concat('v,i)::i` over 16 threads | Yes: a correctness failure, not a speed number |

Stavros asked for concrete cases twice (9 Jun, 18 Sep) and got no concrete
answer. Gunter's survey reports test-suite pass rates across Lisps, which
measures whether single-threaded behaviour still works, not whether threading
does.

### `wc_systematic` as the reference workload

`share/contrib/wrstcse.mac` ships `wc_systematic`, the workload Gunter cites,
along with `rtest_wrstcse.mac`. It is an outer `makelist` over
`valuespertol^numoftols` corners. Each corner calls `subst` on the whole
expression and simplifies the result.

It also shows the problem directly. The inner `makelist` counts with
`wc_tolnum:wc_tolnum+1`, where `wc_tolnum` is a `block` local. Maxima locals
are dynamic, so parallel outer iterations would share one `wc_tolnum`: the
same failure David showed with the Newton example. Simplifying the
substituted expression also reaches `sign` whenever it contains `abs`,
powers or comparisons. So the one real workload on record doesn't qualify as
a "pure" loop body without changes.

### Proposed criteria

1. **Correctness, the gate.** Run each `rtest_*.mac` file in N threads at
   once, and repeatedly, then compare the output with a sequential run.
   Include the discussion's failure cases (`::` into `$values`, parallel
   `limit`, the `block`-local Newton loop, `wc_systematic`) as regression
   tests. A speedup doesn't count if any of these differ.
2. **Speed against processes, not against a single thread.** The realistic
   alternative is a process pool (`distribute_over_tranches`). Threads have to
   beat it on the same workload in wall-clock time, peak RSS, or both. Beating
   a sequential run proves nothing that processes don't already give.
3. **Workload set:**
   - `wc_systematic` at a size that runs for minutes, with the number of
     tolerances and values per tolerance fixed;
   - Michel's `partfrac` map (the case where threads lost);
   - a numeric map with no simplifier involvement (an upper bound on
     achievable speedup);
   - a simplifier-heavy map with `abs` and `sign` (the hard case).
4. **Single-thread overhead.** The test suite and `wc_systematic` must not
   slow down measurably when threading support is compiled in but unused.
   This matters most for any change to `db.lisp`.
5. **Scaling curve.** Report 1, 2, 4 and 8 workers, not a single ratio.

## Open questions for this research

1. **Fact database.** Can `db.lisp` keep its traversal state (marks, labels,
   queues) per query instead of on symbol plists, without a measurable
   single-thread slowdown? Gunter claims several working designs; they are
   unpublished.
2. **Plist categories.** Which plist indicators are written at run time on
   common paths (simplification, `sign`, evaluation), and which change only
   through user definitions (`:=`, `tellsimp`, `declare`, `kill`)? The
   second group could be declared off-limits inside parallel regions.
3. **Info lists.** Can `$values`, `$functions`, `$arrays` and the other
   `add2lnc` lists become per-thread or lock-protected without breaking
   `kill` and `values`?
4. **Option variables.** Which `defmvar`s do the simplifier and evaluator
   `setq` during computation rather than bind? Those would leak between
   threads even if users set none of them.
5. **Minimal useful subset.** Is there a restricted parallel map (pure
   function, no `assume`, no definitions, no autoload) that works on real
   workloads like `wc_systematic`, and can Maxima detect violations rather
   than trust the user?
6. **Processes vs threads.** On the target workloads, what does a
   process-pool `makelist` cost in memory and start-up time compared with
   threads? This is the baseline for success criterion 2.
7. **API.** Stavros's list: contexts, thread-local arrays, communication,
   cancellation, naming, debugging.

## References

- Bug #4517: <https://sourceforge.net/p/maxima/bugs/4517/>
- Gunter's survey: <https://github.com/gunterkoenigsmann/maxima-multithreading>
  (AI discussion in issue #1)
- Michel Talon's threaded and multi-process distributors:
  <https://github.com/mtalon/mtalon/tree/master/mtalon/maxima-parallel>
- Robert Dodier's process-based `distribute_over_tranches`:
  <https://github.com/robert-dodier/maxima-packages/tree/master/robert-dodier/distribute_over_tranches>
- Carl Ponder, *Parallel Lisp for Algebraic Manipulation Systems* (PhD thesis,
  Berkeley EECS, 1988), cited by Richard Fateman
