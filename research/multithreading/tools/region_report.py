#!/usr/bin/env python3
"""Classify an oracle region profile into the fix tiers of doc 05.

  region_report.py REGION.tsv [--churn oracle-churn.tsv]

Input lines (from ORACLE-REGION-STEP):
  region iteration source op-or-kind object-kind object indicator

Iteration 1 is reported separately (warm-up).  The last iteration also
carries the region's exit (the enclosing MAKELIST and BLOCK restoring their
bindings), so it is excluded too.  A key is STEADY when it occurs in every
iteration from 2 to the second-to-last; only steady keys decide the
conclusion.

Tiers (doc 05, "Decision criteria"):
  T1 bind per thread       T2 per-query / per-thread structure
  T3 shared, needs a lock  T4 breaks the frozen environment
  Unknown                  not categorised
"""
import argparse
import collections
import csv
import re

T1_CATS = {"driver-io", "repl-labels", "eval-trace", "algorithm-scratch",
           "result-vars", "bigfloat-cache", "cre-pool"}
T2_CATS = {"factdb-scratch", "factdb-contexts"}
T3_CATS = {"info-lists", "factdb-nodes", "rules", "lisp-runtime",
           "name-counters"}
T4_CATS = {"parser"}
IGNORE_CATS = {"oracle-artefact"}

LABELS = {"+LABS", "-LABS", "ULABS"}
FACTS = {"DATA", "CON"}
CONTEXT_PROPS = {"SUBC", "CMARK"}
CRE_PROPS = {"DISREP", "TELLRAT", "ALGORD", "UNHACKED", "DIFF", "LEADOP",
             "RISCHEXPR", "RISCHDIFF", "RISCHARG", "VARORDER", "LIMITSUB",
             "$RATWEIGHT"}
DEFINITIONS = {"MPROPS", "MEXPR", "MMACRO", "OPERATORS", "OLDRULES", "RULES",
               "RULE-SYMBOLS", "OPERS", "NOUN", "VERB", "ALIAS",
               "REVERSEALIAS", "LBP", "RBP", "NUD", "LED", "DIMENSION",
               "DISSYM", "GRIND", "TRANSLATED", "MODE", "LINEINFO", "ARRAY",
               "HASHAR", "MFEXPR*", "AUTOLOAD", "GRAD", "ATVALUES", "DEPENDS",
               "$NARY", "TEX", "EVFUN", "EVFLAG", "ASSIGN", "SP2",
               "MFEXPRP", "MLEXPRP", "MFEXPR", "$RULE", "TRACE"}
SHARED_CONSTANTS = {"$%PI", "$%E", "$%GAMMA", "$%PHI", "$%CATALAN", "$ZEROA",
                    "$ZEROB", "GLOBAL", "$GLOBAL", "$INITIAL", "$INF",
                    "$MINF", "$CONSTANT"}


def load_churn(path):
    exact, pats = {}, []
    if path:
        for ln in open(path):
            if ln.startswith("#") or not ln.strip():
                continue
            v, cat, _ = ln.rstrip("\n").split("\t")
            if v.startswith("re:"):
                pats.append((re.compile(v[3:]), cat))
            else:
                exact[v] = cat

    def cat(v):
        if v in exact:
            return exact[v]
        for rx, c in pats:
            if rx.match(v):
                return c
        return None
    return cat


