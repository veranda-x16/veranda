#!/bin/bash
# The dock as a launcher's pictures (DECISIONS V163): the shell before
# (a git ref's, tests/sunroom_dock_script.py: four pins by the menu) and
# after (this tree's, tests/dock2_shot.py: eight pins dragged onto the
# dock), each with Veranda Write and Veranda Gemini put aside, on the
# plain desktop in light mode; the whole screen and the dock's rows.
#
#   tools/dock2_shots.sh <out folder> <APPS folder of a package> [<ref before, default main>]
#
# Out: before.png, after.png, before-dock.png, after-dock.png (rows
# 400-479, twice the size), and dock.png (the manual's picture: after's
# whole screen).
set -e
cd "$(dirname "$0")/.."
OUT=${1:?usage: tools/dock2_shots.sh <out folder> <APPS> [<ref>]}
APPS=${2:?usage: tools/dock2_shots.sh <out folder> <APPS> [<ref>]}
REF=${3:-main}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
mkdir -p "$OUT"
B=$(realpath "$OUT")/build
SDK=$B/sdk
mkdir -p "$B"
make -s api >/dev/null
make -s all >/dev/null
tools/mksdk.sh "$SDK" >/dev/null
for w in before after; do
	mkdir -p "$B/$w"
	find "$B/$w" -mindepth 1 -delete
done
git archive "$REF" shell | tar -x -C "$B/before"
cp -r shell "$B/after/"
for w in before after; do
	rm -f "$B/$w/shell/"*.cvt "$B/$w/shell/"shell.bin*
	make -s -C "$B/$w/shell" SDK="$SDK" >/dev/null 2>&1 || { echo "the shell ($w) does not build"; exit 1; }
done
mkdir -p "$B/fonts"
$PY tools/fontcvt.py testfonts "$B/fonts" >/dev/null
fake() {        # fake <name> <class> <n> [icon3]
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$3 -o "$B/fake$3.o" tests/switch_app.s
	ld65 -C "$SDK/cfg/app.cfg" -o "$B/fake$3.bin" "$B/fake$3.o"
	printf 'name = %s\nclass = %s\nmode = 640x480\napi = 6\nicon = %s\n' "$1" "$2" "$SDK/template/c/icon.pbm" > "$B/fake$3.hdr"
	[ -z "$4" ] || echo "icon3 = $(pwd)/$4" >> "$B/fake$3.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$B/$1.cvt" "$B/fake$3.hdr" "$B/fake$3.bin" >/dev/null
}
fake "Veranda Write" CmdrWrite 1
fake "Veranda Gemini" VerandaGemi 2 apps/gemini/icon.txt
PROGS=("Paint" "Veranda Calc" "Veranda Edit" "Veranda Claude" "Veranda Ask" "Solitaire" "MOD Player")
for w in before after; do
	R=$B/run-$w
	mkdir -p "$R"
	find "$R" -mindepth 1 -delete
	mkdir -p "$R/VERANDA/.SYSTEM" "$R/VERANDA/FONTS" "$R/DOCUMENTS"
	cp "$B/$w/shell/SHELL.cvt" "$R/VERANDA/"
	cp build/VERANDA.SYS build/VERANDA.PRG "$R/"
	cp "$B/fonts/Gate Sans.cvt" "$R/VERANDA/FONTS/"
	cp "$B/Veranda Write.cvt" "$B/Veranda Gemini.cvt" "$R/DOCUMENTS/"
	for p in "${PROGS[@]}"; do
		[ -f "$APPS/$p.cvt" ] && cp "$APPS/$p.cvt" "$R/DOCUMENTS/"
	done
	echo "Dear Ada, the garden is in bloom." > "$R/DOCUMENTS/Note.txt"
	if [ $w = before ]; then
		$PY tests/sunroom_dock_script.py "$R" "Veranda Gemini.cvt"
	else
		$PY tests/dock2_shot.py "$R"
	fi
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 400 "$EMU" -rom "$ROM" -ram 512 -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; echo "$w: no dump"; exit 1; }
	$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/$w.png" >/dev/null
	echo "$OUT/$w.png"
done
$PY - "$OUT" <<'EOF'
import sys
from PIL import Image
out = sys.argv[1]
for w in ('before', 'after'):
    a = Image.open('%s/%s.png' % (out, w)).convert('RGB')
    a.crop((0, 400, 640, 480)).resize((1280, 160), Image.NEAREST).save('%s/%s-dock.png' % (out, w))
Image.open('%s/after.png' % out).convert('RGB').save('%s/dock.png' % out)
EOF
echo "$OUT/before-dock.png $OUT/after-dock.png $OUT/dock.png"
