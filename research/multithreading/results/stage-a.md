# Stage A results: ground truth

Change: `add-environment-accessor-layer`. Tree: `sourceforge/master` at
`9b545c065`, SBCL 2.6.5, macOS, 10 cores. Raw logs are in `../logs/`, which
git ignores.

## Builds (tasks 1.1, 1.2)

| Tree | bootstrap | configure | make | Build warnings |
|---|---|---|---|---|
| `maxima-mt-baseline` (detached, pristine) | 1 s | 4 s | 78 s | none (`caught ERROR`/`WARNING`: 0) |
| `maxima-multithreading` (this worktree) | 1 s | 4 s | 78 s | none |

Both cores are newer than every `src/*.lisp` file.

## Test suite (tasks 1.3, 1.4)

- **Full suite, share tests included (baseline):** no unexpected errors out
  of 21,498 tests. Wall time 145 s, of which 7.8 s GC and 80 GB consed.
- **Core suite timings (baseline):** four sequential runs on an idle
  machine, the first discarded.

| Run | Wall (SBCL real time) | GC |
|---|---|---|
| 0 (discarded) | 48.65 s | 2.29 s |
| 1 | 47.98 s | 2.28 s |
| 2 | 50.52 s | 2.49 s |
| 3 | 50.35 s | 2.39 s |

Mean of runs 1–3: 49.6 s. Spread: 2.5 s, about 5%. That spread is the noise
floor for gate B's performance check. GC is about 4.7% of wall time, which is
the f_gc of doc 02 for this (non-target) workload.

## Differential corpus (tasks 2.1–2.3)

- **Corpus:** 356 files found. 8 graphics demos are skipped by pattern, and
  100 generated files hold 2000 random expressions (seed 20260918).
  448 files are runnable, 443 after exclusions.
- **Run time:** about 105 s per run with 6 parallel processes.
- **Determinism:** two runs of the baseline build agree exactly on all 443
  files, after 5 exclusions and 1 mask (`corpus-exclusions.tsv`,
  `corpus-masks.tsv`, each with a reason). Generic compare-time masks cover
  temp-file names, escaped stream addresses and "Runtime was" lines.
- **Saved baseline:** `logs/corpus-baseline-a/`, with `manifest.json`
  recording the seed, size and per-file times.

Exclusions:

| File | Reason |
|---|---|
| `share/tensor/tensor.dem` | Interactive menu: loops on EOF, printed 1.7 GB in 300 s |
| `tests/rtest_great_slow.mac` | Deliberately outside the test suite; takes about an hour |
| `share/simplification/ineq.dem` | Hangs at input 5, `(b > c)+%`, in the baseline build |
| `share/descriptive/rtest_statgraph.mac` | Histogram of random samples |
| `share/contrib/diffequations/tests/rtestode_kamke_1_4.mac` | Exhausts the default 1 GB SBCL heap and dies; the dump varies |

Mask: `tests/rtest_hg.mac` prints its own elapsed time.

Harness fixes made along the way:

- A stand-in `gnuplot` (`tools/stubbin/`) first on `PATH` for every Maxima
  the tools start. Before this fix, plot and draw tests opened real windows.
- A 20 MB output cap, and killing the whole process group on timeout.

## Static check (tasks 3.1–3.3)

`tools/plist_scan.py` is a reader-level scanner.

- **Fixtures:** it reports every run-time pattern (7 of 7), exits 0 on the
  load-time-only fixture, and exits 1 on the run-time fixture.
- **On `src/`:** 98 run-time and 13 macro-body sites, plus 3 funnel sites on
  the allowlist (`putprop`, `zl-remprop`). 230 top-level (load-time) sites
  are left alone. This matches doc 03's estimate of about 100.

| Operation | Sites |
|---|---|
| `remprop` | 57 |
| `setf get` | 43 |
| `setf symbol-plist` | 9 |
| `push get` | 4 |
| `setf getf` on node plists | 1 |

By file, the largest are:

| File | Sites |
|---|---|
| `suprv1.lisp` | 26 |
| `transl.lisp` | 13 |
| `mdebug.lisp` | 7 |
| `mlisp.lisp` | 6 |
| `mactex.lisp` | 6 |
| `rat3e.lisp` | 4 |
| `nparse.lisp` | 4 |

The worklist is `plist-worklist-unmodified.tsv`, with 111 rows.

## Findings for review

1. **The `defsetf tr-get-*` expanders in `transl.lisp`** write plists at every
   `(setf (tr-get-mode …))` call site, and the scanner can't see those call
   sites. They must be converted at the `defsetf` (task 6.4).
2. **Upstream issues noticed in passing:**
   - `ineq.dem` hangs.
   - `rtestode_kamke_1_4` exhausts the default heap.
   - `tensor.dem` loops forever on EOF.

   None of these affects this work.
3. **Design D11 was revised:** the corpus runs one process per file, not per
   input (see design.md).
4. **Gate B budget:** the per-write hook check has to cost less than the 2.5 s
   noise floor on a 50 s core suite.
