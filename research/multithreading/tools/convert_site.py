#!/usr/bin/env python3
"""Rewrite one bypass site to go through the environment-write funnel.

  convert_site.py FILE LINE [LINE ...]

At each LINE, finds the first bypass form starting on that line and
rewrites it, preserving the source text of its arguments:

  (remprop A B)                 -> (zl-remprop A B)
  (setf (get A B) V)            -> (putprop A V B)
  (setf (symbol-plist A) V)     -> (replace-symbol-plist A V)

Only single-pair SETF forms are handled; anything else is reported and left
alone.  Prints each rewrite.
"""
import re
import sys

OPEN = re.compile(r"\((remprop|setf \(get|setf \(symbol-plist)[\s(]", re.I)


def form_end(s, i):
    """Index just past the balanced form starting at s[i] == '('."""
    depth = 0
    j = i
    in_str = False
    while j < len(s):
        c = s[j]
        if in_str:
            if c == "\\":
                j += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == ";":
            while j < len(s) and s[j] != "\n":
                j += 1
            continue
        elif c == "#" and s[j + 1:j + 2] == "\\":
            j += 3
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise ValueError("unbalanced form at %d" % i)


def split_args(s):
    """Split the text inside a list into top-level argument texts."""
    args = []
    i = 0
    n = len(s)
    while i < n:
        while i < n and s[i].isspace():
            i += 1
        if i >= n:
            break
        start = i
        if s[i] == "(":
            i = form_end(s, i)
        elif s[i] in "'`,#":
            # prefix: quote, backquote, comma, #' -- take the following form
            while i < n and s[i] in "'`,@#":
                i += 1
            if i < n and s[i] == "(":
                i = form_end(s, i)
            else:
                while i < n and not s[i].isspace() and s[i] not in "()":
                    i += 1
        elif s[i] == '"':
            i += 1
            while i < n and s[i] != '"':
                i += 2 if s[i] == "\\" else 1
            i += 1
        else:
            while i < n and not s[i].isspace() and s[i] not in "()":
                i += 1
        args.append(s[start:i])
    return args


def rewrite(form):
    inner = form[1:-1]
    head, _, rest = inner.partition(" ")
    if head.lower() == "remprop":
        return "(zl-remprop " + rest + ")"
    assert head.lower() == "setf"
    args = split_args(rest)
    if len(args) != 2:
        raise ValueError("SETF with %d args" % len(args))
    place, val = args
    pargs = split_args(place[1:-1])
    ph = pargs[0].lower()
    if ph == "get" and len(pargs) == 3:
        return "(putprop %s %s %s)" % (pargs[1], val, pargs[2])
    if ph == "symbol-plist" and len(pargs) == 2:
        return "(replace-symbol-plist %s %s)" % (pargs[1], val)
    raise ValueError("unsupported place %s" % place)


def main():
    path = sys.argv[1]
    lines = [int(x) for x in sys.argv[2:]]
    s = open(path).read()
    starts = [0]
    for m in re.finditer("\n", s):
        starts.append(m.end())
    # Process from the bottom so earlier offsets stay valid.
    for ln in sorted(lines, reverse=True):
        a, b = starts[ln - 1], (starts[ln] if ln < len(starts) else len(s))
        m = OPEN.search(s, a, b)
        if not m:
            print("%s:%d: no bypass form found" % (path, ln))
            continue
        i = m.start()
        j = form_end(s, i)
        old = s[i:j]
        try:
            new = rewrite(old)
        except ValueError as e:
            print("%s:%d: SKIPPED (%s): %s" % (path, ln, e, old[:80]))
            continue
        s = s[:i] + new + s[j:]
        print("%s:%d: %s\n    -> %s" % (path, ln, old.replace("\n", " ")[:100],
                                         new.replace("\n", " ")[:100]))
    open(path, "w").write(s)


if __name__ == "__main__":
    main()
