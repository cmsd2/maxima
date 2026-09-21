# Threads against the process pool: wc_systematic

Machine: Apple M4, 4P+6E cores; SBCL 2.6.5-85913ede1; commit 47867e464.

Records: 184 total, 46 warm-up round (dropped), 138 timed, 0 incorrect (dropped).


Machine state during the sweep: CPU in use 2-219% of one core, 0 runs forced past the quiet check, power battery.


## 10 tolerances

Sequential: median 4.89 s (spread 0.07 s over 3 runs).

### Static scheduling

| Workers | Threads wall | Spread | Speedup | Eff. | Processes wall | Spread | Speedup | Eff. | Threads / processes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4.89 s | 0.10 | 1.00× | 100% | 5.11 s | 0.08 | 0.96× | 96% | 1.04 |
| 2 | 2.53 s | 0.03 | 1.93× | 97% | 2.77 s | 0.17 | 1.77× | 88% | 1.09 |
| 4 | 1.35 s | 0.03 | 3.62× | 91% | 1.45 s | 0.05 | 3.36× | 84% | 1.08 |
| 8* | 1.06 s | 0.04 | 4.62× | 58% | 1.26 s | 0.07 | 3.88× | 49% | 1.19 |
| 10* | 0.99 s | 0.05 | 4.92× | 49% | 1.18 s | 0.03 | 4.15× | 41% | 1.19 |

\* above the 4 performance cores. Speedup is against the sequential run; the ratio is thread speedup over process speedup.

### Dynamic scheduling

| Workers | Threads wall | Spread | Speedup | Eff. | Processes wall | Spread | Speedup | Eff. | Threads / processes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4.95 s | 0.06 | 0.99× | 99% | 5.43 s | 0.08 | 0.90× | 90% | 1.10 |
| 2 | 2.53 s | 0.00 | 1.93× | 97% | 2.94 s | 0.09 | 1.66× | 83% | 1.16 |
| 4 | 1.35 s | 0.02 | 3.63× | 91% | 1.62 s | 0.11 | 3.01× | 75% | 1.21 |
| 8* | 1.04 s | 0.05 | 4.68× | 58% | 1.27 s | 0.01 | 3.84× | 48% | 1.22 |
| 10* | 0.96 s | 0.06 | 5.10× | 51% | 1.22 s | 0.04 | 3.99× | 40% | 1.28 |

\* above the 4 performance cores. Speedup is against the sequential run; the ratio is thread speedup over process speedup.

### Guard cost

| Mode | Workers | Guard on | Guard off | Cost |
|---|---|---|---|---|
| static | 4 | 1.35 s | 1.35 s | -0.1% |
| dynamic | 4 | 1.35 s | 1.32 s | +2.3% |

Cost is the guard's share of the guarded run's wall time: one hash lookup per assignment, unbind or property write.


## 12 tolerances

Sequential: median 61.89 s (spread 1.38 s over 3 runs).

### Static scheduling

| Workers | Threads wall | Spread | Speedup | Eff. | Processes wall | Spread | Speedup | Eff. | Threads / processes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 61.84 s | 1.16 | 1.00× | 100% | 64.00 s | 1.07 | 0.97× | 97% | 1.03 |
| 2 | 32.09 s | 0.55 | 1.93× | 96% | 33.57 s | 0.43 | 1.84× | 92% | 1.05 |
| 4 | 16.91 s | 0.71 | 3.66× | 92% | 17.83 s | 0.62 | 3.47× | 87% | 1.05 |
| 8* | 13.59 s | 0.66 | 4.55× | 57% | 13.67 s | 0.37 | 4.53× | 57% | 1.01 |
| 10* | 12.95 s | 0.90 | 4.78× | 48% | 12.25 s | 0.39 | 5.05× | 51% | 0.95 |

\* above the 4 performance cores. Speedup is against the sequential run; the ratio is thread speedup over process speedup.

### Dynamic scheduling

| Workers | Threads wall | Spread | Speedup | Eff. | Processes wall | Spread | Speedup | Eff. | Threads / processes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 62.92 s | 1.10 | 0.98× | 98% | 66.55 s | 1.23 | 0.93× | 93% | 1.06 |
| 2 | 32.49 s | 0.52 | 1.91× | 95% | 35.94 s | 0.50 | 1.72× | 86% | 1.11 |
| 4 | 17.30 s | 0.53 | 3.58× | 89% | 19.12 s | 0.97 | 3.24× | 81% | 1.11 |
| 8* | 13.48 s | 0.56 | 4.59× | 57% | 13.75 s | 0.19 | 4.50× | 56% | 1.02 |
| 10* | 12.72 s | 0.92 | 4.87× | 49% | 12.39 s | 0.42 | 4.99× | 50% | 0.97 |

\* above the 4 performance cores. Speedup is against the sequential run; the ratio is thread speedup over process speedup.

### Guard cost

| Mode | Workers | Guard on | Guard off | Cost |
|---|---|---|---|---|
| static | 4 | 16.91 s | 17.90 s | -5.5% |
| dynamic | 4 | 17.30 s | 17.64 s | -1.9% |

Cost is the guard's share of the guarded run's wall time: one hash lookup per assignment, unbind or property write.


## Verdict against design D4

A win needs threads ahead of processes at 4 workers, static, by more than the run-to-run spread; within spread is a tie, which counts as a loss because processes need no changes to Maxima; behind is a loss.

- 10 tolerances, p = 4 static: threads 1.35 s (3.62×), processes 1.45 s (3.36×); threads ahead by +0.11 s against a spread of 0.05 s: **WIN**
- 12 tolerances, p = 4 static: threads 16.91 s (3.66×), processes 17.83 s (3.47×); threads ahead by +0.92 s against a spread of 0.71 s: **WIN**
