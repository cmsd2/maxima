#!/usr/bin/env python3
"""Report direct symbol-plist writes in Maxima's Lisp sources.

Reads each file with a small Lisp reader (comments, #|...|#, strings,
character literals, |symbols|, #+/#- conditionals) and reports every form
that writes a property list without going through the observable funnel
(PUTPROP, ZL-REMPROP, the replace-plist function):

  (setf (get ...) ...)          and psetf, push, pushnew, pop, incf, decf,
  (setf (symbol-plist ...) ...)     rotatef, shiftf, remf on the same places
  (setf (getf (cdr ...) ...) ...)
  (remprop ...)
  (funcall #'(setf get) ...)

Each hit is classified by where it sits:

  runtime   inside a function body (defun, defmfun, defmspec, lambda, flet,
            labels, def-simplifier, ...) -- these must go through the funnel
  macro     inside a defmacro/define-compiler-macro body -- review by hand
  toplevel  a load-time form -- left alone

Usage:
  plist_scan.py [--allowlist FILE] [--all] [--tsv] PATH...

PATH may be a file or a directory (scanned recursively for *.lisp, skipping
binary-* directories).  Exit status is 0 when there are no runtime or macro
hits that are not on the allowlist, 1 otherwise, 2 on usage errors.

The allowlist is a TSV file: file<TAB>enclosing-form<TAB>reason.  Blank lines
and lines starting with # are ignored.  "file" is the path's basename.
"""

import argparse
import os
import sys

# ---------------------------------------------------------------- reader


class Sym(str):
    """A Lisp symbol, upcased (the reader upcases unless |escaped|)."""


class Form(list):
    """A parsed list form, remembering the line it started on."""

    def __init__(self, items, line):
        super().__init__(items)
        self.line = line


class Quoted:
    def __init__(self, kind, form, line):
        self.kind = kind      # "'", "`", ",", ",@", "#'"
        self.form = form
        self.line = line


class Skip:
    """A form removed by a false read-time conditional (#+nil etc.)."""


FALSE_FEATURES = {"NIL", "(OR)", "BROKEN", "NEVER", "IGNORE", "NILL"}

DELIMS = set("()'`,\";") | set(" \t\r\n\f")


