#!/bin/sh
# Seeded-bypass test (task 5.2): every planted bypass must be caught by the
# scanner, the oracle, or both.  Run from anywhere; $1 is the Maxima tree.
set -u
here=$(cd "$(dirname "$0")" && pwd)
tree=${1:-$here/../../..}
fixture=$here/fixtures/seeded-bypasses.lisp
fail=0

scan=$(python3 "$here/plist_scan.py" --tsv "$fixture" 2>/dev/null | cut -f5 | sort)
for fn in "defun seeded-setf-get" "defun seeded-funcall-setf-get" "defun seeded-getf-symbol-plist"; do
  if echo "$scan" | grep -qx "$fn"; then echo "scanner  caught  $fn"; else echo "scanner  MISSED  $fn"; fi
done

out=$(cd "$tree" && timeout 120 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/oracle.lisp\") (load \"$fixture\") (values))
:lisp (in-package :maxima)
:lisp (defun seeded-check (label thunk) (clrhash *oracle-log*) (let ((a (let ((*environment-write-hook* nil)) (oracle-snapshot)))) (let ((*environment-write-hook* (function oracle-hook))) (funcall thunk)) (let ((u (remove-if (function oracle-explained-p) (let ((*environment-write-hook* nil)) (oracle-diff a (oracle-snapshot)))))) (format t \"~&SEEDED ~A ~A ~S~%\" (if u \"caught\" \"MISSED\") label u))))
:lisp (seeded-check \"setf-get\" (function seeded-setf-get))
:lisp (seeded-check \"getf-symbol-plist\" (function seeded-getf-symbol-plist))
:lisp (let ((cell (seeded-rplacd-stored-value))) (seeded-check \"rplacd-stored-value\" (lambda () (seeded-rplacd-now cell))))
:lisp (seeded-check \"nconc-values\" (function seeded-nconc-values))" 2>&1 | grep '^SEEDED')
echo "$out" | sed 's/^SEEDED /oracle   /'
echo "$out" | grep -q MISSED && fail=1
echo "$scan" | grep -qx "defun seeded-setf-get" || fail=1
echo "$scan" | grep -qx "defun seeded-funcall-setf-get" || fail=1
echo "$scan" | grep -qx "defun seeded-getf-symbol-plist" || fail=1
[ $(echo "$out" | grep -c caught) -eq 4 ] || fail=1
[ $fail -eq 0 ] && echo "PASS: all seeded bypasses caught" || echo "FAIL"
exit $fail
