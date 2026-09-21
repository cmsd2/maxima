#!/usr/bin/env python3
"""Report for the GC scaling spike (task 2.6).

  gcspike_report.py SWEEP.jsonl [--pcores 4] [--expect-checksum N]

Reads the records written by gcspike-bench.sh, drops warm-up rounds, and
prints a markdown report:
  - per arm and worker count: median wall, spread, throughput and
    efficiency, allocation rate

Each worker runs the same fixed number of iterations whatever p is, so the
benchmark measures throughput, not time to a fixed result: perfect scaling
holds wall time constant as workers are added.  Throughput is therefore
C(p) = p * wall(1) / wall(p), against that arm's own one-worker time, and
efficiency is C(p) / p.
  - collector: collections, GC wall time, the share of wall time a worker
    spends stopped, mean and worst pause
  - attribution: how much of the gap from ideal speedup GC accounts for,
    and how much is left for memory bandwidth and scheduling
  - the verdict against the thresholds fixed in design D4

Attribution. At one worker a worker's loop takes W seconds of its own time.
With perfect scaling, p workers would still finish in W. The measured wall
is longer; the excess is split into the time every worker spent halted for
collection (the thread arm's GC is stop-the-world, so its whole GC wall time
halts every thread) and a residual that GC does not explain.
"""
import argparse
import json
import statistics as st
import sys

ARMS = ("threads", "processes")


def med(xs):
    return st.median(xs) if xs else float("nan")


def spread(xs):
    return (max(xs) - min(xs)) if len(xs) > 1 else 0.0


