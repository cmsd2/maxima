# Region profile: wc

Iterations: 81 (steady state: iterations 2-80)

| Tier | Steady writes per iteration | Share |
|---|---|---|
| T1 | 21.0 | 36.2% |
| T2 | 32.0 | 55.2% |
| T3 | 5.0 | 8.6% |
| T4 | 0.0 | 0.0% |
| Unknown | 0.0 | 0.0% |

**Criterion matched:** Possible with locks, T3 at 8.6% of steady writes (high rate rules threads out)

## T3 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 5.0 | assignment to a variable shared across iterations | hook | assign | symbol $WC_TOLNUM | `NIL` |

## T2 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 16.0 | fact-database query labels | hook | remove | symbol |$U_In| | `+LABS` |
| 16.0 | fact-database query labels | hook | put | symbol |$U_In| | `+LABS` |

## T1 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 8.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $WC_TOL | `NIL` |
| 8.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $WC_TOL | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $WC_NUM | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $WC_NUM | `NIL` |
| 1.0 | special: algorithm-scratch | oracle | replaced | symbol ANS | `:VALUE` |

## First iteration only (warm-up)

none
