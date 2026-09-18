#!/bin/sh
# Bootstrap, configure (SBCL only) and build the Maxima tree given as $1,
# timing each step.  Output goes to $2 (a log file); step timings are
# appended to $2.times.
set -eu
tree=$1
log=$2
cd "$tree"
: > "$log"
: > "$log.times"
step() {
    name=$1; shift
    start=$(date +%s)
    echo "=== $name: $*" >> "$log"
    "$@" >> "$log" 2>&1
    end=$(date +%s)
    echo "$name $((end - start))s" >> "$log.times"
}
[ -x ./configure ] || step bootstrap sh bootstrap
step configure ./configure --enable-sbcl
step make make
echo "done" >> "$log.times"
