#!/bin/bash
# Gate archive: Archive (apps/archive), C64 and C128 GEOS disk images on
# Veranda, checked against tools/vdisk.py (DECISIONS V52).
#
#   tools/gate_archive.sh          (ARCHIVE_SD=0: skip the SD card run)
#
# 1. make api, the kernel, the SDK (build/gate/archive/sdk); Archive built
#    against the installed SDK: an application, class Archive, VRND,
#    640x480, API 5, documents D64 D71 D81, below $8000, the SDK's Open
#    dialog in banked overlay 1 (DECISIONS V82); it starts through
#    the loader (AUTOSTART.cvt) and logs ARCHIVE RUNNING
# 2. the fixtures (tests/archive_fixture.py, made with vdisk.py: no GEOS
#    disk from anywhere else): D64/Test.d64, D71/Side.d71, D81/Big.d81;
#    vdisk.py's listings, files and conversions (the oracle); vdisk.py
#    paint draws the geoPaint picture (sunset.png)
# 3. the session (the test build, tests/archive_play.c): the Open dialog
#    (Return: the folder D64; 't', Return: Test.d64 under a long name,
#    "Test disk with a long name 1988.d64"); the listing; extract (all);
#    select all, to Paint; then Side.d71 (extract) and Big.d81 (extract,
#    to Paint, two files selected, the list scrolled to page 2): the
#    console's listings equal vdisk.py ls, the files extracted equal
#    vdisk.py's byte for byte, the Paint documents vdisk.py's conversions
#    (picture, card colours, ink); the screen at the end (Big.d81 from
#    file 18: the rows' texts in the UI font, icons, the selection's colour,
#    the status bar; DECISIONS V148) read back from VRAM
# 4. the listing's screenshot (the test build stopped after Test.d64's
#    listing): the rows, the icons (archive.png)
# 5. the same session on an SD card image (tools/vcard.py), and on one
#    under R49 (ROM_R49); the Open dialog's screenshot there (ARCHIVE_SHOT:
#    the run ends in it, the long name selected: dialog-r49.png)
# 6. Paint opens "Sunset 1" (Paint's test build, PAINT_ARCHIVE): its
#    drawing area and colours are the converted picture (paint.png)
# 7. the shell: a double click on Test.d64 starts Archive with it as its
#    document (ARCHIVE_DOC): the listing on the console; the same with
#    the long name (dataLongName, V82), on the host and an SD card (R49)
# The timings (the emulator's cycle counter, 8 MHz) are printed at the end.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/archive
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49=${ROM_R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || R49=$ROM
LONG="Test disk with a long name 1988.d64"
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

# 1. the application
mkdir -p "$OUT/app"
make -s -C apps/archive SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Archive does not build"; }
A=$OUT/app/Archive.cvt
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" class)" = 'Archive     V1.0' ] || fail "Archive.cvt: type or class"
[ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] && [ "$(field "$A" api)" = 5 ] \
	|| fail "Archive.cvt: VRND, the mode or the API level"
