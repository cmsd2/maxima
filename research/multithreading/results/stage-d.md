# Stage D results: converting bypass sites

Change: `add-environment-accessor-layer`, tasks 6.1–6.6.

## Outcome

Oracle class A (unobserved plist slot writes over the full suite) fell from
**19,033 to 181** (−99.05%). The scanner reports **0** run-time, macro or
generated-code sites outside the allowlist. Every gate kept the core suite
and the full suite under the oracle at no unexpected errors.

| Step | Gate | Class A after | Notes |
|---|---|---|---|
| start (stage C) | | 19,033 | |
| `suprv1.lisp` | full | 5,026 | `kill` and friends; `kill(f)` now reports its removals |
| `transl.lisp` | full | 4,583 | `MODE` and `ONCE-TRANSLATED` fully observed |
| `mlisp.lisp` | full | 1,242 | `LINEINFO` |
| `mdebug.lisp` | full | 1,242 | no change: the suite doesn't exercise the debugger |
| `db.lisp` | full | 1,242 | no change: the removal path isn't exercised |
| `compar.lisp` | full | 1,241 | one `$INITIAL` removal |
| 24 small files + run-time `defprop`s | batch | **181** | |

Allowlist: 39 entries, each with a reason.

| Kind | Entries |
|---|---|
| Funnel functions | 3 |
| Unbuilt `optimize.lisp` | 2 |
| Definer macros called only at top level (verified by call-site scan) | 31 |
| Functions that emit code for output files | 3 |

## How the conversions were made

- **Six large or sensitive files** (`suprv1`, `transl`, `mlisp`, `mdebug`,
  `db`, `compar`): converted by hand with exact-match edits, then the full
  gate (build, core suite, oracle).
- **24 small files:** `tools/convert_site.py` rewrites each site, preserving
  argument text; `tools/quick-compile.sh` compiles the file inside the built
  image; one commit per file; the full gate ran once for the batch.
- **Return values are identical by construction:**
  - `putprop` returns the value, as `setf` does;
  - `zl-remprop` returns `remprop`'s result for symbols;
  - `replace-symbol-plist` returns the new plist.

  Only the evaluation position of the indicator argument moves, and every
  converted indicator is a constant or a plain variable.

## Findings along the way

1. **`defprop` inside function bodies was a scanner blind spot.**
   `defprop` expands to `(setf (get …))`. There were 7 run-time uses:
   - 3 in `killallcontexts`, which resets context marks;
   - 4 in `fortran-print`, which temporarily changes the *global* print
     properties of `MEXPT`, `MMINUS` and `MSETQ`. That is a concrete
     concurrency hazard: while one thread runs `fortran()`, every thread's
     `^` prints differently.

   The scanner now flags `defprop` in function bodies (run-time) and in
   backquoted code (generated).
2. **Generated code is left unconverted on purpose.** `tr-mdefine-toplevel`,
   `meta-putprop` and `dskary` emit `defprop` forms into translated or saved
   files. Converting them would change `translate_file`/`save` output. Their
   run-time effect is the remaining `TRANSLATED` writes.
3. **Package loading is run time too.** About 116 of the remaining 181
   writes come from top-level forms in `share/` packages (`defprop`,
   `defmvar`, `defmspec`) that run when `load()` or autoload brings the
   package in during a computation. For `src/`, load time means image build
   time; for `share/` it can be the middle of a computation. This is doc
   03's autoload hazard, now measured.
4. **`optimize.lisp` isn't built** (`#+(and nil gcl)` in `maxima.system`).
   It is allowlisted, not converted.
5. **The oracle only sees code the suite runs.** The debugger conversions and
   the `db-gc-nobjects` removal produced no measurable change because the
   suite never takes those paths. The scanner, not the oracle, is the
   evidence for those sites.
6. **An upstream curiosity in `fortran-print`.** Its `unwind-protect`
   protects only the first `defprop`; the `mstring` call and everything
   after it sit in the cleanup forms. It works, but not as its comment
   describes. The code is left unchanged.
7. **The `defsetf tr-get-*` concern from gate A was wrong for SBCL.** There
   they are `(defun (setf …))` functions, which the scanner sees directly;
   the `defsetf`s are GCL-only. Both variants were converted.

## Remaining class A (181)

| Source | Writes (approx.) | Status |
|---|---|---|
| Translator-generated `defprop … translated` | 65 | Documented gap: generated code |
| `share/` top-level forms run by `load`/autoload during tests | 116 | Documented gap: `share/` and run-time package loading |
