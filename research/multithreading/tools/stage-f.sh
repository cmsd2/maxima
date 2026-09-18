#!/bin/sh
# Stage F: profile wc_systematic and the four mailing-list failure cases,
# one region per fresh session, then classify each (task 11.3).
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
region() {  # $1 label, $2 setup (Maxima, may be empty), $3 region body
  timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/oracle.lisp\") (values))
$2
:lisp (maxima::oracle-region-begin \"$1\" \"$L/region-$1.tsv\")
$3
?oracle\\-region\\-step()\$
:lisp (maxima::oracle-region-end)" > "$L/region-$1.log" 2>&1
  python3 "$here/region_report.py" "$L/region-$1.tsv" --churn "$R/oracle-churn.tsv" > "$R/results/region-$1.md"
  printf "%-14s %s\n" "$1" "$(grep '^\*\*Criterion' "$R/results/region-$1.md")"
}
region wc 'load("wrstcse")$ ratprint:false$ batchload("'"$R"'/workloads/wc_profiled.mac")$
assume(U_In>0)$
vals:[R_1=10e3*(1+.01*tol[1]), R_2=1e3*(1+.01*tol[2]), R_3=4.7e3*(1+.01*tol[3]), R_4=2.2e3*(1+.01*tol[4])]$
u_out:U_In*R_2/(R_1+R_2)*R_4/(R_3+R_4)$
wc_expr:subst(vals,u_out)$' 'res:wc_systematic_profiled(wc_expr)$'
region globals '' 'makelist((?oracle\-region\-step(), concat('"'"'v,i)::i), i, 1, 20)$'
region limits '' 'makelist((?oracle\-region\-step(), limit(abs(x-i)/(x-i), x, i)), i, 1, 20)$'
region newton '' 'makelist((?oracle\-region\-step(), block([x_n:float(N), x_next, i], for i:1 thru 20 do (x_next:0.5*(x_n+N/x_n), x_n:x_next), x_n)), N, 1, 20)$'
