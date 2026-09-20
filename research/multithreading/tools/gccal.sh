#!/bin/sh
# Calibration run for the GC spike allocator (task 1.3).
#   ARGS  [""] -- empty uses the calibrated defaults in gcspike.lisp
#   ITERS [1000000]  LABEL [cal]  OUT [logs/gccal.jsonl]
set -u
here=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$here/.." && pwd); W=$(cd "$R/../.." && pwd); L=$R/logs
ITERS=${ITERS:-1000000}
ARGS=${ARGS:-""}
LABEL=${LABEL:-cal}; OUT=${OUT:-$L/gccal.jsonl}
mkdir -p "$L"
cd "$W"
timeout 1800 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/pool.lisp\") (load \"$here/gcspike.lisp\") (maxima::gcspike-calibrate $ITERS $ARGS :record-path \"$OUT\" :label \"$LABEL\"))" \
  > "$L/gccal-last.log" 2>&1
grep -q "Maxima encountered a Lisp error" "$L/gccal-last.log" && {
  echo "LISP ERROR, see $L/gccal-last.log"; exit 1; }
grep -E "^$LABEL:" "$L/gccal-last.log" || { sed -n '1,40p' "$L/gccal-last.log"; exit 1; }
