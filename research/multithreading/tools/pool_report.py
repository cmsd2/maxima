#!/usr/bin/env python3
"""Report for the process-pool benchmark (task 4.1).

  pool_report.py SWEEP.jsonl [--pcores 4]
  pool_report.py --selftest

Reads the JSON records written by pool-bench.sh, ignores warm-up rounds and
failed runs (reporting them), and prints a markdown report:
  - sequential baseline per workload (wall, GC share, per-item mean and CV)
  - scaling table per workload and scheduling mode: median wall, spread,
    speedup, efficiency, marking worker counts above the performance cores
  - memory: parent and per-worker peak RSS, summed total, heap growth
  - overheads: fork, wait, read; worker busy-time spread (imbalance)
  - Universal Scalability Law fit, C(p) = p / (1 + s(p-1) + k p(p-1)),
    over p <= pcores and over the full curve
"""
import argparse
import json
import math
import statistics as st
import sys


# ------------------------------------------------------------ USL fit

def usl(p, s, k):
    return p / (1 + s * (p - 1) + k * p * (p - 1))


def fit_usl(ps, cs):
    """Least-squares fit of sigma, kappa to relative capacities C(p).
    Gauss-Newton on the linearised form p/C - 1 = s(p-1) + k p(p-1),
    which is linear in (s, k); returns (s, k, rms residual of C)."""
    # Linear least squares: y = p/C - 1 = s*x1 + k*x2
    x1 = [p - 1 for p in ps]
    x2 = [p * (p - 1) for p in ps]
    y = [p / c - 1 for p, c in zip(ps, cs)]
    a11 = sum(v * v for v in x1)
    a12 = sum(u * v for u, v in zip(x1, x2))
    a22 = sum(v * v for v in x2)
    b1 = sum(u * v for u, v in zip(x1, y))
    b2 = sum(u * v for u, v in zip(x2, y))
    det = a11 * a22 - a12 * a12
    if abs(det) < 1e-12:
        s = b1 / a11 if a11 else 0.0
        k = 0.0
    else:
        s = (b1 * a22 - b2 * a12) / det
        k = (a11 * b2 - a12 * b1) / det
    res = math.sqrt(sum((usl(p, s, k) - c) ** 2 for p, c in zip(ps, cs))
                    / len(ps))
    return s, k, res


def usl_peak(s, k):
    if k <= 0:
        return None
    return math.sqrt((1 - s) / k) if s < 1 else None


def selftest():
    ok = True
    for s0, k0 in [(0.05, 0.001), (0.10, 0.01), (0.02, 0.0005)]:
        ps = [1, 2, 3, 4, 6, 8, 10]
        cs = [usl(p, s0, k0) for p in ps]
        s, k, res = fit_usl(ps, cs)
        good = abs(s - s0) <= 0.05 * s0 and abs(k - k0) <= 0.05 * k0
        ok &= good
        print("sigma %.4f->%.4f  kappa %.5f->%.5f  res %.2e  %s" % (
            s0, s, k0, k, res, "ok" if good else "FAIL"))
    print("selftest", "PASS" if ok else "FAIL")
    return ok


# ------------------------------------------------------------ report

def med(xs):
    return st.median(xs) if xs else float("nan")


