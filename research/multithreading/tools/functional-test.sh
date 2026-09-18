#!/bin/sh
# Functional tests for the environment write hook (tasks 7.1-7.3).
# Exits 0 only if every check passes.  $1 is the Maxima tree.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tree=${1:-$(cd "$here/../../.." && pwd)}
PATH="$here/stubbin:$PATH"; export PATH
cd "$tree"
run() {
  timeout 300 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/functional-test.lisp\") (values))
:lisp $1" 2>&1 | grep -E "^(PASS|FAIL) "
}
out=$(run "(maxima::envhook-test-scenarios)")
for w in rat sign limit integrate rectform block; do
  out="$out
$(run "(maxima::envhook-test-writer :$w)")"
done
echo "$out" | grep -v '^$'
pass=$(echo "$out" | grep -c '^PASS')
fail=$(echo "$out" | grep -c '^FAIL')
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ] && [ "$pass" -eq 14 ]
