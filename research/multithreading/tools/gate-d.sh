#!/bin/sh
# Stage D gate for one conversion step.  $1 is a label (e.g. suprv1).
# Checks: build clean, image fresh, scanner count, core suite vs baseline,
# oracle class A count.  With QUICK=1 only the build and scanner checks run.
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd)
W=$(cd "$R/../.." && pwd)
L=$R/logs
label=$1
cd "$W"
make > "$L/build-D-$label.log" 2>&1 || { echo "BUILD FAILED"; exit 1; }
w=$(grep -c -E "caught (ERROR|WARNING)" "$L/build-D-$label.log")
u=$(grep "undefined function:" "$L/build-D-$label.log" | grep -vc "MAKE:")
stale=$(find src -name '*.lisp' -newer src/binary-sbcl/maxima.core | wc -l | tr -d ' ')
echo "build: caught=$w  undefined(non-MAKE)=$u  stale=$stale"
python3 "$here/plist_scan.py" --allowlist "$R/plist-allowlist.tsv" src > "$L/scan-D-$label.txt" 2> "$L/scan-D-$label.sum"
echo "scanner: $(cat "$L/scan-D-$label.sum")"
[ "${QUICK:-}" ] && exit 0
"$here/suite.sh" "$W" "$L/suite-core-D-$label.log" core
echo "core suite: $(grep -o 'No unexpected errors found out of [0-9,]* tests' "$L/suite-core-D-$label.log" | tail -1)$(grep -c 'Error summary' "$L/suite-core-D-$label.log" | sed 's/^0$//;s/^[1-9].*/ ERRORS - see log/')"
"$here/oracle-suite.sh" "$W" "$L/oracle-D-$label.tsv"
grep -o "No unexpected errors found out of [0-9,]* tests" "$L/oracle-D-$label.tsv.log" | tail -1 | sed 's/^/oracle suite: /'
python3 "$here/gap_report.py" "$L/oracle-D-$label.tsv" --churn "$R/oracle-churn.tsv" > "$L/gap-D-$label.md"
grep "^| A\." "$L/gap-D-$label.md"
