#!/bin/bash
# Gate font (docs/DECISIONS.md V62): fonts from RAM banks (the font
# service, bank T), the font picker, Paint's text tool in a chosen font,
# the Font Editor.
#
#   tools/gate_font.sh          (FONT_SD=0: skip the SD card run)
#
# 1. make api, the kernel, the SDK into build/gate/font/sdk (the picker in
#    lib/veranda.lib, include/fontpick.h); the test fonts (tools/fontcvt.py
#    testfonts: Gate Sans 9, 12, 18, 27 (two banks), Gate Mono 10 and 12
#    (tools/gatemono.py; the test draws 10): drawn here, no Berkeley
#    Softworks font) in the run folder's /VERANDA/FONTS
# 2. tests/font.s (TEST.PRG): FontList from a folder (the current
#    directory the same after), FontSizes, FontInfo, the errors; each test
#    record's line in every style from the program's memory (LoadCharSet)
#    and from banks (LoadFont, UseFont): tests/check_font.py compares them
#    byte for byte and with the record as tools/fontcvt.py draws it; the
#    timings; a menu in the UI font (uiFont = FONT_UI); italic's lean
#    drawn whole (V122: italic, plain after it, a string's end, the next
#    WPutString) against tools/fontcvt.py render_runs
# 3. the same on an SD card image (the "$=C" listing of the real DOS)
# 4. Paint (tests/font_script.py: tests/font_paint_script.h): options/text
#    font, the picker (Gate Sans, 18, OK), the text tool: "Veranda" in Gate
#    Sans 18 as the record draws it; screenshots: the picker, the text
# 5. the Font Editor (apps/fonted; tests/fonted_script.h): open Gate Sans
#    12 with the picker, change A (three cells, a drag, Width +), save; a
#    new size 24, save: the file checked on the host (tests/check_font.py
#    --fonted: a valid GEOS font, the other sizes byte for byte, A as
#    edited, 24 as size 12 scaled); screenshots
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/font
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py > "$OUT/kbuild.txt" || fail "the kernel does not build"
cat "$OUT/kbuild.txt"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
[ -f "$SDK/include/fontpick.h" ] && ar65 t "$SDK/lib/veranda.lib" | grep -q fontpick || fail "the SDK has no font picker"
ok "the SDK has the font picker: include/fontpick.h, lib/veranda.lib (fontpick)"

$PY tests/font_script.py "$OUT" || fail "tests/font_script.py"
for s in font_paint fonted; do
	cmp -s "$OUT/${s}_script.h" tests/${s}_script.h || fail "tests/${s}_script.h is not what tests/font_script.py writes"
done

F=$OUT/fonts
$PY tools/fontcvt.py testfonts "$F" || fail "the test fonts"
for f in "Gate Sans" "Gate Mono"; do
	$PY tools/fontcvt.py check "$F/$f.cvt" || fail "$f.cvt"
done

# a run folder: $1; the fonts, a folder SUB/DEEP with HERE.TXT
folder() {
	mkdir -p "$1/VERANDA/FONTS" "$1/SUB/DEEP"
	cp "$F/Gate Sans.cvt" "$F/Gate Mono.cvt" "$1/VERANDA/FONTS/"
	echo here > "$1/SUB/DEEP/HERE.TXT"
}

