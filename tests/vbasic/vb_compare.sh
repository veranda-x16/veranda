#!/bin/bash
# A session's log against the reference's (gate vb_files): the reference
# runs each program of the session in a folder of its own, made as the
# session's was (PROG.dir copied in), and its files must equal Run's.
#
#   tests/vbasic/vb_compare.sh DIR PROG.bas ...      (R49: the ROM image)
# prints the differences; exit 1 when there are any.
cd "$(dirname "$0")/../.."
D=$1; shift
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
bad=0
rm -rf "$D/ref"
cp -r "$D/init" "$D/ref"
for p in "$@"; do
	n=$(basename "$p" .bas)
	b=$(dirname "$p")/$n
	awk -v n="VB RUN $n" '$0 == n { on = 1; next } /^VB RUN / { on = 0 } on' "$D/x16.log" > "$D/$n.log"
	grep -v '^VB RUN\|^VB BANKS\|^VB GC\|^VB DONE\|^VB TEST\|^VB ASIDE\|^VB CTRL' "$D/$n.log" > "$D/$n.x16"
	keys=()
	[ -f "$b.key" ] && keys=(--input "$b.key")
	$PY tools/vbasic.py run --rom "$R49" --log --replay "$D/$n.log" --dir "$D/ref" "${keys[@]}" "$p" > "$D/$n.ref" 2>&1
	if ! cmp -s "$D/$n.x16" "$D/$n.ref"; then
		echo "== $n: Run and the reference differ"
		diff "$D/$n.x16" "$D/$n.ref" | head -20
		bad=1
	fi
done
exit $bad
