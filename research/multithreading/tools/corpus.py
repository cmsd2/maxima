#!/usr/bin/env python3
"""Differential corpus runner for Maxima builds.

  corpus.py run TREE OUTDIR [--corpus-root ROOT] [--seed N] [--gen N]
                            [--jobs N] [--timeout S] [--exclusions FILE]
                            [--hook LISPFILE]
  corpus.py compare DIR_A DIR_B [--exclusions FILE]

"run" evaluates every corpus file with TREE's ./maxima-local, one process
per file, and writes normalised output to OUTDIR/<corpus path>.out plus a
manifest.  The corpus is:

  - every tests/rtest*.mac and share/**/rtest*.mac under ROOT
    (read with batch(), so each input and its result are printed),
  - every demo/*.dem and share/**/*.dem under ROOT,
  - generated files of random expressions (--gen expressions, 20 per file,
    from a fixed --seed).

ROOT defaults to TREE; use the same ROOT for both builds so that the corpus
files are byte-identical.  Output is normalised: tree roots become <ROOT>,
gensym-style names become G#, hex addresses become #x, and timing lines are
dropped.  With --hook, the given Lisp file is loaded before each corpus file
(for example, to install a passive environment-write observer).

"compare" diffs two output directories file by file, ignoring excluded
paths, and exits 1 if any non-excluded file differs or is missing.

The exclusions file is TSV: corpus path<TAB>reason.
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import signal
import re
import subprocess
import sys
import tempfile
import time

GEN_PER_FILE = 20

# Demo files that open viewers or read the terminal are not run.
SKIP_DEM = re.compile(
    r"\b(plot2d|plot3d|draw2d|draw3d|draw\(|wxplot|wxdraw|contour_plot|"
    r"implicit_plot|plotdf|julia|mandelbrot|openplot|gnuplot|scene\(|"
    r"read\(|readonly\(|pause\()", re.I)


def find_corpus(root):
    files = []
    for sub in ("tests",):
        d = os.path.join(root, sub)
        for fn in sorted(os.listdir(d)):
            if fn.startswith("rtest") and fn.endswith(".mac"):
                files.append(os.path.join(sub, fn))
    for sub in ("demo", "share"):
        for dp, dns, fns in os.walk(os.path.join(root, sub)):
            dns.sort()
            for fn in sorted(fns):
                rel = os.path.relpath(os.path.join(dp, fn), root)
                if fn.endswith(".dem"):
                    files.append(rel)
                elif (sub == "share" and fn.startswith("rtest")
                      and fn.endswith(".mac")):
                    files.append(rel)
    return files


def dem_is_skipped(path):
    try:
        with open(path, errors="replace") as fh:
            return bool(SKIP_DEM.search(fh.read()))
    except OSError:
        return True


# ------------------------------------------------------------ generator

ATOMS = ["x", "y", "a", "b", "1", "2", "3", "-1", "1/2", "-3/4", "%pi", "%e"]
UNARY = ["sin", "cos", "exp", "log", "sqrt", "abs", "atan"]
BINARY = ["+", "-", "*", "/", "^"]
WRAPPERS = [
    "expand({e})", "ratsimp({e})", "factor({e})", "diff({e}, x)",
    "integrate({e}, x)", "limit({e}, x, 0)", "taylor({e}, x, 0, 3)",
    "trigsimp({e})", "radcan({e})", "rectform({e})", "sign({e})",
    "is({e} > 0)", "float({e})", "subst(2, x, {e})", "rat({e})",
    "{e}",
]


def gen_expr(rng, depth):
    if depth <= 0 or rng.random() < 0.3:
        return rng.choice(ATOMS)
    if rng.random() < 0.4:
        return "%s(%s)" % (rng.choice(UNARY), gen_expr(rng, depth - 1))
    op = rng.choice(BINARY)
    left = gen_expr(rng, depth - 1)
    right = gen_expr(rng, depth - 1)
    if op == "^":
        right = rng.choice(["2", "3", "-1", "1/2", "a", "x"])
    return "(%s %s %s)" % (left, op, right)


def write_generated(outdir, seed, n):
    rng = random.Random(seed)
    gdir = os.path.join(outdir, "_generated")
    os.makedirs(gdir, exist_ok=True)
    paths = []
    for k in range(0, n, GEN_PER_FILE):
        lines = ["assume(a > 0, b > 0)$"]
        for _ in range(min(GEN_PER_FILE, n - k)):
            e = gen_expr(rng, 3)
            lines.append(rng.choice(WRAPPERS).format(e=e) + ";")
        p = os.path.join(gdir, "gen%05d.mac" % (k // GEN_PER_FILE))
        with open(p, "w") as fh:
            fh.write("\n".join(lines) + "\n")
        paths.append(p)
    return paths


# ------------------------------------------------------------ running

NORMALISERS = [
    (re.compile(r"#:G\d+"), "#:G#"),
    (re.compile(r"\bG\d{3,}\b"), "G#"),
    (re.compile(r"\{[0-9A-Fa-f]{6,}\}"), "{#x}"),
    (re.compile(r"#x[0-9A-Fa-f]{6,}"), "#x"),
    (re.compile(r"\bgensym\d+\b"), "gensym#"),
]
TIMING = re.compile(r"(Evaluation took|seconds \(|real time|run time|"
                    r"bytes consed|elapsed)", re.I)


def normalise(text, roots, gen_src=None):
    if gen_src:
        text = text.replace(gen_src, "<GEN>")
    for r in sorted(roots, key=len, reverse=True):
        text = text.replace(r, "<ROOT>")
    out = []
    for ln in text.splitlines():
        if TIMING.search(ln):
            continue
        for rx, rep in NORMALISERS:
            ln = rx.sub(rep, ln)
        out.append(ln)
    return "\n".join(out) + "\n"


def lisp_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


OUTPUT_CAP = 20 * 1024 * 1024

# A stand-in gnuplot, first on PATH for every corpus process, so plot2d and
# draw never open a window.  It swallows its input and exits successfully.
STUB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stubbin")


def child_env():
    env = dict(os.environ)
    env["PATH"] = STUB_DIR + os.pathsep + env.get("PATH", "")
    return env


def run_one(tree, path, hook, timeout):
    """Run one corpus file.  Output goes to a temporary file and only the
    first OUTPUT_CAP bytes are kept, so a runaway input can't fill memory.
    On timeout the whole process group is killed."""
    pre = ""
    if hook:
        pre = ":lisp (progn (load %s) (values))\n" % lisp_string(hook)
    batch = "%sdisplay2d:false$\nbatch(%s)$\n" % (pre, lisp_string(path))
    t0 = time.time()
    status = "ok"
    with tempfile.TemporaryFile() as out:
        p = subprocess.Popen(
            [os.path.join(tree, "maxima-local"), "--no-init", "--quiet",
             "--batch-string=" + batch],
            cwd=tree, stdout=out, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, start_new_session=True,
            env=child_env())
        try:
            p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            status = "timeout"
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.wait()
        size = out.tell()
        out.seek(0)
        text = out.read(OUTPUT_CAP).decode("utf-8", "replace")
    if size > OUTPUT_CAP:
        status = status + "+truncated"
    return text, status, time.time() - t0


def cmd_run(a):
    tree = os.path.abspath(a.tree)
    root = os.path.abspath(a.corpus_root or a.tree)
    outdir = os.path.abspath(a.outdir)
    os.makedirs(outdir, exist_ok=True)
    excluded = load_exclusions(a.exclusions)

    rels = find_corpus(root)
    skipped = []
    jobs = []
    for rel in rels:
        if rel in excluded:
            continue
        full = os.path.join(root, rel)
        if rel.endswith(".dem") and dem_is_skipped(full):
            skipped.append(rel)
            continue
        jobs.append((rel, full))
    gen_src = os.path.join(outdir, "_gensrc")
    for p in write_generated(gen_src, a.seed, a.gen):
        rel = os.path.relpath(p, gen_src)
        jobs.append((rel, p))

    roots = {tree, root, os.path.realpath(tree), os.path.realpath(root)}
    results = {}
    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        futs = {ex.submit(run_one, tree, full, a.hook, a.timeout): rel
                for rel, full in jobs}
        for f in concurrent.futures.as_completed(futs):
            rel = futs[f]
            text, status, secs = f.result()
            dst = os.path.join(outdir, rel + ".out")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w") as fh:
                fh.write(normalise(text, roots, gen_src))
            results[rel] = {"status": status, "secs": round(secs, 2)}
    manifest = {
        "tree": tree, "corpus_root": root, "seed": a.seed,
        "generated_expressions": a.gen, "files_run": len(jobs),
        "dem_skipped_graphics_or_input": len(skipped),
        "timeouts": sorted(r for r, v in results.items()
                           if v["status"] != "ok"),
        "wall_seconds": round(time.time() - t0, 1),
        "hook": a.hook, "jobs": a.jobs, "timeout": a.timeout,
        "files": results, "skipped": skipped,
    }
    with open(os.path.join(outdir, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    print("files %d  skipped %d  timeouts %d  wall %.1fs" % (
        len(jobs), len(skipped), len(manifest["timeouts"]),
        manifest["wall_seconds"]))


def load_exclusions(path):
    ex = {}
    if not path:
        return ex
    with open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            parts = ln.split("\t")
            if len(parts) < 2 or not parts[1].strip():
                sys.exit("exclusion without reason: %r" % ln)
            ex[parts[0]] = parts[1]
    return ex


# Compare-time masks for output that legitimately varies between runs of the
# same build.  Generic masks apply to every file; per-file masks come from
# the --masks file (path<TAB>regex<TAB>replacement<TAB>reason).
GENERIC_MASKS = [
    (re.compile(r"/var/folders/[^\s\"]*/T/[^\s\",\]]*"), "<TMPFILE>"),
    (re.compile(r"\\\{[0-9A-Fa-f]{6,}\\\}"), "{#x}"),
    (re.compile(r"Runtime was\s+[0-9.]+\s+seconds"), "Runtime was <T> seconds"),
    # Build identity differs legitimately between two builds.
    (re.compile(r"branch_\d+_\d+_base_\d+_g[0-9a-f]+(_dirty)?"), "<VERSION>"),
    (re.compile(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d"), "<DATETIME>"),
    (re.compile(r"maxima\\?-(mt\\?-baseline|multithreading)"), "<TREE>"),
    # Tests that print their own elapsed time with the idiom
    # (time:absolute_real_time()-start,print(time),...).
    (re.compile(r"(absolute_real_time\(\)-start,print\(time\).*\n)\d+ \n"),
     "\\1<ELAPSED> \n"),
]


def load_masks(path):
    masks = {}
    if not path:
        return masks
    with open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln.strip() or ln.startswith("#"):
                continue
            parts = ln.split("\t")
            if len(parts) < 4 or not parts[3].strip():
                sys.exit("mask without reason: %r" % ln)
            masks.setdefault(parts[0], []).append(
                (re.compile(parts[1], re.M), parts[2]))
    return masks


def digest(path, masks=()):
    with open(path, errors="replace") as fh:
        text = fh.read()
    for rx, rep in GENERIC_MASKS:
        text = rx.sub(rep, text)
    for rx, rep in masks:
        text = rx.sub(rep, text)
    return hashlib.sha256(text.encode()).hexdigest()


def outputs(d):
    res = {}
    for dp, dns, fns in os.walk(d):
        if os.path.basename(dp) == "_gensrc":
            dns[:] = []
            continue
        for fn in fns:
            if fn.endswith(".out"):
                p = os.path.join(dp, fn)
                res[os.path.relpath(p, d)[:-4]] = p
    return res


def cmd_compare(a):
    excluded = load_exclusions(a.exclusions)
    masks = load_masks(a.masks)
    A, B = outputs(a.dir_a), outputs(a.dir_b)
    bad = []
    for rel in sorted(set(A) | set(B)):
        if rel in excluded:
            continue
        if rel not in A or rel not in B:
            bad.append((rel, "missing in " + ("A" if rel not in A else "B")))
        elif (digest(A[rel], masks.get(rel, ()))
              != digest(B[rel], masks.get(rel, ()))):
            bad.append((rel, "differs"))
    for rel, why in bad:
        print("%s\t%s" % (rel, why))
    n = len((set(A) | set(B)) - set(excluded))
    sys.stderr.write("compared %d files, %d differ, %d excluded\n" % (
        n, len(bad), len(excluded)))
    sys.exit(1 if bad else 0)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("run")
    r.add_argument("tree")
    r.add_argument("outdir")
    r.add_argument("--corpus-root")
    r.add_argument("--seed", type=int, default=20260918)
    r.add_argument("--gen", type=int, default=2000)
    r.add_argument("--jobs", type=int, default=8)
    r.add_argument("--timeout", type=int, default=300)
    r.add_argument("--exclusions")
    r.add_argument("--hook")
    c = sp.add_parser("compare")
    c.add_argument("dir_a")
    c.add_argument("dir_b")
    c.add_argument("--exclusions")
    c.add_argument("--masks")
    a = ap.parse_args()
    (cmd_run if a.cmd == "run" else cmd_compare)(a)


if __name__ == "__main__":
    main()
