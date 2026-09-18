# Region profile: wc-local

Iterations: 81 (steady state: iterations 2-80)

| Tier | Steady writes per iteration | Share |
|---|---|---|
| T1 | 27.0 | 45.8% |
| T2 | 32.0 | 54.2% |
| T3 | 0.0 | 0.0% |
| T4 | 0.0 | 0.0% |
| Unknown | 0.0 | 0.0% |

**Criterion matched:** Plausible: only T1 and T2 in the steady state

## T2 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 16.0 | fact-database query labels | hook | put | symbol |$U_In| | `+LABS` |
| 16.0 | fact-database query labels | hook | remove | symbol |$U_In| | `+LABS` |

## T1 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 8.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $WC_TOL | `NIL` |
| 8.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $WC_TOL | `NIL` |
| 5.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $WC_TOLNUM | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $WC_NUM | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $WC_NUM | `NIL` |
| 1.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $WC_TOLNUM | `NIL` |
| 1.0 | special: algorithm-scratch | oracle | replaced | symbol ANS | `:VALUE` |

## First iteration only (warm-up)

none
