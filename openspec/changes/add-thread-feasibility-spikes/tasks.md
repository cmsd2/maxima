Tasks run in four stages. Each stage ends with a gate; stop and review
before starting the next. No stage changes `src/` or `share/`.

## 1. Stage A: calibration

- [x] 1.1 Measure the reference allocation profile. Run `wc_systematic` at
  10 tolerances in a built image, recording bytes consed, wall time, GC run
  time, and `sb-ext:generation-number-of-gcs` for generations 0–2 before and
  after. Verify the rate lands near the 0.76 GB/s measured at 12 tolerances;
  record both. *Result:* 0.78 GB/s at 10 tolerances, 0.74 GB/s at 12;
  20 collections per GB, GC 1.2-1.3%, pause 0.8-0.9 ms, survival 0.04%.
  `generation-number-of-gcs` resets on collection and under-counts by
  three orders of magnitude; an `*after-gc-hooks*` hook replaced it.
- [x] 1.2 Write the allocator (`research/multithreading/tools/gcspike.lisp`):
  nested list structures two to three deep, a per-thread ring buffer
  retaining a configurable survival fraction, and a size knob. It must
  return a checksum the harness verifies, so the work cannot be optimised
  away.
- [x] 1.3 Calibrate. In one thread, tune the size knob until the measured
  rate is within 20% of 0.76 GB/s, and the survival fraction until
  collections per generation match 1.1's ratios. Record the settings and
  the achieved numbers in the file header. *Result:* `:depth 2 :width 3
  :walks 9 :retain-every 512 :ring-size 4096` gives 0.78 GB/s, 20
  collections per GB, GC 1.17%, pause 0.75 ms. Survival cannot be matched
  at the same time as the pause (page-granularity floor); GC cost was
  preferred, with the survival-matched config kept as a sensitivity check.
- [x] 1.4 **Gate A.** Report achieved allocation rate, GC share and
  generation ratios against the Maxima reference. Stop for review.
  *Report:* `research/multithreading/results/gcspike-stage-a.md`.

## 2. Stage B: spike A, GC scaling

- [ ] 2.1 Add the thread arm: *p* threads each running the calibrated loop
  for a fixed iteration count, joined by the parent. Record per-thread
  iterations and elapsed time, `*gc-run-time*` delta, collection count and
  per-collection durations via an `sb-ext:*after-gc-hooks*` hook.
- [ ] 2.2 Add the process arm: fork *p* workers before any thread exists,
  each running the identical loop; parent waits and collects each worker's
  record. Verify the checksum from both arms matches the single-threaded
  value.
- [ ] 2.3 Write the driver (`gcspike-bench.sh`): one fresh image per
  measurement, arm × *p* ∈ {1,2,4,8} × rounds, first round discarded, order
  rotated, machine state recorded per record (total CPU, load average, power
  source, battery, SBCL version, collector features, commit). Refuse to
  start when total CPU exceeds 250% of one core.
- [ ] 2.4 Dry run at small iteration counts. Verify records parse, both arms
  produce equal checksums, and the refusal-when-busy check fires.
- [ ] 2.5 Full sweep on a quiet machine. Write
  `research/multithreading/results/gcspike.jsonl`.
- [ ] 2.6 Report (`gcspike_report.py`): per arm and *p*, median wall,
  spread, speedup against that arm's own *p* = 1, efficiency, GC time,
  collection count, per-thread stopped share. State whether GC or bandwidth
  accounts for the gap from ideal.
- [ ] 2.7 **Gate B.** Judge against design D4's spike A thresholds, written
  before the data. Stop for review.

## 3. Stage C: spike B, binding cost

- [ ] 3.1 Write the microbenchmark
  (`research/multithreading/tools/progv-bench.lisp`): a `progv` arm and a
  baseline arm reproducing `mbind-doit`'s read, `mset`, and the two conses
  onto `bindlist`/`mspeclist`, with `munbind`'s pop. Symbol lists built at
  run time; the body reads the bound special and accumulates a checked sum.
- [ ] 3.2 Measure both arms at 1, 2, 5 and 10 variables per binding,
  reporting nanoseconds and bytes consed per binding, and the ratio. Verify
  the checksum and that timings scale with the variable count (a flat curve
  means the compiler elided the binding).
- [ ] 3.3 Count `mbind` frequency: a redefinition wrapper loaded at run time
  (printing to `*debug-io*`), run over the core test suite and over
  `wc_systematic` at 10 tolerances. Record calls, total variables bound, and
  calls per second for each.
- [ ] 3.4 Combine 3.2 and 3.3 into an estimated whole-workload percentage
  cost, stating the arithmetic.
- [ ] 3.5 **Gate C.** Judge against design D4's spike B thresholds. Stop for
  review.

## 4. Stage D: decision

- [ ] 4.1 Write `docs/multithreading/08-thread-feasibility-spikes.md`:
  method, results, thresholds, verdict per spike, and one recommendation
  (proceed to step 1 / proceed with a stated design change / stop and ship a
  process-based parallel map). Include the caveats from design D1 and the
  Risks section.
- [ ] 4.2 Cross-reference it from doc 07's closing section and from doc 02's
  measured-parameters table (GC scaling with threads was previously an
  assumption there).
- [ ] 4.3 Record reproduction instructions: commands, machine state
  requirements, and which results file each number comes from.
- [ ] 4.4 **Gate D.** Present the recommendation. Stop for review before
  archiving.