def gc_stall(r):
    """Seconds each worker spent halted for collection."""
    if r["arm"] == "threads":
        # One collector, every other thread stopped: all of it halts everyone.
        return r["gc_real"]
    # Separate images collect in parallel; each worker pays only its own.
    return r["gc_real"] / max(r["workers"], 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep")
    ap.add_argument("--pcores", type=int, default=4)
    ap.add_argument("--expect-checksum", type=int, default=None)
    a = ap.parse_args()

    recs = [json.loads(l) for l in open(a.sweep)]
    timed = [r for r in recs if not r["warmup"]]
    bad = [r for r in timed if not r["ok"]]
    good = [r for r in timed if r["ok"]]
    meta = recs[0]

    print("# GC scaling spike: threads against processes\n")
    print("Machine: %s, %s cores; SBCL %s; commit %s." % (
        meta.get("cpu"), meta.get("cores"), meta.get("sbcl"), meta.get("commit")))
    c = meta["collector"]
    yn = lambda v: "yes" if v else "no"
    print("Collector: gencgc %s, mark-region %s, parallel marking %s, nursery "
          "%.1f MiB.\n" % (yn(c["gencgc"]), yn(c["mark-region"]),
                           yn(c["gc-parallel"]), c["nursery-bytes"] / 2**20))
    print("Records: %d total, %d warm-up (dropped), %d timed, %d failed.\n"
          % (len(recs), len(recs) - len(timed), len(timed), len(bad)))
    for r in bad:
        print("- FAILED: %s p=%d round %d (bad exits %d)" % (
            r["arm"], r["workers"], r["round"], r["bad_exits"]))

    sums = {r["checksum"] for r in good}
    print("Checksums: %s" % ("all %d runs agree on %d" % (len(good), sums.pop())
                             if len(sums) == 1 else "DISAGREE: %s" % sums))
    if a.expect_checksum is not None:
        ok = all(r["checksum"] == a.expect_checksum for r in good)
        print("Cross-check against the single-threaded calibration value "
              "%d: %s\n" % (a.expect_checksum, "match" if ok else "MISMATCH"))
    busy = [r["cpu_busy"] for r in timed]
    forced = [r for r in timed if r.get("forced")]
    print("Machine state during the sweep: CPU in use %.0f-%.0f%% of one "
          "core, battery %d-%d%%, %d runs forced past the quiet check.\n" % (
              min(busy), max(busy), min(r["battery"] for r in timed),
              max(r["battery"] for r in timed), len(forced)))

    one = {}
    for arm in ARMS:
        rs = [r for r in good if r["arm"] == arm and r["workers"] == 1]
        if rs:
            one[arm] = {"wall": med([r["wall"] for r in rs]),
                        "busy": med([r["busy_median"] for r in rs])}

    table = {}
    for arm in ARMS:
        arm_recs = [r for r in good if r["arm"] == arm]
        if not arm_recs:
            continue
        print("\n## %s\n" % arm.capitalize())
        print("| Workers | Median wall | Spread | Throughput | Efficiency | "
              "Rate | Collections | GC wall | Stopped | Mean pause |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for p in sorted({r["workers"] for r in arm_recs}):
            rs = [r for r in arm_recs if r["workers"] == p]
            w = [r["wall"] for r in rs]
            mw = med(w)
            sp = p * one[arm]["wall"] / mw
            stall = med([gc_stall(r) for r in rs])
            pause = med([r["pause_mean"] for r in rs])
            table[(arm, p)] = {
                "wall": mw, "spread": spread(w), "speedup": sp,
                "stall": stall,
                "rate": med([r["alloc_rate_gbs"] for r in rs]),
                "busy": med([r["busy_median"] for r in rs]),
                "gc": med([r["gc_real"] for r in rs]),
                "coll": med([r["collections"] for r in rs]),
                "pause": pause}
            print("| %d%s | %.2f s | %.2f | %.2f× | %.0f%% | %.2f GB/s | %d | "
                  "%.2f s | %.1f%% | %s |" % (
                      p, "*" if p > a.pcores else "", mw, spread(w), sp,
                      100 * sp / p, table[(arm, p)]["rate"],
                      table[(arm, p)]["coll"], table[(arm, p)]["gc"],
                      100 * stall / mw,
                      "%.2f ms" % (1000 * pause) if pause else "n/a"))
        print("\n\\* above the %d performance cores." % a.pcores)
        if arm == "processes":
            print("\nPause times are not collected in the process arm: each "
                  "child reports its collection count and GC time, not its "
                  "individual pauses. The stopped share is what the "
                  "comparison turns on, and that is measured in both arms.")

    print("\n## Where the time goes\n")
    print("| Arm | Workers | Ideal wall | Measured | Excess | GC stall | "
          "Residual | GC share of excess |")
    print("|---|---|---|---|---|---|---|---|")
    for arm in ARMS:
        if arm not in one:
            continue
        ideal = one[arm]["busy"]
        for p in sorted({p for (aa, p) in table if aa == arm}):
            t = table[(arm, p)]
            excess = t["wall"] - ideal
            resid = excess - t["stall"]
            # Run-to-run spread is 0.03-0.06 s, so an excess below 0.1 s is
            # the measurement floor and a ratio against it means nothing.
            small = excess < 0.10
            print("| %s | %d | %.2f s | %.2f s | %.2f s | %.2f s | %s | %s |"
                  % (arm, p, ideal, t["wall"], excess, t["stall"],
                     "n/a" if small else "%.2f s" % resid,
                     "n/a" if small else "%.0f%%" % (100 * t["stall"] / excess)))
    print("\nRows whose excess is under 0.1 s are left blank: run-to-run "
          "spread is 0.03-0.06 s, so at that size the excess is the "
          "measurement floor and a ratio against it means nothing.")
    print("\nIdeal wall is the one-worker loop time: with perfect scaling, p "
          "workers finish in the same wall time as one. GC stall is the time "
          "each worker spent halted for collection. The residual is what "
          "collection does not explain: memory bandwidth, scheduling, and "
          "cores that are not all equal.\n")

    print("## Verdict against design D4\n")
    p = a.pcores
    if ("threads", p) in table and ("processes", p) in table:
        ts = table[("threads", p)]["speedup"]
        ps = table[("processes", p)]["speedup"]
        ratio = ts / ps
        eff = ts / p
        if ratio >= 0.90 and eff >= 0.70:
            verdict = "PASS"
        elif ratio >= 0.70 and ts >= 2.0:
            verdict = "REDESIGN"
        else:
            verdict = "FAIL"
        print("At p = %d: threads %.2f×, processes %.2f×, ratio %.2f, thread "
              "efficiency %.0f%%.\n" % (p, ts, ps, ratio, 100 * eff))
        print("Thresholds (design D4, fixed before the data): pass needs "
              "ratio >= 0.90 and efficiency >= 70%; 0.70-0.90 is redesign; "
              "below 0.70, or under 2.0x absolute, is fail.\n")
        print("**Spike A: %s**\n" % verdict)
    else:
        print("Not enough data at p = %d for a verdict.\n" % p)


if __name__ == "__main__":
    main()
