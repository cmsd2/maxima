#!/bin/sh
# Threads against the process pool (add-threaded-prototype, stage D).
# One fresh image per measurement, the process-pool benchmark's methodology.
# Environment (defaults in brackets):
#   SIZES [10 12]  WORKERS [1 2 3 4 6 8 10]  ROUNDS [3] (+ one discarded)
#   ARMS [threads pool]  MODES [static dynamic]
#   GUARDOFF [4] -- worker counts at which a thread run is repeated with
#                   the guard off, to price it (task 4.3); "" for none
#   OUT [logs/bench-d.jsonl]  FORCE [0] -- 1 skips the quiet-machine check
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
SIZES=${SIZES:-"10 12"}; WORKERS=${WORKERS:-"1 2 3 4 6 8 10"}
ROUNDS=${ROUNDS:-3}; ARMS=${ARMS:-"threads pool"}; MODES=${MODES:-"static dynamic"}
GUARDOFF=${GUARDOFF:-"4"}; OUT=${OUT:-$L/bench-d.jsonl}; FORCE=${FORCE:-0}
TMP=$L/pool-tmp; mkdir -p "$TMP" "$L"
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
busy() { ps -A -o %cpu | awk 'NR>1{s+=$1} END{printf "%.1f", s}'; }
if [ "$FORCE" -ne 1 ]; then
  b=$(busy)
  if [ "$(echo "$b" | cut -d. -f1)" -ge 250 ]; then
    echo "machine is busy: $b% of one core; quiet test is < 250%"; exit 2
  fi
  echo "machine check: ${b}% CPU in use"
fi
commit=$(git rev-parse --short HEAD)
sbcl=$(sbcl --version | cut -d' ' -f2)
cores="$(sysctl -n hw.perflevel0.physicalcpu)P+$(sysctl -n hw.perflevel1.physicalcpu)E"
mem=$(sysctl -n hw.memsize); cpu=$(sysctl -n machdep.cpu.brand_string)

maxima_run() {  # $1 = lisp form after setup; $2 = size
  timeout 3600 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/threads.lisp\") (load \"$here/threads-bench.lisp\") (values))
batchload(\"$R/workloads/wc_pool.mac\")\$
wc_setup($2)\$
:lisp $1" > "$L/bench-d-last.log" 2>&1
  if grep -q "Maxima encountered a Lisp error" "$L/bench-d-last.log"; then
    echo "LISP ERROR, see $L/bench-d-last.log"; exit 1
  fi
}

for n in $SIZES; do
  ref=$L/expected-t$n.lisp
  if [ ! -s "$ref" ]; then
    echo "reference results for $n tolerances"
    maxima_run "(progn (maxima::seq-run '\$wc_item \$wc_n_items \"$L/bench-d-reference.jsonl\" :label \"ref$n\" :item-times nil) (maxima::seq-save-results \"$ref\"))" $n
  fi
done

configs=""
for n in $SIZES; do
  configs="$configs $n:seq:static:0:on"
  for a in $ARMS; do for m in $MODES; do for p in $WORKERS; do
    configs="$configs $n:$a:$m:$p:on"
    if [ "$a" = threads ]; then
      for g in $GUARDOFF; do [ "$g" = "$p" ] && configs="$configs $n:$a:$m:$p:off"; done
    fi
  done; done; done
done
nconf=$(echo $configs | wc -w | tr -d ' ')

r=0
while [ $r -le "$ROUNDS" ]; do
  set -- $configs
  shift_by=$(( (r * 5) % nconf ))
  i=0; head=""; tail=""
  for c in "$@"; do
    if [ $i -lt $shift_by ]; then tail="$tail $c"; else head="$head $c"; fi
    i=$((i+1))
  done
  for c in $head $tail; do
    n=${c%%:*}; rest=${c#*:}; a=${rest%%:*}; rest=${rest#*:}
    m=${rest%%:*}; rest=${rest#*:}; p=${rest%%:*}; g=${rest#*:}
    load1=$(sysctl -n vm.loadavg | awk '{print $2}')
    cpubusy=$(busy)
    pct=$(pmset -g batt | tail -1 | grep -o '[0-9]*%' | tr -d '%')
    src=$(pmset -g batt | head -1 | grep -qi "AC Power" && echo ac || echo battery)
    extra="(list :load1 $load1 :cpu_busy $cpubusy :power \"$src\" :battery_pct ${pct:-0} :round $r :warmup_round $( [ $r -eq 0 ] && echo t || echo nil ) :tolerances $n :started \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" :commit \"$commit\" :sbcl \"$sbcl\" :cores \"$cores\" :memsize $mem :cpu \"$cpu\" :forced $( [ "$FORCE" -eq 1 ] && echo t || echo nil ))"
    case $a in
      seq) maxima_run "(maxima::seq-run '\$wc_item \$wc_n_items \"$OUT\" :label \"t$n\" :item-times nil :extra $extra)" $n ;;
      pool) maxima_run "(maxima::pool-run '\$wc_item \$wc_n_items $p \"$OUT\" :mode :$m :label \"t$n\" :tmp-dir \"$TMP/\" :expected (maxima::seq-load-results \"$L/expected-t$n.lisp\") :extra $extra)" $n ;;
      threads) maxima_run "(maxima::thread-bench '\$wc_item \$wc_n_items $p \"$OUT\" :mode :$m :label \"t$n\" :guard $( [ "$g" = on ] && echo t || echo nil ) :expected (maxima::seq-load-results \"$L/expected-t$n.lisp\") :extra $extra)" $n ;;
    esac
    printf "round %d  %-3s %-7s %-7s p=%-2s guard=%-3s %s\n" $r "$n" "$a" "$m" "$p" "$g" "$(tail -1 "$OUT" | python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print("wall=%.3f"%r["wall"], "correct=%s"%r.get("correct","-"))')"
  done
  r=$((r+1))
done
echo "sweep complete: $OUT"
