#!/bin/sh
# Convert every run-time bypass site in src/$1, check it, and commit it.
set -u
here=$(cd "$(dirname "$0")" && pwd)
W=$(cd "$here/../../.." && pwd)
f=$1
cd "$W"
rows=$(python3 "$here/plist_scan.py" --tsv "src/$f" 2>/dev/null | awk -F'\t' '$3=="runtime"')
lines=$(echo "$rows" | cut -f2 | tr '\n' ' ')
funcs=$(echo "$rows" | cut -f5 | sed 's/^[a-z-]* //' | tr 'a-z' 'A-Z' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')
[ -n "$lines" ] || { echo "$f: nothing to convert"; exit 0; }
python3 "$here/convert_site.py" "src/$f" $lines
left=$(python3 "$here/plist_scan.py" --allowlist "$W/research/multithreading/plist-allowlist.tsv" --tsv "src/$f" 2>/dev/null | awk -F'\t' '$3=="runtime"' | wc -l | tr -d ' ')
qc=$("$here/quick-compile.sh" "$f")
echo "$qc" | head -1
echo "$qc" | grep -q "failure=NIL caught=0" || { echo "$f: COMPILE CHECK FAILED"; echo "$qc"; exit 1; }
[ "$left" = 0 ] || { echo "$f: $left sites remain"; exit 1; }
git add "src/$f"
git commit -q -F - <<MSG
$f: route $funcs plist writes through the funnel

Replace REMPROP with ZL-REMPROP, (SETF (GET ...)) with PUTPROP and
(SETF (SYMBOL-PLIST ...)) with REPLACE-SYMBOL-PLIST, so the environment
write hook observes these writes.  Return values are unchanged.

Per-file check: scanner clean, file compiles in the built image with no
warnings.  Suite and oracle checks run per batch.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
echo "$f: committed $(git log --oneline -1 | cut -c1-9)"
