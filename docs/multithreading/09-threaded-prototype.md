# Multi-threading in Maxima: the threaded prototype

Doc 08 recommended proceeding, and this document reports what happened
when Maxima first ran on threads: the OpenSpec change
`add-threaded-prototype`. It fixed the three things doc 05 measured as
breaking `wc_systematic` under threads, ran the workload on native threads
in one image, and measured it against doc 07's process pool.

Stage reports: `research/multithreading/results/threads-stage-{a,b,c,d}.md`.
Data: `results/bench-d.jsonl` and the files each stage report names.

## What was built

**A per-query table for sign-query labels** (`src/db.lisp`,
`src/compar.lisp`). Sign queries marked fact-database nodes with `putprop`
under `+labs` and `-labs`, and `clear` swept the marks off at the start of
the next query. The marks were always transient; what they wrote was
structure every thread shares. They now live in two `eq` hash tables
behind two accessor macros, 50 insertions and 33 deletions. Full suite
with share tests green, dependency check clean, differential corpus 443
files with 0 differences, and `wc_systematic` 3% *faster* single-threaded
(a hash lookup replacing a plist scan and a `putprop` per mark). `ulabs`
stays on the plist: `local()` writes it persistently to hide facts, which
is not query scratch, and separating its two lifetimes is its own change.

**A per-corner counter in `wrstcse.mac`.** `wc_tolnum` is bound inside
each corner's `subst` instead of once for the sweep. Results identical;
`rtest_wrstcse` 97/97.

**A thread runner** (research tooling, not shipped). Each worker enters
through `progv` over a symbol set, so `mset`'s
`(setf (symbol-value x) y)` lands in the worker's own binding rather than
the global value cell. `mbind`, `munbind` and `mset` are untouched. A
guard installed as `*environment-write-hook*` refuses an assignment to any
symbol not bound at entry and any property write, naming the symbol,
because the alternative is silent: the same assignment with no binding in
force writes the global cell and every thread sees it, with no error and
no warning. A warm-up evaluates item 0 in the parent first. Every result
is compared with the sequential run.

## What the symbol set turned out to need

"Bound at thread entry" was the design. It was necessary and not
sufficient, and finding out how took most of the change. The set ended at
101 symbols in **three classes**:

| Class | Members | Why |
|---|---|---|
| Copied by reference | 90 | `progv` over the parent's values. Unbound symbols stay in the set and are bound *as unbound*, which `progv` does for a symbol past the end of the value list. `ANS` is written every iteration and is unbound in a fresh image; the first version dropped it and would have leaked in silence. |
| Copied by value | 8 info lists | `add2lnc` grows `$values` with `nconc` and `munbind` shrinks it with `delete`, both on the list's own conses. A reference copy shares exactly those conses. `wc_systematic`'s three locals are unbound between calls, so every block entry and exit in every thread spliced one list. |
| Fresh | 3 | A constructor at entry. The two label tables, and `*mlambda-call-stack*`, an adjustable vector `mlambda` pushes a frame onto per call and pops in an unwind cleanup: four threads sharing one drove its fill pointer to −4. |

And one symbol nobody had classified: `loclist`, the `local()` frame
stack, with `mproplist` and `factlist`. Every `mlambda` call, `block` and
`ev` pushes a frame on entry and `munlocal` pops it on exit. Shared,
lost-update pushes and pops let `munlocal` walk past a thread's own
frames and "restore" whatever it found there, a `tol[k]` expression in
both captured backtraces.

**Why the observation facility missed these.** All of them are Lisp-level
writes: a `push`, an `nconc`, a `vector-push`, a `setq`. The write hook
sees `mset` and property writes, so the guard could not refuse them and
the trace under threads could not show them (it matched the sequential
trace exactly, and the runs still failed). The oracle's snapshot diff
found `ANS` and `$values` and classified them correctly, and the runner
did not act on the classification. It never saw `loclist` at all, because
every iteration restores it before the snapshot: doc 05's stated
"transient special-variable writes" blind spot, now with a name.

**What caught them.** The correctness check against sequential results,
and Lisp type errors. 6 tolerances passed 20 of 20 runs; 10 tolerances
failed every run with four or more threads, twice over. The race windows
open with scale, and the check has to run at that scale. After the fixes,
an audit bound every remaining global the evaluator files write, on the
grounds that case-by-case reasoning was what had missed the first two and
a binding nothing writes costs nothing.

