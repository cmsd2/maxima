#!/bin/sh
# Process-pool benchmark sweep (task 3.1, design D5).
# Environment (defaults in brackets):
#   SIZES [10 12]  WORKERS [1 2 3 4 6 8 10]  MODES [dynamic static]
#   ROUNDS [3] (timed rounds; one discarded warm-up round runs first)
#   OUT [logs/pool-sweep.jsonl]
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
SIZES=${SIZES:-"10 12"}
WORKERS=${WORKERS:-"1 2 3 4 6 8 10"}
MODES=${MODES:-"dynamic static"}
ROUNDS=${ROUNDS:-3}
OUT=${OUT:-$L/pool-sweep.jsonl}
TMP=$L/pool-tmp; mkdir -p "$TMP"
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
commit=$(git rev-parse --short HEAD)
sbcl=$(sbcl --version | cut -d' ' -f2)
cores="$(sysctl -n hw.perflevel0.physicalcpu)P+$(sysctl -n hw.perflevel1.physicalcpu)E"
mem=$(sysctl -n hw.memsize)
cpu=$(sysctl -n machdep.cpu.brand_string)

maxima_run() {  # $1 = lisp form to evaluate after setup; $2 = size
  timeout 3600 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (values))
batchload(\"$R/workloads/wc_pool.mac\")\$
wc_setup($2)\$
:lisp $1" > "$L/pool-bench-last.log" 2>&1
  grep -q "Maxima encountered a Lisp error" "$L/pool-bench-last.log" && { echo "LISP ERROR, see $L/pool-bench-last.log"; exit 1; }
  return 0
}

# Reference results per size (not timed).
for n in $SIZES; do
  ref=$L/expected-t$n.lisp
  if [ ! -s "$ref" ]; then
    echo "reference results for $n tolerances"
    maxima_run "(progn (maxima::seq-run '\$wc_item \$wc_n_items \"$L/pool-reference.jsonl\" :label \"ref$n\" :item-times nil) (maxima::seq-save-results \"$ref\"))" $n
  fi
done

configs=""
for n in $SIZES; do
  configs="$configs $n:seq:0"
  for m in $MODES; do for p in $WORKERS; do configs="$configs $n:$m:$p"; done; done
done
nconf=$(echo $configs | wc -w | tr -d ' ')

r=0
while [ $r -le "$ROUNDS" ]; do
  # Rotate the configuration order by r*5 positions each round.
  set -- $configs
  shift_by=$(( (r * 5) % nconf ))
  i=0; head=""; tail=""
  for c in "$@"; do
    if [ $i -lt $shift_by ]; then tail="$tail $c"; else head="$head $c"; fi
    i=$((i+1))
  done
  for c in $head $tail; do
    n=${c%%:*}; rest=${c#*:}; m=${rest%%:*}; p=${rest#*:}
    extra="(list :round $r :warmup $( [ $r -eq 0 ] && echo t || echo nil ) :tolerances $n :started \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" :commit \"$commit\" :sbcl \"$sbcl\" :cores \"$cores\" :memsize $mem :cpu \"$cpu\")"
    if [ "$m" = seq ]; then
      maxima_run "(maxima::seq-run '\$wc_item \$wc_n_items \"$OUT\" :label \"t$n\" :extra $extra)" $n
    else
      maxima_run "(maxima::pool-run '\$wc_item \$wc_n_items $p \"$OUT\" :mode :$m :label \"t$n\" :tmp-dir \"$TMP/\" :expected (maxima::seq-load-results \"$L/expected-t$n.lisp\") :extra $extra)" $n
    fi
    printf "round %d  %-3s %-7s p=%-2s  %s\n" $r "$n" "$m" "$p" "$(tail -1 "$OUT" | python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print("wall=%.3f"%r["wall"], "correct=%s"%r.get("correct","-"))')"
  done
  r=$((r+1))
done
