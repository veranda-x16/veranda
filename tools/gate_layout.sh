#!/bin/bash
# Gate layout (DECISIONS V71): the card's folders. /VERANDA holds the
# system, /VERANDA/APPS the applications and accessories, /VERANDA/.SYSTEM
# the system's data (hidden), /DOCUMENTS the user's files; Veranda Setup
# moves a card of the layout before into it, once.
#
#   tools/gate_layout.sh      (X16MOD=<x16-mod tree>: the MOD Player's run;
#                              LAYOUT_R49=<rom>: the ROM of the main runs)
#
# 1. the kernel, the SDK, the shell, Veranda Setup and the applications
#    and accessories (Paint's and Veranda Edit's test builds: their
#    scripted sessions save), the MOD Player (x16-mod, branch layout) if
#    its tree is there
# 2. an SD card image in the old layout, of the user's kind
#    (tests/layout_gate.py card: settings, Note File, a scrap, the trash,
#    a pin, documents test.cvt, eeee.cvt, NOTES.TXT, song.mod, a folder of
#    the user's; DOCUMENTS/NOTES.TXT there already), booted as the user
#    does (DOS"CD:VERANDA", LOAD"VERANDA.PRG", RUN; typed) under R49: the
#    shell starts Setup, which moves the files, writes .SYSTEM/LAYOUT.LOG
#    and quits to the shell, in /DOCUMENTS; a host-side inventory before
#    and after: every file's bytes where they belong, nothing lost
#    (tests/layout_gate.py check); the shell on the migrated card:
#    build/gate/layout/migrated.png
# 3. runs on the migrated card (each from its files, a new image): the
#    settings from .SYSTEM (Graphite's colours); the trash in
#    .SYSTEM/TRASH and the desk accessories' list from APPS; Note Pad from
#    APPS with its Note File; Veranda Edit from APPS saving to /DOCUMENTS;
#    the old pin starting Paint from APPS, its saves in /DOCUMENTS; open
#    with: NOTES.TXT (Veranda Edit), song.mod (the MOD Player); BASIC
#    (keep Veranda) and LOAD"RBOOT" from /VERANDA; BOOT (AUTOBOOT.X16)
# 4. a second start on the migrated card: Setup does not run again
set -e
cd "$(dirname "$0")/.."
TOP=$PWD
OUT=build/gate/layout
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49=${LAYOUT_R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || R49=$ROM
X16MOD=${X16MOD:-$HOME/Projects/x16-mod}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
skip() { echo "SKIP  $*"; }

rm -rf "$OUT"
mkdir -p "$OUT/apps"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$TOP/$OUT/sdk
A=$TOP/$OUT/apps
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }

