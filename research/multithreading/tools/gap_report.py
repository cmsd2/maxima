#!/usr/bin/env python3
"""Summarise an oracle TSV into gap classes.

  gap_report.py ORACLE.tsv [--churn churn.tsv] [--by-file]

Classes:
  A  slot writes outside the funnel: :added/:removed/:replaced of a plist
     indicator on an object that existed before and after -- the stage D
     conversion targets
  M  object membership: :appeared/:vanished (fresh symbols, fact-database
     nodes linked into or dropped from DOBJECTS/*NOBJECTS*)
  B  in-place mutation of a stored plist value (:mutated, indicator not
     :VALUE) -- documented unobserved class
  C  value-cell changes of Lisp specials (:VALUE) -- documented unobserved
     class; subdivided by the churn file's categories

The churn file is TSV: variable<TAB>category<TAB>reason.
"""
import argparse
import collections
import csv
import re


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--churn")
    ap.add_argument("--by-file", action="store_true")
    a = ap.parse_args()

    churn, patterns = {}, []
    if a.churn:
        for ln in open(a.churn):
            if ln.startswith("#") or not ln.strip():
                continue
            v, cat, why = ln.rstrip("\n").split("\t")
            if v.startswith("re:"):
                patterns.append((re.compile(v[3:]), cat))
            else:
                churn[v] = cat

    class Cat(dict):
        def get(self, v, default=None):
            if v in self:
                return self[v]
            for rx, cat in patterns:
                if rx.match(v):
                    return cat
            return default
    churn = Cat(churn)

    rows = list(csv.reader(open(a.tsv), delimiter="\t"))
    A, M, B, C = [], [], [], []
    for r in rows:
        kind, ind = r[2], r[5]
        if kind in ("appeared", "vanished"):
            M.append(r)
        elif ind == ":VALUE":
            C.append(r)
        elif kind == "mutated":
            B.append(r)
        else:
            A.append(r)

    def top(rs, key, n=25):
        return collections.Counter(key(r) for r in rs).most_common(n)

    print("# Gap report\n")
    print("Unexplained differences: %d over %d problems (%d files)\n" % (
        len(rows), len({(r[0], r[1]) for r in rows}),
        len({r[0] for r in rows})))
    print("| Class | Differences | Distinct keys |")
    print("|---|---|---|")
    print("| A. slot writes outside the funnel | %d | %d indicators |" % (
        len(A), len({r[5] for r in A})))
    print("| M. objects appearing/vanishing | %d | %d object kinds |" % (
        len(M), len({r[3] for r in M})))
    print("| B. in-place mutation of stored values | %d | %d indicators |" % (
        len(B), len({r[5] for r in B})))
    print("| C. value-cell changes of specials | %d | %d variables |" % (
        len(C), len({r[4] for r in C})))

    print("\n## A. Slot writes outside the funnel (conversion targets)\n")
    print("| Count | Kind | Object | Indicator |")
    print("|---|---|---|---|")
    for (k, o, i), n in top(A, lambda r: (r[2], r[3], r[5]), 40):
        print("| %d | %s | %s | `%s` |" % (n, k, o, i))
    print("\nBy test file (top 15):\n")
    for f, n in top(A, lambda r: r[0], 15):
        print("- %s: %d" % (f, n))

    print("\n## M. Objects appearing or vanishing\n")
    for (k, o), n in top(M, lambda r: (r[2], r[3])):
        print("- %s %s: %d" % (k, o, n))

    print("\n## B. In-place mutation of stored values\n")
    for (o, i), n in top(B, lambda r: (r[3], r[5])):
        print("- %s `%s`: %d" % (o, i, n))

    print("\n## C. Value-cell changes by category\n")
    cats = collections.Counter(churn.get(r[4], "uncategorised") for r in C)
    print("| Category | Differences | Variables |")
    print("|---|---|---|")
    for cat, n in cats.most_common():
        nv = len({r[4] for r in C if churn.get(r[4], "uncategorised") == cat})
        print("| %s | %d | %d |" % (cat, n, nv))
    print("\nUncategorised variables (top 40):\n")
    unc = [r for r in C if churn.get(r[4]) is None]
    for v, n in top(unc, lambda r: r[4], 40):
        print("- `%s`: %d" % (v, n))


if __name__ == "__main__":
    main()