class Reader:
    def __init__(self, text):
        self.s = text
        self.i = 0
        self.line = 1
        self.n = len(text)

    def peek(self):
        return self.s[self.i] if self.i < self.n else ""

    def adv(self, k=1):
        for _ in range(k):
            if self.i < self.n:
                if self.s[self.i] == "\n":
                    self.line += 1
                self.i += 1

    def skip_ws(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n\f":
                self.adv()
            elif c == ";":
                while self.i < self.n and self.s[self.i] != "\n":
                    self.adv()
            elif c == "#" and self.s.startswith("#|", self.i):
                self.block_comment()
            else:
                return

    def block_comment(self):
        depth = 0
        while self.i < self.n:
            if self.s.startswith("#|", self.i):
                depth += 1
                self.adv(2)
            elif self.s.startswith("|#", self.i):
                depth -= 1
                self.adv(2)
                if depth == 0:
                    return
            else:
                self.adv()

    def read_all(self):
        forms = []
        while True:
            self.skip_ws()
            if self.i >= self.n:
                return forms
            f = self.read()
            if not isinstance(f, Skip):
                forms.append(f)

    def read(self):
        self.skip_ws()
        if self.i >= self.n:
            raise EOFError
        c = self.peek()
        line = self.line
        if c == "(":
            self.adv()
            items = []
            while True:
                self.skip_ws()
                if self.i >= self.n:
                    raise EOFError("unterminated list from line %d" % line)
                if self.peek() == ")":
                    self.adv()
                    return Form(items, line)
                f = self.read()
                if not isinstance(f, Skip):
                    items.append(f)
        if c == ")":
            self.adv()      # stray paren: ignore
            return Skip()
        if c in "'`":
            self.adv()
            return Quoted(c, self.read(), line)
        if c == ",":
            self.adv()
            kind = ","
            if self.peek() in "@.":
                self.adv()
                kind = ",@"
            return Quoted(kind, self.read(), line)
        if c == '"':
            return self.read_string()
        if c == "#":
            return self.read_dispatch(line)
        return self.read_atom()

    def read_string(self):
        self.adv()
        out = []
        while self.i < self.n:
            c = self.peek()
            if c == "\\":
                self.adv()
                out.append(self.peek())
                self.adv()
            elif c == '"':
                self.adv()
                return "".join(out)
            else:
                out.append(c)
                self.adv()
        return "".join(out)

    def read_atom(self):
        out = []
        escaped = False
        while self.i < self.n:
            c = self.peek()
            if c == "|":
                escaped = True
                self.adv()
                while self.i < self.n and self.peek() != "|":
                    out.append(self.peek())
                    self.adv()
                self.adv()
            elif c == "\\":
                self.adv()
                out.append(self.peek())
                self.adv()
            elif c in DELIMS:
                break
            else:
                out.append(c if escaped else c.upper())
                self.adv()
        tok = "".join(out)
        # strip package prefixes like MAXIMA:: or CL:
        if "::" in tok:
            tok = tok.split("::", 1)[1]
        elif ":" in tok and not tok.startswith(":"):
            tok = tok.split(":", 1)[1]
        return Sym(tok)

    def read_dispatch(self, line):
        nxt = self.s[self.i + 1] if self.i + 1 < self.n else ""
        if nxt == "'":
            self.adv(2)
            return Quoted("#'", self.read(), line)
        if nxt == "\\":
            # character literal: #\x, #\Space, #\( ...
            self.adv(2)
            out = [self.peek()]
            self.adv()
            while self.i < self.n and self.peek() not in DELIMS:
                out.append(self.peek())
                self.adv()
            return Sym("#\\" + "".join(out))
        if nxt in "+-":
            self.adv(2)
            feature = self.read()
            form = self.read()
            text = render(feature).upper()
            if nxt == "+" and text in FALSE_FEATURES:
                return Skip()
            if nxt == "-" and text in ("(AND)",):
                return Skip()
            # Any other conditional: keep the form (conservative).
            return form
        if nxt == "$":
            # Maxima's #$...$ reader macro: skip to closing $
            self.adv(2)
            while self.i < self.n and self.peek() != "$":
                self.adv()
            self.adv()
            return Sym("#$EXPR$")
        if nxt == "(":
            self.adv()      # vector: read the list after #
            return self.read()
        if nxt == ".":
            self.adv(2)
            return self.read()
        if nxt == ":":
            self.adv(2)
            return self.read_atom()
        if nxt.isdigit():
            # #1= / #1# / #2A(...) etc.
            self.adv()
            while self.peek().isdigit():
                self.adv()
            d = self.peek()
            self.adv()
            if d in "=Aa":
                return self.read()
            return Sym("#REF#")
        if nxt in "xXbBoOcCpPsS*":
            self.adv(2)
            if nxt in "cCpPsS":
                return self.read()
            return self.read_atom()
        # Unknown dispatch: treat the rest as an atom.
        self.adv()
        return self.read_atom()


def render(f):
    if isinstance(f, Form):
        return "(" + " ".join(render(x) for x in f) + ")"
    if isinstance(f, Quoted):
        return f.kind + render(f.form)
    return str(f)


# ---------------------------------------------------------------- analysis

FUNCTION_DEFINERS = {
    "DEFUN", "DEFMFUN", "DEFMSPEC", "DEFUN-PROP", "DEF-SIMPLIFIER",
    "DEFMETHOD", "DEFGENERIC", "LAMBDA", "FLET", "LABELS", "DEFUN-MAYBE",
    "DEF-NARY", "DEFMFUN1", "DEFINE-SIMP-FUN",
}
MACRO_DEFINERS = {"DEFMACRO", "DEFINE-COMPILER-MACRO", "DEFINE-SETF-EXPANDER",
                  "DEFSETF", "DEFINE-MODIFY-MACRO", "DEFTYPE"}
PLACE_MACROS = {"SETF", "PSETF", "PUSH", "PUSHNEW", "POP", "INCF", "DECF",
                "ROTATEF", "SHIFTF", "REMF"}
PLIST_PLACES = {"GET", "SYMBOL-PLIST"}


def head(f):
    return f[0] if isinstance(f, Form) and f and isinstance(f[0], Sym) else None


def place_kind(p):
    """Return a label if P is a plist place, else None."""
    h = head(p)
    if h in PLIST_PLACES:
        return h.lower()
    if h == "GETF" and len(p) > 1 and head(p[1]) in ("CDR", "SYMBOL-PLIST"):
        return "getf-" + head(p[1]).lower()
    return None


def place_args(f):
    """Yield the place arguments of a place-modifying macro call F."""
    h = head(f)
    args = list(f[1:])
    if h in ("SETF", "PSETF"):
        return args[0::2]
    if h in ("PUSH", "PUSHNEW"):
        return args[1:2]
    if h in ("POP", "INCF", "DECF", "REMF"):
        return args[0:1]
    if h in ("ROTATEF",):
        return args
    if h in ("SHIFTF",):
        return args[:-1]
    return []


def is_setf_get_function(q):
    # #'(setf get) or (function (setf get))
    if isinstance(q, Quoted) and q.kind == "#'":
        q = q.form
    elif head(q) == "FUNCTION" and len(q) > 1:
        q = q[1]
    else:
        return False
    return (isinstance(q, Form) and len(q) == 2 and head(q) == "SETF"
            and isinstance(q[1], Sym) and q[1] in PLIST_PLACES)


def top_name(f):
    """A readable name for a top-level form."""
    h = head(f)
    if h is None:
        return "?"
    if len(f) > 1:
        n = f[1]
        if isinstance(n, Form) and n and isinstance(n[0], Sym):
            n = n[0]
        if isinstance(n, Sym):
            return "%s %s" % (h.lower(), n.lower())
    return h.lower()


def scan_form(f, ctx, hits, where, quoted=False):
    """Walk F.  CTX is 'toplevel', 'runtime' or 'macro'."""
    if isinstance(f, Quoted):
        if f.kind == "'":
            return      # quoted data, not code
        if f.kind == "`":
            # Backquoted code in a macro is generated code: keep scanning.
            scan_form(f.form, ctx, hits, where, quoted=True)
            return
        scan_form(f.form, ctx, hits, where, quoted)
        return
    if not isinstance(f, Form):
        return
    h = head(f)
    if h == "QUOTE":
        return
    newctx = ctx
    if (h in FUNCTION_DEFINERS or h in MACRO_DEFINERS) and h not in (
            "LAMBDA", "FLET", "LABELS"):
        # Name hits by the innermost named definition, not the top form.
        where = top_name(f)
    if h in MACRO_DEFINERS:
        newctx = "macro"
    elif h in FUNCTION_DEFINERS and ctx != "macro":
        newctx = "runtime"
    if ctx == "macro" and h in FUNCTION_DEFINERS:
        newctx = "macro"

    # Pattern checks at this node.
    if h in PLACE_MACROS:
        for p in place_args(f):
            k = place_kind(p)
            if k:
                hits.append((ctx, f.line, "%s %s" % (h.lower(), k), where,
                             render(f)[:100]))
    if h == "REMPROP":
        hits.append((ctx, f.line, "remprop", where, render(f)[:100]))
    if h in ("FUNCALL", "APPLY") and len(f) > 1 and is_setf_get_function(f[1]):
        hits.append((ctx, f.line, "funcall (setf get)", where,
                     render(f)[:100]))

    for x in f[1:] if h else f:
        scan_form(x, newctx, hits, where, quoted)


def scan_file(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    r = Reader(text)
    try:
        forms = r.read_all()
    except EOFError as e:
        sys.stderr.write("%s: read error: %s\n" % (path, e))
        forms = []
    hits = []
    for f in forms:
        where = top_name(f)
        h = head(f)
        ctx = "toplevel"
        if h in MACRO_DEFINERS:
            ctx = "macro"
        # A top-level definer sets the context for its body in scan_form.
        scan_form(f, ctx, hits, where)
    return hits


def iter_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = sorted(d for d in dirs
                                 if not d.startswith("binary"))
                for fn in sorted(files):
                    if fn.endswith(".lisp"):
                        yield os.path.join(root, fn)
        else:
            yield p


def load_allowlist(path):
    allow = {}
    if not path:
        return allow
    with open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.lstrip().startswith("#"):
                continue
            parts = ln.split("\t")
            if len(parts) < 3 or not parts[2].strip():
                sys.stderr.write("allowlist entry without reason: %r\n" % ln)
                sys.exit(2)
            allow[(parts[0], parts[1])] = parts[2]
    return allow


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--allowlist")
    ap.add_argument("--all", action="store_true",
                    help="also list toplevel hits")
    ap.add_argument("--tsv", action="store_true",
                    help="machine-readable output")
    a = ap.parse_args()
    allow = load_allowlist(a.allowlist)

    counts = {"runtime": 0, "macro": 0, "toplevel": 0, "allowed": 0}
    rows = []
    for path in iter_files(a.paths):
        base = os.path.basename(path)
        for ctx, line, op, where, snippet in scan_file(path):
            if ctx != "toplevel" and (base, where) in allow:
                counts["allowed"] += 1
                continue
            counts[ctx] += 1
            if ctx != "toplevel" or a.all:
                rows.append((base, line, ctx, op, where, snippet))

    for base, line, ctx, op, where, snippet in rows:
        if a.tsv:
            print("\t".join([base, str(line), ctx, op, where, snippet]))
        else:
            print("%s:%d: %s: %s in (%s): %s" % (base, line, ctx, op, where,
                                                 snippet))
    sys.stderr.write("runtime %(runtime)d  macro %(macro)d  "
                     "toplevel %(toplevel)d  allowed %(allowed)d\n" % counts)
    sys.exit(1 if counts["runtime"] or counts["macro"] else 0)


if __name__ == "__main__":
    main()
