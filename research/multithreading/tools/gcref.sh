#!/bin/sh
# Reference allocation profile for the GC spike (task 1.1).
#   SIZE [10]  LABEL [wc<SIZE>]  OUT [logs/gcref.jsonl]
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
SIZE=${SIZE:-10}; LABEL=${LABEL:-wc$SIZE}; OUT=${OUT:-$L/gcref.jsonl}
mkdir -p "$L"
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/gcspike.lisp\") (values))
batchload(\"$R/workloads/wc_pool.mac\")\$
wc_setup($SIZE)\$
:lisp (maxima::gcspike-reference '\$wc_item \$wc_n_items \"$OUT\" :label \"$LABEL\")" \
  > "$L/gcref-last.log" 2>&1
grep -q "Maxima encountered a Lisp error" "$L/gcref-last.log" && {
  echo "LISP ERROR, see $L/gcref-last.log"; exit 1; }
grep -E "^$LABEL:" "$L/gcref-last.log"
