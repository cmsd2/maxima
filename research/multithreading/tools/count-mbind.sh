#!/bin/sh
# Count MBIND calls over a real workload (task 3.3).
#   WHAT [wc10|suite]   OUT [logs/mbind-count.jsonl]   COUNT [1] -- 0 measures
#   the same workload without the counting wrapper, for the wall-time baseline
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
WHAT=${WHAT:-wc10}; OUT=${OUT:-$L/mbind-count.jsonl}; COUNT=${COUNT:-1}
mkdir -p "$L"; PATH="$here/stubbin:$PATH"; export PATH; cd "$W"

q='"'
if [ "$COUNT" -eq 1 ]; then
  loadcount=" (load ${q}$here/count-mbind.lisp${q})"
  label="$WHAT-counted"
else
  loadcount=""
  label="$WHAT-plain"
fi
load=":lisp (progn (load ${q}$here/pool.lisp${q})$loadcount (values))"

case "$WHAT" in
  wc10) work="(dotimes (i \$wc_n_items) (maxima::pool-item '\$wc_item i))"
        setup="batchload(${q}$R/workloads/wc_pool.mac${q})\$
wc_setup(10)\$" ;;
  suite) work="(maxima::\$run_testsuite)"; setup="" ;;
  *) echo "WHAT must be wc10 or suite"; exit 2 ;;
esac

if [ "$COUNT" -eq 1 ]; then
  form=":lisp (maxima::with-mbind-count (${q}$label${q} ${q}$OUT${q}) $work)"
else
  form=":lisp (let ((t0 (maxima::pool-now))) $work (maxima::pool-append-record ${q}$OUT${q} (list :label ${q}$label${q} :kind ${q}wall-only${q} :wall (maxima::pool-secs (- (maxima::pool-now) t0)))) (values))"
fi

timeout 3600 ./maxima-local --no-init --quiet --batch-string="$load
$setup
$form" > "$L/mbind-count-$label.log" 2>&1
if grep -q "Maxima encountered a Lisp error" "$L/mbind-count-$label.log"; then
  echo "LISP ERROR, see $L/mbind-count-$label.log"; exit 1
fi
grep -E "^$label:|No unexpected errors" "$L/mbind-count-$label.log" | tail -3
[ "$COUNT" -eq 0 ] && tail -1 "$OUT"
exit 0