# the programs, each as "<its GEOS name>.cvt" in $A
build() {               # $1 the app's folder, $2 the make target, $3.. its outputs
	local d=$1 t=$2 b=$OUT/b/$(basename "$1")-$2
	shift 2
	mkdir -p "$b"
	make -s -C "$d" $t SDK="$SDK" OUT="$TOP/$b" >"$b/build.log" 2>&1 || { tail -20 "$b/build.log"; fail "$d ($t) does not build"; }
	for f in "$@"; do
		cp "$b/$f" "$A/$(field "$b/$f" name).cvt"
	done
}
mkdir -p "$OUT/b/shell"
cp -r shell "$OUT/b/shell/src"
rm -f "$OUT/b/shell/src"/*.cvt "$OUT/b/shell/src"/*.bin "$OUT/b/shell/src"/*.map
make -s -C "$OUT/b/shell/src" SDK="$SDK" >"$OUT/b/shell/build.log" 2>&1 || { tail -20 "$OUT/b/shell/build.log"; fail "the shell does not build"; }
build apps/setup all Setup.cvt
build apps/paint test Paint.cvt
build apps/edit test Edit.cvt
for a in notepad:NotePad dex:Dex calendar:Calendar prefs:Preferences calc:Calculator view:View \
		archive:Archive term:Term fonted:FontEd; do
	build "apps/${a%%:*}" all "${a#*:}.cvt"
done
build apps/scrapman all PhotoMgr.cvt TextMgr.cvt
MOD=0
if [ -d "$X16MOD/examples/veranda" ]; then
	if make -s -C "$X16MOD" veranda VSDK="$SDK" >"$OUT/b/mod.log" 2>&1 && [ -f "$X16MOD/build/veranda/MOD Player.cvt" ]; then
		cp "$X16MOD/build/veranda/MOD Player.cvt" "$A/"
		MOD=1
	else
		tail -5 "$OUT/b/mod.log"
		skip "the MOD Player does not build in $X16MOD (its run is left out)"
	fi
else
	skip "no x16-mod tree at $X16MOD (the MOD Player's run is left out)"
fi
[ "$(field "$A/Veranda Setup.cvt" 'geos type')" = 6 ] || fail "Veranda Setup.cvt is not an application"
ok "built: the kernel, the SDK, the shell, Veranda Setup, $(ls "$A" | wc -l) programs ($(ls "$A" | sed 's/\.cvt$//' | tr '\n' ',' | sed 's/,$//; s/,/, /g'))"

# ---------------------------------------------------------------- the old card
OLD=$OUT/old
mkdir -p "$OLD/VERANDA"
cp build/VERANDA.PRG build/VERANDA.SYS build/RBOOT "$OUT/b/shell/src/SHELL.cvt" "$OLD/VERANDA/"
cp build/VERANDA.PRG "$OLD/VERANDA/AUTOBOOT.X16"
for f in "$A"/*.cvt; do cp "$f" "$OLD/VERANDA/"; done
$PY tests/layout_gate.py card "$OLD" || fail "the old card's files"
$PY tests/layout_gate.py inventory "$OLD" "$OUT/before.json" || fail "the inventory"
ok "the old card: $(find "$OLD" -type f | wc -l) files, everything in /VERANDA ($(ls "$OLD/VERANDA" | wc -l) entries) and DOCUMENTS/NOTES.TXT"

# a run: $1 the name, $2 the card's folder (copied), $3 the ROM, $4 seconds,
# $5 how it starts (load: DOS"CD:VERANDA", LOAD"VERANDA.PRG", RUN; boot:
# DOS"CD:VERANDA", BOOT). The card's files after: $OUT/<name>/out; $6 the session's script (default $1)
run() {
	local d=$OUT/$1
	rm -rf "$d"
	mkdir -p "$d"
	cp -r "$2" "$d/card"
	$PY tests/layout_gate.py script "${6:-$1}" "$d/card" || fail "$1: the script"
	$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || fail "$1: vcard make"
	if [ "$5" = boot ]; then
		printf 'DOS"CD:VERANDA"\nBOOT\n' > "$d/start.txt"
	else
		printf 'DOS"CD:VERANDA"\nLOAD"VERANDA.PRG"\nRUN\n' > "$d/start.txt"
	fi
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT "$4" "$EMU" -rom "$3" -sdcard sd.img -bas start.txt \
		-warp -sound none -echo -dump RV > console.txt 2>&1) || true
	mkdir -p "$d/out"
	$PY tools/vcard.py ls "$d/sd.img" | while read -r line; do
		f=$(echo "$line" | sed 's/ *[0-9]*$//')
		case "$f" in */) mkdir -p "$d/out/$f"; continue ;; esac
		mkdir -p "$d/out/$(dirname "$f")"
		$PY tools/vcard.py get "$d/sd.img" "$f" "$d/out/$f" >/dev/null
	done
}

echo "== the old card booted (under $R49): Veranda Setup moves it"
run migrate "$OLD" "$R49" 300 load
[ -f "$OUT/migrate/dump.bin" ] || { tail -20 "$OUT/migrate/console.txt"; fail "migrate: the session did not end"; }
tr -d '\r' < "$OUT/migrate/console.txt" | grep -a -o 'SETUP [A-Z]*[^C]*' | sed 's/CD:.*//' | head -40 > "$OUT/setup.txt" || true
rm -f "$OUT/migrate/out/SHELL.TST" "$OUT/migrate/out/SHELL.STP" "$OUT/migrate/out/dump.bin"
$PY tests/layout_gate.py check "$OUT/before.json" "$OUT/migrate/out" "$OUT/migrate/console.txt" || fail "the migration"
$PY tools/vram2png.py --color "$OUT/migrate/dump.bin" "$OUT/migrated.png" >/dev/null || fail "vram2png"
ok "the shell on the migrated card: $OUT/migrated.png (Setup's moves: $OUT/setup.txt)"
M=$OUT/migrated
rm -rf "$M"
cp -r "$OUT/migrate/out" "$M"
rm -f "$M/SHELL.TST" "$M/SHELL.STP"

