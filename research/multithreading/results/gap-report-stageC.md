# Gap report

Unexplained differences: 197962 over 21498 problems (160 files)

| Class | Differences | Distinct keys |
|---|---|---|
| A. slot writes outside the funnel | 19033 | 70 indicators |
| M. objects appearing/vanishing | 8612 | 3 object kinds |
| B. in-place mutation of stored values | 27046 | 3 indicators |
| C. value-cell changes of specials | 143271 | 1802 variables |

## A. Slot writes outside the funnel (conversion targets)

| Count | Kind | Object | Indicator |
|---|---|---|---|
| 5944 | removed | symbol | `MPROPS` |
| 5048 | removed | symbol | `LINEINFO` |
| 3163 | added | symbol | `LINEINFO` |
| 578 | replaced | symbol | `MPROPS` |
| 555 | removed | symbol | `MODE` |
| 530 | removed | symbol | `NOUN` |
| 526 | removed | symbol | `VERB` |
| 513 | removed | symbol | `RULE-SYMBOLS` |
| 422 | added | symbol | `MODE` |
| 161 | removed | symbol | `DIMENSION` |
| 142 | replaced | symbol | `LINEINFO` |
| 140 | removed | symbol | `DISSYM` |
| 114 | removed | symbol | `RBP` |
| 110 | removed | symbol | `LBP` |
| 103 | removed | symbol | `OPERATORS` |
| 75 | removed | symbol | `OP` |
| 72 | added | symbol | `TRANSLATED` |
| 70 | removed | symbol | `GRIND` |
| 70 | removed | symbol | `POS` |
| 57 | removed | symbol | `LPOS` |
| 52 | removed | symbol | `LED` |
| 43 | removed | symbol | `RPOS` |
| 31 | added | symbol | `DIMENSION` |
| 24 | added | symbol | `OPERATORS` |
| 23 | added | symbol | `ONCE-TRANSLATED` |
| 22 | removed | gensym | `TELLRAT` |
| 21 | added | symbol | `FUNCTION-MODE` |
| 21 | removed | symbol | `TRANSLATE` |
| 21 | removed | symbol | `DEFSTRUCT-DEFAULT` |
| 21 | removed | symbol | `DEFSTRUCT-TEMPLATE` |
| 21 | removed | symbol | `EVFLAG` |
| 20 | added | symbol | `TEX` |
| 19 | removed | symbol | `NUD` |
| 19 | removed | gensym | `ALGORD` |
| 17 | replaced | symbol | `GRAD` |
| 14 | removed | symbol | `MFEXPR` |
| 13 | replaced | symbol | `INTEGRAL` |
| 13 | removed | symbol | `REVERSEALIAS` |
| 13 | removed | symbol | `ALIAS` |
| 13 | added | symbol | `TRANSLATE` |

By test file (top 15):

- rtest16.mac: 1665
- rtest_abs_integrate.mac: 1394
- rtest_pdiff.mac: 909
- rtest15.mac: 868
- rtest_descriptive.mac: 766
- rexamples.mac: 535
- rtest_solve_rec.mac: 466
- rtest_rules.mac: 449
- rtest_numericalio.mac: 437
- rtestode.mac: 409
- rtest2.mac: 385
- rtest_zeilberger.mac: 363
- rtest_fourier_elim.mac: 363
- rtest_antid.mac: 327
- rtest3.mac: 307

## M. Objects appearing or vanishing

- appeared symbol: 6626
- appeared gensym: 531
- vanished gensym: 531
- appeared node: 462
- vanished node: 462

## B. In-place mutation of stored values

- symbol `DATA`: 18349
- node `DATA`: 7616
- symbol `MPROPS`: 1078
- symbol `LINEINFO`: 3

## C. Value-cell changes by category

| Category | Differences | Variables |
|---|---|---|
| driver-io | 64353 | 8 |
| eval-trace | 24198 | 4 |
| repl-labels | 19144 | 78 |
| lisp-runtime | 8582 | 1 |
| factdb-scratch | 7142 | 10 |
| uncategorised | 5321 | 1656 |
| info-lists | 4113 | 8 |
| algorithm-scratch | 3585 | 14 |
| factdb-nodes | 2016 | 2 |
| cre-pool | 1560 | 2 |
| result-vars | 1186 | 3 |
| bigfloat-cache | 827 | 7 |
| name-counters | 647 | 2 |
| oracle-artefact | 160 | 1 |
| rules | 159 | 1 |
| parser | 154 | 2 |
| factdb-contexts | 124 | 3 |

Uncategorised variables (top 40):

- `$RATPRINT`: 152
- `*USER-GR-DEFAULT-OPTIONS*`: 102
- `*INPUT*`: 50
- `$A`: 46
- `$FOO`: 39
- `*SHR-SL*`: 38
- `*PR-SL*`: 38
- `*GF-FS-ORD*`: 37
- `*GF-RED*`: 37
- `*GF-ORD*`: 37
- `DN*`: 36
- `*GF-CARD*`: 36
- `*GF-X^P-POWERS*`: 35
- `OLDSVARS`: 34
- `*PI-SL*`: 34
- `*GF-FSX-BASE-P*`: 34
- `*GF-FSX*`: 34
- `$B`: 33
- `*GF-PRIM*`: 33
- `HEADER`: 32
- `*HR-SL*`: 32
- `*QPI-SL*`: 32
- `*SHI-SL*`: 32
- `*QPR-SL*`: 32
- `*QHR-SL*`: 32
- `*GF-CHAR*`: 31
- `*GF-EXP*`: 30
- `$PSLQ_FAIL_NORM`: 30
- `$FACSUM_COMBINE`: 29
- `$NEXTLAYERFACTOR`: 29
- `$STRUCTURES`: 29
- `#:G10771912`: 27
- `#:G10771935`: 26
- `$X`: 25
- `*LEADCOEF*`: 25
- `NISTREE`: 25
- `#:G10772227`: 25
- `CONTEXTS`: 24
- `$ACTIVECONTEXTS`: 24
- `#:G10772900`: 24
