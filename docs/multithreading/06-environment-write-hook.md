# Multi-threading in Maxima: the environment write hook

This document covers the facility built by the OpenSpec change
`add-environment-accessor-layer`: what it observes, what it doesn't, how to
use it, and the tools that check it. Doc 05 explains why it was built and
how it was validated. The stage results are in
`research/multithreading/results/`.

## The hook

`*environment-write-hook*` (declared in `src/clmacs.lisp`) is `nil`, or a
function called **before** each observable write:

```lisp
(funcall *environment-write-hook* operation object indicator value)
```

| Operation | Called from | Object | Indicator | Value |
|---|---|---|---|---|
| `:put` | `putprop` | symbol, or fact-database node `(x . plist)` | property | new value |
| `:remove` | `zl-remprop` | symbol or node | property | `nil` |
| `:replace-plist` | `replace-symbol-plist` | symbol | `nil` | new plist |
| `:assign` | `mset` | Maxima variable | `nil` | new value |
| `:unbind` | `mset` (restoring a binding) and `munbind-makunbound` | Maxima variable | `nil` | restored value, or `munbound` |

`mputprop`, `meta-putprop` and `meta-mputprop` end in `putprop`, and
`mremprop` in `zl-remprop`, so their writes are observed too.

**Observer rules:**

1. **Refuse with an ordinary Maxima error** (`merror`). The write happens
   only if the hook returns normally, and `errcatch` catches the refusal.
2. **Never refuse `:unbind`.** It restores a binding on exit from
   `block`/function calls; refusing it would leave a binding frame half
   restored.
3. **Refuse at the first write of an operation.** A multi-step update
   refused halfway (for example, `mputprop` creating the `mprops` cell and
   then writing into it) leaves the first step applied.
4. **Don't write the environment from the hook, and be reentrancy-safe.**
   Bind the hook to `nil` around any code in the hook that might write.
5. **Bind the hook with `let` to scope it.** In SBCL that binding is also
   thread-local.

Unused, the hook costs one special-variable read and a null test per
write. Stage B and final timings show no difference outside the noise
floor.

## What is observed, and what isn't

**Observed:**

- Property slot puts, removals and whole-plist replacements made at run
  time by code in `src/`, through the funnel. The static check verifies
  that no unlisted bypass exists.
- Maxima-level value assignment, binding and restoration (`mset`).

**Not observed.** Each of these classes shows up in the oracle's
reports:

| Class | Examples | Oracle class |
|---|---|---|
| In-place mutation of structures stored in properties | fact `DATA` lists (`fdel`'s `rplacd`), `mprops` cells edited outside the funnel | B |
| Destructive edits of global information lists | `$values`, `$functions`, `$props` (`add2lnc`'s `nconc`) | C |
| Assignment to Lisp special variables | `*last-meval1-form*`, fact-database query scratch (`+labs`, `-s`, …), `varlist`/`genvar`, the `bcons` bigfloat header cache, unbound algorithm working arrays | C |
| Value cells of CRE gensyms | `$rat` renumbering the shared variable pool (`prenumber`) | C |
| Hash tables and arrays | memo tables, `*lambda-expr-funs*`, `*bigprimes*` | not fingerprinted |
| Top-level forms of packages loaded at run time | `share/` `defprop`/`defmvar`/`defmspec` run by `load` or autoload | A, in `load:` units |
| Translator-generated code | `(defprop f t translated)` emitted by `tr-mdefine-toplevel`, evaluated by `translate` | A, `TRANSLATED` |
| Writes before a hook is installed | image build, the initial load of `src/` | — |
| `share/` code in general | not converted | A (in `load:` units) and others |

**"No write observed" means no write in the observed classes.** Only the
oracle can support a claim that nothing was written at all, and only for
code paths the test suite exercises.

### Allowlist

`research/multithreading/plist-allowlist.tsv` has 28 entries covering 39
sites, each with a reason:

| Reason | Entries | Unobserved class it belongs to |
|---|---|---|
| Funnel functions (`putprop`, `zl-remprop`, `replace-symbol-plist`) | 3 | none: these *are* the observed path |
| Definer macros called only at top level (`defprop`, `def-simplifier`, `displa-def`, `def-lbp`, …; verified by a call-site scan) | 20 | writes before a hook is installed (load time) |
| Functions that emit generated code (`tr-mdefine-toplevel`, `meta-putprop`, `dskary`) | 3 | translator-generated code |
| Unbuilt `optimize.lisp` (`#+(and nil gcl)` in `maxima.system`) | 2 | none: not compiled |

## Tools

All tools are in `research/multithreading/tools/` and take the Maxima tree
as an argument or find it from their own location. Every tool puts a
stand-in `gnuplot` (`stubbin/`) first on `PATH`, so plot tests open no
windows.

| Tool | What it does |
|---|---|
| `plist_scan.py [--allowlist F] [--tsv] PATH…` | Static check. Reports direct plist writes in function bodies (`setf get`, `setf symbol-plist`, `remprop`, `setf getf` on node plists, modify macros on those places, `defprop` in function bodies, and `setf` of accessor macros that expand to `get`, such as `symbol-array`). Generated code is reported separately. Exits 0 only when every hit is allowlisted |
| `convert_site.py FILE LINE…` | Rewrites one bypass site to the funnel, preserving argument text |
| `convert-file.sh FILE` | Converts every site in a file, compile-checks it and commits |
| `quick-compile.sh FILE` | Compiles one source file inside the built image and reports warnings |
| `record-hook.lisp` | `(show-writes "maxima input;")` for ad hoc inspection |
| `count-hook.lisp` | Passive counting hook (`*environment-write-count*`) |
| `functional-test.sh` | The spec scenarios, refusal, and the expected-writer table: 14 checks |
| `profile.lisp` | `(envprofile "input;" :repeat n)` and `envprofile-region-begin/end`: aggregated profile by operation × object kind × indicator, with no generated names |
| `profile-repeat.sh` | Repeatability check: three workloads, three fresh sessions each |
| `oracle.lisp`, `oracle-suite.sh` | Snapshot-diff oracle over the full suite, one unit per test problem and per package load |
| `gap_report.py` | Classifies oracle output into classes A/M/B/C, with the class A verdict |
| `seeded-test.sh` | Checks that the scanner and oracle catch planted bypasses |
| `corpus.py` | Differential corpus runner and comparer |
| `gate-b.sh`, `gate-d.sh`, `gate-e.sh` | Stage gates |

## Known limits of the checkers

- **The scanner reads source; it doesn't expand macros.** It recognises
  `defprop` and accessor macros that expand to `get` by name. A new
  write-performing macro of some other shape would need adding. Two blind
  spots of this kind were found and closed during the work (`defprop` in
  function bodies, `setf` of `symbol-array`).
- **The oracle sees only code paths the suite executes.** The debugger
  (`mdebug.lisp`) and the `db-gc-nobjects` removal branch are never run, so
  the scanner is the only evidence for those conversions.
- **The oracle fingerprints** package symbols, `genvar` gensyms,
  fact-database nodes and temporary contexts. It does not fingerprint hash
  tables, arrays held outside plists, or symbols in other packages.

## Measurements (final validation, stage E)

Tree: `feature/multithreading` after all conversions; baseline
`9b545c065`; SBCL 2.6.5, macOS, 10 cores.

| Measurement | Value |
|---|---|
| Full suite with share tests, no hook | no unexpected errors out of 21,498 tests |
| Core suite with a passive counting hook | no unexpected errors out of 16,409 tests; **66,553,837 observed writes** |
| Differential corpus (443 files: rtest inputs, demos, 2000 generated expressions; 5 exclusions, 1 mask) | identical to baseline with no hook and with a passive hook |
| Core-suite timing, runs 1–4 of 5 alternating pairs | baseline 57.66 s (spread 3.04 s), changed 57.58 s (spread 3.32 s) |
| Oracle, full suite (21,498 problems plus 1,224 package-load units) | class A 221: 196 package loading, 25 translator-generated, **0 undocumented** |
| Oracle, class B (in-place mutation) | 26,722 |
| Oracle, class C (special variables) | 149,605 over 1,812 variables |
| Class A progression | 19,033 (hook only) → 181 (after stage D conversions) → 0 undocumented once package loads are attributed and 7 `symbol-array` sites converted |
| Functional tests | 14 of 14 |
| Seeded bypasses | all caught |
| Profile repeatability | identical across 3 sessions for 3 workloads |

A first timing run in stage E was disturbed by other machine load (one
baseline run took 64.2 s against about 53 s for the others). It passed the
spec's criterion only because of its wide spread, so it was repeated; the
repeat is the figure above.
