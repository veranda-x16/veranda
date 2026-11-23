#!/bin/bash
# Gate cpaint (DECISIONS V167): Colour Paint (apps/cpaint), a picture of
# 320 x 240 pixels of any of 256 colours in the kernel's canvas mode.
#
#   tools/gate_cpaint.sh
#
# 1. the kernel, the SDK installed; apps/cpaint built against it (its CVT
#    an application: class ColourPaint, 320x240, VRND, overlays banked)
#    and its test build (CP_TEST: tests/cpaint_play.c, tests/sdk_play.s,
#    the script tests/cpaint_script.h, which tests/cpaint_script.py
#    writes); Oldpic.cvt, a black and white picture of Paint's
#    (tests/check_cpaint.py oldpic: 29 PackBits bands of 74 x 16)
# 2. the session (AUTOSTART.cvt): colour A from the popup; pencil, line,
#    rectangle, colour B, filled rectangle, oval, filled oval, a fill
#    inside and one of the background (the seed stack overflows), the
#    eraser, the eyedropper and a stroke, undo, scrolled 40 right and 14
#    down and a stroke; save as Colours, new, open Colours, open Oldpic;
#    View > Whole picture and back
# 3. tests/check_cpaint.py run: each step's picture (STEPn.PIC, from the
#    banks) equal to the Python reference byte for byte (the fill exactly);
#    Colours.cvt decoded equal to the picture saved, opened again the
#    same bytes; Oldpic at half size; the view in the dump the picture
#    from (40, 16); the TIME lines (frame timings)
# 4. screenshots at 2x (vram2png --color --scale 2): popup, tools,
#    colours (the popup over the colours), opened (Colours again), whole,
#    end
# 5. (V177) the desktop's mode after Colour Paint: a test desktop of mode
#    "keep" at 640 x 480 and at 640 x 240 starts it; it puts itself aside
#    and comes back, then quits: the desktop in its own mode each time
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/cpaint
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
$PY tests/cpaint_script.py "$OUT/cpaint_script.h" && cmp -s "$OUT/cpaint_script.h" tests/cpaint_script.h \
	|| fail "tests/cpaint_script.h is not what tests/cpaint_script.py writes"
shot() { sed -n "s|^/\* shot $1 \([0-9]*\) \*/|\1|p" tests/cpaint_script.h; }
# (V170) the column's art: apps/cpaint/art.s and art.h are what mkart.py writes
$PY apps/cpaint/mkart.py --check || fail "apps/cpaint/mkart.py"
$PY apps/cpaint/mkart.py --png "$OUT/column.png" >/dev/null || fail "mkart.py --png"

mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/cpaint SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Colour Paint does not build"; }
A=$OUT/app/ColourPaint.cvt
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" class)" = 'ColourPaint V1.0' ] \
	&& [ "$(field "$A" mode)" = 320x240 ] && [ "$(field "$A" veranda)" = True ] || fail "ColourPaint.cvt: type, class, mode"
# (V173) its colour icon (tools/mkicons3.py writes apps/cpaint/icon.txt) and
# its pictures' icons in the shell's libraries, by their class
case "$(field "$A" icon3)" in "16 tiles,"*) ;; *) fail "ColourPaint.cvt: no colour icon (icon.txt)" ;; esac
grep -q '^for class PaintColour$' shell/icons3.txt && grep -q '^for class PaintColour$' shell/icons3s.txt \
	&& grep -q '^for class ColourPaint$' shell/icons3s.txt || fail "the shell's icon libraries: no PaintColour or ColourPaint icon"
end=$(sed -n 's/^BSS *[0-9A-F]* *\([0-9A-F]*\).*/\1/p' "$OUT/app/cpaint.map" | head -1)
ovl=$(sed -n 's/^OVL1RO *[0-9A-F]* *\([0-9A-F]*\).*/\1/p' "$OUT/app/cpaint.map" | head -1)
ok "Colour Paint builds: main RAM \$0801-\$${end#00} (the C stack below \$8800 from \$8400), overlay 1 (the Open and Save dialog) to \$${ovl#00}"

make -s -C apps/cpaint test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "Colour Paint's test build"; }
O=$OUT/old
mkdir -p "$O"
$PY tests/check_cpaint.py oldpic "$O" || fail "check_cpaint.py oldpic"
printf 'name = Oldpic\nclass = Paint Image\nversion = 1.0\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$O/old.hdr"
# shellcheck disable=SC2046
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$O/Oldpic.cvt" "$O/old.hdr" "$O/rec0.bin" \
	$(for b in $(seq 1 29); do echo "$O/rec$b.bin"; done) >/dev/null || fail "vpack Oldpic"

