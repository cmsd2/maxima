#!/bin/sh
# Stage A checks for the thread runner.
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
mkdir -p "$L"; PATH="$here/stubbin:$PATH"; export PATH; cd "$W"
timeout 600 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/threads.lisp\") (load \"$here/threads-test.lisp\") (maxima::tt-run-stage-a))" \
  > "$L/threads-test.log" 2>&1
grep -E "^(PASS|FAIL) |^;; stage A" "$L/threads-test.log"
if grep -q "Maxima encountered a Lisp error" "$L/threads-test.log"; then
  echo "LISP ERROR, see $L/threads-test.log"; exit 1
fi
grep -q "^FAIL " "$L/threads-test.log" && exit 1
exit 0
