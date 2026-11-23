#!/bin/bash
# Gate view: Veranda View (apps/view) shows text, BMPs, a Paint document,
# a Photo Scrap, a photo album and an info block, each screen equal to
# tests/check_view.py's drawing of the same file.
#
#   tools/gate_view.sh
#
# 1. the kernel, the SDK; View built against it (it must end below its C
#    stack) and its test build (tests/view_play.c); the scene
#    (tests/view_scene.c, AUTOSTART)
# 2. the fixtures (tests/view_fixture.py): Readme.txt, Picture.cvt (Paint),
#    Sunset.cvt (a Photo Scrap), Album.cvt (a photo album)
# 3. a run on the host folder: the scene draws a picture in colours with a
#    red ink, writes SCENE.RAW and exports Line.bmp (1 bpp) and Color.bmp
#    (4 bpp) with ExportRect, then starts View, which opens Readme.txt
#    (and finds NEEDLE twice, copies the page), Line.bmp, Color.bmp (fit;
#    then 1:1 panned; copied), Picture.cvt, Sunset.cvt, Album.cvt (two
#    pages), View.cvt (its info block), Line.bmp as text, each screen
#    written to a file; check_view.py compares them, the BMPs with the
#    scene, the Text Scrap and the Photo Scrap with what was shown
#    then the Open dialog (the SDK's vrchoose, overlay 2: DECISIONS V82):
#    'h' and Return open "Holiday photos from the lake 2026.bmp" (the
#    scene exported Line.bmp under that name too)
# 4. the same on an SD card image, and on one under R49 (ROM_R49, default
#    ~/Downloads/Release.R49.ROM.Image/rom.bin); there the dialog's
#    screenshot (VIEW.SHT: the run ends in it: dialog-r49.png)
# 5. the shell opens Line.bmp with View (View declares BMP: V48), and
#    "Holiday photos from the lake 2026.bmp": View has its whole name
#    (dataLongName, V82); the long one also on an SD card under R49
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/view
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49=${ROM_R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || R49=$ROM
LONG="Holiday photos from the lake 2026.bmp"
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# View and its test build, from copies of apps/view
for b in app test; do
	mkdir -p "$OUT/$b"
	cp apps/view/view.c apps/view/fast.s apps/view/app.hdr apps/view/icon.pbm apps/view/tile.txt apps/view/icon.txt apps/view/Makefile "$OUT/$b/"
done
make -s -C "$OUT/app" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "View does not build"; }
make -s -C "$OUT/test" SDK="$SDK" TEST_SRC="$PWD/tests/view_play.c" test >>"$OUT/build.log" 2>&1 \
	|| { cat "$OUT/build.log"; fail "View's test build does not build"; }
