#!/bin/sh
# Run the full test suite (share tests included) with the snapshot oracle,
# writing unexplained differences to $2 (TSV) and the suite log to $2.log.
# $1 is the Maxima tree.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tree=$1
out=$2
PATH="$here/stubbin:$PATH"; export PATH
rm -f "$out"
cd "$tree"
start=$(date +%s)
timeout 10800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/oracle.lisp\") (maxima::oracle-install \"$out\") (values))
run_testsuite(share_tests=true);
:lisp (maxima::oracle-summary)" > "$out.log" 2>&1
echo "wall $(( $(date +%s) - start ))s" >> "$out.log"
