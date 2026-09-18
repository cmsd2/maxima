# Region profile: limits

Iterations: 20 (steady state: iterations 2-19)

| Tier | Steady writes per iteration | Share |
|---|---|---|
| T1 | 5.0 | 4.9% |
| T2 | 72.0 | 69.9% |
| T3 | 26.0 | 25.2% |
| T4 | 0.0 | 0.0% |
| Unknown | 0.0 | 0.0% |

**Criterion matched:** Possible with locks, T3 at 25.2% of steady writes (high rate rules threads out)

## T3 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 13.0 | fact filed on a shared object (symbol) | hook | put | symbol $INITIAL | `DATA` |
| 4.0 | fact filed on a shared object (node) | hook | put | node 0 | `DATA` |
| 3.0 | fact filed on a shared object (node) | hook | remove | node MGRP | `CON` |
| 2.0 | fact filed on a shared object (node) | hook | put | node 100000000 | `DATA` |
| 1.0 | special: lisp-runtime | oracle | replaced | symbol *GENSYM-COUNTER* | `:VALUE` |
| 1.0 | fact filed on a shared object (symbol) | hook | put | symbol PRIN-INF | `DATA` |
| 1.0 | fact filed on a shared object (node) | hook | put | node (MGRP PRIN-INF (100000000 DATA (#))) | `CON` |
| 1.0 | fact filed on a shared object (symbol) | hook | remove | symbol PRIN-INF | `DATA` |

## T2 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 22.0 | per-computation CRE/integration gensym | hook | put | gensym #gensym | `DISREP` |
| 8.0 | fact-database query labels | hook | put | gensym #gensym | `+LABS` |
| 8.0 | fact-database query labels | hook | remove | gensym #gensym | `+LABS` |
| 6.0 | fact-database query labels | hook | put | symbol PRIN-INF | `+LABS` |
| 6.0 | fact-database query labels | hook | remove | symbol PRIN-INF | `+LABS` |
| 4.0 | per-computation CRE/integration gensym | hook | remove | gensym #gensym | `UNHACKED` |
| 3.0 | per-computation CRE/integration gensym | hook | put | gensym #gensym | `INTERNAL` |
| 3.0 | per-computation CRE/integration gensym | hook | put | gensym #gensym | `UNHACKED` |
| 2.0 | fact on a per-computation gensym | hook | remove | gensym #gensym | `DATA` |
| 2.0 | fact on a per-computation gensym | hook | put | gensym #gensym | `DATA` |
| 2.0 | fact-database query labels | hook | put | node 100000000 | `+LABS` |
| 2.0 | fact-database query labels | hook | remove | node 0 | `+LABS` |
| 2.0 | fact-database query labels | hook | put | node 0 | `+LABS` |
| 2.0 | fact-database query labels | hook | remove | node 100000000 | `+LABS` |

## T1 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $I | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $I | `NIL` |
| 1.0 | special: algorithm-scratch | oracle | replaced | symbol ANS | `:VALUE` |

## First iteration only (warm-up)

T2: 3 keys, T3: 19 keys, Unknown: 4 keys
- T2 hook remove $CONSTANT `+LABS` (fact-database query labels)
- T2 hook remove $INF `+LABS` (fact-database query labels)
- T2 oracle replaced +LABS `:VALUE` (special: factdb-scratch)
- T3 hook put (MGRP #:G599 (0 DATA (# # #))) `CON` (fact filed on a shared object (node))
- T3 hook put (MGRP #:G600 (0 DATA (# # #))) `CON` (fact filed on a shared object (node))
- T3 hook put 3.141592653589793d0 `DATA` (fact filed on a shared object (node))
- T3 hook put GLOBAL `DATA` (fact filed on a shared object (symbol))
- T3 oracle appeared 100000000 `NIL` (fact-database node linked or dropped)
- T3 oracle mutated 0 `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated 0.5772156649015329d0 `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated 0.915965594177219d0 `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated 1.618033988749895d0 `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated 2.718281828459045d0 `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated $%CATALAN `DATA` (shared fact list (constants, number chain))
- T3 oracle mutated $%E `DATA` (shared fact list (constants, number chain))
