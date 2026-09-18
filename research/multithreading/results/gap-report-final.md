# Gap report

Unexplained differences: 185352 over 21893 problems (365 files)

| Class | Differences | Distinct keys |
|---|---|---|
| A. slot writes outside the funnel | 221 | 28 indicators |
| M. objects appearing/vanishing | 8804 | 3 object kinds |
| B. in-place mutation of stored values | 26722 | 3 indicators |
| C. value-cell changes of specials | 149605 | 1812 variables |

## A. Slot writes outside the funnel (conversion targets)

| Count | Kind | Object | Indicator |
|---|---|---|---|
| 74 | added | symbol | `TRANSLATED` |
| 21 | added | symbol | `DIMENSION` |
| 18 | added | symbol | `TEX` |
| 16 | added | symbol | `SHARE-FORMATTER` |
| 12 | added | symbol | `OPERATORS` |
| 10 | replaced | symbol | `ASSIGN` |
| 9 | replaced | symbol | `FLOATPROG` |
| 7 | added | symbol | `INTEGER-VALUED` |
| 5 | added | symbol | `RING` |
| 4 | replaced | symbol | `MFEXPR*` |
| 4 | replaced | symbol | `$NARY` |
| 3 | added | symbol | `VERB` |
| 3 | added | symbol | `$NARY` |
| 3 | added | symbol | `DISSYM` |
| 3 | added | symbol | `ORIG` |
| 3 | replaced | symbol | `OPERATORS` |
| 2 | added | symbol | `MACSYMA-MODULE` |
| 2 | replaced | symbol | `DISSYM` |
| 2 | added | symbol | `GRIND` |
| 2 | added | symbol | `LED` |
| 2 | added | symbol | `RBP` |
| 2 | added | symbol | `LBP` |
| 2 | added | symbol | `OP` |
| 1 | added | symbol | `TEXWORD` |
| 1 | added | symbol | `MFEXPR*` |
| 1 | added | symbol | `MAPPLY1-EXTENSION` |
| 1 | added | symbol | `WXXML` |
| 1 | replaced | symbol | `TRANSLATE` |
| 1 | added | symbol | `ALIAS` |
| 1 | added | symbol | `$PRESENT` |
| 1 | replaced | symbol | `DIMENSION` |
| 1 | added | symbol | `USER-SIMPLIFYING` |
| 1 | replaced | symbol | `RBP` |
| 1 | replaced | symbol | `LBP` |
| 1 | added | symbol | `NOUN` |

By test file (top 15):

- load:orthopoly: 35
- load:cartan_new.lisp: 23
- load:combinatorics.lisp: 20
- load:miller-format.lisp: 16
- load:bitwise.lisp: 15
- load:decfp.lisp: 15
- rtest15.mac: 12
- load:to_poly_solve_extra.lisp: 9
- load:load-linearalgebra-lisp-files.lisp: 8
- load:hypergeometric.lisp: 8
- load:sregex.lisp: 7
- load:cryptools.lisp: 5
- load:pdiff.lisp: 5
- load:unwind_protect.lisp: 4
- load:sha1.lisp: 3

## M. Objects appearing or vanishing

- appeared symbol: 6474
- appeared gensym: 625
- vanished gensym: 625
- appeared node: 540
- vanished node: 540

## B. In-place mutation of stored values

- symbol `DATA`: 18932
- node `DATA`: 7756
- symbol `MPROPS`: 29
- symbol `LINEINFO`: 3
- gensym `DATA`: 2

## Verdict on class A

| Documented class | Writes |
|---|---|
| Package loading at run time (load: units) | 196 |
| Translator-generated code (TRANSLATED) | 25 |
| **Undocumented (must be 0)** | **0** |

## C. Value-cell changes by category

| Category | Differences | Variables |
|---|---|---|
| driver-io | 65588 | 8 |
| eval-trace | 25202 | 4 |
| repl-labels | 19170 | 78 |
| lisp-runtime | 8694 | 1 |
| uncategorised | 7908 | 1666 |
| factdb-scratch | 7418 | 10 |
| info-lists | 4689 | 8 |
| algorithm-scratch | 3661 | 14 |
| factdb-nodes | 2104 | 2 |
| cre-pool | 1591 | 2 |
| result-vars | 1208 | 3 |
| bigfloat-cache | 891 | 7 |
| name-counters | 647 | 2 |
| factdb-contexts | 358 | 3 |
| rules | 162 | 1 |
| oracle-artefact | 160 | 1 |
| parser | 154 | 2 |

Uncategorised variables (top 40):

- `ERRCATCH`: 490
- `LOCLIST`: 213
- `MSPECLIST`: 205
- `BINDLIST`: 205
- `MLOCP`: 202
- `$LOAD_PATHNAME`: 188
- `TRANSP`: 154
- `$RATPRINT`: 152
- `ANS`: 116
- `*USER-GR-DEFAULT-OPTIONS*`: 102
- `$%%`: 93
- `DN*`: 74
- `MPROGP`: 63
- `*INTEGRATOR-LEVEL*`: 56
- `*EXP*`: 56
- `$OPSUBST`: 54
- `*INPUT*`: 50
- `$A`: 46
- `EXP`: 40
- `$FOO`: 39
- `*CURRENT-ASSUMPTIONS*`: 39
- `*DEFINT-ASSUMPTIONS*`: 39
- `$EXPTSUBST`: 38
- `*GLOBAL-DEFINT-ASSUMPTIONS*`: 38
- `*DINTLOG-RECUR*`: 38
- `$NOPRINCIPAL`: 38
- `*SHR-SL*`: 38
- `*PR-SL*`: 38
- `*GF-FS-ORD*`: 37
- `*GF-RED*`: 37
- `*GF-ORD*`: 37
- `*GF-CARD*`: 36
- `*GF-X^P-POWERS*`: 35
- `OLDSVARS`: 34
- `*PI-SL*`: 34
- `*GF-FSX-BASE-P*`: 34
- `*GF-FSX*`: 34
- `$B`: 33
- `*GF-PRIM*`: 33
- `HEADER`: 32
