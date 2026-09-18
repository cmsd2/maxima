# Stage B results: hook and funnels

Change: `add-environment-accessor-layer`, tasks 4.1–4.6.

## Code change

About 35 lines in 3 files, with no conversions of bypass sites yet:

- **`src/clmacs.lisp`**
  - `defvar *environment-write-hook*`, with its calling convention in the
    docstring;
  - the hook call in `zl-remprop`;
  - new `replace-symbol-plist`.
- **`src/globals.lisp`:** the hook call in `putprop`.
- **`src/mlisp.lisp`:**
  - the hook call in `mset`, after the `assign` check and before the
    `setter-method` branch and the `add2lnc` bookkeeping, so a refused
    assignment changes nothing;
  - the hook call in `munbind-makunbound`.

**Build-order correction:** `clmacs.lisp` compiles *before* `globals.lisp`
(`globals` depends on `compatibility-macros1`). The first build placed the
`defvar` in `globals.lisp` and gave 4 undefined-variable warnings. After the
move the build is clean: 0 `caught WARNING`/`ERROR`, and the same 165
pre-existing `MAKE::` undefined-function notes as the baseline.

## Ad hoc checks

| Input | Recorded |
|---|---|
| `f(x):=x^2` | `:PUT $F MPROPS` |
| `y:5` | `:ASSIGN $Y` |
| `block([z:1],z+1)` | `:ASSIGN $Z`, then `:UNBIND $Z` |
| `assume(x>0)` | `:PUT` on `$INITIAL DATA`, the fact node, `$X DATA`, `$X +LABS` |
| `sign(x)` | `:REMOVE`/`:PUT` of `+LABS` on `$X` and a node: hidden writes with no definition involved |
| `kill(f)` | **nothing for `$f`**. `kill` uses direct `remprop` (a stage D site in `suprv1.lisp`), so this is the first concrete example of the gap |

## Gate B

| Check | Result |
|---|---|
| Full suite, share tests included, no hook | No unexpected errors out of 21,498 tests (same as baseline) |
| Corpus, no hook, against baseline | 0 of 443 files differ |
| Corpus, passive counting hook, against baseline | 0 of 443 files differ |
| Hook sanity (the with-hook run really counts) | `x:1` gives 3 writes |

Alternating core-suite timings, with run 0 discarded:

| Run | Baseline | Stage B |
|---|---|---|
| 1 | 51.73 s | 50.36 s |
| 2 | 51.16 s | 50.80 s |
| 3 | 50.77 s | 51.00 s |
| **Mean** | **51.22 s** | **50.72 s** |

The difference (−0.5 s) is well inside the 2.5 s noise floor from stage A,
so the unused hook costs nothing measurable.

## Harness problems found and fixed during gate B

1. **The with-hook corpus run silently never loaded the hook.** The hook path
   was built with the tree name twice. The first gate run looked like it
   worked, and only the error text in the output gave it away. This is
   exactly the failure doc 05 warns about. **Fix:** the path is computed
   once, and a hook sanity check (the write count must be above 0) now runs
   before any with-hook corpus run and stops the gate if it fails.
2. **First-run share compilation.** The worktree's fresh runtime object
   directory printed compile messages for cobyla, lapack and minpack. **Fix:**
   a discarded warm-up corpus run before comparing (AGENTS.md sec. 5).
3. **Build identity in output:** `build_info()` version, build date, and
   escaped tree names. **Fix:** generic compare-time masks.
4. **Tests that print their own elapsed time** (`rtest_hg`, `rtest_nfloat`,
   `rtest_to_poly_solve`). **Fix:** a generic mask for the
   `absolute_real_time()-start, print(time)` idiom, plus a per-file mask.
5. **Silent hook loading:** loading the hook file printed `T`. **Fix:** wrap
   it in `(progn (load …) (values))`.

After the fixes, baseline-a against baseline-b still shows 0 differences, so
the masks don't hide anything that varies within one build.
