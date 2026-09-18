# Region profile: newton

Iterations: 20 (steady state: iterations 2-19)

| Tier | Steady writes per iteration | Share |
|---|---|---|
| T1 | 73.0 | 100.0% |
| T2 | 0.0 | 0.0% |
| T3 | 0.0 | 0.0% |
| T4 | 0.0 | 0.0% |
| Unknown | 0.0 | 0.0% |

**Criterion matched:** Plausible: only T1 and T2 in the steady state

## T1 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 22.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $I | `NIL` |
| 21.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $X_N | `NIL` |
| 21.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $X_NEXT | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol |$n| | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $I | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol |$n| | `NIL` |
| 1.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $X_NEXT | `NIL` |
| 1.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $X_N | `NIL` |
| 1.0 | special: algorithm-scratch | oracle | replaced | symbol ANS | `:VALUE` |

## First iteration only (warm-up)

none
