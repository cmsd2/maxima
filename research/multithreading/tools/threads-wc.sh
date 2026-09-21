#!/bin/sh
# wc_systematic on the thread pool, checked against sequential (task 3.3).
#   SIZE [6]  WORKERS ["1 2 4"]  MODE [static]  OUT [logs/threads-wc.jsonl]
#   LABEL [wc<SIZE>]
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
SIZE=${SIZE:-6}; WORKERS=${WORKERS:-"1 2 4"}; MODE=${MODE:-static}
OUT=${OUT:-$L/threads-wc.jsonl}; LABEL=${LABEL:-wc$SIZE}
mkdir -p "$L"; PATH="$here/stubbin:$PATH"; export PATH; cd "$W"
status=0
for p in $WORKERS; do
  timeout 3600 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/threads.lisp\") (load \"$here/threads-wc.lisp\") (values))
batchload(\"$R/workloads/wc_pool.mac\")\$
wc_setup($SIZE)\$
:lisp (maxima::thread-wc-check '\$wc_item \$wc_n_items $p \"$OUT\" :mode :$MODE :label \"$LABEL\")" \
    > "$L/threads-wc-$LABEL-p$p.log" 2>&1
  if grep -q "Maxima encountered a Lisp error" "$L/threads-wc-$LABEL-p$p.log"; then
    echo "LISP ERROR (p=$p), see $L/threads-wc-$LABEL-p$p.log"; status=1; continue
  fi
  line=$(grep -E "^$LABEL p=$p " "$L/threads-wc-$LABEL-p$p.log")
  echo "${line:-no result line (p=$p), see $L/threads-wc-$LABEL-p$p.log}"
  echo "$line" | grep -q " correct" || status=1
done
exit $status
