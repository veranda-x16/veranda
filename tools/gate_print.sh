#!/bin/bash
# Gate print (docs/DECISIONS.md V38): printing to a PDF file.
#
#   tools/gate_print.sh          (PRINT_SD=0: skip the SD card run)
#
# 1. tests/print.s as TEST.PRG: PrintBand and PrintClose with no
#    document; BANDS.PDF (A4, 300 dpi): page 1, 3,508 rows of a test
#    pattern in bands of 16 from main RAM, page 2, 1,000 rows in bands of
#    26 from a RAM bank, then PrintPage; TEXT150.PDF (A4, 150 dpi): a
#    screen of text fit to the page (timed), then a part at 80 pixels an
#    inch; TEXT300.PDF (A4, 300 dpi): the text fit (timed); COLOR.PDF (US
#    Letter): the back screen's scene in its colours and red ink, then a
#    part; NONE.PDF: no pages (an empty area refused); the VRAM dump
# 2. tests/check_print.py: each file parsed (cross reference offsets,
#    stream lengths, the page tree), qpdf --check, every page's CCITT G4
#    image decoded (libtiff) and equal to the pattern or to the screen
#    area scaled as PrintRect scales it; the colours' image equal to the
#    colour map; on the host folder
# 3. the same on an SD card image (tools/vcard.py), the files copied out
# 4. Paint's file/print (tests/print_script.h, the test build with
#    PAINT_PRINT): the page setup box (screenshot), Printed.pdf (Letter,
#    fit to the page) and Actual.pdf (A4, 80 pixels an inch), each equal
#    to the drawing area in the dump, in its colours
# Pictures (pdftoppm, if installed): build/gate/print/text150.png,
# text300.png, color.png, bands.png, paint.png, actual.png (page 1 of each
# file), printdlg.png (Paint's page setup box).
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/print
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/host"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
$PY tools/mkfax.py --test >/dev/null || fail "tools/mkfax.py: the CCITT codes do not decode (libtiff)"
ok "the CCITT codes: every run length coded here decodes with libtiff"
H=$OUT/host
ca65 --cpu 65C02 -I build/gen -I inc tests/print.s -o "$H/print.o" || fail "tests/print.s does not assemble"
ca65 tests/prghdr.s -o "$H/prghdr.o"
ld65 -C cfg/testprg.cfg "$H/prghdr.o" "$H/print.o" -o "$H/TEST.PRG" || fail "tests/print.s does not link"
cp build/VERANDA.PRG build/VERANDA.SYS "$H/"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "the test did not finish"; }
$PY tools/check_vera.py "$H/dump.bin" || fail "the display does not show the bitmap"
echo "== on the host folder"
$PY tests/check_print.py "$H" "$OUT" 2>"$H/libtiff.txt" || fail "the PDF files (host folder)"

if [ "${PRINT_SD:-1}" != 0 ]; then
	S=$OUT/sd
	mkdir -p "$S/card" "$S/out"
	cp "$H/TEST.PRG" build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -20 "$S/out/console.txt"; fail "SD card: the test did not finish"; }
	mv "$S/dump.bin" "$S/out/"
	for f in BANDS TEXT150 TEXT300 COLOR NONE; do
		$PY tools/vcard.py get "$S/sd.img" "$f.PDF" "$S/out/$f.PDF" >/dev/null || fail "SD card: no $f.PDF"
	done
	echo "== on an SD card image"
	$PY tests/check_print.py "$S/out" 2>"$S/libtiff.txt" || fail "the PDF files (SD card)"
fi

# Paint's file/print, against the installed SDK
echo "== Paint: file/print"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
$PY tests/print_script.py "$OUT/script.h" && cmp -s "$OUT/script.h" tests/print_script.h \
	|| fail "tests/print_script.h is not what tests/print_script.py writes"
run() {
	mkdir -p "$2"
	cp "$1" "$2/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
	(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
P=$OUT/paint
mkdir -p "$P"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$P" TESTFLAGS=-DPAINT_PRINT >"$P/build.log" 2>&1 \
	|| { cat "$P/build.log"; fail "Paint's test build (PAINT_PRINT) does not build"; }
run "$P/Paint.cvt" "$P/run" 120
[ -f "$P/run/dump.bin" ] || { tail -5 "$P/run/console.txt"; fail "Paint's print session did not finish"; }
grep -c "PAINT PRINTED" "$P/run/console.txt" | grep -q 2 || { grep -a PAINT "$P/run/console.txt"; fail "Paint did not print twice"; }
ok "Paint printed twice (PAINT PRINTED)"
$PY tests/check_print.py --paint "$P/run" Printed.pdf letter 1 "$OUT" 2>/dev/null || fail "Paint's Printed.pdf"
mv "$OUT/paint.png" "$OUT/printed.png" 2>/dev/null || true
$PY tests/check_print.py --paint "$P/run" Actual.pdf a4 0 "$OUT" 2>/dev/null || fail "Paint's Actual.pdf"
mv "$OUT/paint.png" "$OUT/actual.png" 2>/dev/null || true
frame=$(sed -n 's|^/\* shot printdlg \([0-9]*\) \*/|\1|p' tests/print_script.h)
T=$P/shot
mkdir -p "$T"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS="-DPAINT_PRINT -DPAINT_STOP=$frame" >"$T/build.log" 2>&1 \
	|| { cat "$T/build.log"; fail "Paint's test build (stopped at $frame)"; }
run "$T/Paint.cvt" "$T/run" 30
[ -f "$T/run/dump.bin" ] || fail "no dump at frame $frame"
$PY tools/check_vera.py "$T/run/dump.bin" || fail "the page setup box: the display"
$PY tools/vram2png.py --color "$T/run/dump.bin" "$OUT/printdlg.png" 2>/dev/null \
	|| $PY tools/vram2png.py "$T/run/dump.bin" "$OUT/printdlg.png" 2>/dev/null || true
ok "the page setup box: $OUT/printdlg.png"

echo "pictures: $OUT/text150.png, text300.png, color.png, bands.png (page 1 of each file),"
echo "          printed.png, actual.png (Paint's), printdlg.png (Paint's page setup box)"
echo "GATE print: PASS"