def classify(rec, churn, paired):
    """Return (tier, reason) for one record."""
    region, it, src, op, okind, obj, ind = rec
    if src == "hook":
        if op in ("assign", "unbind"):
            if (it, obj) in paired:
                return "T1", "bind/restore of a local (needs MBIND on PROGV)"
            return "T3", "assignment to a variable shared across iterations"
        if ind in LABELS:
            return "T2", "fact-database query labels"
        if ind in CONTEXT_PROPS:
            return "T2", "temporary context"
        if ind in FACTS:
            # Facts hang off the objects they mention.  On a gensym made in
            # this computation that is per-computation state (T2); on a
            # shared object (an interned symbol, a number node, the
            # $INITIAL context) the fact list itself is shared (T3, doc 03).
            if okind == "gensym":
                return "T2", "fact on a per-computation gensym"
            return "T3", "fact filed on a shared object (%s)" % okind
        if ind in CRE_PROPS or (ind == "INTERNAL" and okind == "gensym"):
            if okind == "gensym":
                return "T2", "per-computation CRE/integration gensym"
            return "T3", "per-computation property on a shared symbol"
        if ind == "INTERNAL":
            return "T3", "INTERNAL on a user symbol (limit variable)"
        if ind in DEFINITIONS:
            return "T4", "definition property"
        if ind == "LENGTH" and obj == "*PARSE-WINDOW*":
            return "T1", "reader state"
        return "Unknown", "hook write %s %s" % (op, ind)
    # Unexplained net differences from the oracle.
    if op in ("appeared", "vanished"):
        if okind == "gensym":
            return "T2", "per-computation gensym"
        if okind == "node":
            return "T3", "fact-database node linked or dropped"
        return "T3", "symbol interned (package table)"
    if ind == ":VALUE":
        c = churn(obj)
        if c in IGNORE_CATS:
            return None, None
        if c in T1_CATS:
            return "T1", "special: " + c
        if c in T2_CATS:
            return "T2", "special: " + c
        if c in T3_CATS:
            return "T3", "special: " + c
        if c in T4_CATS:
            return "T4", "special: " + c
        return "Unknown", "special not categorised"
    if op == "mutated":
        if ind == "MPROPS":
            return "T4", "definition cell mutated outside the funnel"
        if ind == "DATA":
            if okind == "node" or obj in SHARED_CONSTANTS:
                return "T3", "shared fact list (constants, number chain)"
            return "T2", "fact list of a symbol (temporary assumption)"
        return "Unknown", "mutation of %s" % ind
    if ind in DEFINITIONS:
        return "T4", "definition property (unobserved)"
    return "Unknown", "unexplained %s %s" % (op, ind)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--churn")
    a = ap.parse_args()
    churn = load_churn(a.churn)
    recs = [tuple(r[:3]) + tuple(r[3:7]) for r in
            csv.reader(open(a.tsv), delimiter="\t") if len(r) >= 7]
    recs = [(r[0], int(r[1])) + r[2:] for r in recs]
    if not recs:
        print("no records")
        return
    region = recs[0][0]
    iters = sorted({r[1] for r in recs})
    last = max(iters)
    # A local is "paired" in an iteration when it is both assigned and
    # restored there.
    ops = collections.defaultdict(set)
    for r in recs:
        if r[2] == "hook" and r[3] in ("assign", "unbind"):
            ops[(r[1], r[5])].add(r[3])
    paired = {k for k, v in ops.items() if v == {"assign", "unbind"}}

    # Symbols created in an iteration: writes to them are grouped as
    # #new-symbol, so "a fresh global every iteration" is one steady key.
    fresh = {(r[1], r[5]) for r in recs
             if r[2] == "oracle" and r[3] == "appeared" and r[4] == "symbol"}

    def objkey(r):
        if r[4] == "gensym":
            return "#gensym"
        if (r[1], r[5]) in fresh:
            return "#new-symbol"
        return r[5]

    per_key_iters = collections.defaultdict(set)
    per_key_count = collections.Counter()
    tier_of = {}
    for r in recs:
        tier, why = classify(r, churn, paired)
        if tier is None:
            continue
        key = (tier, why, r[2], r[3], r[4], objkey(r), r[6])
        per_key_iters[key].add(r[1])
        per_key_count[(key, r[1])] += 1
        tier_of[key] = tier

    # Iterations 2 .. last-1: iteration 1 is warm-up, the last iteration
    # also contains the region's exit.
    steady_iters = [i for i in iters if 2 <= i < last]
    steady = {k for k, its in per_key_iters.items()
              if steady_iters and set(steady_iters) <= its}
    first_only = {k for k, its in per_key_iters.items() if its == {1}}

    def per_iter(k):
        n = sum(per_key_count[(k, i)] for i in steady_iters)
        return n / len(steady_iters) if steady_iters else 0.0

    print("# Region profile: %s\n" % region)
    print("Iterations: %d (steady state: iterations 2-%d)\n" % (len(iters), last - 1))
    totals = collections.Counter()
    for k in steady:
        totals[tier_of[k]] += per_iter(k)
    grand = sum(totals.values())
    print("| Tier | Steady writes per iteration | Share |")
    print("|---|---|---|")
    for t in ("T1", "T2", "T3", "T4", "Unknown"):
        share = 100 * totals[t] / grand if grand else 0
        print("| %s | %.1f | %.1f%% |" % (t, totals[t], share))

    # Conclusion per doc 05.
    unknown_share = 100 * totals["Unknown"] / grand if grand else 0
    t3_share = 100 * totals["T3"] / grand if grand else 0
    if unknown_share > 5:
        concl = "No conclusion: Unknown above 5% of steady writes"
    elif totals["T4"] > 0:
        concl = "Threads ruled out: T4 present in the steady state"
    elif totals["T3"] > 0:
        concl = ("Possible with locks, T3 at %.1f%% of steady writes "
                 "(high rate rules threads out)" % t3_share)
    else:
        concl = "Plausible: only T1 and T2 in the steady state"
    print("\n**Criterion matched:** %s\n" % concl)

    for t in ("T4", "T3", "Unknown", "T2", "T1"):
        ks = sorted((k for k in steady if tier_of[k] == t),
                    key=lambda k: -per_iter(k))
        if not ks:
            continue
        print("## %s (steady)\n" % t)
        print("| Per iteration | Reason | Source | Op/kind | Object | Indicator |")
        print("|---|---|---|---|---|---|")
        for k in ks[:25]:
            _, why, src, op, okind, obj, ind = k
            print("| %.1f | %s | %s | %s | %s %s | `%s` |" % (
                per_iter(k), why, src, op, okind, obj, ind))
        if len(ks) > 25:
            print("| … | %d more | | | | |" % (len(ks) - 25))
        print()
    fo = collections.Counter(tier_of[k] for k in first_only)
    print("## First iteration only (warm-up)\n")
    print(", ".join("%s: %d keys" % (t, n) for t, n in sorted(fo.items())) or "none")
    for k in sorted(first_only)[:15]:
        print("- %s %s %s %s `%s` (%s)" % (k[0], k[2], k[3], k[5], k[6], k[1]))


if __name__ == "__main__":
    main()
