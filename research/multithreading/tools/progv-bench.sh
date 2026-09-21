#!/bin/sh
# Binding cost microbenchmark (task 3.2).
#   ITERS [200000]  NVARS ["1 2 5 10"]  OUT [logs/progv.jsonl]  ROUNDS [3]
#   FORCE [0] -- 1 skips the quiet-machine check
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
ITERS=${ITERS:-200000}; NVARS=${NVARS:-"1 2 5 10"}; ROUNDS=${ROUNDS:-3}
OUT=${OUT:-$L/progv.jsonl}; FORCE=${FORCE:-0}
mkdir -p "$L"; cd "$W"
busy() { ps -A -o %cpu | awk 'NR>1{s+=$1} END{printf "%.1f", s}'; }
if [ "$FORCE" -ne 1 ]; then
  b=$(busy)
  if [ "$(echo "$b" | cut -d. -f1)" -ge 250 ]; then
    echo "machine is busy: $b% of one core; quiet test is < 250%"; exit 2
  fi
  echo "machine check: ${b}% CPU in use"
fi
commit=$(git rev-parse --short HEAD); sbcl=$(sbcl --version | cut -d' ' -f2)
nl=$(echo $NVARS | sed 's/ /  /g')
r=1
while [ $r -le "$ROUNDS" ]; do
  extra="(list :commit \"$commit\" :sbcl \"$sbcl\" :round $r :cpu_busy $(busy))"
  timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/progv-bench.lisp\") (maxima::pv-bench \"$OUT\" :nvars '($nl) :iterations $ITERS :extra $extra))" \
    > "$L/progv-last.log" 2>&1
  grep -q "Maxima encountered a Lisp error" "$L/progv-last.log" && {
    echo "LISP ERROR, see $L/progv-last.log"; exit 1; }
  echo "--- round $r"
  grep -E "^progv n=" "$L/progv-last.log" || { sed -n '1,40p' "$L/progv-last.log"; exit 1; }
  r=$((r+1))
done
