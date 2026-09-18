#!/bin/sh
# Stage E full validation (tasks 9.1-9.6).  Run from anywhere.
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); WS=$(cd "$W/.." && pwd)
B=$WS/maxima-mt-baseline; L=$R/logs; HOOK=$here/count-hook.lisp
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
echo "== 9.1 oracle over the full suite"
"$here/oracle-suite.sh" "$W" "$L/oracle-final.tsv"
grep -o "No unexpected errors found out of [0-9,]* tests" "$L/oracle-final.tsv.log" | tail -1
python3 "$here/gap_report.py" "$L/oracle-final.tsv" --churn "$R/oracle-churn.tsv" > "$R/results/gap-report-final.md"
sed -n '/^| Class/,/^$/p;/## Verdict/,/^## C/p' "$R/results/gap-report-final.md" | grep "^|"
echo "== 9.2 seeded bypasses"; "$here/seeded-test.sh" "$W" | tail -1
echo "== 9.3 full suite, no hook"
"$here/suite.sh" "$W" "$L/suite-full-final.log" full
grep -o "No unexpected errors found out of [0-9,]* tests" "$L/suite-full-final.log" | tail -1
echo "== 9.4 core suite, passive counting hook"
timeout 3600 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$HOOK\") (values))
run_testsuite();
:lisp (format t \"~&HOOKCOUNT=~D~%\" maxima::*environment-write-count*)" > "$L/suite-core-hook-final.log" 2>&1
grep -o "No unexpected errors found out of [0-9,]* tests" "$L/suite-core-hook-final.log" | tail -1
grep "^HOOKCOUNT=" "$L/suite-core-hook-final.log"
echo "== 9.5 differential corpus"
cd "$WS"
for v in warmup nohook hook; do
  if [ $v = hook ]; then h="--hook $HOOK"; else h=""; fi
  python3 "$here/corpus.py" run "$W" "$L/corpus-final-$v" --corpus-root "$B" --jobs 6 --exclusions "$R/corpus-exclusions.tsv" $h | tail -1
done
for v in nohook hook; do
  printf "corpus %s vs baseline: " $v
  python3 "$here/corpus.py" compare "$L/corpus-baseline-a" "$L/corpus-final-$v" --exclusions "$R/corpus-exclusions.tsv" --masks "$R/corpus-masks.tsv" 2>&1 | tail -3 | tr '\n' ' '; echo
done
echo "== 9.6 alternating core-suite timing (run 0 discarded)"
for i in 0 1 2 3; do
  for t in baseline final; do
    if [ $t = baseline ]; then tree=$B; else tree=$W; fi
    "$here/suite.sh" "$tree" "$L/timing-E-$t-$i.log" core
    echo "timing $t $i: $(grep -o '[0-9.]* seconds of real time' "$L/timing-E-$t-$i.log")"
  done
done
