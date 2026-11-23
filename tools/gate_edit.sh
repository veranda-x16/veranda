#!/bin/bash
# Gate edit: Veranda Edit (apps/edit), a text editor in C with the SDK.
#
#   tools/gate_edit.sh          (EDIT_SD=0: skip the SD card run)
#
# 1. the SDK installed; Veranda Edit built against it: an application
#    (VRND, 640x480, API 2), its code in main RAM and two banked overlays
#    (tests/check_edit_banks.py: no call into an overlay that may not be
#    mapped), "documents" TXT MD INI LOG (the shell opens them with it)
# 2. the gap buffer alone (tests/edit_buftest.c): 700 random edits across
#    nine banks against a Python copy of them; the text written in its
#    three line-end forms and read back (tests/check_edit_buf.py)
# 3. the session (tests/edit_script.py; tests/edit_play.s plays it): a
#    100 KB file opened through the file chooser, edited at the start, the
#    middle and the end, find and replace all, a selection deleted, undo,
#    a styled Text Scrap pasted plain, two lines copied and pasted (the
#    scrap written), saved; the mouse, the wheel, the geos menu; Save as
#    into a folder with a long name; CR LF, LF and CR files edited and
#    saved; a 262,000-byte file (more than application RAM) edited at both
#    ends and saved; (V143) a UTF-8 file in Polish opened (decoded into
#    the set), "Żółw" typed in the set's bytes, saved (UTF-8 again), Ctrl+E
#    and Save as (the set's bytes). tests/check_edit.py: 22 states as the Python model,
#    the files on the host byte for byte, the Text Scrap; the timings
# 4. screenshots on the way (the session stopped there; check_vera.py):
#    the chooser, a selection, the find dialog, Save as
# 5. the session on an SD card image
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/edit
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

mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/edit SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Veranda Edit does not build"; }
A="$OUT/app/Veranda Edit.cvt"
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] \
	|| fail "Veranda Edit.cvt: not an application (VRND, 640x480)"
$PY "$SDK/tools/vpack.py" --list "$A" | grep -q "TXT" || fail "Veranda Edit.cvt: no documents TXT"
end=$(sed -n 's/^BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' "$OUT/app/edit.map")
[ $((16#$end)) -lt $((16#8400)) ] || fail "main RAM ends at \$$end (the C stack is at \$8400)"
for n in 1 2; do
	s=$(stat -c %s "$OUT/app/edit.bin.$n")
	[ "$s" -le 8191 ] || fail "overlay $n: $s bytes"
done
ok "Veranda Edit builds against the installed SDK: an application, main RAM to \$$end, overlays of $(stat -c %s "$OUT/app/edit.bin.1") and $(stat -c %s "$OUT/app/edit.bin.2") bytes, documents TXT MD INI LOG"
$PY tests/check_edit_banks.py apps/edit || fail "the overlays' calls"

# the gap buffer alone
B=$OUT/buf
mkdir -p "$B/run"
printf 'name = BufTest\nclass = BufTest\nmode = 640x480\napi = 2\nicon = %s/apps/edit/icon.pbm\n' "$TOP" > "$B/app.hdr"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$B/bt.bin" \
	-I "$SDK/src/textkit" -I tests tests/edit_buftest.c "$SDK/src/textkit/text.c" "$SDK/src/textkit/buf.s" "$SDK/lib/veranda.lib" >"$B/build.log" 2>&1 \
	|| { cat "$B/build.log"; fail "the buffer test does not build"; }
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$B/run/AUTOSTART.cvt" "$B/app.hdr" "$B/bt.bin" >/dev/null
cp build/VERANDA.PRG build/VERANDA.SYS "$B/run/"
(cd "$B/run" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
$PY tests/check_edit_buf.py "$B/run" || fail "the gap buffer"

make -s -C apps/edit test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }

# the session in folder $1 (made here), stopped at $2 if given
run() {
	rm -rf "$1"
	mkdir -p "$1"
	cp "$OUT/test/Edit.cvt" "$1/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$1/"
	$PY tests/edit_script.py "$1" ${2:+--stop $2} || fail "tests/edit_script.py"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -5 "$1/console.txt"; fail "the session did not finish ($1)"; }
}
R=$OUT/run
run "$R"
$PY tools/check_vera.py "$R/dump.bin" || fail "the display"
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/end.png" 2>/dev/null || true
echo "== the session on the host folder"
$PY tests/check_edit.py "$R" || fail "the session (host folder)"

for s in chooser select findfull saveas2 newfolder popup polish; do
	run "$OUT/shot-$s" $s
	$PY tools/check_vera.py "$OUT/shot-$s/dump.bin" || fail "the display ($s)"
	$PY tools/vram2png.py --color "$OUT/shot-$s/dump.bin" "$OUT/$s.png" 2>/dev/null || true
	$PY tests/check_edit.py "$OUT/shot-$s" --partial >/dev/null || fail "the session stopped at $s"
done
ok "screenshots: $OUT/chooser.png, select.png, findfull.png, saveas2.png, newfolder.png (the Save dialog moved), popup.png (its folder pop-up), polish.png, end.png"
# (V143) the UTF-8 file in Polish, decoded into the set, in the ROM's
# ISO-8859-16 glyphs (the cursor is on the first line's Z)
$PY tests/check_l10_text.py "$OUT/shot-polish/dump.bin" "$ROM" "ażółć gęślą jaźń" "ZAŻÓŁĆ GĘŚLĄ JAŹŃ" \
	|| fail "the Polish text on the screen"

# the session on an SD card image: $1 the folder's name, $2 the ROM
sdsession() {
	S=$OUT/$1
	rm -rf "$S"
	mkdir -p "$S/card" "$S/out"
	cp "$OUT/test/Edit.cvt" "$S/card/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$S/card/"
	$PY tests/edit_script.py "$S/card" || fail "tests/edit_script.py"
	mv "$S/card/expect.json" "$S/out/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$2" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: the session did not finish"; }
	mkdir -p "$S/out/Docs" "$S/out/VERANDA/.SYSTEM" "$S/out/A folder with a long name"
	for f in BIG.TXT HUGE.TXT "Docs/Copy of big.txt" "Docs/CRLF Long Name File.txt" Docs/Lone.txt \
		"Docs/OLD MAC.TXT" "VERANDA/.SYSTEM/Text  Scrap.cvt" "A folder with a long name/Notes from the dialog.txt" ZAZOLC.TXT Polski.txt; do
		$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null || fail "SD card: no $f"
	done
	echo "== the same on an SD card image ($2)"
	$PY tests/check_edit.py "$S/out" || fail "the session (SD card, $2)"
}
if [ "${EDIT_SD:-1}" != 0 ]; then
	sdsession sd "$ROM"
	R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
	[ -f "$R49" ] && sdsession sd49 "$R49"         # (V82: the long names under R49)
fi
echo "GATE edit: PASS"
