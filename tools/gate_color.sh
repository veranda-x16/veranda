#!/bin/bash
# Gate color (docs/PLAN.md phase 9, 5.1: the colour map): ColorRect gives
# 8 x 8 cards a paper colour from a tile layer under the bitmap.
#
#   tools/gate_color.sh
#
# 1. tests/color.s as TEST.PRG: a picture, the whole screen coloured
#    (timed) and cleared, then eight areas (overlapping, clipped, one off
#    the screen, two back to 0); the VRAM dump
# 2. tests/check_color.py: tools/check_vera.py accepts the display (layer
#    1 the bitmap, layer 0 the map); the map's entries are the areas';
#    the picture composed as VERA shows it (tools/vram2png.py --color) has
#    each card's paper in its colour and the ink in palette entry 1
# 3. the same with ColorRect $FF at the end (-D OFF), and with
#    SetVideoMode at the end (-D MODE): the plain display again
# 4. menus and dialog boxes in the normal colours (DECISIONS V33): a menu
#    and a dialog box opened and closed over the areas (timed), the map
#    exactly back (1.); the test ended with the menu open (-D MENU) and
#    with the dialog box open (-D DLG): the cards under it 0, their
#    colours kept, black on white in the composed picture
# Pictures: build/gate/color/color.png (composed), off.png, mode.png,
# menu.png, dlg.png.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/color
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
for k in on off mode menu dlg; do
	T=$OUT/$k
	mkdir -p "$T"
	def=
	[ $k = off ] && def="-D OFF"
	[ $k = mode ] && def="-D MODE"
	[ $k = menu ] && def="-D MENU"
	[ $k = dlg ] && def="-D DLG"
	ca65 --cpu 65C02 -I build/gen -I inc $def tests/color.s -o "$T/color.o" || fail "tests/color.s does not assemble"
	ca65 tests/prghdr.s -o "$T/prghdr.o"
	ld65 -C cfg/testprg.cfg "$T/prghdr.o" "$T/color.o" -o "$T/TEST.PRG" || fail "tests/color.s does not link"
	cp build/VERANDA.PRG build/VERANDA.SYS "$T/"
	(cd "$T" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$T/dump.bin" ] || { tail -20 "$T/console.txt"; fail "the test did not finish ($k)"; }
	echo "== $k"
	$PY tools/check_vera.py "$T/dump.bin" || fail "check_vera ($k)"
	png=$OUT/$k.png
	[ $k = on ] && png=$OUT/color.png
	$PY tests/check_color.py "$T" "$png" $k || fail "the colour map ($k)"
done
echo "pictures: $OUT/color.png (as VERA composes it), off.png, mode.png, menu.png (a menu open), dlg.png (a dialog box)"
echo "GATE color: PASS"
