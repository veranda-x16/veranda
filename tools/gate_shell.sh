#!/bin/bash
# Gate shell (docs/PLAN.md phase 6): a scripted session opens two
# applications and returns, and opens two plain files with the application
# that declares their extension (DECISIONS V41).
#
#   tools/gate_shell.sh
#
# 1. make api, the kernel, the SDK (build/gate/shell/sdk); the shell
#    (shell/) built against the installed SDK only; two tiny applications
#    (tests/shell_app.s: each logs "APP n RAN" and returns to the shell
#    with EnterDeskTop 30 frames later, in its own colours: the shell
#    starts in Veranda's, the colour map hidden)
# 2. a run folder: VERANDA.PRG/SYS, SHELL.cvt, AppOne.cvt, AppTwo.cvt,
#    Note.txt, Junk.txt, Docs/Readme.txt and SHELL.TST, the script
#    (tests/shell_script.py: the shell plays part n at its n-th start,
#    counted in SHELL.STP)
# 3. the console's order: the shell, app 1, the shell, app 2, the shell,
#    SHELL DONE; the files on the host after part 2 (open a folder, up,
#    duplicate, rename, delete, two video modes, refresh); the shell's
#    screen as a PNG (build/gate/shell/shell.png)
# 4. the same on an SD card image (tools/vcard.py)
# 5. the file utilities (shell/files.c, DECISIONS V61), in run folders of
#    their own (tests/shell_files_script.py): find a file three folders
#    down and reveal it, copy a folder tree, move a folder into another,
#    delete a file and a folder to the trash, edit a description (get
#    info), checked on the host; on an SD card image too; then empty the
#    trash, cancel a copy from its progress box; PNGs of the find results
#    and the progress box (build/gate/shell/files-*.png)
# 6. the shell's own folder (DECISIONS V63; tests/shell_script.py --home):
#    the shell in /VERANDA starts AppGo, which changes to /Mods (ChDir and
#    curDirName, as Veranda Calc does) and quits: the shell is back in
#    /VERANDA; Docs/Readme.txt opened with AppGo: it sees /VERANDA/Docs,
#    goes to /Mods, quits: the shell is back in /VERANDA/Docs; AppCrash
#    goes to /Mods and crashes: the panic box's OK, the shell in
#    /VERANDA/Docs; on the host folder and an SD card image
# 7. the theme (DECISIONS V65, Veranda Look 2: V74; tests/check_theme.py
#    reads the palette, the colour map and the pointer in the dump): with
#    no settings file (Veranda) Look 2's palette, the menu bar on the
#    chrome with the mark on cyan, the title bar on the accent, the
#    selected icon on the highlight, the pointer white with a dark
#    outline; the bar's item 0 open shows in the highlight colour (its
#    sub menu covers its cards), and closed (a click outside, then
#    Veranda > About and its box) the colours are back; dark mode (the
#    settings' byte 14): the dark palette; settings files of each preset
#    (Graphite and a custom theme saved before Look 2: converted; Mint;
#    Classic: no colour map at all, also dark), read at start-up; on the
#    host folder and an SD card image; PNGs build/gate/shell/theme-*.png
# 8. (V182) the trash from /VERANDA/APPS in the list (tests/shell_trash_script.py):
#    a geoWrite document and a long-named one deleted from APPS (file >
#    delete, the Del key), one from /DOCUMENTS (~2 in the trash), each
#    gone from its list at once and in the trash's; one deleted for good
#    there; the trash folder, SHELL.cvt, APPS kept; empty trash; on the
#    host folder and an SD card image
# 9. (V185) the mouse wheel (tests/shell_wheel_script.py): /VERANDA/APPS in
#    the list and the icons, a notch down and up over window 0: 3 rows or
#    a row of icons and back; nothing at the top or off the windows
# 10. (V193) the dragged icon's ghost (tests/shell_ghost_script.py): a
#    document dragged out of window 0 (the button held at the end): sprite
#    2 on, 8 bpp, at the pointer less the press's place in the icon, each
#    of its pixels the screen's colour at the icon (every other left out);
#    on over the dock; a desktop icon; a dock pin; in Sunroom, dark mode and
#    on the tile wallpaper (Dusk); let go: gone; Esc over the dock's trash:
#    gone and nothing deleted. Screenshots with the sprites drawn:
#    build/gate/shell/ghost-*.png
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/shell}
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

