#!/bin/sh
# Run the Maxima test suite in tree $1, writing the log to $2 and the wall
# time in seconds to $2.time.  $3 selects the suite: "full" (core + share,
# as make check) or "core".
set -eu
tree=$1
log=$2
which=${3:-full}
case $which in
    full) call='run_testsuite(share_tests=true);' ;;
    core) call='run_testsuite();' ;;
    *) echo "unknown suite $which" >&2; exit 2 ;;
esac
# Put the stand-in gnuplot first so plot tests never open windows.
PATH="$(cd "$(dirname "$0")" && pwd)/stubbin:$PATH"
export PATH
cd "$tree"
start=$(date +%s)
timeout 7200 ./maxima-local --no-init --quiet --batch-string="$call" > "$log" 2>&1 || true
end=$(date +%s)
echo $((end - start)) > "$log.time"