[ "$(field "$A" documents)" = "D64 D71 D81" ] || fail "Archive.cvt: its documents are not D64 D71 D81"
top=$(sed -n '/^Segment list/,/^$/s/^[A-Z0-9]* *00[0-9][0-9A-F]* *\([0-9A-F]*\).*/\1/p' "$OUT/app/archive.map" | sort | tail -1)
[ $((16#$top)) -lt $((16#8000)) ] || fail "Archive's memory reaches \$$top (the C stack is at \$8000)"
ok "Archive builds against the installed SDK: an application, class Archive, VRND, 640x480, API 5, documents D64 D71 D81, \$0801-\$${top#00}, the Open dialog in overlay 1"

run() {     # a CVT as AUTOSTART.cvt in folder $2 for at most $3 seconds
	mkdir -p "$2"
	cp "$1" "$2/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
	(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
run "$A" "$OUT/app/run" 15
grep -q "ARCHIVE RUNNING" "$OUT/app/run/console.txt" || { tail -3 "$OUT/app/run/console.txt"; fail "Archive does not start"; }
ok "Archive starts through the loader (AUTOSTART.cvt)"

# 2. the fixtures and the oracle
F=$OUT/fx
$PY tests/archive_fixture.py "$F" || fail "the fixtures"
IMAGES="D64/Test.d64 D71/Side.d71 D81/Big.d81"
mkdir -p "$F/D64" "$F/D71" "$F/D81"
mv "$F/Disks/Test.d64" "$F/D64/"
mv "$F/Disks/Side.d71" "$F/D71/"
mv "$F/Disks/Big.d81" "$F/D81/"
for i in $IMAGES; do
	$PY tools/vdisk.py ls "$F/$i" > "$F/$(basename "$i").ls" || fail "vdisk.py ls $i"
	$PY tools/vdisk.py getall "$F/$i" "$OUT/ref/$(dirname "$i")" >/dev/null || fail "vdisk.py getall $i"
done
c1541 -attach "$F/D64/Test.d64" -list >"$F/c1541.txt" 2>&1 \
	&& grep -q "^$(sed -n '1s/.*|//p' "$F/Test.d64.ls") blocks free" "$F/c1541.txt" \
	&& echo "ok    VICE's c1541 lists Test.d64 with the same blocks free" || echo "note  (c1541 not checked)"
$PY tools/vdisk.py get "$F/D64/Test.d64" Sunset "$OUT/ref/Sunset.cvt" || fail "vdisk.py get Sunset"
$PY tools/vdisk.py paint "$OUT/ref/Sunset.cvt" "$OUT/sunset.png" || fail "vdisk.py paint"
$PY tools/vdisk.py topaint "$OUT/ref/Sunset.cvt" "$OUT/ref/paint" >/dev/null || fail "vdisk.py topaint"
ok "the fixtures: $(head -1 "$F/Test.d64.ls"), $(head -1 "$F/Side.d71.ls"), $(head -1 "$F/Big.d81.ls"); vdisk.py's picture of Sunset: $OUT/sunset.png"

# 3. the session on the host folder
mkdir -p "$OUT/test"
make -s -C apps/archive test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
R=$OUT/test/run
mkdir -p "$R"
# (Test.d64 under a long name in the runs: the dialog opens it, V82)
put() { for i in $IMAGES; do mkdir -p "$1/$(dirname "$i")"; cp "$F/$i" "$1/$i"; done; mv "$1/D64/Test.d64" "$1/D64/$LONG"; }
put "$R"
run "$OUT/test/Archive.cvt" "$R" 300
[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "the session did not finish"; }
$PY tools/check_vera.py "$R/dump.bin" || fail "the display does not show the bitmap"
echo "== the session on the host folder"
$PY tests/check_archive.py log "$R/console.txt" $(for i in $IMAGES; do echo "$F/$i"; done) || fail "the console"
$PY tests/check_archive.py files "$R/D64" "$F/D64/Test.d64" --paint || fail "Test.d64's files"
$PY tests/check_archive.py files "$R/D71" "$F/D71/Side.d71" || fail "Side.d71's files"
$PY tests/check_archive.py files "$R/D81" "$F/D81/Big.d81" --paint || fail "Big.d81's files"
$PY tests/check_archive.py screen "$R/dump.bin" "$ROM" "$F/D81/Big.d81" Big.d81 17 18 20 || fail "the screen at the end"
$PY tools/vram2png.py "$R/dump.bin" "$OUT/end.png" 2>/dev/null || true

# 4. the listing's screenshot
T=$OUT/shot
mkdir -p "$T"
make -s -C apps/archive test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS=-DARCHIVE_STOP=1 >"$T/build.log" 2>&1 \
	|| { cat "$T/build.log"; fail "the test build (stopped after the listing)"; }
mkdir -p "$T/run/D64"
cp "$F/D64/Test.d64" "$T/run/D64/$LONG"
run "$T/Archive.cvt" "$T/run" 60
[ -f "$T/run/dump.bin" ] || fail "no dump after the listing"
$PY tools/check_vera.py "$T/run/dump.bin" || fail "the listing: the display"
$PY tests/check_archive.py screen "$T/run/dump.bin" "$ROM" "$F/D64/Test.d64" "$LONG" 0 || fail "the listing on the screen"
$PY tools/vram2png.py "$T/run/dump.bin" "$OUT/archive.png" || fail "vram2png"

# 5. the same on an SD card image ($1 the folder, $2 the ROM)
sdrun() {
	S=$1
	mkdir -p "$S/card" "$S/out"
	put "$S/card"
	cp "$OUT/test/Archive.cvt" "$S/card/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$2" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card ($2): the session did not finish"; }
	mv "$S/dump.bin" "$S/out/"
	for i in $IMAGES; do
		d=$(dirname "$i")
		mkdir -p "$S/out/$d"
		cp "$F/$i" "$S/out/$i"
		(cd "$R/$d" && ls -1) | grep -v -i '\.d[678][14]$' | while IFS= read -r f; do
			$PY tools/vcard.py get "$S/sd.img" "$d/$f" "$S/out/$d/$f" >/dev/null || fail "SD card: no $d/$f"
		done
	done
	echo "== the same on an SD card image ($2)"
	$PY tests/check_archive.py log "$S/out/console.txt" $(for i in $IMAGES; do echo "$F/$i"; done) || fail "SD card: the console"
	$PY tests/check_archive.py files "$S/out/D64" "$F/D64/Test.d64" --paint || fail "SD card: Test.d64's files"
	$PY tests/check_archive.py files "$S/out/D71" "$F/D71/Side.d71" || fail "SD card: Side.d71's files"
	$PY tests/check_archive.py files "$S/out/D81" "$F/D81/Big.d81" --paint || fail "SD card: Big.d81's files"
	$PY tests/check_archive.py screen "$S/out/dump.bin" "$2" "$F/D81/Big.d81" Big.d81 17 18 20 || fail "SD card: the screen"
}
if [ "${ARCHIVE_SD:-1}" != 0 ]; then
	sdrun "$OUT/sd" "$ROM"
	sdrun "$OUT/sd49" "$R49"
	ok "SD card images, also under $R49: the dialog opened \"$LONG\", the session as on the host folder"
	# the dialog's screenshot (R49, SD card; ARCHIVE_SHOT: the run ends in it)
	D=$OUT/shot49
	mkdir -p "$D/card"
	make -s -C apps/archive test SDK="$SDK" OUT="$TOP/$D" TESTFLAGS=-DARCHIVE_SHOT >"$D/build.log" 2>&1 \
		|| { cat "$D/build.log"; fail "the test build (ARCHIVE_SHOT)"; }
	put "$D/card"
	cp "$D/Archive.cvt" "$D/card/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$D/card/"
	$PY tools/vcard.py make --mb 64 "$D/sd.img" "$D/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$D/"
	(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$D/dump.bin" ] || { tail -5 "$D/console.txt"; fail "the dialog's screenshot run did not end"; }
	tr -d '\r' < "$D/console.txt" | grep -a -q "VRF SHOW [0-9]* /D64" || fail "the dialog did not list /D64"
	$PY tools/vram2png.py "$D/dump.bin" "$OUT/dialog-r49.png" || fail "vram2png"
	ok "Archive's Open dialog under R49 on an SD card, in /D64, \"$LONG\" selected: $OUT/dialog-r49.png"
fi

# 6. Paint opens the converted picture
P=$OUT/paint
mkdir -p "$P/run"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$P" TESTFLAGS=-DPAINT_ARCHIVE >"$P/build.log" 2>&1 \
	|| { cat "$P/build.log"; fail "Paint's test build (PAINT_ARCHIVE)"; }
cp "$R/D64/Sunset 1.cvt" "$P/run/"
run "$P/Paint.cvt" "$P/run" 60
[ -f "$P/run/dump.bin" ] || { tail -5 "$P/run/console.txt"; fail "Paint: the session did not finish"; }
grep -q "PAINT OPENED" "$P/run/console.txt" || fail "Paint did not open Sunset 1"
echo "== Paint"
$PY tests/check_archive.py paint "$P/run" "$OUT/ref/paint/Sunset 1.cvt" || fail "Paint's picture"
$PY tools/check_vera.py "$P/run/dump.bin" || fail "Paint: the display"
$PY tools/vram2png.py --color "$P/run/dump.bin" "$OUT/paint.png" || fail "vram2png"

# 7. the shell opens Test.d64 with Archive
H=$OUT/shell
mkdir -p "$H/run" "$H/doc"
cp -r shell "$H/src"
rm -f "$H/src"/*.cvt "$H/src"/*.bin "$H/src"/*.map
make -s -C "$H/src" SDK="$SDK" >"$H/build.log" 2>&1 || { cat "$H/build.log"; fail "the shell does not build"; }
make -s -C apps/archive test SDK="$SDK" OUT="$TOP/$H/doc" TESTFLAGS=-DARCHIVE_DOC >>"$H/build.log" 2>&1 \
	|| { cat "$H/build.log"; fail "the test build (ARCHIVE_DOC)"; }
cp "$H/src/SHELL.cvt" "$H/doc/Archive.cvt" build/VERANDA.PRG build/VERANDA.SYS "$F/D64/Test.d64" "$H/run/"
$PY tests/archive_shell.py "$H/run" console.txt || fail "the shell's script"
(cd "$H/run" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -a -q "ARCHIVE DOC Test.d64 IN /" "$H/run/console.txt" || { tail -5 "$H/run/console.txt"; fail "the shell did not open Test.d64 with Archive"; }
echo "== the shell"
$PY tests/check_archive.py listing "$H/run/console.txt" "$F/D64/Test.d64" || fail "the shell's start: the listing"
ok "a double click on Test.d64 in the shell starts Archive with it as its document (ST_LD_DATA, documents D64): ARCHIVE DOC Test.d64 IN /"
# the long name (V82): Archive gets it whole (dataLongName); host, SD card under R49
mkdir -p "$H/long"
cp "$H/src/SHELL.cvt" "$H/doc/Archive.cvt" build/VERANDA.PRG build/VERANDA.SYS "$H/long/"
cp "$F/D64/Test.d64" "$H/long/$LONG"
$PY tests/archive_shell.py "$H/long" --name "$LONG" console.txt || fail "the shell's script"
(cd "$H/long" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -a -q "ARCHIVE DOC $LONG IN /" "$H/long/console.txt" || { tail -5 "$H/long/console.txt"; fail "the shell did not open $LONG with Archive"; }
$PY tests/check_archive.py listing "$H/long/console.txt" "$F/D64/Test.d64" || fail "the shell's long document: the listing"
ok "a double click on \"$LONG\" starts Archive with its whole name (dataLongName): ARCHIVE DOC $LONG IN /"
L=$H/long49
mkdir -p "$L/card"
cp "$H/src/SHELL.cvt" "$H/doc/Archive.cvt" build/VERANDA.SYS "$L/card/"
cp "$F/D64/Test.d64" "$L/card/$LONG"
$PY tests/archive_shell.py "$L/card" --name "$LONG" || fail "the shell's script"
$PY tools/vcard.py make --mb 64 "$L/sd.img" "$L/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$L/"
(cd "$L" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -a -q "ARCHIVE DOC $LONG IN /" "$L/console.txt" || { tail -5 "$L/console.txt"; fail "R49, SD card: the shell did not open $LONG with Archive"; }
$PY tests/check_archive.py listing "$L/console.txt" "$F/D64/Test.d64" || fail "R49, SD card: the listing"
ok "the same on an SD card image under R49"

# the timings
t() { v=$(grep -a -o "TIME $1 [0-9A-F]*" "$2" | sed -n "${3:-1}p" | awk '{print $NF}'); \
	[ -n "$v" ] && $PY -c "print('%.2f s' % (int('$v', 16) / 8e6))" || echo "?"; }
echo "timings (host folder): listing Test.d64 $(t list "$R/console.txt" 1), Big.d81 $(t list "$R/console.txt" 3);" \
	"extracting all: Test.d64 $(t 'extract all' "$R/console.txt" 1), Big.d81 $(t 'extract all' "$R/console.txt" 3);" \
	"geoPaint (Sunset: two Paint documents) $(t 'convert Sunset' "$R/console.txt" 1)"
if [ "${ARCHIVE_SD:-1}" != 0 ]; then
	echo "timings (SD card):     listing Test.d64 $(t list "$S/out/console.txt" 1), Big.d81 $(t list "$S/out/console.txt" 3);" \
		"extracting all: Test.d64 $(t 'extract all' "$S/out/console.txt" 1), Big.d81 $(t 'extract all' "$S/out/console.txt" 3);" \
		"geoPaint $(t 'convert Sunset' "$S/out/console.txt" 1)"
fi
echo "screenshots: $OUT/archive.png (Test.d64 listed), $OUT/end.png (Big.d81, page 2, two selected), $OUT/dialog-r49.png (the Open dialog, R49),"
echo "             $OUT/paint.png (Paint with Sunset 1, composed), $OUT/sunset.png (vdisk.py's picture of the page)"
echo "GATE archive: PASS"
