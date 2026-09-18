#!/bin/sh
# Profile three fixed workloads three times each in fresh sessions and
# check the aggregated profiles are identical (task 8.2).
set -u
here=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$here/../../.." && pwd)
L=$here/../logs
PATH="$here/stubbin:$PATH"; export PATH
cd "$W"
prof() {  # $1 = label, $2 = maxima batch body
  timeout 900 ./maxima-local --no-init --quiet --batch-string=":lisp (progn (load \"$here/profile.lisp\") (values))
$2" 2>&1 | grep '^PROFILE'
}
fail=0
for w in suite rat integrate; do
  for i in 1 2 3; do
    case $w in
      suite) prof $w ':lisp (maxima::envprofile-region-begin)
run_testsuite(tests=["rtest1","rtest_sign","rtest_rules","rtest_limit"])$
:lisp (progn (maxima::envprofile-region-end) (maxima::envprofile-print 1))' ;;
      rat) prof $w ':lisp (maxima::envprofile "for i thru 40 do ratdisrep(rat((x+y+z)^i));")' ;;
      integrate) prof $w ':lisp (maxima::envprofile "for i thru 8 do integrate(x^i*exp(a*x), x);")' ;;
    esac > "$L/profile-$w-$i.txt"
  done
  if cmp -s "$L/profile-$w-1.txt" "$L/profile-$w-2.txt" && cmp -s "$L/profile-$w-1.txt" "$L/profile-$w-3.txt"; then
    echo "$w: identical across 3 sessions ($(head -1 "$L/profile-$w-1.txt" | cut -d' ' -f2-))"
  else
    echo "$w: PROFILES DIFFER"; diff "$L/profile-$w-1.txt" "$L/profile-$w-2.txt" | head -10; fail=1
  fi
done
exit $fail
