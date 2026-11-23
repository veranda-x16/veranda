#!/bin/bash
# Gate paint (docs/PLAN.md phase 7): Paint, a C application at 640x480;
# a scripted session draws, saves, clears, opens the picture again, and
# the picture is equal.
#
#   tools/gate_paint.sh          (PAINT_SD=0: skip the SD card run)
#
# 1. make api, the kernel, the SDK installed into build/gate/paint/sdk;
#    apps/paint built against the installed SDK; its CVT an application
#    (class Paint, $0801, VRND, 640x480, below $8800); it starts through
#    the loader (AUTOSTART.cvt) and logs "PAINT RUNNING"
# 2. the test build (PAINT_TEST: tests/paint_play.c, tests/sdk_play.s, the
#    script tests/paint_script.h): file/open, the SDK's Open dialog
#    (vrchoose, V79, V82), cancelled with Esc (the test build then saves
#    the empty documents Draft 1-5 and Zebra); pencil strokes, two
#    lines, a rectangle, filled rectangles in three patterns, text, the
#    eraser; file/save as "Picture" (the drawing area's rows written to
#    SAVED.RAW when the save starts), file/new (CLEAR.RAW), two lines saved
#    as "Sketch" (SAVED2.RAW), file/new; file/open: 's' selects Sketch,
#    Return (OPENED.RAW); Zebra ('z'); Picture ('p', OPENED2.RAW);
#    file/export: the name typed over, "Print" (Print.bmp, ExportRect
#    from the back screen); long names (DECISIONS V82): save as, the
#    field's "Picture" deleted, "Holiday sketch from the lake shore 2026"
#    typed (SAVED3.RAW), file/new, file/open, 'h', Return (OPENED3.RAW);
#    VRAM at the end
# 3. tests/check_paint.py: the picture at the save equals the drawing area
#    at the end; new cleared it; Picture.cvt on the host is a VLIR
#    APPL_DATA document of class "Paint Image V1.0" with Paint as its
#    parent, whose 29 bands unpack to the same picture; each file/open
#    gave the picture chosen; Print.bmp is a 1 bpp BMP equal to the
#    drawing area in the dump (tests/check_export.py)
# 4. screenshots during the session (the script's "shot" frames): a drag
#    (the rubber band on the foreground only), the save dialog, the open
#    dialog (Draft 1 selected; scrolled, Sketch selected: the rows checked,
#    tools/check_vera.py on the dump)
# 5. the same session on an SD card image (tools/vcard.py), with the
#    default ROM and with R49 (the user's X16; the long name's Save and
#    Open dialogs as screenshots: savelong-r49.png, openlong-r49.png)
# 6. the ink (DECISIONS V33; tests/ink_script.h, the test build with
#    PAINT_INK): a picture in two colours, the options menu and
#    options/about's box opened over it (screenshots: black on white under
#    them, the colours back after); options/ink colour (red), saved as
#    Inked, file/new, opened again: the ink red in the palette and in the
#    composed display; file/export: Inked.bmp's palette has it
#    (tests/check_ink.py)
# Screenshots in build/gate/paint: screen.png (the end), picture.png (the
# picture saved), band.png, dialog.png, files.png, opendlg.png.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/paint
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
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)

# the Sunroom column's art (DECISIONS V147): apps/paint/art.s and art.h
# are what apps/paint/mkart.py writes
$PY apps/paint/mkart.py --check || fail "apps/paint/mkart.py"

# the application, against the installed SDK
mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/paint SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Paint does not build"; }
A=$OUT/app/Paint.cvt
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" class)" = 'Paint       V1.0' ] || fail "Paint.cvt: type or class"
[ "$(field "$A" load)" = '$0801' ] && [ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] \
	|| fail "Paint.cvt: load address, VRND or mode"