## The measurement

184 measurements, 0 incorrect, fresh image each, rotated order, discarded
warm-up round, three timed rounds, quiet machine, guard active throughout.
Speedups against the sequential run:

| Workers | 10 tol., threads | 10 tol., processes | 12 tol., threads | 12 tol., processes |
|---|---|---|---|---|
| 1 | 1.00× | 0.96× | 1.00× | 0.97× |
| 2 | 1.93× | 1.77× | 1.93× | 1.84× |
| **4** | **3.62×** | **3.36×** | **3.66×** | **3.47×** |
| 8 | 4.62× | 3.88× | 4.55× | 4.53× |
| 10 | 4.92× | 4.15× | 4.78× | 5.05× |

Static scheduling; dynamic favours threads by a further few percent,
because the process pool's dynamic mode waits for every fork before
handing out work. Paired by round, threads led in **every round at every
worker count up to four**, both sizes. The guard's cost is inside the
noise.

**Verdict against design D4** (fixed before the data: ahead at four
workers, static, by more than the run-to-run spread, no lock on a hot
path, guard active): **win on both sizes**, 0.11 s against a 0.05 s spread
at 10 tolerances, 0.92 s against 0.71 s at 12.

Three things the numbers say:

- **The win is the process overhead, and no more.** 5–8% at four workers,
  which is what doc 07 measured processes paying in fork and result
  transfer. The loop body is the same code either way.
- **Past the performance cores it erodes and reverses.** On the larger
  workload the ratio goes 1.05 → 1.01 → 0.95 from 4 to 10 workers. Spike A
  said why: more threads collect more often and promote more, and
  processes do not. On a machine with more performance cores the crossing
  point would sit elsewhere, and this measurement cannot say where.
- **Threads' real advantage was not measured.** Results here are small
  numbers or tiny expressions in `U_In`, so the process pool's result
  transfer is cheap. A workload returning large expressions pays that
  transfer in full; threads pay nothing. That case is where a bigger
  margin would come from, and it was out of scope.

## Recommendation

**Proceed.** The threading path passed the gate it set itself, the fixes
it needed are correctness improvements that stay whatever comes next, and
the measured margin, thin as it is, is the floor: it excludes the one
advantage threads have that this workload cannot show.

Proceed means the generality work the prototype deferred:

1. **`mbind` rebuilt on `progv`** (doc 03), so user code can bind symbols
   nobody enumerated. The prototype's thread-entry set is derived per
   workload from a trace and hand-sorted into three classes; that is
   research tooling, not a product, and it is the reason the runner stays
   in `research/`.
2. **`ulabs` split** into its query-scratch and `local()` lifetimes, so
   `cancel` no longer stops the guard.
3. **A workload whose results are large**, to measure the margin this one
   could not.

**Until then the process pool is the shipped answer.** It needs no
changes to Maxima, it works with `wrstcse` as released, and on this
workload it is within 8% of threads on four cores and ahead on ten.

**What would reverse this.** If step 1's general binding costs the 5–8%
(spike B says the mechanism is a saving, but the restructuring was never
priced), or if the `ulabs` split needs a lock on the `sign` path, the
margin is gone and processes stay the answer.

## What stays regardless

- The fact-database change: sign queries no longer write shared
  structure, and sequential Maxima is slightly faster for it.
- The `wrstcse` counter fix.
- The three-class account of what a thread needs bound: by reference, by
  value, or fresh. Anyone attempting threads in Maxima needs it, and
  nothing in the source says it.
- `loclist`, `mproplist`, `factlist` and `*mlambda-call-stack*` as named
  hazards, with the class of write that hides them.
- The correctness check at scale as the net under everything the hook
  and the oracle cannot see.

## Deferred, and not verified

- `mbind` on `progv` (above).
- `intern` thread safety under SBCL: doc 05 recorded it as unverified,
  `wc_systematic` does not intern, and this change leaves it so.
- Any workload beyond `wc_systematic` on the voltage-divider chain. Doc
  05's limits on one input stand, and the guard is what makes a new
  workload fail loudly rather than quietly.
- Streams. `*standard-output*` and its kin are bound per thread to the
  same stream objects, and SBCL's `fd-stream`s are not safe for concurrent
  writes. This workload prints nothing.