for b in app test; do
	# (main RAM: the overlay, V79, is at $A000 in a bank of its own)
	top=$(sed -n '/^Segment list/,/^$/s/^[A-Z0-9]* *\(00[0-9][0-9A-F]*\) *\([0-9A-F]*\).*/\2/p' "$OUT/$b/view.map" | grep -v '^00A' | sort | tail -1)
	[ $((16#$top)) -lt $((16#8680)) ] || fail "View ($b) reaches \$$top (its C stack is at \$8680)"
done
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$OUT/app/View.cvt" documents)" = BMP ] || fail "View.cvt: its documents are not BMP"
ok "View builds against the installed SDK (\$0801-\$${top#00}, below its C stack), and its test build; it opens BMP files (info block 144-159)"

S=$OUT/scene
mkdir -p "$S"
printf 'name = AUTOSTART\nclass = ViewScene\nmode = 640x480\napi = 2\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$S/app.hdr"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$S/scene.bin" tests/view_scene.c tests/view_play.c \
	"$SDK/lib/veranda.lib" || fail "tests/view_scene.c"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$S/AUTOSTART.cvt" "$S/app.hdr" "$S/scene.bin" >/dev/null || fail "vpack the scene"

F=$OUT/fixtures
$PY tests/view_fixture.py "$F" || fail "the fixtures"
ok "the fixtures: $(cd "$F" && ls | tr '\n' ' ')"

# the files of a run ($1)
files() {
	mkdir -p "$1"
	cp "$F"/* "$S/AUTOSTART.cvt" "$OUT/test/View.cvt" build/VERANDA.SYS "$1/"
}
SNAPS="SCENE.RAW TEXT1.RAW TEXT2.RAW TEXT3.RAW BMP1.RAW BMP4F.RAW BMP4A.RAW PAINT.RAW SCRAP.RAW ALBUM1.RAW ALBUM2.RAW INFO.RAW ASTEXT.RAW LONG.RAW"
steps() {
	tr -d '\r' < "$1" | grep -a -o -E 'VIEW (EXPORTED|EXPORT FAILED|DID NOT START|RUNNING|STEP [a-z0-9 :]*|COPIED [A-Z]*|SNAP FAILED|DONE)' | tr '\n' ','
}
want="VIEW EXPORTED,VIEW RUNNING,VIEW STEP text,VIEW STEP find,VIEW STEP find again,VIEW COPIED TEXT,VIEW STEP bmp1,"
want="${want}VIEW STEP bmp4 fit,VIEW STEP bmp4 1:1,VIEW COPIED PICTURE,VIEW STEP paint,VIEW STEP scrap,VIEW STEP album 1,"
want="${want}VIEW STEP album 2,VIEW STEP info,VIEW STEP as text,VIEW STEP long name,VIEW DONE,"

echo "== the host folder"
H=$OUT/host
files "$H"
cp build/VERANDA.PRG "$H/"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ "$(steps "$H/console.txt")" = "$want" ] || { tail -5 "$H/console.txt"; fail "host folder: the console has $(steps "$H/console.txt")"; }
[ -f "$H/dump.bin" ] || fail "host folder: no VRAM dump"
ok "host folder: the scene exported its BMPs, View opened every file in turn (the console in order)"
$PY tests/check_view.py "$H" "$ROM" "$OUT/png" || fail "host folder: the screens"
$PY tools/check_vera.py "$H/dump.bin" || fail "host folder: the display does not show the bitmap"
$PY tools/vram2png.py "$H/dump.bin" "$OUT/png/end.png" || fail "vram2png"
ok "host folder: every screen equals check_view.py's drawing"

# the session on an SD card image in $1 under ROM $2 (PNGs in $3)
sdrun() {
	C=$1
	files "$C/card"
	$PY tools/vcard.py make --mb 64 "$C/sd.img" "$C/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$C/"
	(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$2" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ "$(steps "$C/console.txt")" = "$want" ] || { tail -5 "$C/console.txt"; fail "SD card ($2): the console has $(steps "$C/console.txt")"; }
	mkdir -p "$C/out"
	cp "$F"/* "$OUT/test/View.cvt" "$C/out/"
	for f in $SNAPS Line.bmp Color.bmp "$LONG" "Text  Scrap.cvt" "Photo Scrap.cvt"; do
		$PY tools/vcard.py get "$C/sd.img" "$f" "$C/out/$f" >/dev/null || fail "SD card: no $f"
	done
	$PY tests/check_view.py "$C/out" "$2" "$3" || fail "SD card ($2): the screens"
}
echo "== an SD card image"
sdrun "$OUT/sd" "$ROM" "$OUT/png-sd"
ok "SD card: every screen equals check_view.py's drawing"
echo "== an SD card image under R49"
sdrun "$OUT/sd49" "$R49" "$OUT/png-sd49"
ok "SD card under $R49: every screen equals check_view.py's drawing (the Open dialog opened \"$LONG\")"

# the dialog's screenshot (R49, SD card): VIEW.SHT ends the run in it
C=$OUT/shot49
files "$C/card"
echo 1 > "$C/card/VIEW.SHT"
$PY tools/vcard.py make --mb 64 "$C/sd.img" "$C/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$C/"
(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$C/dump.bin" ] || { tail -5 "$C/console.txt"; fail "the dialog's screenshot run did not end"; }
tr -d '\r' < "$C/console.txt" | grep -a -q "VRF SHOW [0-9]* /" || fail "the dialog did not list the folder"
$PY tools/vram2png.py "$C/dump.bin" "$OUT/dialog-r49.png" || fail "vram2png"
ok "View's Open dialog under R49 on an SD card, \"$LONG\" selected: $OUT/dialog-r49.png"

echo "== the shell opens Line.bmp with View"
D=$OUT/doc
mkdir -p "$D"
mkdir -p "$OUT/shell"
cp -r shell/* "$OUT/shell/"
rm -f "$OUT/shell"/*.cvt "$OUT/shell"/*.bin
make -s -C "$OUT/shell" SDK="$SDK" >>"$OUT/build.log" 2>&1 || fail "the shell does not build"
cp "$OUT/shell/SHELL.cvt" "$OUT/test/View.cvt" "$H/Line.bmp" build/VERANDA.SYS build/VERANDA.PRG "$D/"
$PY tests/view_fixture.py --shell "$D" || fail "the shell's script"
(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
tr -d '\r' < "$D/console.txt" | grep -a -q "VIEW DOC Line.bmp IN /" || { tail -5 "$D/console.txt"; fail "the shell did not start View with Line.bmp"; }
$PY tests/check_view.py doc "$D" "$ROM" Line.bmp || fail "the shell's document"
ok "a double click on Line.bmp in the shell starts View with it (VIEW DOC Line.bmp IN /), the picture shown"
# a long name (V82): View gets it whole (dataLongName), on the host and on an SD card under R49
D=$OUT/doclong
mkdir -p "$D"
cp "$OUT/shell/SHELL.cvt" "$OUT/test/View.cvt" build/VERANDA.SYS build/VERANDA.PRG "$D/"
cp "$H/Line.bmp" "$D/$LONG"
$PY tests/view_fixture.py --shell "$D" "$LONG" || fail "the shell's script"
(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
tr -d '\r' < "$D/console.txt" | grep -a -q "VIEW DOC $LONG IN /" || { tail -5 "$D/console.txt"; fail "the shell did not start View with $LONG"; }
$PY tests/check_view.py doc "$D" "$ROM" "$LONG" || fail "the shell's long document"
ok "a double click on \"$LONG\" starts View with its whole name (dataLongName: VIEW DOC $LONG IN /), the picture shown"
D=$OUT/doclong49
mkdir -p "$D/card" "$D/out"
cp "$OUT/shell/SHELL.cvt" "$OUT/test/View.cvt" build/VERANDA.SYS "$D/card/"
cp "$H/Line.bmp" "$D/card/$LONG"
$PY tests/view_fixture.py --shell "$D/card" "$LONG" sd || fail "the shell's script"
$PY tools/vcard.py make --mb 64 "$D/sd.img" "$D/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$D/"
(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
tr -d '\r' < "$D/console.txt" | grep -a -q "VIEW DOC $LONG IN /" || { tail -5 "$D/console.txt"; fail "R49, SD card: the shell did not start View with $LONG"; }
cp "$D/card/$LONG" "$D/out/"
$PY tools/vcard.py get "$D/sd.img" DOC.RAW "$D/out/DOC.RAW" >/dev/null || fail "R49, SD card: no DOC.RAW"
$PY tests/check_view.py doc "$D/out" "$R49" "$LONG" || fail "R49, SD card: the shell's long document"
ok "the same on an SD card image under R49"
echo "screenshots: $OUT/png/*.png (each file in View), $OUT/png/scene.png (the scene the BMPs came from), $OUT/dialog-r49.png (the Open dialog, R49)"
echo "GATE view: PASS"