end=$(field "$A" end)
[ $((16#${end#\$})) -le $((16#8000)) ] || fail "Paint.cvt ends at $end (the C stack is at \$8000)"
ok "Paint builds against the installed SDK: an application, class Paint, \$0801-$end, VRND, 640x480"

# run a CVT as AUTOSTART.cvt in folder $2 for at most $3 seconds; dump VRAM
run() {
	mkdir -p "$2"
	cp "$1" "$2/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
	(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
run "$A" "$OUT/app/run" 15
grep -q "PAINT RUNNING" "$OUT/app/run/console.txt" || { tail -3 "$OUT/app/run/console.txt"; fail "Paint does not start"; }
ok "Paint starts through the loader (AUTOSTART.cvt)"

# the scripted session (tests/paint_script.h is tests/paint_script.py's)
$PY tests/paint_script.py "$OUT/script.h" && cmp -s "$OUT/script.h" tests/paint_script.h \
	|| fail "tests/paint_script.h is not what tests/paint_script.py writes"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
R=$OUT/test/run
run "$OUT/test/Paint.cvt" "$R" 120
[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "the session did not finish"; }
$PY tools/vram2png.py "$R/dump.bin" "$OUT/screen.png" 2>/dev/null || true
$PY tools/check_vera.py "$R/dump.bin" || fail "the display does not show the bitmap"
echo "== the session on the host folder"
$PY tests/check_paint.py "$R" "$OUT" || fail "the session (host folder)"
$PY "$SDK/tools/vpack.py" --list "$R/Picture.cvt" | grep -q "^records" || fail "vpack --list does not read Picture.cvt"

# screenshots on the way ("/* shot NAME FRAME */" in the script): the
# session stopped there; during a drag the rubber band is on the
# foreground only
sed -n 's|^/\* shot \([a-z]*\) \([0-9]*\) \*/|\1 \2|p' tests/paint_script.h | while read -r name frame; do
	T=$OUT/shot-$name
	mkdir -p "$T"
	make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS=-DPAINT_STOP=$frame >"$T/build.log" 2>&1 \
		|| { cat "$T/build.log"; fail "the test build (stopped at $frame)"; }
	run "$T/Paint.cvt" "$T/run" 30
	[ -f "$T/run/dump.bin" ] || fail "no dump at frame $frame"
	$PY tools/vram2png.py "$T/run/dump.bin" "$OUT/$name.png" 2>/dev/null || true
	case $name in
	band) $PY tests/check_paint.py --band "$T/run/dump.bin" 380 240 560 400 || fail "the rubber band" ;;
	dialog|files|opendlg|savelong|openlong)
		$PY tools/check_vera.py "$T/run/dump.bin" || fail "$name: the display does not show the bitmap"
		$PY tests/check_paint.py --dialog "$T/run/dump.bin" "$T/run/console.txt" || fail "$name: the dialog" ;;
	esac
done

# the ink session (host folder)
$PY tests/ink_script.py "$OUT/ink.h" && cmp -s "$OUT/ink.h" tests/ink_script.h \
	|| fail "tests/ink_script.h is not what tests/ink_script.py writes"
I=$OUT/ink
mkdir -p "$I"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$I" TESTFLAGS=-DPAINT_INK >"$I/build.log" 2>&1 \
	|| { cat "$I/build.log"; fail "the ink session's test build"; }
run "$I/Paint.cvt" "$I/run" 60
[ -f "$I/run/dump.bin" ] || { tail -5 "$I/run/console.txt"; fail "the ink session did not finish"; }
for name in inkmenu inkdlg; do
	frame=$(sed -n "s|^/\* shot $name \([0-9]*\) \*/|\1|p" tests/ink_script.h)
	T=$I/shot-$name
	mkdir -p "$T"
	make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS="-DPAINT_INK -DPAINT_STOP=$frame" >"$T/build.log" 2>&1 \
		|| { cat "$T/build.log"; fail "the ink session's test build (stopped at $frame)"; }
	run "$T/Paint.cvt" "$T/run" 30
	[ -f "$T/run/dump.bin" ] || fail "no dump at frame $frame (ink session)"
	$PY tools/check_vera.py "$T/run/dump.bin" || fail "$name: the display"
done
echo "== the ink session"
$PY tests/check_ink.py "$I/run" "$I/shot-inkmenu/run/dump.bin" "$I/shot-inkdlg/run/dump.bin" "$OUT" \
	|| fail "the ink session"

# the same on an SD card image: the system, the application and the files
# it writes on the card, copied out afterwards
if [ "${PAINT_SD:-1}" != 0 ]; then
	# a CVT ($2) as AUTOSTART.cvt on a card image in $1 under ROM $3, $4
	# seconds at most; the console, the dump and every file into $1/out
	sdrun() {
		mkdir -p "$1/card" "$1/out"
		cp "$2" "$1/card/AUTOSTART.cvt"
		cp build/VERANDA.SYS "$1/card/"
		$PY tools/vcard.py make --mb 64 "$1/sd.img" "$1/card" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$1/"
		(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$4" "$EMU" -rom "$3" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
		[ -f "$1/dump.bin" ] || { tail -5 "$1/out/console.txt"; fail "SD card ($3): the session did not finish"; }
		mv "$1/dump.bin" "$1/out/"
		$PY tools/vcard.py ls "$1/sd.img" | while read -r line; do
			f=$(echo "$line" | sed 's/ *[0-9]*$//')         # (names may have spaces)
			case "$f" in */|AUTOSTART.cvt|VERANDA.SYS) continue ;; esac
			$PY tools/vcard.py get "$1/sd.img" "$f" "$1/out/$f" >/dev/null || fail "SD card: $f"
		done
	}
	sdcheck() {
		for f in Picture.cvt Print.bmp Sketch.cvt Zebra.cvt SAVED.RAW SAVED2.RAW SAVED3.RAW CLEAR.RAW OPENED.RAW \
			OPENED2.RAW OPENED3.RAW OLD.RAW "Holiday sketch from the lake shore 2026.cvt" \
			"Draft 1.cvt" "Draft 2.cvt" "Draft 3.cvt" "Draft 4.cvt" "Draft 5.cvt"; do
			[ -f "$1/out/$f" ] || fail "SD card: no $f"
		done
		mkdir -p "$1/png"
		$PY tests/check_paint.py "$1/out" "$1/png" || fail "the session (SD card: $1)"
	}
	S=$OUT/sd
	sdrun "$S" "$OUT/test/Paint.cvt" "$ROM" 150
	echo "== the same on an SD card image"
	sdcheck "$S"
	# (DECISIONS V82) and under R49, the ROM of the user's X16: the session,
	# the long name's save and open, the dialogs' screenshots
	R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
	if [ -f "$R49" ]; then
		S=$OUT/sd49
		sdrun "$S" "$OUT/test/Paint.cvt" "$R49" 150
		echo "== the same on an SD card image under R49"
		sdcheck "$S"
		for name in savelong openlong; do
			frame=$(sed -n "s|^/\* shot $name \([0-9]*\) \*/|\1|p" tests/paint_script.h)
			T=$OUT/shot49-$name
			mkdir -p "$T"
			make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS=-DPAINT_STOP=$frame >"$T.log" 2>&1 \
				|| { cat "$T.log"; fail "the test build (stopped at $frame)"; }
			sdrun "$T/sd" "$T/Paint.cvt" "$R49" 150
			$PY tools/vram2png.py "$T/sd/out/dump.bin" "$OUT/$name-r49.png" 2>/dev/null || true
			$PY tests/check_paint.py --dialog "$T/sd/out/dump.bin" "$T/sd/out/console.txt" \
				|| fail "R49: $name: the dialog"
		done
		ok "R49 screenshots: $OUT/savelong-r49.png (Save as, the long name typed), $OUT/openlong-r49.png (Open, it selected)"
	fi
fi
echo "colour: $OUT/colour.png (the end as VERA composes it, the colour map under the bitmap)"
echo "ink:    $OUT/inkmenu.png (a menu over the colours), inkdlg.png (a dialog box), ink.png (the red ink; composed)"
echo "screenshots: $OUT/screen.png (the end), picture.png (the picture saved), band.png (a drag), dialog.png (save as),"
echo "             files.png (file/open), opendlg.png (file/open: Sketch selected), savelong.png, openlong.png (V82)"
echo "GATE paint: PASS"
