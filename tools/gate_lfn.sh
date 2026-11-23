#!/bin/bash
# Gate lfn (DECISIONS V82): long file names from the shell.
#
#   tools/gate_lfn.sh
#
# 1. the kernel, the SDK, the shell (built against the installed SDK); two
#    test programs (tests/shell_app.s -D LFN): AppOne (it opens .txt files)
#    and AppTwo, copied as "Application Seven.cvt" (17 characters: GEOS's
#    16 would look for "Application Seve.cvt"); both are GEOS programs as
#    far as names go (longNames 0): AppOne logs dataFileName (the short
#    form), dataLongName and the document's first line read with
#    FOpen(dataFileName)
# 2. a run (tests/lfn_shell_script.py): the shell double-clicks Application
#    Seven; "Holiday photos from the lake 2026.txt" (AppOne in the same
#    folder); in Docs a 48-character document (AppOne found in the top
#    folder: open with); Application Seven pinned (options > pin) and the
#    pin double-clicked; the console's lines in order
# 3. on the host folder, an SD card image (tools/vcard.py), and an SD card
#    image under R49 (~/Downloads/Release.R49.ROM.Image/rom.bin); a
#    screenshot of the shell's window with the long names under R49
#    (build/gate/lfn/shell-r49.png)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/lfn}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }
A=$OUT/apps
mkdir -p "$A"
for n in 1 2; do
	nm=$([ $n = 1 ] && echo AppOne || echo AppTwo)
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$n -D LFN -o "$A/app$n.o" tests/shell_app.s || fail "tests/shell_app.s"
	ld65 -C "$SDK/cfg/app.cfg" -o "$A/app$n.bin" "$A/app$n.o" || fail "tests/shell_app.s does not link"
	printf 'name = %s\nclass = Test%s\nmode = 640x480\napi = 1\nicon = %s\n' $nm $n \
		"$SDK/template/c/icon.pbm" > "$A/app$n.hdr"
	[ $n = 1 ] && echo "documents = TXT" >> "$A/app$n.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/app$n.hdr" "$A/app$n.bin" >/dev/null || fail "vpack $nm"
done
ca65 --cpu 65C02 -I "$SDK/include" -D APPN=3 -D DA -o "$A/da.o" tests/shell_app.s || fail "tests/shell_app.s -D DA"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/da.bin" "$A/da.o" || fail "the accessory does not link"
printf 'name = TestDa\nclass = TestDa\ntype = deskacc\napi = 1\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/da.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/TestDa.cvt" "$A/da.hdr" "$A/da.bin" >/dev/null || fail "vpack TestDa"
ok "the shell, AppOne.cvt (opens .txt) and AppTwo.cvt (tests/shell_app.s -D LFN: GEOS programs, longNames 0)"

files() {
	mkdir -p "$1/Docs"
	cp "$OUT/src/SHELL.cvt" "$A/AppOne.cvt" build/VERANDA.SYS "$1/"
	cp "$A/AppTwo.cvt" "$1/Application Seven.cvt"
	cp "$A/TestDa.cvt" "$1/Desk accessory with a long name.cvt"
	echo "A week of photos by the lake." > "$1/Holiday photos from the lake 2026.txt"
	echo "Notes kept on the way." > "$1/Docs/Notes from a longer trip to the lake in 2026.txt"
}

order() {
	got=$(tr -d '\r' < "$1" | grep -a -o -E 'SHELL STARTED|DA RAN|SHELL PINNED .*|APP [12] (RAN|DOC .*|LONG .*|READ .*)|SHELL DONE' \
		| sed 's/ *$//')
	want=$($PY tests/lfn_shell_script.py --want x)
	[ "$got" = "$want" ] || { echo "$got" | diff <(echo "$want") - | head -20; fail "$2: the console's lines"; }
	ok "$2: Application Seven.cvt (17 characters) started by a double click; Holiday photos from the lake 2026.txt"
	ok "$2:   opened with AppOne (same folder), a 48-character document in Docs with AppOne from the top folder"
	ok "$2:   (open with): AppOne saw the short forms in dataFileName ($(echo "$got" | sed -n 's/^APP 1 DOC \(.*\) IN.*/\1/p' | tr '\n' ',' | sed 's/,$//')),"
	ok "$2:   the whole names in dataLongName, and FOpen(dataFileName) read each long file; the accessory of 32 characters opened over the shell and back; Application Seven pinned, started by its pin"
}

# on the host folder
H=$OUT/host
mkdir -p "$H"
files "$H"
cp build/VERANDA.PRG "$H/"
$PY tests/lfn_shell_script.py "$H" console.txt || fail "the script"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "host folder: the session did not end (no dump)"; }
order "$H/console.txt" "host folder"

# on SD card images: $1 the folder, $2 the ROM, $3 what
sd() {
	S=$OUT/$1
	mkdir -p "$S/card"
	files "$S/card"
	$PY tests/lfn_shell_script.py "$S/card" || fail "the script"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 200 "$EMU" -rom "$2" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -20 "$S/console.txt"; fail "$3: the session did not end (no dump)"; }
	order "$S/console.txt" "$3"
	$PY tools/vcard.py ls "$S/sd.img" | grep -q '~' && fail "$3: a file under a short form on the card"
	ok "$3: no file under a short form on the card"
	$PY tools/vram2png.py "$S/dump.bin" "$OUT/shell-$1.png" || fail "vram2png"
}
sd sd "$ROM" "SD card image"
if [ -f "$R49" ]; then
	sd sd49 "$R49" "SD card image, R49"
	ok "screenshot: $OUT/shell-sd49.png (the shell under R49 with the long names and the pin)"
fi
echo "GATE lfn: PASS"
