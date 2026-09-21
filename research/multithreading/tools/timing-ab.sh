#!/bin/sh
# Single-thread timing gate (add-threaded-prototype task 2.5).
# Alternates two trees, A then B, ROUNDS times after one discarded round,
# on wc_systematic at 10 tolerances and on the core suite.  Prints one line
# per measurement; medians are for the reader.
#   A [../maxima-mt-baseline]  B [this tree]  ROUNDS [3]  OUT [logs/timing-ab.tsv]
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); WS=$(cd "$W/.." && pwd); L=$R/logs
A=${A:-$WS/maxima-mt-baseline}; B=${B:-$W}; ROUNDS=${ROUNDS:-3}
OUT=${OUT:-$L/timing-ab.tsv}
PATH="$here/stubbin:$PATH"; export PATH
busy() { ps -A -o %cpu | awk 'NR>1{s+=$1} END{printf "%.0f", s}'; }
b=$(busy); [ "$b" -ge 250 ] && { echo "machine busy: ${b}%"; exit 2; }
echo "machine check: ${b}% CPU in use"
printf 'round\ttree\tworkload\twall\n' > "$OUT"
wc10() {  # $1 tree
  cd "$1"
  timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (values))
batchload(\"$R/workloads/wc_pool.mac\")\$
wc_setup(10)\$
:lisp (let ((t0 (maxima::pool-now))) (dotimes (i \$wc_n_items) (maxima::pool-item '\$wc_item i)) (format t \"~&WALL=~,3F~%\" (maxima::pool-secs (- (maxima::pool-now) t0))))" 2>&1 | grep '^WALL=' | cut -d= -f2
}
core() {  # $1 tree
  cd "$1"
  timeout 3600 ./maxima-local --no-init --quiet --batch-string='run_testsuite();' 2>&1 | grep -o '[0-9.]* seconds of real time' | tail -1 | cut -d' ' -f1
}
r=0
while [ $r -le "$ROUNDS" ]; do
  for t in A B; do
    if [ $t = A ]; then tree=$A; else tree=$B; fi
    w=$(wc10 "$tree"); s=$(core "$tree")
    tag=$r; [ $r -eq 0 ] && tag="warmup"
    printf '%s\t%s\t%s\t%s\n' "$tag" "$t" wc10 "$w" >> "$OUT"
    printf '%s\t%s\t%s\t%s\n' "$tag" "$t" core "$s" >> "$OUT"
    echo "round $tag $t: wc10 ${w}s core ${s}s"
  done
  r=$((r+1))
done
echo "medians (timed rounds):"
awk -F'\t' 'NR>1 && $1!="warmup"{k=$2" "$3; v[k]=v[k]" "$4} END{for(k in v){n=split(v[k],a," "); asort(a); print "  "k": "a[int((n+1)/2)]"s  ("v[k]" )"}}' "$OUT" 2>/dev/null || \
python3 - "$OUT" <<'PY'
import sys,statistics,collections
d=collections.defaultdict(list)
for l in open(sys.argv[1]).read().splitlines()[1:]:
    r,t,w,v=l.split('\t')
    if r!='warmup': d[(t,w)].append(float(v))
for k in sorted(d): print("  %s %s: median %.2fs  %s" % (k[0],k[1],statistics.median(d[k]),d[k]))
PY
