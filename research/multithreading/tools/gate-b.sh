#!/bin/sh
# Gate B checks: full suite (no hook), corpus with and without a passive
# hook, and alternating core-suite timings.  Run from the workspace root.
set -u
R=maxima-multithreading/research/multithreading
L=$R/logs
W=$PWD/maxima-multithreading
B=$PWD/maxima-mt-baseline
HOOK=$PWD/$R/tools/count-hook.lisp

# Hook sanity: the passive hook must load and count writes.
n=$(cd "$W" && timeout 60 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$HOOK\") (values))
x:1\$
:lisp (format t \"~&HOOKCOUNT=~D~%\" *environment-write-count*)" 2>&1 | sed -n 's/^HOOKCOUNT=//p')
echo "hook sanity: count=$n"
[ "${n:-0}" -gt 0 ] || { echo "hook did not load or count; stopping"; exit 1; }

[ "${SKIP_SUITE:-}" ] || $R/tools/suite.sh "$W" "$PWD/$L/suite-full-stageB.log" full
[ "${SKIP_SUITE:-}" ] || echo "full suite: $(cat $L/suite-full-stageB.log.time)s $(grep -o 'No unexpected errors found out of [0-9,]* tests' $L/suite-full-stageB.log | tail -1)"

# Warm-up (discarded): compiles share packages into the worktree's objdir.
python3 $R/tools/corpus.py run maxima-multithreading $L/corpus-stageB-warmup --corpus-root maxima-mt-baseline --jobs 6 --exclusions $R/corpus-exclusions.tsv | tail -1
python3 $R/tools/corpus.py run maxima-multithreading $L/corpus-stageB-nohook --corpus-root maxima-mt-baseline --jobs 6 --exclusions $R/corpus-exclusions.tsv | tail -1
python3 $R/tools/corpus.py run maxima-multithreading $L/corpus-stageB-hook --corpus-root maxima-mt-baseline --jobs 6 --exclusions $R/corpus-exclusions.tsv --hook "$HOOK" | tail -1
for v in nohook hook; do
  echo "corpus $v vs baseline:"
  python3 $R/tools/corpus.py compare $L/corpus-baseline-a $L/corpus-stageB-$v --exclusions $R/corpus-exclusions.tsv --masks $R/corpus-masks.tsv 2>&1 | tail -15
done

[ "${SKIP_TIMING:-}" ] && exit 0
for i in 0 1 2 3; do
  for t in baseline stageB; do
    if [ $t = baseline ]; then tree=$B; else tree=$W; fi
    $R/tools/suite.sh "$tree" "$PWD/$L/timing-$t-$i.log" core
    echo "timing $t $i: $(grep -o '[0-9.]* seconds of real time' $L/timing-$t-$i.log) $(grep -c 'No unexpected errors' $L/timing-$t-$i.log)"
  done
done
