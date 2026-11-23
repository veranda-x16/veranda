#!/bin/bash
# Gate switch, part 3 (DECISIONS V163): the dock as a launcher
# (tests/dock2_script.py), run by tests/dock_gate.sh with its folder ($1:
# the SDK, the shell built there): drag to pin at a place, reorder, unpin
# by dragging off and onto the trash, one click starts, a full dock, the
# pins and their order kept over a restart (desk file version 4), a
# version 3 desk file's four pins, Preferences' Dock page, the defaults.
set -e
OUT=$1
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
A=$OUT/apps2
mkdir -p "$A"
[ -f "$OUT/shell/SHELL.cvt" ] || fail "no shell built ($OUT/shell)"

# PinA ... PinK: tests/shell_app.s (APP 1 RAN, back to the shell); Veranda
# Edit, Paint, Term: the same, by those names (the defaults)
ca65 --cpu 65C02 -I "$SDK/include" -D APPN=1 -o "$A/pin.o" tests/shell_app.s || fail "tests/shell_app.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/pin.bin" "$A/pin.o" || fail "tests/shell_app.s does not link"
for nm in PinA PinB PinC PinD PinE PinF PinG PinH PinI PinJ PinK "Veranda Edit" Paint Term; do
	printf 'name = %s\nclass = Test1\nmode = 640x480\napi = 1\nicon = %s\n' "$nm" "$SDK/template/c/icon.pbm" > "$A/pin.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/pin.hdr" "$A/pin.bin" >/dev/null || fail "vpack $nm"
done
# Preferences' test build: the Dock page (tests/dock2_script.py --prefs)
$PY tests/dock2_script.py --prefs "$TOP/$OUT/p" || fail "the Preferences script"
make -s -C apps/prefs SDK="$SDK" OUT="$TOP/$OUT/p/prefsdock" test TESTFLAGS="-I$TOP/$OUT/p/prefsdock" \
	>"$OUT/p/prefsdock.log" 2>&1 || { cat "$OUT/p/prefsdock.log"; fail "Preferences (its test build)"; }
ok "PinA ... PinK, Veranda Edit, Paint, Term (tests/shell_app.s) and Preferences' test build (the Dock page) built"

pins() { for c in "$@"; do cp "$A/Pin$c.cvt" "$D/"; done; }
run() {         # run <folder> [card]: the shell in the top folder; card: in /VERANDA (the card's layout)
	if [ "$2" = card ]; then
		cp "$OUT/shell/SHELL.cvt" "$1/VERANDA/"
		cp build/VERANDA.SYS build/VERANDA.PRG "$1/"
	else
		cp "$OUT/shell/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$1/"
	fi
	rm -f "$1/dump.bin"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 400 "$EMU" -rom "$ROM" -ram 512 -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -20 "$1/console.txt"; fail "$1: the session did not end"; }
}
order() {       # order <folder> <run>: the lines expected, in their order, among the console's
	$PY - "$1/console.txt" "$2" <<-'EOF' || fail "$2: the console's lines ($1/console.txt)"
	import subprocess, sys
	got = [l.strip() for l in open(sys.argv[1], 'rb').read().decode('latin-1').replace('\r', '').split('\n')]
	want = subprocess.run(['python3', '-I', '-B', 'tests/dock2_script.py', '--want', sys.argv[2]],
	                      capture_output=True, text=True).stdout.split('\n')[:-1]
	i = 0
	for w in want:
	    while i < len(got) and not got[i].endswith(w):      # (a line may follow a CD: without its end)
	        i += 1
	    if i == len(got):
	        print('missing, in this order:', w)
	        sys.exit(1)
	    i += 1
	EOF
}
mk() { rm -rf "$1"; mkdir -p "$1"; D=$1; }
on() { [ -z "$DOCK2_ONLY" ] || [[ " $DOCK2_ONLY " == *" $1 "* ]]; }   # DOCK2_ONLY="prefs defaults": those runs alone

