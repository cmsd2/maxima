Tasks run in five stages. Each stage ends with a gate; stop and review
before starting the next. Stage 2 is the only one that changes `src/`.

## 1. Stage A: the runner, on safe work

- [x] 1.1 Extract the symbol set for `wc_systematic` from the recorded
  write trace (`results/region-*.md` and the record-hook log of the
  archived observation change). List every symbol assigned or unbound
  inside the region, plus `bindlist` and `mspeclist`. Verify the set against
  a fresh trace rather than the stored one. *Result:* the fresh trace
  matches the stored one: $WC_NUM, $WC_TOL, $WC_TOLNUM assigned, and
  |$U_In| receiving +LABS plist writes. Full set is 46 symbols.
- [x] 1.2 Write the runner (`research/multithreading/tools/threads.lisp`):
  *p* threads released together, static and dynamic scheduling, each thread
  entering through `progv` over the symbol set, results collected in index
  order. No Maxima algebra yet.
- [x] 1.3 Write the guard: an `*environment-write-hook*` function checking
  each assigned symbol against a per-thread table, signalling an error that
  names the symbol. Verify it fires by assigning an unbound symbol inside
  the region on purpose, and that it does not fire for the bound set.
- [x] 1.4 Confinement test: a worker assigns a Maxima variable; verify no
  other worker and not the parent sees it, and the parent's value after the
  region is unchanged. *Result:* verified, with a negative control showing
  the same work without the binding: workers read back whichever write
  landed last and the value escaped to the parent, silently.
- [x] 1.5 **Gate A.** Report the symbol set, the guard firing on a planted
  escape, and the confinement test. Stop for review.

## 2. Stage B: per-query fact labels (`src/`)

- [ ] 2.1 Read the label lifecycle end to end: `clear`, the `+labs`,
  `-labs`, `ulabs` accessor macros, `unlab`, `selector`, the `putprop`
  sites, and `*labindex*`/`+lab-high-bit+`. Decide whether a per-query table
  makes the numbering redundant (design, open question).
- [ ] 2.2 Replace the property writes with a per-query table behind the
  selector macros, bound per thread. Keep the diff inside the macros and
  their call sites; do not reindent or rename surrounding code.
- [ ] 2.3 Bind the label state where `$sign`/`$asksign` rebind the sign
  specials, so a nested query cannot see an outer query's table.
- [ ] 2.4 Verify the labels are gone: run the write observer over
  `wc_systematic` and confirm no `+labs`/`-labs`/`ulabs` writes on shared
  nodes remain.
- [ ] 2.5 **Gate B.** Full suite with share tests green and registry
  unchanged; `make check`'s dependency check passing; differential corpus
  with no new diffs; single-thread timing on `wc_systematic` and the suite
  showing no slowdown outside the noise floor. Stop for review.

## 3. Stage C: the remaining two fixes

- [ ] 3.1 `share/contrib/wrstcse.mac`: make `wc_tolnum` local to each
  iteration. One line. Verify `wc_systematic` results are unchanged at 4
  and 6 tolerances, and that the package's own tests still pass.
- [ ] 3.2 Add the warm-up iteration to the runner, before the region, and
  record in each run that it happened.
- [ ] 3.3 Run `wc_systematic` on the thread pool for the first time, at 2
  threads, checking every result against the sequential list.
- [ ] 3.4 **Gate C.** Report correctness at 1, 2 and 4 threads, and any
  guard firing. A guard firing here is the expected way to discover a
  symbol the trace missed: add it to the set, say which, and note why the
  trace missed it. Stop for review.

## 4. Stage D: the measurement

- [ ] 4.1 Extend the sweep driver to run the thread arm beside doc 07's
  process arm: same workload sizes, fresh image per measurement, discarded
  warm-up round, three timed rounds, rotated order, machine state recorded,
  refusal above 250% CPU.
- [ ] 4.2 Re-run the write observer under threads, with per-thread
  attribution, and compare the trace against the single-threaded one. Any
  new T3 or T4 write stops the stage.
- [ ] 4.3 Measure what the thread arm spends on the guard and on any
  synchronisation, by running with the guard disabled as a comparison, so a
  win or loss can be attributed.
- [ ] 4.4 Full sweep on a quiet machine; report per worker count the median
  wall, spread, speedup against sequential, and the thread-to-process
  ratio.
- [ ] 4.5 **Gate D.** Judge against design D4: a win needs threads ahead of
  processes at four workers by more than the run-to-run spread, with no lock
  on a hot path. Stop for review.

## 5. Stage E: decision

- [ ] 5.1 Write `docs/multithreading/09-threaded-prototype.md`: what was
  fixed, what the guard caught, the measurement, the verdict, and one
  recommendation.
- [ ] 5.2 Record what stays regardless of the verdict (the fact-database
  change) and what was deferred (`mbind` on `progv`, other workloads,
  `intern` thread safety).
- [ ] 5.3 Cross-reference from docs 05, 07 and 08.
- [ ] 5.4 `ChangeLog` entry for the `src/` change, under the heading that
  fits the cycle being committed against.
- [ ] 5.5 **Gate E.** Present the recommendation. Stop for review before
  archiving.
