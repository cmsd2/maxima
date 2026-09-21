#!/bin/sh
# GC scaling spike sweep (task 2.3).  One fresh image per measurement.
# Environment (defaults in brackets):
#   ARMS [threads processes]  WORKERS [1 2 4 8]  ROUNDS [3]
#   ITERS [8000000]           ARGS [""] -- allocator knobs, default calibrated
#   OUT [logs/gcspike.jsonl]  TAG [""] -- label suffix
#   FORCE [0] -- 1 skips the quiet-machine check
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
ARMS=${ARMS:-"threads processes"}
WORKERS=${WORKERS:-"1 2 4 8"}
ROUNDS=${ROUNDS:-3}
ITERS=${ITERS:-8000000}
ARGS=${ARGS:-""}
TAG=${TAG:-""}
OUT=${OUT:-$L/gcspike.jsonl}
FORCE=${FORCE:-0}
mkdir -p "$L"
cd "$W"

busy() { ps -A -o %cpu | awk 'NR>1{s+=$1} END{printf "%.1f", s}'; }
if [ "$FORCE" -ne 1 ]; then
  b=$(busy)
  if [ "$(echo "$b" | cut -d. -f1)" -ge 250 ]; then
    echo "machine is busy: $b% of one core in use; quiet test is < 250%"
    echo "set FORCE=1 to measure anyway (the records will say so)"
    exit 2
  fi
  echo "machine check: ${b}% CPU in use"
fi

commit=$(git rev-parse --short HEAD)
sbcl=$(sbcl --version | cut -d' ' -f2)
cores="$(sysctl -n hw.perflevel0.physicalcpu)P+$(sysctl -n hw.perflevel1.physicalcpu)E"
cpu=$(sysctl -n machdep.cpu.brand_string)

measure() {  # $1 arm  $2 workers  $3 round  $4 warmup(t/nil)
  load1=$(sysctl -n vm.loadavg | awk '{print $2}')
  cpubusy=$(busy)
  power=$(pmset -g batt | head -1 | sed -e "s/.*'\(.*\)'.*/\1/")
  batt=$(pmset -g batt | tail -1 | sed -e 's/.*[^0-9]\([0-9]*\)%.*/\1/')
  extra="(list :commit \"$commit\" :sbcl \"$sbcl\" :cpu \"$cpu\" :cores \"$cores\" \
:load1 $load1 :cpu_busy $cpubusy :power \"$power\" :battery $batt :forced $([ "$FORCE" -eq 1 ] && echo t || echo nil))"
  timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/gcspike.lisp\") (maxima::gcspike-run :$1 $2 $ITERS \"$OUT\" :label \"gcspike$TAG\" :round $3 :warmup $4 :extra $extra $([ -n "$ARGS" ] && echo ":work-args (list $ARGS)")))" \
    > "$L/gcspike-last.log" 2>&1
  if grep -q "Maxima encountered a Lisp error" "$L/gcspike-last.log"; then
    echo "LISP ERROR ($1 p=$2), see $L/gcspike-last.log"; exit 1
  fi
  grep -E "^gcspike$TAG " "$L/gcspike-last.log" || {
    echo "no result line ($1 p=$2), see $L/gcspike-last.log"; exit 1; }
}

configs=""
for a in $ARMS; do for p in $WORKERS; do configs="$configs $a:$p"; done; done
nconf=$(echo $configs | wc -w | tr -d ' ')

r=0
while [ $r -le "$ROUNDS" ]; do
  [ $r -eq 0 ] && warm=t || warm=nil
  # Rotate the configuration order by r positions each round.
  set -- $configs
  shift_by=$(( r % nconf ))
  i=0; head=""; tail=""
  for c in "$@"; do
    if [ $i -lt $shift_by ]; then tail="$tail $c"; else head="$head $c"; fi
    i=$((i+1))
  done
  for c in $head $tail; do
    arm=${c%%:*}; p=${c#*:}
    measure "$arm" "$p" "$r" "$warm"
  done
  r=$((r+1))
done
echo "sweep complete: $OUT"