echo "== the migrated card"
run theme "$M" "$ROM" 120 load
[ -f "$OUT/theme/dump.bin" ] || { tail -10 "$OUT/theme/console.txt"; fail "theme: the session did not end"; }
grep -a -q 'SETUP RUNNING' "$OUT/theme/console.txt" && fail "Setup ran again on the migrated card"
$PY tests/check_theme.py bars "$OUT/theme/dump.bin" 15 0 12 >/dev/null || fail "the settings (Graphite) not found in VERANDA/.SYSTEM"
ok "a new start on the migrated card: Setup did not run again (LAYOUT.LOG); the settings from VERANDA/.SYSTEM/Veranda Prefs.cvt (Graphite's colours in the colour map)"

run look "$M" "$ROM" 120 load
[ -f "$OUT/look/dump.bin" ] || { tail -10 "$OUT/look/console.txt"; fail "look: the session did not end"; }
$PY tests/layout_gate.py after look "$OUT/look/out" "$OUT/look/console.txt" || fail "look"
$PY tools/vram2png.py --color "$OUT/look/dump.bin" "$OUT/accessories.png" >/dev/null || fail "vram2png"

# the runs that end in a program that does not quit: the console
run note "$M" "$ROM" 60 load
$PY tests/layout_gate.py after note "$OUT/note/out" "$OUT/note/console.txt" || fail "note"
# (V168) Note Pad over the shell on a picture wallpaper (Dusk), at 512 KB:
# the desktop's banks lent to the accessory, the picture read again after
MP=$OUT/migrated-pic
rm -rf "$MP"
cp -r "$M" "$MP"
mkdir -p "$MP/VERANDA/WALLPAPERS"
$PY tools/mkwall.py -o "$MP/VERANDA/WALLPAPERS/Dusk.cvt" --dusk >/dev/null 2>&1 || fail "mkwall --dusk"
$PY -c 'import sys
c = bytearray(64)
c[0:3] = b"WP\x01"
c[8:12] = b"Dusk"
c[32:51] = b"/VERANDA/WALLPAPERS"
open(sys.argv[1], "wb").write(bytes(c))' "$MP/VERANDA/.SYSTEM/WALLPAPER.CFG"
run notepic "$MP" "$ROM" 60 load note
grep -a -q "SHELL WALLPAPER ON" "$OUT/notepic/console.txt" || fail "notepic: no picture wallpaper"
$PY tests/layout_gate.py after note "$OUT/notepic/out" "$OUT/notepic/console.txt" || fail "notepic"
ok "Note Pad over the shell on the Dusk wallpaper at 512 KB: the desktop's banks lent to it (V168)"
run edit "$M" "$ROM" 120 load
$PY tests/layout_gate.py after edit "$OUT/edit/out" "$OUT/edit/console.txt" || fail "edit"
run paint "$M" "$ROM" 240 load
$PY tests/layout_gate.py after paint "$OUT/paint/out" "$OUT/paint/console.txt" || fail "paint"
run txt "$M" "$ROM" 60 load
$PY tests/layout_gate.py after txt "$OUT/txt/out" "$OUT/txt/console.txt" || fail "txt"
if [ $MOD = 1 ]; then
	run mod "$M" "$ROM" 60 load
	$PY tests/layout_gate.py after mod "$OUT/mod/out" "$OUT/mod/console.txt" || fail "mod"
fi
run basic "$M" "$ROM" 120 load
$PY tests/layout_gate.py after basic "$OUT/basic/out" "$OUT/basic/console.txt" || fail "basic"
run boot "$M" "$R49" 120 boot
$PY tests/layout_gate.py after boot "$OUT/boot/out" "$OUT/boot/console.txt" || fail "boot"
ok "BOOT in /VERANDA (AUTOBOOT.X16, a copy of VERANDA.PRG) under $R49: the shell in /DOCUMENTS"
echo "screenshots: $OUT/migrated.png (the shell on the migrated card), $OUT/accessories.png (the trash, the accessories' list)"
echo "GATE layout: PASS"