# the shell, from a copy of shell/ (the installed SDK only)
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
C=$OUT/src/SHELL.cvt
[ "$(field "$C" 'geos type')" = 6 ] && [ "$(field "$C" veranda)" = True ] || fail "SHELL.cvt: not a Veranda application"
end=$(field "$C" end)
[ $((16#${end#\$})) -le $((16#8000)) ] || fail "SHELL.cvt ends at $end (the C stack is at \$8000)"
# (the resident part below $8000; the overlays at $A000, each in a RAM bank of its own: V37)
top=$(sed -n '/^Segment list/,/^$/s/^[A-Z]* *00[0-9][0-9A-F]* *\([0-9A-F]*\).*/\1/p' "$OUT/src/shell.map" | sort | tail -1)
[ $((16#$top)) -lt $((16#8000)) ] || fail "the shell's memory reaches \$$top"
novl=$(sed -n '/^Segment list/,/^$/p' "$OUT/src/shell.map" | grep -c '^OVERLAY')
ok "the shell builds against the installed SDK: SHELL.cvt, a Veranda application, \$0801-\$${top#00}, $novl banked overlays"
$PY tools/check_ovl.py shell || fail "a call between overlays not through XCALL (tools/check_ovl.py)"
ok "every call between the shell's overlays goes through its trampoline (tools/check_ovl.py)"

# the two applications
A=$OUT/apps
mkdir -p "$A"
for n in 1 2; do
	nm=$([ $n = 1 ] && echo AppOne || echo AppTwo)
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$n -o "$A/app$n.o" tests/shell_app.s || fail "tests/shell_app.s"
	ld65 -C "$SDK/cfg/app.cfg" -o "$A/app$n.bin" "$A/app$n.o" || fail "tests/shell_app.s does not link"
	printf 'name = %s\nclass = Test%s\nmode = 640x480\napi = 1\nicon = %s\n' $nm $n \
		"$SDK/template/c/icon.pbm" > "$A/app$n.hdr"
	[ $n = 1 ] && echo "documents = TXT" >> "$A/app$n.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/app$n.hdr" "$A/app$n.bin" >/dev/null || fail "vpack $nm"
done
[ "$(field "$A/AppOne.cvt" documents)" = TXT ] || fail "AppOne.cvt: its documents are not TXT (vpack.py)"
ok "two applications: AppOne.cvt (it opens .txt files: info block 144-159), AppTwo.cvt"

# the files of a run ($1)
files() {
	mkdir -p "$1/Docs"
	cp "$C" "$A/AppOne.cvt" "$A/AppTwo.cvt" build/VERANDA.SYS "$1/"
	echo "a note" > "$1/Note.txt"
	echo "junk" > "$1/Junk.txt"
	echo "read me" > "$1/Docs/Readme.txt"
}

# the console's order: $1 console, $2 where
order() {
	got=$(tr -d '\r' < "$1" | grep -a -o -E 'SHELL STARTED|APP [12] RAN|APP 1 DOC [A-Za-z.]* IN [/A-Za-z]*|SHELL DONE' | tr '\n' ',')
	want="SHELL STARTED,APP 1 RAN,SHELL STARTED,APP 2 RAN,SHELL STARTED,APP 1 RAN,APP 1 DOC Note.txt IN /,"
	want="${want}SHELL STARTED,APP 1 RAN,APP 1 DOC Readme.txt IN /Docs,SHELL STARTED,SHELL DONE,"
	[ "$got" = "$want" ] || { tail -20 "$1"; fail "$2: the console has $got"; }
	ok "$2: the shell started app 1, app 1 returned, app 2, it returned; Note.txt opened with app 1 (its documents), Docs/Readme.txt too (app 1 in the top folder, the document's folder in curDirName); SHELL DONE (the console in order)"
}

# the files after the session: $1 the folder, $2 where
after() {
	[ "$(cat "$1/Note.txt")" = "a note" ] || fail "$2: Note.txt changed"
	[ -f "$1/Memo.txt" ] && cmp -s "$1/Note.txt" "$1/Memo.txt" || fail "$2: no Memo.txt equal to Note.txt (duplicate, rename)"
	[ ! -e "$1/Copy of Note.txt" ] || fail "$2: Copy of Note.txt is still there (rename)"
	[ ! -e "$1/Junk.txt" ] || fail "$2: Junk.txt is still there (delete)"
	[ "$(cat "$1/Docs/Readme.txt")" = "read me" ] || fail "$2: Docs/Readme.txt"
	[ "$(od -An -tu1 "$1/SHELL.STP" | tr -d ' ')" = 5 ] || fail "$2: SHELL.STP is not 5 (five starts)"
	ok "$2: duplicate + rename made Memo.txt (= Note.txt), Junk.txt deleted, Docs untouched, five starts"
}

# on the host folder
H=$OUT/host
mkdir -p "$H"
files "$H"
cp build/VERANDA.PRG "$H/"
$PY tests/shell_script.py "$H" console.txt || fail "the script"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "host folder: the session did not end (no dump)"; }
order "$H/console.txt" "host folder"
after "$H" "host folder"
$PY tools/vram2png.py "$H/dump.bin" "$OUT/shell.png" || fail "vram2png"
$PY tools/check_vera.py "$H/dump.bin" || fail "host folder: the display does not show the bitmap"
$PY tests/check_theme.py bars "$H/dump.bin" 3 14 5 \
	|| fail "host folder: the shell is not in Veranda's colours with the default theme"
ok "the shell after an application in its own colours (paper yellow, ink red, the colour map): Look 2's palette (white paper, slate ink), the theme's colour map (no settings file: Sunroom, V132)"
ok "the shell's screen at the end: $OUT/shell.png"

# on an SD card image: the card holds the files; the folder only VERANDA.PRG
S=$OUT/sd
mkdir -p "$S/card"
files "$S/card"
$PY tests/shell_script.py "$S/card" || fail "the script"
$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$S/"
(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$S/dump.bin" ] || { tail -20 "$S/console.txt"; fail "SD card: the session did not end (no dump)"; }
order "$S/console.txt" "SD card"
mkdir -p "$S/out"
$PY tools/vcard.py ls "$S/sd.img" | while read -r line; do
	f=$(echo "$line" | sed 's/ *[0-9]*$//')         # (names may have spaces)
	case "$f" in */) continue ;; esac
	mkdir -p "$S/out/$(dirname "$f")"
	$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null
done
after "$S/out" "SD card"
$PY tools/vram2png.py "$S/dump.bin" "$OUT/shell-sd.png" || fail "vram2png"
$PY tools/check_vera.py "$S/dump.bin" || fail "SD card: the display does not show the bitmap"
$PY tests/check_theme.py bars "$S/dump.bin" 3 14 5 || fail "SD card: the theme's colours"
# another desktop (DECISIONS V46): with DESKTOP.cvt there, EnterDeskTop
# starts it instead of SHELL.cvt (AppOne quits to AppTwo as DESKTOP.cvt)
D=$OUT/desktop
mkdir -p "$D"
cp "$C" build/VERANDA.SYS build/VERANDA.PRG "$D/"
cp "$A/AppOne.cvt" "$D/AUTOSTART.cvt"
cp "$A/AppTwo.cvt" "$D/DESKTOP.cvt"
(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 30 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > ../desktop-console.txt 2>&1) || true
got=$(grep -a -o -E 'SHELL STARTED|APP [12] RAN' "$OUT/desktop-console.txt" | head -3 | tr '\n' ',')
[ "$got" = "APP 1 RAN,APP 2 RAN,APP 2 RAN," ] || fail "DESKTOP.cvt: the console has $got"
ok "with DESKTOP.cvt there, EnterDeskTop starts it, not SHELL.cvt (AppOne, then AppTwo as DESKTOP.cvt, twice)"
# the shell's own folder (DECISIONS V63): applications change curDirName
for n in 3 4; do
	nm=$([ $n = 3 ] && echo AppGo || echo AppCrash)
	def=$([ $n = 4 ] && echo "-D CRASH" || true)
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$n -D GO $def -o "$A/app$n.o" tests/shell_app.s || fail "tests/shell_app.s ($nm)"
	ld65 -C "$SDK/cfg/app.cfg" -o "$A/app$n.bin" "$A/app$n.o" || fail "tests/shell_app.s does not link ($nm)"
	printf 'name = %s\nclass = Test%s\nmode = 640x480\napi = 1\nicon = %s\n' $nm $n \
		"$SDK/template/c/icon.pbm" > "$A/app$n.hdr"
	[ $n = 3 ] && echo "documents = TXT" >> "$A/app$n.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/app$n.hdr" "$A/app$n.bin" >/dev/null || fail "vpack $nm"
done
# (the layout of DECISIONS V71: SHELL.cvt in /VERANDA; the shell starts
# in /DOCUMENTS, made at its first start)
hfiles() {
	mkdir -p "$1/VERANDA" "$1/DOCUMENTS/Docs" "$1/Mods"
	cp "$C" "$1/VERANDA/"
	cp "$A/AppGo.cvt" "$1/DOCUMENTS/"
	cp "$A/AppGo.cvt" build/VERANDA.SYS "$1/"
	cp "$A/AppCrash.cvt" "$1/DOCUMENTS/Docs/"
	echo "read me" > "$1/DOCUMENTS/Docs/Readme.txt"
	$PY tests/shell_script.py --home "$1" || fail "the script (home)"
}
hwant="SHELL READY 0 IN /DOCUMENTS,APP 3 RAN,SHELL READY 1 IN /DOCUMENTS,APP 3 RAN,APP 3 DOC Readme.txt IN /DOCUMENTS/Docs,"
hwant="${hwant}SHELL READY 2 IN /DOCUMENTS/Docs,APP 4 RAN,PANIC,SHELL READY 3 IN /DOCUMENTS/Docs,SHELL DONE,"
hlog() {
	tr -d '\r' < "$1" | grep -a -o -E 'SHELL READY [0-9] IN [/A-Za-z]*|APP [34] RAN|APP 3 DOC [A-Za-z.]* IN [/A-Za-z]*|PANIC|SHELL DONE' \
		| tr '\n' ','
}
echo "== the shell's own folder"
HH=$OUT/home/host
mkdir -p "$HH"
hfiles "$HH"
cp build/VERANDA.PRG "$HH/"
(cd "$HH" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$HH/dump.bin" ] || { tail -20 "$HH/console.txt"; fail "home, host folder: the session did not end (no dump)"; }
[ "$(hlog "$HH/console.txt")" = "$hwant" ] || { tail -20 "$HH/console.txt"; fail "home, host folder: the console has $(hlog "$HH/console.txt")"; }
$PY tools/vram2png.py "$HH/dump.bin" "$OUT/home.png" || fail "vram2png"
ok "host folder: the shell started in /DOCUMENTS (V71); AppGo went to /Mods and quit: the shell back in /DOCUMENTS; Readme.txt opened with AppGo, in /DOCUMENTS/Docs (curDirName); it went to /Mods: the shell back in /DOCUMENTS/Docs; AppCrash went to /Mods and crashed: the panic box's OK, the shell in /DOCUMENTS/Docs ($OUT/home.png)"
HS=$OUT/home/sd
mkdir -p "$HS/card"
hfiles "$HS/card"
$PY tools/vcard.py make --mb 64 "$HS/sd.img" "$HS/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$HS/"
(cd "$HS" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
[ "$(hlog "$HS/console.txt")" = "$hwant" ] || { tail -20 "$HS/console.txt"; fail "home, SD card: the console has $(hlog "$HS/console.txt")"; }
ok "SD card: the same session, the shell back in its own folder each time"

# a document whose application is missing opens with a substitute
# (DECISIONS V135; shell/dir.c's tSubst; tests/shell_subst.py): geoWrite's
# documents with Veranda Write. Two stubs (tests/shell_app.s) of the
# classes: Veranda Write's (APPN 5, "CmdrWrite   V0.1", the package's
# Veranda Write.cvt's when it is there: CWAPP) and geoWrite's (APPN 6)
CWAPP=${CWAPP:-$HOME/Projects/commander-write/build/veranda/Veranda Write.cvt}
for n in 5 6; do
	nm=$([ $n = 5 ] && echo "Veranda Write" || echo geoWrite)
	cl=$([ $n = 5 ] && echo "CmdrWrite" || echo geoWrite)
	ve=$([ $n = 5 ] && echo 0.1 || echo 2.1)
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$n -o "$A/app$n.o" tests/shell_app.s || fail "tests/shell_app.s ($nm)"
	ld65 -C "$SDK/cfg/app.cfg" -o "$A/app$n.bin" "$A/app$n.o" || fail "tests/shell_app.s does not link ($nm)"
	printf 'name = %s\nclass = %s\nversion = %s\nmode = 640x480\napi = 1\nicon = %s\n' "$nm" $cl $ve \
		"$SDK/template/c/icon.pbm" > "$A/app$n.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/app$n.hdr" "$A/app$n.bin" >/dev/null || fail "vpack $nm"
done
[ "$(field "$A/Veranda Write.cvt" class)" = "CmdrWrite   V0.1" ] || fail "the Veranda Write stub's class: $(field "$A/Veranda Write.cvt" class)"
if [ -f "$CWAPP" ]; then
	[ "$(field "$CWAPP" class)" = "CmdrWrite   V0.1" ] || fail "$CWAPP: its class is $(field "$CWAPP" class), not the stub's"
	ok "Veranda Write's class (the package's $CWAPP) is the stub's: CmdrWrite   V0.1"
fi
sfiles() {              # $1 the folder, $2 subst or geowrite
	mkdir -p "$1/VERANDA/APPS" "$1/DOCUMENTS"
	cp "$C" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
	cp "$A/Veranda Write.cvt" "$1/VERANDA/APPS/"
	[ "$2" = geowrite ] && cp "$A/geoWrite.cvt" "$1/VERANDA/APPS/"
	$PY tests/shell_subst.py "$1" "$2" || fail "the script (subst, $2)"
}
slog() {
	tr -d '\r' < "$1" | grep -a -o -E 'SHELL READY [0-9] IN [/A-Za-z]*|APP [56] RAN|APP [56] DOC [A-Za-z]* IN [/A-Za-z]*|No application opens this document\.|SHELL DONE' \
		| tr '\n' ','
}
srun() {                # $1 the folder (host)
	cp build/VERANDA.PRG "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -20 "$1/console.txt"; fail "$1: the session did not end (no dump)"; }
}
echo "== a document's substitute application (V135)"
swant="SHELL READY 0 IN /DOCUMENTS,APP 5 RAN,APP 5 DOC GeoLetter IN /DOCUMENTS,SHELL READY 1 IN /DOCUMENTS,"
swant="${swant}No application opens this document.,SHELL DONE,"
SU=$OUT/subst/host
sfiles "$SU" subst
srun "$SU"
[ "$(slog "$SU/console.txt")" = "$swant" ] || { tail -20 "$SU/console.txt"; fail "subst, host folder: the console has $(slog "$SU/console.txt")"; }
ok "host folder: GeoLetter (Write Image V2.1, its parent geoWrite missing) opened with Veranda Write (/VERANDA/APPS), by its GEOS name, in /DOCUMENTS; Mystery (an unknown class): \"No application opens this document.\""
gwant="SHELL READY 0 IN /DOCUMENTS,APP 6 RAN,APP 6 DOC GeoLetter IN /DOCUMENTS,SHELL READY 1 IN /DOCUMENTS,SHELL DONE,"
SG=$OUT/subst/geowrite
sfiles "$SG" geowrite
srun "$SG"
[ "$(slog "$SG/console.txt")" = "$gwant" ] || { tail -20 "$SG/console.txt"; fail "subst, geoWrite there: the console has $(slog "$SG/console.txt")"; }
ok "host folder, geoWrite installed too: GeoLetter opened with geoWrite, its parent (the substitute only when the parent is missing)"
SS=$OUT/subst/sd
sfiles "$SS/card" subst
$PY tools/vcard.py make --mb 64 "$SS/sd.img" "$SS/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$SS/"
(cd "$SS" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
[ "$(slog "$SS/console.txt")" = "$swant" ] || { tail -20 "$SS/console.txt"; fail "subst, SD card: the console has $(slog "$SS/console.txt")"; }
ok "SD card: the same session"

# the file utilities (shell/files.c, DECISIONS V61): find, copying and
# moving folders, the trash, get info (tests/shell_files_script.py). The
# run folders have a /VERANDA holding SHELL.cvt and a /DOCUMENTS, where
# the shell starts (DECISIONS V71); the trash is /VERANDA/.SYSTEM/TRASH.
FS="$PY tests/shell_files_script.py"
fprep() {               # $1 the folder, $2 make or make-big
	mkdir -p "$1/VERANDA" "$1/DOCUMENTS"
	$FS "$2" "$1" || fail "the fixtures ($2)"
	cp "$C" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
}
frun() {                # $1 the folder (host), $2 seconds
	cp build/VERANDA.PRG "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$2" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -5 "$1/console.txt"; fail "$1: the session did not end"; }
}
flog() {
	tr -d '\r' < "$1" | grep -a -o -E 'SHELL (FOUND|HIT|REVEAL|OPEN|PICKED TO COPY|PICKED TO MOVE|COPIED|MOVED|TRASHED|INFO|EMPTIED|STOPPED|DONE)[[:print:]]*' \
		| tr '\n' ','
}
fwant="SHELL HIT /A/B/C/Deep.txt,SHELL FOUND 1,SHELL REVEAL /A/B/C Deep.txt,SHELL PICKED TO COPY Tree,SHELL COPIED 4,"
fwant="${fwant}SHELL PICKED TO MOVE Mover,SHELL MOVED 2,SHELL TRASHED Gone.txt AS Gone.txt,SHELL TRASHED Old AS Old,"
fwant="${fwant}SHELL INFO Info.cvt: Edited by the gate.,SHELL DONE,"

echo "== the file utilities: find, copy and move folders, the trash, get info"
FA=$OUT/files/host
fprep "$FA" make
cp -r "$FA" "$OUT/files/before"
$FS a "$FA" console.txt || fail "the script (a)"
frun "$FA" 180
[ "$(flog "$FA/console.txt")" = "$fwant" ] || fail "host folder: the console has $(flog "$FA/console.txt")"
ok "host folder: find deep* gave /A/B/C/Deep.txt, revealed; Tree copied into Dest (4 files), Mover moved into Box (2), Gone.txt and Old to the trash, Info's description edited (the console in order)"
$FS check-a "$OUT/files/before" "$FA" || fail "host folder: the files"
ok "host folder: the files on the host after the session"
$PY tools/vram2png.py "$FA/dump.bin" "$OUT/files-end.png" || fail "vram2png"

FD=$OUT/files/sd
fprep "$FD/card" make
$FS a "$FD/card" || fail "the script (a, SD)"
$PY tools/vcard.py make --mb 64 "$FD/sd.img" "$FD/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$FD/"
(cd "$FD" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
[ "$(flog "$FD/console.txt")" = "$fwant" ] || fail "SD card: the console has $(flog "$FD/console.txt")"
mkdir -p "$FD/out"
$PY tools/vcard.py ls "$FD/sd.img" | while read -r line; do
	f=$(echo "$line" | sed 's/ *[0-9]*$//')
	case "$f" in */) mkdir -p "$FD/out/$f"; continue ;; esac
	mkdir -p "$FD/out/$(dirname "$f")"
	$PY tools/vcard.py get "$FD/sd.img" "$f" "$FD/out/$f" >/dev/null
done
$FS check-a "$OUT/files/before" "$FD/out" || fail "SD card: the files"
ok "SD card: the same session, the same files"

FF=$OUT/files/find
fprep "$FF" make
$FS find "$FF" console.txt || fail "the script (find)"
frun "$FF" 60
$PY tools/vram2png.py "$FF/dump.bin" "$OUT/files-find.png" || fail "vram2png"
ok "find's results: $OUT/files-find.png"

FB=$OUT/files/big
fprep "$FB" make-big
cp -r "$FB" "$OUT/files/big-before"
$FS b "$FB" console.txt || fail "the script (b)"
frun "$FB" 180
$FS check-b "$OUT/files/big-before" "$FB" "$FB/console.txt" || fail "host folder: empty trash, cancel"
ok "host folder: disk > empty trash emptied it; a copy of 40 files cancelled from its progress box"

FP=$OUT/files/progress
fprep "$FP" make-big
$FS progress "$FP" console.txt || fail "the script (progress)"
frun "$FP" 120
$PY - "$FP/dump.bin" <<'EOF' || fail "the progress box is not on the screen"
import sys
sys.path.insert(0, 'tools')
import vram2png
v = vram2png.section(sys.argv[1])
bit = lambda x, y: v[y * 80 + x // 8] >> (7 - x % 8) & 1
sys.exit(0 if all(bit(x, 190) and bit(x, 279) for x in range(160, 480)) and all(bit(160, y) for y in range(190, 280)) else 1)
EOF
$PY tools/vram2png.py "$FP/dump.bin" "$OUT/files-progress.png" || fail "vram2png"
ok "the progress box during a copy: $OUT/files-progress.png"

# (V182) the trash from /VERANDA/APPS, in the list (tests/shell_trash_script.py):
# the user's letter (a geoWrite document) in APPS could not be deleted:
# V71's vr_insys refused all of /VERANDA ("Use file > empty trash.", the
# wrong menu too). A package's APPS folder when there is one (APPS=<folder>,
# default the newest ~/Projects/veranda-dist/pkg-*), else three stubs
echo "== the trash from /VERANDA/APPS (V182)"
TS="$PY tests/shell_trash_script.py"
TAPPS=${APPS:-$(ls -td "$HOME"/Projects/veranda-dist/pkg-*/VERANDA/APPS 2>/dev/null | head -1)}
tprep() {               # $1 the folder
	mkdir -p "$1"
	$TS make "$1" $TAPPS || fail "the trash fixtures"
	cp "$C" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
	$TS script "$1" || fail "the trash script"
}
TH=$OUT/trash/host
tprep "$TH"
frun "$TH" 300
$TS check "$TH" "$TAPPS" "$TH/console.txt" || fail "trash, host folder"
$PY tools/vram2png.py "$TH/dump.bin" "$OUT/trash-end.png" || fail "vram2png"
ok "host folder: letter.cvt and a long-named document deleted from APPS (file > delete, the Del key) vanish from the list at once and are in the trash's window; /DOCUMENTS/letter.cvt there as letter~2.cvt, deleted for good from the trash; the trash folder, SHELL.cvt and APPS kept with a warning; empty trash 2; APPS ${TAPPS:-(three stubs)} otherwise unchanged"
TD=$OUT/trash/sd
tprep "$TD/card"
$PY tools/vcard.py make --mb 64 "$TD/sd.img" "$TD/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$TD/"
(cd "$TD" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
mkdir -p "$TD/out"
$PY tools/vcard.py ls "$TD/sd.img" | while read -r line; do
	f=$(echo "$line" | sed 's/ *[0-9]*$//')
	case "$f" in */) mkdir -p "$TD/out/$f"; continue ;; esac
	mkdir -p "$TD/out/$(dirname "$f")"
	$PY tools/vcard.py get "$TD/sd.img" "$f" "$TD/out/$f" >/dev/null
done
$TS check "$TD/out" "$TAPPS" "$TD/console.txt" || fail "trash, SD card"
ok "SD card: the same session, the same files"

# (V185) the mouse wheel scrolls the front window under the pointer
# (tests/shell_wheel_script.py; shell/play.s's wheel records): /VERANDA/APPS
# (the package's when there is one, else 36 stubs) in the list and in the
# icons; a notch down: 3 rows (FIRST 1, 2, 3: view_page's row step) or a
# row of icons; up again: back to the first page, window 0 pixel for pixel
# as before; a notch up at the top, over the desktop beside and below the
# window: nothing
echo "== the mouse wheel in the windows (V185)"
WS="$PY tests/shell_wheel_script.py"
COLS=$($PY -c 'import sys; sys.path.insert(0, "tests"); import shell_script as S; print(S.grid()[2])')
for view in list icon; do
	for run in ref down both; do
		WD=$OUT/wheel/$view-$run
		mkdir -p "$WD"
		$WS make "$WD" $TAPPS || fail "the wheel fixtures"
		cp "$C" "$WD/VERANDA/"
		cp build/VERANDA.SYS "$WD/"
		$WS script "$WD" $view $run || fail "the wheel script"
		frun "$WD" 120
		$WS check "$WD/console.txt" $view $run "$COLS" || fail "wheel, $view, $run"
	done
	$WS same "$OUT/wheel/$view-ref/dump.bin" "$OUT/wheel/$view-both/dump.bin" || fail "wheel, $view: up again"
	$PY tools/vram2png.py --color "$OUT/wheel/$view-down/dump.bin" "$OUT/wheel-$view.png" 2>/dev/null \
		|| $PY tools/vram2png.py "$OUT/wheel/$view-down/dump.bin" "$OUT/wheel-$view.png" || fail "vram2png"
	[ $view = list ] && n="3 rows" || n="a row of icons ($COLS)"
	ok "the wheel over the Apps window, $view: a notch down scrolls $n, up again the first page (window 0 as before); at the top, over the desktop beside and below the window: nothing ($OUT/wheel-$view.png)"
done

# (V193) the dragged icon's ghost: a sprite with the icon's own colours
echo "== the dragged icon's ghost (V193)"
GS="$PY tests/shell_ghost_script.py"
$PY "$SDK/tools/mkwall.py" -o "$OUT/Dusk.cvt" --dusk 2>/dev/null || fail "mkwall --dusk (the ghost on the tile desktop)"
for lr in light:mid light:over light:desk light:after light:esc dark:mid wall:mid wall:over ${TAPPS:+light:pin}; do
	look=${lr%%:*}
	run=${lr##*:}
	GD=$OUT/ghost/$look-$run
	rm -rf "$GD"
	mkdir -p "$GD"
	$GS make "$GD" $look "$OUT/Dusk.cvt" $TAPPS || fail "the ghost's fixtures"
	cp "$C" "$GD/VERANDA/"
	cp build/VERANDA.SYS "$GD/"
	$GS script "$GD" $run || fail "the ghost's script"
	frun "$GD" 120
	grep -a -q "SHELL DONE" "$GD/console.txt" || fail "ghost, $look $run: the session did not end"
	$GS check "$GD" $run || fail "ghost, $look $run"
	$GS png "$GD/dump.bin" "$OUT/ghost-$look-$run.png" || fail "the ghost's screenshot"
done
ok "the ghost: a document dragged from window 0 shows sprite 2 (8 bpp, 32 x 32, at the pointer less the press's place in the icon), each of its pixels the screen's colour at the icon, every other left out: in Sunroom, dark mode and on the tile desktop (Dusk); on over the dock; the card's desktop icon${TAPPS:+; a dock pin}; let go in its own window: gone; Esc over the dock's trash: gone, the file kept ($OUT/ghost-*.png)"

echo "== Shell 2: the desktop and its windows (DECISIONS V70)"
# tests/shell_desk_script.py: the card's icon opens window 1, both windows
# moved and resized, drags between them, onto the trash, the printer and
# the desktop (a pin), the list sorted three ways, paging, the pin started
DS="$PY tests/shell_desk_script.py"
desk() {                # $1 the name, $2 sd for an SD card image, $3 the ROM
	local d=$OUT/desk/$1
	mkdir -p "$d/card"
	$DS make "$d/card" "$A/AppOne.cvt" || fail "the desk fixtures"
	cp "$C" "$d/card/VERANDA/"
	cp build/VERANDA.SYS "$d/card/"
	if [ "$2" = sd ]; then
		$DS script "$d/card" || fail "the desk script"
		$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$d/"
		(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 200 "$EMU" -rom "$3" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump RV > console.txt 2>&1) || true
		[ -f "$d/dump.bin" ] || { tail -5 "$d/console.txt"; fail "$1: the session did not end"; }
		mkdir -p "$d/out"
		$PY tools/vcard.py ls "$d/sd.img" | while read -r line; do
			f=$(echo "$line" | sed 's/ *[0-9]*$//')
			case "$f" in */) mkdir -p "$d/out/$f"; continue ;; esac
			mkdir -p "$d/out/$(dirname "$f")"
			$PY tools/vcard.py get "$d/sd.img" "$f" "$d/out/$f" >/dev/null
		done
		$DS check "$d/out" "$d/console.txt" "$d/sd.img" || fail "$1"
	else
		cp build/VERANDA.PRG "$d/card/"
		$DS script "$d/card" console.txt || fail "the desk script"
		(cd "$d/card" && SDL_VIDEODRIVER=dummy timeout -s INT 200 "$EMU" -rom "$3" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump RV > console.txt 2>&1) || true
		[ -f "$d/card/dump.bin" ] || { tail -5 "$d/card/console.txt"; fail "$1: the session did not end"; }
		$DS check "$d/card" "$d/card/console.txt" || fail "$1"
		cp "$d/card/dump.bin" "$d/dump.bin"
	fi
	$PY tools/vram2png.py --color "$d/dump.bin" "$OUT/desk-$1.png" >/dev/null || fail "vram2png"
}
desk host "" "$ROM"
ok "host folder: windows moved and resized, drags between them, the trash, the printer, a pin, the list, pages ($OUT/desk-host.png)"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || R49=$ROM
desk sd sd "$R49"
ok "SD card image under $R49: the same session; the list's sizes and dates from CMDR-DOS's long listing (\$=L), the free Kbytes as the card's FSInfo has them ($OUT/desk-sd.png)"

echo "== the theme: the shell's colours (DECISIONS V65)"
# $1 the name, $2 the script (probe, menu, closed), $3 the settings
# ("accent desk hilite preset", or "" for none), $4 sd for an SD card image
theme() {
	local d=$OUT/theme/$1
	rm -rf "$d"
	mkdir -p "$d/card"
	cp "$C" build/VERANDA.SYS "$d/card/"
	[ -z "$3" ] || $PY tests/check_theme.py prefs "$d/card/Veranda Prefs.cvt" $3
	if [ "$4" = sd ]; then
		$PY tests/shell_script.py --theme "$d/card" "$2" || fail "the script ($1)"
		$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$d/"
		(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump RV > console.txt 2>&1) || true
		T=$d
	else
		$PY tests/shell_script.py --theme "$d/card" "$2" console.txt || fail "the script ($1)"
		cp build/VERANDA.PRG "$d/card/"
		(cd "$d/card" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump RV > console.txt 2>&1) || true
		T=$d/card
	fi
	[ -f "$T/dump.bin" ] || { tail -5 "$T/console.txt"; fail "$1: the session did not end"; }
	$PY tools/check_vera.py "$T/dump.bin" >/dev/null || fail "$1: the display"
	$PY tools/vram2png.py --color "$T/dump.bin" "$OUT/theme-$1.png" || fail "vram2png"
}
theme sunroom probe ""
$PY tests/check_theme.py bars "$T/dump.bin" 3 14 5 || fail "Sunroom (no settings file)"
grep -a "SHELL THEME 3 14 5" "$T/console.txt" | grep -a -q -v DARK || fail "Sunroom: the shell's log"
ok "Veranda Look 3's Sunroom (no settings file; V132): $OUT/theme-sunroom.png"
theme blue probe "5 13 4 0"
$PY tests/check_theme.py bars "$T/dump.bin" 5 13 4 || fail "Veranda (its preset saved)"
grep -a "SHELL THEME 5 13 4" "$T/console.txt" | grep -a -q -v DARK || fail "Veranda: the shell's log"
ok "Veranda Look 2's preset (a settings file): $OUT/theme-blue.png"
$PY tests/check_theme.py pointer "$T/dump.bin" || fail "the pointer"
theme menu menu ""
$PY tests/check_theme.py menu "$T/dump.bin" 5 || fail "the Veranda menu open"
ok "the menu bar's item 0 open: $OUT/theme-menu.png"
theme closed closed ""
$PY tests/check_theme.py bars "$T/dump.bin" 3 14 5 || fail "the bar's colours after the menu and a dialog box"
ok "the menu closed by a click outside it, then Veranda > About and OK: the bar's colours back"
theme dark probe "5 13 4 0 129"
$PY tests/check_theme.py bars "$T/dump.bin" 5 13 4 1 || fail "dark mode"
grep -a -q "SHELL THEME 5 13 4 DARK" "$T/console.txt" || fail "dark mode: the shell's log"
ok "dark mode (the settings' byte 14 bit 0): the dark palette, the same colour map: $OUT/theme-dark.png"
theme graphite probe "15 0 12 2 0"
$PY tests/check_theme.py bars "$T/dump.bin" 2 3 2 || fail "Graphite (a settings file saved before V74)"
ok "Graphite from a settings file saved before Look 2 (V65's colours): Look 2's Graphite: $OUT/theme-graphite.png"
theme mint probe "8 0 8 3" sd
$PY tests/check_theme.py bars "$T/dump.bin" 8 0 8 || fail "Mint (SD card)"
ok "Mint, on an SD card image: $OUT/theme-mint.png"
theme custom probe "14 15 7 4 0"
$PY tests/check_theme.py bars "$T/dump.bin" 5 2 6 || fail "a custom theme saved before V74"
ok "a custom theme saved before Look 2 (blue bars, a silver desktop, a yellow selection): Look 2's nearest (title blue, chrome, yellow): $OUT/theme-custom.png"
theme classic probe "0 0 0 1"
$PY tests/check_theme.py none "$T/dump.bin" || fail "Classic"
ok "Classic: no colour map at all, the shell as before: $OUT/theme-classic.png"
theme classicsd probe "0 0 0 1" sd
$PY tests/check_theme.py none "$T/dump.bin" || fail "Classic (SD card)"
ok "Classic on an SD card image"
theme classicdark probe "0 0 0 1 129"
$PY tests/check_theme.py none "$T/dump.bin" 1 || fail "Classic, dark"
ok "Classic in dark mode: no colour map, the dark paper and ink"

echo "== the tiles (Veranda Look 2, DECISIONS V77)"
# shell/tiles.h is tools/mktiles.py's from shell/tiles.txt; an application
# with a tile of its own (vpack's "tile": Paint's), a port known by its
# class (the shell's library: V207 VIDKIT Player's, was geoWrite's tile), one with only
# its GEOS icon (a chrome tile), a folder (yellow) and a plain file (the
# sidebar colour); their tiles' cards, and the own tile's pixels
$PY tools/mktiles.py shell/tiles.txt "$OUT/tiles.h" || fail "mktiles"
cmp -s "$OUT/tiles.h" shell/tiles.h || fail "shell/tiles.h is not tools/mktiles.py's from shell/tiles.txt"
ok "shell/tiles.h is tools/mktiles.py's from shell/tiles.txt"
TL=$OUT/tiles/card
rm -rf "$OUT/tiles"
mkdir -p "$TL/Docs"
for n in Tile Write Icon; do
	cls=$([ $n = Tile ] && echo TestTile || ([ $n = Icon ] && echo TestIcon) || echo VIDKITPlay)   # (V207: VIDKIT Player's class; was geoWrite's)
	printf 'name = App%s\nclass = %s\nmode = 640x480\napi = 1\nicon = %s\n' $n $cls "$SDK/template/c/icon.pbm" > "$A/app$n.hdr"
	[ $n = Tile ] && echo "tile = $PWD/apps/paint/tile.txt" >> "$A/app$n.hdr"
	[ $n = Icon ] && echo "icon3 = $PWD/apps/paint/icon.txt" >> "$A/app$n.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$TL/App$n.cvt" "$A/app$n.hdr" "$A/app1.bin" >/dev/null || fail "vpack App$n"
done
[ "$(field "$TL/AppTile.cvt" tile)" = "orange, 135 ink pixels" ] && [ "$(field "$TL/AppTile.cvt" flags)" = 2 ] \
	|| fail "vpack: AppTile.cvt's tile: $(field "$TL/AppTile.cvt" tile), flags $(field "$TL/AppTile.cvt" flags)"
[ -z "$(field "$TL/AppWrite.cvt" tile)" ] || fail "vpack: AppWrite.cvt has a tile"
[ "$(field "$TL/AppIcon.cvt" icon3)" = "15 tiles, 172 ink pixels" ] && [ "$(field "$TL/AppIcon.cvt" flags)" = 8 ] \
	|| fail "vpack: AppIcon.cvt's colour icon: $(field "$TL/AppIcon.cvt" icon3), flags $(field "$TL/AppIcon.cvt" flags)"
ok "vpack.py: AppTile.cvt with Paint's tile (orange; flags bit 1), AppWrite.cvt without one, AppIcon.cvt with Paint's colour icon (V133: flags bit 3, 15 tiles)"
cp "$C" build/VERANDA.SYS build/VERANDA.PRG "$A/AppTwo.cvt" "$TL/"
echo "a note" > "$TL/Note.txt"
# (V156) Veranda Write's documents: Page.cvt of geoWrite's class (Write Image V2.1, as
# tests/shell_subst.py makes them), Page.cwr one of its own (not a GEOS file)
$PY -c "import sys; sys.path.insert(0, 'tests'); import shell_subst as s
open(sys.argv[1], 'wb').write(s.cvt('Page', 'Write Image V2.1', 'geoWrite    V2.1', {0: b'x'}))" "$TL/Page.cvt" \
	|| fail "Page.cvt"
echo "CWR" > "$TL/Page.cwr"
# (V207) a MIDI file and an SPV video: the library's music and video documents (prg.c's ic3_ext)
echo "MThd" > "$TL/Page.mid"
echo "SPV" > "$TL/Page.spv"
$PY tests/shell_script.py --probe "$TL/SHELL.TST" || fail "the script (tiles)"
(cd "$TL" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump RV > console.txt 2>&1) || true
[ -f "$TL/dump.bin" ] || { tail -5 "$TL/console.txt"; fail "tiles: the session did not end"; }
# the top folder: Docs, AppIcon, AppTile, AppTwo, AppWrite, console.txt, Note.txt, Page.cvt, Page.cwr, Page.mid, Page.spv ...
# (V133: on the plain tile desktop: c a colour icon in palette row 12, its ink the source's 'K';
# V156: a file with no colour icon, AppTile's Look 2 tile and AppTwo's GEOS icon, its picture
# alone on the paper, no frame)
$PY tests/check_theme.py tiles "$TL/dump.bin" 0:c,1:c,2:0,3:0,4:c,6:c,7:c,8:c,9:c,10:c 2:-apps/paint/tile.txt 1:apps/paint/icon.txt \
	0:Folder@shell/icons3.txt "4:VIDKIT Player@shell/icons3.txt" 6:Document@shell/icons3.txt \
	"7:Veranda Write document@shell/icons3.txt" "8:Veranda Write document@shell/icons3.txt" \
	"9:Music document@shell/icons3.txt" "10:Video document@shell/icons3.txt" || fail "the tiles"
$PY tests/check_theme.py bars "$TL/dump.bin" 3 14 5 || fail "the tiles: the colour map"
$PY tools/vram2png.py --color "$TL/dump.bin" "$OUT/tiles.png" || fail "vram2png"
ok "the tiles on the plain tile desktop (V133): Docs the library's folder, AppIcon its own colour icon (Paint's, from its file's end), AppTile its own Look 2 tile's pixels alone on the paper and AppTwo its GEOS icon so (V156: no colour icon, no frame), AppWrite the library's VIDKIT Player (V207), Note.txt the library's document, Page.cvt (geoWrite's class) and Page.cwr the library's Veranda Write document (V156), Page.mid and Page.spv the library's music and video documents (V207: past its records, after overlay 17): $OUT/tiles.png"
# the folder's sort (DECISIONS V80): a folder of 59 files whose names are
# alike for 5 characters, in the reverse of their order; the shell logs
# the sort's time (TIME SORT <entries> <cycles>); cc65's qsort took
# 7,635,000 cycles (954 ms) for this folder, the insertion sort 418,000
SR=$OUT/sort
rm -rf "$SR"
mkdir -p "$SR"
for i in $(seq 1 59); do
	echo "file $i" > "$SR/$(printf 'Note %02d %03d.txt' $((59 - i)) $((i * 37 % 1000)))"
done
cp "$C" build/VERANDA.SYS build/VERANDA.PRG "$SR/"
$PY tests/shell_script.py --probe "$SR/SHELL.TST" || fail "the script (sort)"
(cd "$SR" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$SR/dump.bin" ] || { tail -5 "$SR/console.txt"; fail "sort: the session did not end"; }
st=$(tr -d '\r' < "$SR/console.txt" | grep -a -o 'TIME SORT [0-9]* [0-9]*' | tail -1)
sn=$(echo "$st" | cut -d' ' -f3)
sc=$(echo "$st" | cut -d' ' -f4)
[ -n "$sc" ] && [ "$sn" -ge 60 ] || fail "sort: no TIME SORT line for the folder ($st)"
[ "$sc" -le $((sn * 13000)) ] || fail "sort: $sn entries in $sc cycles (more than 13,000 an entry: 100 ms for 60)"
ok "the folder's sort: $sn entries in $sc cycles ($((sc / 8000)) ms; cc65's qsort took 954 ms for 60)"

# the window operations' times (DECISIONS V81; tests/shell_speed_script.py):
# the card's layout with the desktop's picture (Dusk), 30 files; window 1
# opened over window 0, moved, closed, opened, resized, window 0 raised,
# its list, a sort, a row scrolled, icons, zoom, unzoom, a page; each
# operation's time (TIME <what> <cycles>) at most its limit (V80's shell
# took: MOVE 29.4 M cycles, CLOSE 7.8 M, RESIZE 11.9 M, FRONT 8.3 M, LIST
# 13.3 M, HEADER 10.8 M, SCROLL 9.1 M, ICONS 8.3 M, ZOOM 14.8 M, UNZOOM
# 12.4 M, PAGE 3.6 M, DESKOPEN 5.4 M, SELECT 1.06 M, DESKSELECT 0.55 M)
SP=$OUT/speed
rm -rf "$SP"
mkdir -p "$SP/VERANDA/WALLPAPERS" "$SP/VERANDA/.SYSTEM" "$SP/DOCUMENTS"
cp "$C" "$SP/VERANDA/"
cp build/VERANDA.SYS build/VERANDA.PRG "$SP/"
$PY "$SDK/tools/mkwall.py" -o "$SP/VERANDA/WALLPAPERS/Dusk.cvt" --dusk >/dev/null 2>&1 || fail "mkwall --dusk"
$PY tests/shell_speed_script.py make "$SP" || fail "the speed fixtures"
$PY tests/shell_speed_script.py script "$SP" || fail "the speed script"
(cd "$SP" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$SP/dump.bin" ] || { tail -5 "$SP/console.txt"; fail "speed: the session did not end"; }
LIM="SELECT=650000,DESKSELECT=300000,DESKOPEN=4500000,MOVE=4000000,CLOSE=6000000,RESIZE=9500000"
LIM="$LIM,FRONT=6600000,LIST=7800000,HEADER=7800000,SCROLL=1300000,ICONS=4500000,ZOOM=12800000"
LIM="$LIM,UNZOOM=10800000,PAGE=2900000"
$PY tests/shell_speed_script.py times "$SP/console.txt" "$LIM" > "$SP/times.txt" || { cat "$SP/times.txt"; fail "speed"; }
$PY tools/vram2png.py --color "$SP/dump.bin" "$OUT/speed.png" >/dev/null || fail "vram2png"
ok "the window operations under $R49 (ms): $(awk '{printf "%s %d, ", $1, $3}' "$SP/times.txt" | sed 's/, $//') ($OUT/speed.png)"
echo "GATE shell: PASS"
