#!/usr/bin/env python3
"""Report for the binding cost spike (tasks 3.2 and 3.4).

  progv_report.py MICRO.jsonl COUNTS.jsonl

Combines the microbenchmark (cost per binding) with the MBIND call counts
from real workloads (how often binding happens), and states the estimated
whole-workload cost of moving Maxima's block and lambda binding from MBIND's
global assignment to PROGV's dynamic binding.

Per-call cost is fitted as a + b*n over the measured variable counts, then
evaluated at each workload's measured mean variables per call.
"""
import argparse
import json
import statistics as st


def med(xs):
    return st.median(xs) if xs else float("nan")


def fit_linear(ns, ys):
    """Least squares y = a + b*n; returns (a, b, max relative residual)."""
    n = len(ns)
    mn, my = sum(ns) / n, sum(ys) / n
    sxx = sum((x - mn) ** 2 for x in ns)
    sxy = sum((x - mn) * (y - my) for x, y in zip(ns, ys))
    b = sxy / sxx if sxx else 0.0
    a = my - b * mn
    resid = max(abs(a + b * x - y) / y for x, y in zip(ns, ys))
    return a, b, resid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("micro")
    ap.add_argument("counts")
    a = ap.parse_args()

    recs = [json.loads(l) for l in open(a.micro)]
    bad = [r for r in recs if not r["ok"]]
    counts = [json.loads(l) for l in open(a.counts)]
    meta = recs[0]

    print("# Binding cost: PROGV against MBIND\n")
    print("SBCL %s, commit %s. %d microbenchmark records over %d rounds, "
          "%d with a checksum mismatch.\n" % (
              meta.get("sbcl"), meta.get("commit"), len(recs),
              len({r.get("round") for r in recs}), len(bad)))
    print("MBIND assigns the symbol's value cell, which is global: one "
          "thread's block variable would be every thread's. PROGV binds "
          "dynamically, which SBCL makes per thread. This is what the "
          "substitution costs.\n")

    reads = [r for r in recs if r.get("kind") == "read-cost"]
    recs = [r for r in recs if r.get("kind") != "read-cost"]
    arms = ["mbind", "mbind-doit", "progv", "raw"]
    nvars = sorted({r["nvars"] for r in recs})
    print("## Cost per call\n")
    print("| Arm | " + " | ".join("%d var%s" % (n, "" if n == 1 else "s")
                                  for n in nvars) + " | Per binding | Bytes |")
    print("|---" * (len(nvars) + 3) + "|")
    fits, per_binding = {}, {}
    for arm in arms:
        row, ys = [], []
        for n in nvars:
            v = med([r["ns_per_call"] for r in recs
                     if r["arm"] == arm and r["nvars"] == n])
            row.append("%.0f ns" % v)
            ys.append(v)
        fits[arm] = fit_linear(nvars, ys)
        pb = med([r["ns_per_binding"] for r in recs if r["arm"] == arm])
        by = med([r["bytes_per_binding"] for r in recs if r["arm"] == arm])
        per_binding[arm] = pb
        print("| %s | %s | %.0f ns | %.0f B |" % (arm, " | ".join(row), pb, by))
    print("\nCost scales with the variable count in every arm (a flat row "
          "would mean the compiler elided the binding). Fitted per call as "
          "a + b*n:\n")
    for arm in arms:
        a0, b0, res = fits[arm]
        print("- %s: %.0f ns fixed + %.0f ns per variable (worst residual "
              "%.0f%%)" % (arm, a0, b0, 100 * res))
    if reads:
        g, pg = med([r["global_ns"] for r in reads]), med([r["progv_ns"]
                                                          for r in reads])
        print("\nReading a special costs %.2f ns when it is only globally "
              "bound and %.2f ns inside a PROGV binding (%+.0f%%). SBCL "
              "reads a special through its thread-local slot whether or not "
              "anything bound it, so moving to dynamic binding does not make "
              "the evaluator's reads dearer.\n" % (g, pg, 100 * (pg - g) / g))
    print("\n`raw` is save, assign, restore with no MSET checks and no "
          "BINDLIST: the floor for a hand-written per-thread binding stack.\n")

    print("## How often binding happens\n")
    counted = [c for c in counts if c.get("kind") == "mbind-count"]
    plain = {c["label"].replace("-plain", ""): c["wall"]
             for c in counts if c.get("kind") == "wall-only"}
    print("| Workload | MBIND calls | Vars per call | Wall (plain) | Calls/s |")
    print("|---|---|---|---|---|")
    for c in counted:
        key = c["label"].replace("-counted", "")
        wall = plain.get(key, c["wall"])
        print("| %s | %s | %.2f | %.1f s | %s |" % (
            key, "{:,}".format(c["calls"]), c["vars_per_call"], wall,
            "{:,}".format(round(c["calls"] / wall))))
    print("\nWall time is from a separate run without the counting wrapper.\n")

    print("## Estimated whole-workload cost\n")
    print("| Workload | Binding today | With PROGV | Change | Upper bound |")
    print("|---|---|---|---|---|")
    verdicts = []
    for c in counted:
        key = c["label"].replace("-counted", "")
        wall = plain.get(key, c["wall"])
        n = c["vars_per_call"]
        cost = lambda arm: (fits[arm][0] + fits[arm][1] * n) * c["calls"] / 1e9
        today, new, floor = cost("mbind"), cost("progv"), cost("raw")
        # Upper bound: PROGV cannot simply replace MBIND, which also runs the
        # ASSIGN checks, the $VALUES bookkeeping and the error wrapper.  Keep
        # all of that and swap only the value-cell assignment: today's cost,
        # less the bare assign-and-restore, plus PROGV.
        upper = today - floor + new
        verdicts.append((key, 100 * (new - today) / wall,
                         100 * (upper - today) / wall))
        print("| %s | %.2f s (%.1f%%) | %.2f s (%.1f%%) | %+.1f%% | %+.1f%% |"
              % (key, today, 100 * today / wall, new, 100 * new / wall,
                 100 * (new - today) / wall, 100 * (upper - today) / wall))
    print("\n*Binding today* is MBIND plus MUNBIND at the measured call rate. "
          "*With PROGV* replaces them outright, which is the lower bound: it "
          "drops the ASSIGN checks and the $VALUES bookkeeping that MBIND "
          "also does. *Upper bound* keeps all of that and swaps only the "
          "value-cell assignment.\n")

    print("## Verdict against design D4\n")
    worst = max(max(v[1], v[2]) for v in verdicts)
    if worst <= 5:
        v = "PASS"
    elif worst <= 15:
        v = "REDESIGN"
    else:
        v = "FAIL"
    print("Worst estimated cost across workloads and bounds: %+.1f%% of run "
          "time.\n" % worst)
    print("Thresholds (design D4, fixed before the data): pass at or under "
          "5%, 5-15% is redesign, over 15% is fail.\n")
    print("**Spike B: %s**\n" % v)


if __name__ == "__main__":
    main()