def spread(xs):
    return (max(xs) - min(xs)) if len(xs) > 1 else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep", nargs="?")
    ap.add_argument("--pcores", type=int, default=4)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)

    recs = [json.loads(l) for l in open(a.sweep)]
    timed = [r for r in recs if not r.get("warmup")]
    failed = [r for r in timed if r["kind"] == "pool" and not r["correct"]]
    good = [r for r in timed if r["kind"] == "sequential" or r["correct"]]
    meta = recs[0]
    print("# Process-pool baseline for wc_systematic\n")
    print("Machine: %s, %s cores, %d GB; SBCL %s; commit %s.\n" % (
        meta.get("cpu"), meta.get("cores"), meta.get("memsize", 0) // 2**30,
        meta.get("sbcl"), meta.get("commit")))
    print("Records: %d total, %d warm-up (ignored), %d timed, %d failed "
          "correctness.\n" % (len(recs), len(recs) - len(timed), len(timed),
                              len(failed)))
    print("There is no thread arm: the symbolic loop body can't run "
          "correctly on threads until the stage F fixes (binding on progv, "
          "per-query fact labels) exist.\n")
    for r in failed:
        print("- FAILED: %s %s p=%s round %s, first mismatch %s" % (
            r["label"], r["mode"], r["workers"], r["round"],
            r["first_mismatch"]))

    for tol in sorted({r["tolerances"] for r in good}):
        seq = [r for r in good if r["tolerances"] == tol
               and r["kind"] == "sequential"]
        if not seq:
            continue
        sw = [r["wall"] for r in seq]
        base = med(sw)
        items = seq[0]["items"]
        print("\n## %d tolerances (%d corners)\n" % (tol, items))
        if "item_times" in seq[0]:
            allt = [t for r in seq for t in r["item_times"]]
            m = st.mean(allt)
            cv = st.pstdev(allt) / m
        else:  # compact records: per-run summary statistics
            m = med([r["item_stats"]["mean"] for r in seq])
            cv = med([r["item_stats"]["cv"] for r in seq])
        gc = med([r["gc"] / r["wall"] for r in seq])
        print("**Sequential:** median %.2f s (spread %.2f s over %d runs); "
              "GC %.1f%%; per item mean %.0f µs, CV %.2f; peak RSS %d MB.\n"
              % (base, spread(sw), len(sw), 100 * gc, m * 1e6, cv,
                 med([r["maxrss"] for r in seq]) // 2**20))
        for mode in ("dynamic", "static"):
            pool = [r for r in good if r["tolerances"] == tol
                    and r["kind"] == "pool" and r["mode"] == mode]
            if not pool:
                continue
            print("### %s scheduling\n" % mode.capitalize())
            print("| Workers | Median wall | Spread | Speedup | Efficiency "
                  "| Fork | Busy spread | Peak RSS/worker | Sum RSS | Heap growth/worker |")
            print("|---|---|---|---|---|---|---|---|---|---|")
            ps, cs = [], []
            for p in sorted({r["workers"] for r in pool}):
                rs = [r for r in pool if r["workers"] == p]
                w = [r["wall"] for r in rs]
                mw = med(w)
                sp = base / mw
                ps.append(p)
                cs.append(sp)
                busy = [med([x["busy"] for x in r["worker_stats"]]) for r in rs]
                bspread = med([spread([x["busy"] for x in r["worker_stats"]])
                               for r in rs])
                rss = med([max(x["maxrss"] for x in r["worker_stats"])
                           for r in rs])
                srss = med([sum(x["maxrss"] for x in r["worker_stats"])
                            + r["parent_maxrss"] for r in rs])
                heap = med([max(x["heap_growth"] for x in r["worker_stats"])
                            for r in rs])
                print("| %d%s | %.2f s | %.2f | %.2f× | %.0f%% | %.2f s | %.2f s "
                      "| %d MB | %d MB | %d MB |" % (
                          p, "*" if p > a.pcores else "", mw, spread(w), sp,
                          100 * sp / p, med([r["t_fork"] for r in rs]),
                          bspread, rss // 2**20, srss // 2**20, heap // 2**20))
            print("\n\\* above the %d performance cores.\n" % a.pcores)
            for label, sel in (("p ≤ %d" % a.pcores,
                                [i for i, p in enumerate(ps) if p <= a.pcores]),
                               ("all p", list(range(len(ps))))):
                if len(sel) >= 3:
                    s, k, res = fit_usl([ps[i] for i in sel],
                                        [cs[i] for i in sel])
                    pk = usl_peak(s, k)
                    print("USL over %s: σ = %.4f, κ = %.5f, rms residual "
                          "%.3f%s\n" % (label, s, k, res,
                                        ", throughput peaks at p ≈ %.1f" % pk
                                        if pk else ""))


if __name__ == "__main__":
    main()
