# Region profile: globals

Iterations: 20 (steady state: iterations 2-19)

| Tier | Steady writes per iteration | Share |
|---|---|---|
| T1 | 5.0 | 62.5% |
| T2 | 0.0 | 0.0% |
| T3 | 3.0 | 37.5% |
| T4 | 0.0 | 0.0% |
| Unknown | 0.0 | 0.0% |

**Criterion matched:** Possible with locks, T3 at 37.5% of steady writes (high rate rules threads out)

## T3 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 1.0 | special: info-lists | oracle | mutated | symbol $VALUES | `:VALUE` |
| 1.0 | symbol interned (package table) | oracle | appeared | symbol #new-symbol | `NIL` |
| 1.0 | assignment to a variable shared across iterations | hook | assign | symbol #new-symbol | `NIL` |

## T1 (steady)

| Per iteration | Reason | Source | Op/kind | Object | Indicator |
|---|---|---|---|---|---|
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | unbind | symbol $I | `NIL` |
| 2.0 | bind/restore of a local (needs MBIND on PROGV) | hook | assign | symbol $I | `NIL` |
| 1.0 | special: algorithm-scratch | oracle | replaced | symbol ANS | `:VALUE` |

## First iteration only (warm-up)

none