echo "== fonts from banks (tests/font.s)"
T=$OUT/test
folder "$T"
ca65 --cpu 65C02 -I build/gen -I inc --bin-include-dir "$F" tests/font.s -o "$T/font.o" || fail "tests/font.s"
ca65 tests/prghdr.s -o "$T/prghdr.o"
ld65 -C cfg/testprg.cfg "$T/prghdr.o" "$T/font.o" -o "$T/TEST.PRG" || fail "tests/font.s does not link"
cp build/VERANDA.PRG build/VERANDA.SYS "$T/"
(cd "$T" && SDL_VIDEODRIVER=dummy timeout -s INT 90 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$T/dump.bin" ] || { tail -5 "$T/console.txt"; fail "no dump"; }
$PY tools/check_vera.py "$T/dump.bin" || fail "the display"
$PY tests/check_font.py "$T/dump.bin" "$T/console.txt" "$F" "$OUT" || fail "fonts from banks"

if [ "${FONT_SD:-1}" != 0 ]; then
	echo "== the same on an SD card image"
	S=$OUT/sd
	folder "$S/card"
	cp "$T/TEST.PRG" build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	mkdir -p "$S/out"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: no dump"; }
	$PY tests/check_font.py "$S/dump.bin" "$S/out/console.txt" "$F" "$S/out" || fail "fonts from banks (SD card)"
fi

echo "== Paint: the text tool in a font from the picker"
build_app() {   # app dir, out, flags
	mkdir -p "$2"
	make -s -C "apps/$1" test SDK="$SDK" OUT="$TOP/$2" TESTFLAGS="$3" >"$2/build.log" 2>&1 \
		|| { cat "$2/build.log"; fail "$1's test build ($3)"; }
}
runapp() {      # the .cvt, the run folder, seconds
	folder "$2"
	cp "$1" "$2/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
	(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$2/dump.bin" ] || { tail -5 "$2/console.txt"; fail "$1: no dump"; }
}
shot() { sed -n "s|^/\* shot $1 \([0-9]*\) \*/|\1|p" tests/$2; }

P=$OUT/paint
build_app paint "$P" -DPAINT_FONT
runapp "$P/Paint.cvt" "$P/run" 90
grep -q "PAINT FONT" "$P/run/console.txt" || fail "Paint: the picker did not give a font"
ok "Paint: options/text font, the picker: Gate Sans 18 chosen and loaded (PAINT FONT)"
$PY tests/check_font.py --paint "$P/run/dump.bin" "$F" "$OUT" || fail "Paint's text"
PS=$OUT/paint-picker
build_app paint "$PS" "-DPAINT_FONT -DPAINT_STOP=$(shot picker font_paint_script.h)"
runapp "$PS/Paint.cvt" "$PS/run" 60
$PY tools/vram2png.py --color "$PS/run/dump.bin" "$OUT/picker.png" 2>/dev/null || true
$PY tools/vram2png.py --color "$P/run/dump.bin" "$OUT/paint-text.png" 2>/dev/null || true

echo "== the Font Editor"
E=$OUT/fonted
build_app fonted "$E" ""
end=$($PY tools/vpack.py --list "$E/FontEd.cvt" | sed -n 's/^end *//p')
ok "Font Editor builds: \$0801-$end, API $($PY tools/vpack.py --list "$E/FontEd.cvt" | sed -n 's/^api *//p')"
runapp "$E/FontEd.cvt" "$E/run" 150
[ "$(grep -ac "FONTED SAVED" "$E/run/console.txt")" = 2 ] || { tail -3 "$E/run/console.txt"; fail "Font Editor: not saved twice"; }
ok "Font Editor: opened, edited, saved; a new size, saved (FONTED SAVED twice)"
[ ! -e "$E/run/VERANDA/FONTS/Gate Sans.tmp" ] || fail "Font Editor: Gate Sans.tmp left"
$PY tools/fontcvt.py check "$E/run/VERANDA/FONTS/Gate Sans.cvt" || fail "the saved font"
$PY tests/check_font.py --fonted "$E/run/VERANDA/FONTS/Gate Sans.cvt" "$F/Gate Sans.cvt" || fail "the saved font"
for name in edited sized; do
	ES=$OUT/fonted-$name
	build_app fonted "$ES" "-DFONTED_STOP=$(shot $name fonted_script.h)"
	runapp "$ES/FontEd.cvt" "$ES/run" 120
	$PY tools/vram2png.py --color "$ES/run/dump.bin" "$OUT/fonted-$name.png" 2>/dev/null || true
done

echo "screenshots: $OUT/font-screen.png (memory and banks, a menu in the UI font), picker.png,"
echo "             paint-text.png (Paint's text in Gate Sans 18), fonted-edited.png, fonted-sized.png"
echo "GATE font: PASS"
