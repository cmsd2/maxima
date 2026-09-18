#!/bin/sh
# Compile one source file inside the built image (fasl to a temp dir) and
# report caught warnings/errors.  Fast per-file check for stage D batches.
set -u
here=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$here/../../.." && pwd)
f=$1
tmp=$(mktemp -d)
cd "$W"
out=$(timeout 300 ./maxima-local --no-init --quiet --batch-string=":lisp (let ((*compile-verbose* nil)) (multiple-value-bind (fasl warn fail) (compile-file \"src/$f\" :output-file \"$tmp/x.fasl\") (declare (ignore fasl)) (format t \"~&QC warnings=~A failure=~A~%\" warn fail)))" 2>&1)
rm -rf "$tmp"
res=$(echo "$out" | grep "^QC ")
caught=$(echo "$out" | grep -c "caught \(WARNING\|ERROR\)")
echo "$f: $res caught=$caught"
echo "$out" | grep -B8 "caught \(WARNING\|ERROR\)" | head -30