# run <dir> <cvt> <seconds>
run() {
	mkdir -p "$1"
	cp "$2" "$1/AUTOSTART.cvt"
	cp "$O/Oldpic.cvt" "$1/"
	cp build/VERANDA.PRG build/VERANDA.SYS "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
R=$OUT/run
run "$R" "$OUT/test/ColourPaint.cvt" 400
[ -f "$R/dump.bin" ] || { tr -d '\r' < "$R/console.txt" | grep -a "CPAINT\|PANIC" | tail -10; fail "the session did not end"; }
echo "== the session"
$PY tests/check_cpaint.py run "$R" || { tr -d '\r' < "$R/console.txt" | grep -a "CPAINT\|PANIC\|TIME" | tail -30; fail "the session"; }
$PY tools/vram2png.py --color --scale 2 "$R/dump.bin" "$OUT/end.png" 320 240 || fail "vram2png"

# the screenshots: the session stopped there
for s in popup tools colours pasted palette opened whole; do
	T=$OUT/shot-$s
	mkdir -p "$T/b"
	make -s -C apps/cpaint test SDK="$SDK" OUT="$TOP/$T/b" TESTFLAGS=-DCP_STOP="$(shot $s)" >"$T/build.log" 2>&1 \
		|| { cat "$T/build.log"; fail "the $s shot's build"; }
	run "$T" "$T/b/ColourPaint.cvt" 300
	[ -f "$T/dump.bin" ] || fail "the $s shot: no dump"
	$PY tools/vram2png.py --color --scale 2 "$T/dump.bin" "$OUT/$s.png" 320 240 || fail "vram2png ($s)"
done
ok "screenshots: $OUT/popup.png, tools.png, colours.png, pasted.png, palette.png, opened.png, whole.png, end.png"

# ---------------------------------------------------------------- 5. the desktop's mode (V177)
# Colour Paint (CP_DESK: it puts itself aside, comes back, quits) started
# by gate canvas's test desktop (tests/canvas_desk.c, mode "keep" as the
# shell's, -D ANYTASK), the settings' mode "as it is": the desktop at
# 640 x 480, and one that sets 640 x 240 itself; at each of its starts
# (after Alt + Tab, after Colour Paint quit) the mode it had
D=$OUT/desk
mkdir -p "$D/b"
make -s -C apps/cpaint all SDK="$SDK" OUT="$TOP/$D/b" CFLAGS=-DCP_DESK >"$D/build.log" 2>&1 \
	|| { cat "$D/build.log"; fail "Colour Paint's CP_DESK build"; }
CC="cl65 -t none --cpu 65C02 -O -I $SDK/include -I tests --asm-include-dir $SDK/include"
for m in 480 240; do
	def=-DANYTASK
	[ $m = 240 ] && def="$def -DDESKMODE=1"
	# shellcheck disable=SC2086
	$CC $def -C "$SDK/cfg/app-c.cfg" -o "$D/desk$m.bin" tests/canvas_desk.c "$SDK/lib/veranda.lib" >"$D/desk$m.log" 2>&1 \
		|| { cat "$D/desk$m.log"; fail "the test desktop"; }
	printf 'name = SHELL\nclass = CanvDesk\nmode = keep\napi = 7\nicon = %s\n' "$SDK/template/c/icon.pbm" >"$D/desk.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$D/SHELL$m.cvt" "$D/desk.hdr" "$D/desk$m.bin" >/dev/null || fail "vpack the desktop"
	R=$D/run$m
	mkdir -p "$R/VERANDA/.SYSTEM"
	cp "$D/b/ColourPaint.cvt" "$R/VERANDA/CanvApp.cvt"
	cp "$D/SHELL$m.cvt" "$R/VERANDA/SHELL.cvt"
	$PY -c 'import sys; d=bytearray(open("tests/sound_prefs_v65.cvt","rb").read()); d[508+6] = (d[508+6] & ~0x30) | 16; d[508+7] = 0xFF; open(sys.argv[1],"wb").write(d)' "$R/VERANDA/Veranda Prefs.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	con=$(tr -d '\r' < "$R/console.txt" | grep -a "CANVD\|CPAINT ASIDE\|CPAINT BACK\|CPAINT QUIT\|PANIC")
	want=$([ $m = 240 ] && echo 1 || echo 0)
	m0=$(echo "$con" | sed -n 's/^CANVD 0 FREE [0-9]* OF [0-9]* MODE \([0-9]\)$/\1/p')
	[ $m = 240 ] && m0=$(echo "$con" | sed -n 's/^CANVD SET \([0-9]\)$/\1/p')
	m1=$(echo "$con" | sed -n 's/^CANVD 1 FREE [0-9]* OF [0-9]* MODE \([0-9]\)$/\1/p')
	m2=$(echo "$con" | sed -n 's/^CANVD 2 FREE [0-9]* OF [0-9]* MODE \([0-9]\)$/\1/p')
	echo "$con" | grep -q "CPAINT BACK" && echo "$con" | grep -q "CPAINT QUIT" && echo "$con" | grep -q "CANVD DONE" \
		|| { echo "$con"; fail "the 640 x $m desktop: Colour Paint not aside, back and quit"; }
	[ "$m0" = "$want" ] && [ "$m1" = "$want" ] && [ "$m2" = "$want" ] \
		|| { echo "$con"; fail "the 640 x $m desktop came back in mode $m1 after Alt + Tab, $m2 after Colour Paint quit (it was in $m0)"; }
done
ok "the desktop (mode keep, the settings' none) back at 640 x 480 and at 640 x 240 after Colour Paint was put aside and came back, and after it quit"
echo "GATE cpaint: PASS"
