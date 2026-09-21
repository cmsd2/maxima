#!/usr/bin/env python3
"""Report for the stage D sweep: threads against the process pool.

  threads_report.py SWEEP.jsonl [--pcores 4]

Reads bench-d.sh's records (kinds "sequential", "pool", "threads"), drops
the warm-up round and incorrect runs (reporting them), and prints:
  - the sequential baseline per workload size
  - per arm, mode and worker count: median wall, spread, speedup against
    sequential, efficiency
  - the thread-to-process ratio per mode and worker count
  - the guard's cost: thread runs at the same p with the guard on and off
  - the verdict against design D4 at --pcores workers, static mode
"""
import argparse
import json
import statistics as st


def load_records(path):
    """One JSON record per line.  Records written before the writer escaped
    control characters can be split across lines by a newline inside an
    error message, so a line that does not parse is joined with the lines
    after it until the result does."""
    recs, pending = [], ""
    for l in open(path).read().split("\n"):
        if not l.strip() and not pending:
            continue
        pending = (pending + "\\n" + l) if pending else l
        try:
            recs.append(json.loads(pending))
            pending = ""
        except json.JSONDecodeError:
            continue
    if pending:
        raise ValueError("unparseable record: %s..." % pending[:120])
    return recs


def guard_on(r):
    """The thread arm records :guard T or NIL, and NIL reaches JSON as
    null, so 'off' is False or None; a pool or sequential record has no
    guard and counts as on."""
    return r.get("guard", True) is not False and r.get("guard", True) is not None


def med(xs):
    return st.median(xs) if xs else float("nan")


def spread(xs):
    return (max(xs) - min(xs)) if len(xs) > 1 else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep")
    ap.add_argument("--pcores", type=int, default=4)
    ap.add_argument("--keep-warmup", action="store_true",
                    help="report warm-up-round records too (dry runs)")
    a = ap.parse_args()
    recs = load_records(a.sweep)
    timed = [r for r in recs if a.keep_warmup or not r.get("warmup_round")]
    if not timed:
        print("no timed records (every record is a warm-up round; pass "
              "--keep-warmup to report a dry run)")
        return
    bad = [r for r in timed if r["kind"] != "sequential" and not r["correct"]]
    good = [r for r in timed if r["kind"] == "sequential" or r["correct"]]
    meta = recs[0]
    print("# Threads against the process pool: wc_systematic\n")
    print("Machine: %s, %s cores; SBCL %s; commit %s.\n" % (
        meta.get("cpu"), meta.get("cores"), meta.get("sbcl"), meta.get("commit")))
    print("Records: %d total, %d warm-up round (dropped), %d timed, %d "
          "incorrect (dropped).\n" % (len(recs), len(recs) - len(timed),
                                       len(timed), len(bad)))
    for r in bad:
        print("- INCORRECT: %s %s p=%s round %s: first mismatch %s, errors %s"
              % (r["kind"], r.get("mode"), r["workers"], r.get("round"),
                 r.get("first_mismatch"), r.get("errors")))
    busy = [r.get("cpu_busy", 0) for r in timed]
    print("\nMachine state during the sweep: CPU in use %.0f-%.0f%% of one "
          "core, %d runs forced past the quiet check, power %s.\n" % (
              min(busy), max(busy), sum(1 for r in timed if r.get("forced")),
              "/".join(sorted({r.get("power", "?") for r in timed}))))

    verdict_rows = {}
    for tol in sorted({r["tolerances"] for r in good}):
        seq = [r["wall"] for r in good
               if r["tolerances"] == tol and r["kind"] == "sequential"]
        if not seq:
            continue
        base = med(seq)
        print("\n## %d tolerances\n" % tol)
        print("Sequential: median %.2f s (spread %.2f s over %d runs).\n"
              % (base, spread(seq), len(seq)))
        table = {}
        for mode in ("static", "dynamic"):
            rows = [r for r in good if r["tolerances"] == tol
                    and r["kind"] in ("pool", "threads")
                    and r.get("mode") == mode and guard_on(r)]
            if not rows:
                continue
            print("### %s scheduling\n" % mode.capitalize())
            print("| Workers | Threads wall | Spread | Speedup | Eff. | "
                  "Processes wall | Spread | Speedup | Eff. | Threads / processes |")
            print("|---|---|---|---|---|---|---|---|---|---|")
            for p in sorted({r["workers"] for r in rows}):
                cells = {}
                for arm in ("threads", "pool"):
                    w = [r["wall"] for r in rows
                         if r["kind"] == arm and r["workers"] == p]
                    if w:
                        cells[arm] = (med(w), spread(w), base / med(w))
                        table[(mode, arm, p)] = cells[arm]
                def fmt(arm):
                    if arm not in cells:
                        return "n/a | | | "
                    m, s, sp = cells[arm]
                    return "%.2f s | %.2f | %.2f× | %.0f%% " % (m, s, sp, 100 * sp / p)
                ratio = ("%.2f" % (cells["threads"][2] / cells["pool"][2])
                         if "threads" in cells and "pool" in cells else "n/a")
                print("| %d%s | %s| %s| %s |" % (
                    p, "*" if p > a.pcores else "", fmt("threads"), fmt("pool"),
                    ratio))
            print("\n\\* above the %d performance cores. Speedup is against the "
                  "sequential run; the ratio is thread speedup over process "
                  "speedup.\n" % a.pcores)

        # Guard cost: threads with the guard off, same p and mode.
        off = [r for r in good if r["tolerances"] == tol
               and r["kind"] == "threads" and not guard_on(r)]
        if off:
            print("### Guard cost\n")
            print("| Mode | Workers | Guard on | Guard off | Cost |")
            print("|---|---|---|---|---|")
            for mode in ("static", "dynamic"):
                for p in sorted({r["workers"] for r in off if r["mode"] == mode}):
                    on = [r["wall"] for r in good if r["tolerances"] == tol
                          and r["kind"] == "threads" and r["mode"] == mode
                          and r["workers"] == p and guard_on(r)]
                    o = [r["wall"] for r in off if r["mode"] == mode
                         and r["workers"] == p]
                    if on and o:
                        print("| %s | %d | %.2f s | %.2f s | %+.1f%% |" % (
                            mode, p, med(on), med(o),
                            100 * (med(on) - med(o)) / med(o)))
            print("\nCost is the guard's share of the guarded run's wall time: "
                  "one hash lookup per assignment, unbind or property write.\n")

        key = ("static", "threads", a.pcores), ("static", "pool", a.pcores)
        if key[0] in table and key[1] in table:
            verdict_rows[tol] = (table[key[0]], table[key[1]])

    print("\n## Verdict against design D4\n")
    print("A win needs threads ahead of processes at %d workers, static, by "
          "more than the run-to-run spread; within spread is a tie, which "
          "counts as a loss because processes need no changes to Maxima; "
          "behind is a loss.\n" % a.pcores)
    for tol, (t, p) in sorted(verdict_rows.items()):
        gap = p[0] - t[0]
        noise = max(t[1], p[1])
        if gap > noise:
            v = "WIN"
        elif abs(gap) <= noise:
            v = "TIE (counts as a loss)"
        else:
            v = "LOSS"
        print("- %d tolerances, p = %d static: threads %.2f s (%.2f×), "
              "processes %.2f s (%.2f×); threads ahead by %+.2f s against a "
              "spread of %.2f s: **%s**" % (tol, a.pcores, t[0], t[2], p[0],
                                             p[2], gap, noise, v))
    if not verdict_rows:
        print("Not enough data at p = %d for a verdict." % a.pcores)


if __name__ == "__main__":
    main()