# 1. drag to pin, reorder, unpin by dragging off and onto the trash, a
#    pinned program dropped again moves; a click starts; a restart
if on drag; then
mk "$OUT/dock2-drag"
pins A B C D
$PY tests/dock2_script.py --dsk "$D/SHELL.DSK" 4 / || fail "the desk file"
cp "$OUT/shell/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$D/"
$PY tests/dock2_script.py "$D" drag || fail "the script (drag)"
run "$D"
order "$D" drag
$PY - "$D/SHELL.DSK" <<-'EOF' || fail "drag: SHELL.DSK"
	import sys
	b = open(sys.argv[1], 'rb').read()
	assert b[:4] == b'VSD\x04', b[:4]
	n = b[78]
	names = [b[79 + i * 130 + 62:79 + i * 130 + 130].split(b'\0')[0].decode() for i in range(n)]
	assert names == ['PinD.cvt', 'PinC.cvt'], names
	assert len(b) == 79 + n * 130, len(b)
	EOF
for c in A B C D; do [ -f "$D/Pin$c.cvt" ] || fail "drag: Pin$c.cvt is gone (unpinning deletes nothing)"; done
ok "drag: PinB dropped left of PinA, PinC right of the pins, PinC dragged to the front, PinB off the dock, PinA onto its trash (unpinned, the files kept), PinD and PinC (pinned already: moved) dropped at the end"
ok "drag: a restart: the dock PinD, PinC (SHELL.DSK version 4, in that order); one click on PinC started it"
fi

# 2. a full dock: ten pins, an eleventh refused
if on full; then
mk "$OUT/dock2-full"
pins A B C D E F G H I J K
$PY tests/dock2_script.py --dsk "$D/SHELL.DSK" 4 / PinA PinB PinC PinD PinE PinF PinG PinH PinI PinJ || fail "the desk file"
cp "$OUT/shell/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$D/"
$PY tests/dock2_script.py "$D" full || fail "the script (full)"
run "$D"
order "$D" full
grep -a -q "SHELL PINNED PinK" "$D/console.txt" && fail "full: PinK was pinned"
$PY tools/vram2png.py --color "$D/dump.bin" "$OUT/dock2-full.png" >/dev/null || fail "vram2png"
ok "full: ten pins (a version 4 desk file) in the dock; PinK dropped on it: \"The dock is full\" (SHELL DOCK FULL), not pinned: $OUT/dock2-full.png"
fi

# 3. a version 3 desk file (before V163): its four pins
if on old; then
mk "$OUT/dock2-old"
pins A B C D
$PY tests/dock2_script.py --dsk "$D/SHELL.DSK" 3 / PinA PinB PinC PinD || fail "the desk file"
cp "$OUT/shell/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$D/"
$PY tests/dock2_script.py "$D" old || fail "the script (old)"
run "$D"
order "$D" old
ok "old: a version 3 desk file's four pins in the dock"
fi

# 4. Preferences' Dock page: Add..., Move up, Save; the dock when it
#    closes, and after a restart
if on prefs; then
mk "$OUT/dock2-prefs"                   # (the card's layout: the shell in /VERANDA, starting in /DOCUMENTS)
mkdir -p "$D/VERANDA/APPS" "$D/VERANDA/.SYSTEM" "$D/DOCUMENTS"
cp "$A/PinA.cvt" "$A/PinB.cvt" "$OUT/p/prefsdock/Preferences.cvt" "$D/DOCUMENTS/"
cp "$A/PinK.cvt" "$D/VERANDA/APPS/"
$PY tests/dock2_script.py --dsk "$D/VERANDA/.SYSTEM/SHELL.DSK" 4 /DOCUMENTS PinA PinB || fail "the desk file"
$PY tests/dock2_script.py "$D" prefs || fail "the script (prefs)"
run "$D" card
order "$D" prefs
ok "prefs: the Dock page listed PinA, PinB; Add... PinK (/VERANDA/APPS), Move up, Save; the dock PinA, PinK, PinB when it closed, and after a restart"
fi

# 5. the defaults: nothing ever pinned
if on defaults; then
mk "$OUT/dock2-def"
mkdir -p "$D/VERANDA/APPS"
cp "$A/Veranda Edit.cvt" "$A/Paint.cvt" "$A/Term.cvt" "$D/VERANDA/APPS/"
: > "$D/PINS.DEF"
$PY tests/dock2_script.py "$D" defaults || fail "the script (defaults)"
run "$D" card
order "$D" defaults
$PY tools/vram2png.py --color "$D/dump.bin" "$OUT/dock2-defaults.png" >/dev/null || fail "vram2png"
ok "defaults: no desk file: Veranda Edit, Paint and Term (those of the defaults in /VERANDA/APPS) pinned: $OUT/dock2-defaults.png"
fi
