#!/bin/bash
# Gate tile (the full-colour desktop picture: DECISIONS V101; its colour
# chrome: V102)
#
#   tools/gate_tile.sh
#
# 1. the wallpapers (tools/mkwall.py, its C helper tools/wallcv.c): the
#    dusk scene (--dusk-scene, dithered, 352 tiles: Dusk until V175) and a
#    picture in 10 exact colours (Still Water's, exact, no dither), each in
#    a couple of seconds; version 3 files (tiles, map, palette rows 2-10 of
#    10 colours), --v2 a version 2 one; the shipped pictures drawn as tiles
#    (tools/wallkit.py; V175 Dusk, mkwall --dusk; V162 Still Water, Low
#    Hills, Sunroom Tiles), each under 150 tiles
# 2. the shell in the card's layout (tests/tile_script.py's sessions,
#    tests/check_tile.py on the dump): the picture in tile mode (layer 0's
#    4 bpp tiles at $13000, the file's map, palette rows 2-12, no ink); the
#    three V162 pictures on the screen pixel for pixel; a menu and a dialog box over it
#    (their cards covered: palette row 15 or 14, their own rows in the
#    shadow bytes), closed again; a window moved and closed; dark mode (the
#    dark rows); the screen exported (ExportRect: an 8 bpp BMP equal to the
#    screen); a program started from it (tile mode off, its own palette
#    rows) and quitting (tile mode again); a program put aside (the
#    switcher, as Alt + Tab), the shell with it in the dock, brought back
#    (its rows and map as it left them); under the R49 ROM too
# 2b. the colour chrome (V102; check_tile.py chrome): shell/gui.inc and
#    guiart.s tools/mkgui.py's; the pool's tiles, palette row 13 and the
#    shades; the desktop's icons and window 0's folder in colour, their
#    and the window's corners composed on the picture (pixel for pixel),
#    its title band's gradient, its corners round in the ink; after a
#    move again where it went (one by a desktop icon square); dark mode;
#    the dock's plate; a version 2 wallpaper without any of it
# 3. the times (the emulator's cycle counter): the whole desktop drawn
#    (its bitmap cleared, its map written), window 0 moved, closed, the
#    whole screen
# PNGs: build/gate/tile/*.png
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/tile
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
TOP=$(pwd)
[ -f "$SDK/tools/wallcv.c" ] || fail "the SDK has no wallcv.c"

# ---------------------------------------------------------------- 1. the wallpapers
W=$OUT/wall
mkdir -p "$W"
t0=$(date +%s%N)
$PY "$SDK/tools/mkwall.py" -o "$W/Scene.cvt" --name Scene --dusk-scene 2> "$W/scene.log" || { cat "$W/scene.log"; fail "mkwall --dusk-scene"; }
t1=$(date +%s%N)
# (V175) Dusk drawn as tiles: mkwall --dusk (the SDK's) and tools/wall_dusk.py the same picture
$PY "$SDK/tools/mkwall.py" -o "$W/Dusk.cvt" --dusk 2> "$W/dusk2.log" || { cat "$W/dusk2.log"; fail "mkwall --dusk"; }
$PY tools/wall_dusk.py "$W/Dusk-b.cvt" > "$W/duskb.log" || fail "tools/wall_dusk.py"
cmp -s <(tail -c +509 "$W/Dusk.cvt") <(tail -c +509 "$W/Dusk-b.cvt") || fail "mkwall --dusk and tools/wall_dusk.py differ"
# (V162) the shipped pictures, drawn as tiles (tools/wallkit.py)
for g in dusk:Dusk stillwater:"Still Water" hills:"Low Hills" tiles:"Sunroom Tiles"; do
	$PY tools/wall_${g%%:*}.py "$W/${g#*:}.cvt" "$W/${g%%:*}" > "$W/${g%%:*}.log" || fail "tools/wall_${g%%:*}.py"
	n=$($PY "$SDK/tools/mkwall.py" --check "$W/${g#*:}.cvt" | sed -n '1s/^version 3, variant 0: \([0-9]*\) tiles.*/\1/p')
	[ -n "$n" ] && [ "$n" -lt 150 ] || fail "${g#*:}.cvt: $n tiles (fewer than 150 wanted)"
done
ok "the pictures drawn as tiles: $(cat "$W"/dusk.log "$W"/stillwater.log "$W"/hills.log "$W"/tiles.log | tr '\n' ';')"
# a picture in 10 exact colours through mkwall: exact, no dither (as the Meadow was)
t2=$(date +%s%N)
$PY "$SDK/tools/mkwall.py" -o "$W/Water.cvt" --name Water "$W/stillwater-light.png" 2> "$W/water.log" || { cat "$W/water.log"; fail "mkwall Water"; }
t3=$(date +%s%N)
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
$PY "$SDK/tools/mkwall.py" -o "$W/Dusk2.cvt" --name Dusk2 --v2 --dusk 2>/dev/null || fail "mkwall --v2"
for f in Dusk Scene Water "Still Water" "Low Hills" "Sunroom Tiles"; do
	[ "$(field "$W/$f.cvt" 'geos type')" = 7 ] && [ "$(field "$W/$f.cvt" class)" = "Wallpaper   V3.0" ] \
		&& [ "$(field "$W/$f.cvt" structure)" = sequential ] || fail "$f.cvt: not a sequential APPL_DATA document of class Wallpaper V3.0"
	$PY "$SDK/tools/mkwall.py" --check "$W/$f.cvt" > "$W/$f.check" || fail "mkwall --check $f.cvt"
	$PY "$SDK/tools/mkwall.py" --png "$OUT/$f-file.png" "$W/$f.cvt" || fail "mkwall --png $f.cvt"
done
# (V153: a picture in few exact colours that fits 352 tiles comes out exact
# or near: 45 dB; V162: Still Water's picture, 104 tiles, exact)
grep -q "exact" "$W/water.log" || awk '{for (i = 1; i <= NF; ++i) if ($i ~ /^psnr=/) { split($i, a, "="); exit !(a[2] >= 45) } exit 1}' "$W/water.log" \
	|| { cat "$W/water.log"; fail "Still Water's picture through mkwall is not exact nor near (45 dB)"; }
grep -q "dither on" "$W/scene.log" && grep -q "dither off" "$W/water.log" || fail "the dither: the dusk scene on, Still Water's picture off"
ok "mkwall: the dusk scene (Scene.cvt) in $(( (t1 - t0) / 1000000 )) ms ($(sed 's/^mkwall: //' "$W/scene.log" | tr '\n' ' ')), Still Water's picture (Water.cvt) in $(( (t3 - t2) / 1000000 )) ms ($(sed 's/^mkwall: //' "$W/water.log" | tr '\n' ' ')); $(field "$W/Scene.cvt" size) bytes of data each"
[ $(( (t1 - t0) / 1000000 )) -lt 6000 ] && [ $(( (t3 - t2) / 1000000 )) -lt 6000 ] || fail "mkwall took more than 6 s"

# the old format (V78) made again: --from renders it and converts
$PY - "$W/old.cvt" <<'EOF'
import sys, os
sys.path.insert(0, 'tools')
import vpack, mkwall
data = mkwall.MAGIC + bytes([1, 2, 80, 60]) + bytes(8)
for v in range(2):
    pal = (0x37D, 0x8D3, 0x5A2, 0xAD4)
    cols = bytes(12 + (y // 15) for y in range(60) for x in range(80))
    bm = bytes((0xAA if (y & 1) else 0x55) if y >= 240 else 0 for y in range(480) for x in range(80))
    data += b''.join(c.to_bytes(2, 'little') for c in pal) + cols + bm
open(sys.argv[1], 'wb').write(vpack.pack_doc('Old', 'Wallpaper', data, author='Veranda'))
EOF
$PY "$SDK/tools/mkwall.py" -o "$W/Old2.cvt" --from "$W/old.cvt" 2>/dev/null || fail "mkwall --from a version 1 file"
[ "$(field "$W/Old2.cvt" class)" = "Wallpaper   V3.0" ] || fail "--from: not version 3"
ok "mkwall --from: a version 1 wallpaper (V78's) made again as version 3"

# ---------------------------------------------------------------- the shell, TileApp
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }
$PY tools/check_ovl.py shell || fail "a call between overlays not through XCALL (tools/check_ovl.py)"
A=$OUT/apps
mkdir -p "$A"
for v in plain:"" aside:"-D ASIDE"; do
	n=${v%%:*}
	ca65 --cpu 65C02 -I "$SDK/include" ${v#*:} -o "$A/$n.o" tests/tile_app.s || fail "tests/tile_app.s"
	ld65 -C "$SDK/cfg/app.cfg" -o "$A/$n.bin" "$A/$n.o" || fail "TileApp does not link"
	printf 'name = TileApp\nclass = TileApp\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/$n.hdr"
	mkdir -p "$A/$n"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$n/TileApp.cvt" "$A/$n.hdr" "$A/$n.bin" >/dev/null || fail "vpack TileApp"
done
ok "the shell and TileApp (tests/tile_app.s, and -D ASIDE) built"
$PY tools/mkgui.py shell/tiles.txt "$OUT/gui.inc" "$OUT/guiart.s" --png "$OUT/gui-art.png" >/dev/null || fail "mkgui"
cmp -s "$OUT/gui.inc" shell/gui.inc && cmp -s "$OUT/guiart.s" shell/guiart.s \
	|| fail "shell/gui.inc, shell/guiart.s are not tools/mkgui.py's from shell/tiles.txt"
ok "shell/gui.inc and shell/guiart.s are tools/mkgui.py's from shell/tiles.txt (the chrome's art: $OUT/gui-art.png)"

# folder <dir> <session> <wallpaper> [prefs args] [app build]
folder() {
	rm -rf "$1"
	mkdir -p "$1/VERANDA/WALLPAPERS" "$1/VERANDA/.SYSTEM" "$1/DOCUMENTS"
	cp "$OUT/src/SHELL.cvt" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
	cp "$W/$3.cvt" "$1/VERANDA/WALLPAPERS/"
	if true; then                   # (V132: without WALLPAPER.CFG the plain desktop: Dusk named too)
		$PY - "$1/VERANDA/.SYSTEM/WALLPAPER.CFG" "$3" <<'EOF'
import sys
c = bytearray(64)
c[0:3] = b'WP\x01'
c[8:8 + len(sys.argv[2])] = sys.argv[2].encode()
d = b'/VERANDA/WALLPAPERS'
c[32:32 + len(d)] = d
open(sys.argv[1], 'wb').write(bytes(c))
EOF
	fi
	[ -z "$4" ] || $PY tests/check_theme.py prefs "$1/VERANDA/.SYSTEM/Veranda Prefs.cvt" $4
	[ -z "$5" ] || cp "$A/$5/TileApp.cvt" "$1/DOCUMENTS/"
	echo "a note" > "$1/DOCUMENTS/Note.txt"
	$PY tests/tile_script.py "$1" "$2" || fail "tests/tile_script.py $2"
}
run() {
	local d=$1 rom=$2
	shift 2
	cp build/VERANDA.PRG "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$rom" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V "$@" > console.txt 2>&1) || true
	[ -f "$d/dump.bin" ] || { tail -20 "$d/console.txt"; fail "$d: the session did not end (no dump)"; }
	grep -a -q "SHELL DONE" "$d/console.txt" || fail "$d: the shell's script did not end"
}
png() { $PY tools/vram2png.py --color "$1" "$2" 2>/dev/null || true; }
log() { tr -d '\r' < "$1" | grep -a -o -E 'SHELL WALLPAPER [A-Za-z0-9 .,]*' | sed 's/ *$//' | tr '\n' ',' ; }
CHK="$PY tests/check_tile.py"
WIN0=2,4,62,50                  # window 0 in its default place, with its shadow (cards)
WIN0C=2,4,61,49                 # (without)

# ---------------------------------------------------------------- 2. the desktop
R=$OUT/run/probe
folder "$R" probe Dusk
run "$R" "$ROM"
got=$(log "$R/console.txt")
case "$got" in "SHELL WALLPAPER Dusk.cvt READ IN "*",SHELL WALLPAPER ON LIGHT, TILES IN "*",SHELL WALLPAPER SHOWN,") ;; *) fail "the console has $got" ;; esac
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip $WIN0 || fail "the desktop is not the picture"
png "$R/dump.bin" "$OUT/desktop.png"
ok "the shell with Dusk.cvt (the default): $(echo "$got" | cut -d, -f1-3) cycles: $OUT/desktop.png"
$CHK chrome "$R/dump.bin" "$W/Dusk.cvt" 0 --win $WIN0C --desk --accent 3 || fail "the colour chrome"

# window 0 moved 80 right and down: its corners where it went, the one by
# the printer's icon square (V102)
R=$OUT/run/moved
folder "$R" moved Dusk
run "$R" "$ROM"
$CHK chrome "$R/dump.bin" "$W/Dusk.cvt" 0 --win 12,14,71,59 --square 1 --accent 3 || fail "the colour chrome after a move"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip 2,4,11,50 --skip 12,14,72,59 >/dev/null || fail "the desktop after the move"
png "$R/dump.bin" "$OUT/moved.png"
ok "window 0 moved: its corners composed again where it went (the top right one, by the printer, square), what it left the picture: $OUT/moved.png"

# a wallpaper of version 2 (V101's) shows as before: no chrome
R=$OUT/run/v2
folder "$R" probe Dusk2
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk2.cvt" 0 --skip $WIN0 >/dev/null || fail "a wallpaper of version 2"
$CHK plain "$R/dump.bin" || fail "a wallpaper of version 2: the chrome"
png "$R/dump.bin" "$OUT/desktop-v2.png"
ok "a wallpaper of version 2 (mkwall --v2) shown as before, without the colour chrome: $OUT/desktop-v2.png"

# (V162) the shipped pictures drawn as tiles, light and dark: each on the
# screen exactly as its file (mkwall --png)
for f in "Still Water" "Low Hills" "Sunroom Tiles"; do
	for dk in 0 1; do
		R="$OUT/run/pic-${f// /}-$dk"
		folder "$R" probe "$f" "$([ $dk = 1 ] && echo "3 14 5 5 129")"
		run "$R" "$ROM"
		$CHK desk "$R/dump.bin" "$W/$f.cvt" $dk --skip $WIN0 >/dev/null || fail "$f ($dk)"
		[ $dk = 0 ] || $PY "$SDK/tools/mkwall.py" --png "$OUT/$f-file-dark.png" --dark "$W/$f.cvt"
		$CHK exact "$R/dump.bin" "$OUT/$f-file$([ $dk = 1 ] && echo -dark).png" --skip $WIN0 >/dev/null \
			|| fail "$f ($([ $dk = 1 ] && echo dark || echo light)) is not on the screen as in its file"
		png "$R/dump.bin" "$OUT/${f// /-}-$dk.png"
	done
done
ok "Still Water, Low Hills and Sunroom Tiles (WALLPAPER.CFG), light and dark: on the screen pixel for pixel their files: $OUT/{Still-Water,Low-Hills,Sunroom-Tiles}-{0,1}.png"

R=$OUT/run/shot
folder "$R" shot Dusk
run "$R" "$ROM"
grep -a -q "SHELL SHOT 0" "$R/console.txt" || fail "the export: $(grep -a 'SHELL SHOT' "$R/console.txt")"
$CHK shot "$R/dump.bin" "$R/SHOT.BMP" || fail "SHOT.BMP"
cp "$R/SHOT.BMP" "$OUT/shot.bmp"
ok "the screen exported by ExportRect on the tile desktop: $OUT/shot.bmp"

# the Veranda menu open and Veranda > About's box (cards: the menu with
# its shadow 0-11 x 2-8, its three items since V134's Help; the box with
# its shadow)
MENU=0,2,11,7                    # (V146: the list ends on a card's last line, no row below it covered)
BOX=28,24,52,36
BOXC=28,27,52,36                # (its title band, a corner and a shadow's end show the chrome: V102)
R=$OUT/run/menu
folder "$R" menu Dusk
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip $WIN0 --covered $MENU || fail "the menu open"
png "$R/dump.bin" "$OUT/menu.png"
ok "the Veranda menu open over the picture: $OUT/menu.png"
R=$OUT/run/dialog
folder "$R" dialog Dusk
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --covered $BOXC --any 28,24,52,26 --any 28,35,28,36 || fail "the dialog box open"
$CHK box "$R/dump.bin" "$W/Dusk.cvt" 0 || fail "the message box's chrome"
png "$R/dump.bin" "$OUT/dialog.png"
ok "window 0 closed, Veranda > About's box open over the picture: $OUT/dialog.png"

# (V181, from the user's X16: Get Info on "letter", a geoWrite document,
# drew its class, author and application lines under a band of noise and
# its 1-bit icon) File > Get Info on a geoWrite document with junk in its
# info block (tests/info_box.py): the box as with the junk taken out,
# pixel for pixel, its colour icon, no noise; on Sunroom Tiles (the list),
# Dusk (the icons) and the plain desktop (the list); after Cancel the
# screen as without the box (the icon's cards given back)
I=$OUT/info
mkdir -p "$I"
for k in junk clean; do $PY tests/info_box.py doc "$I/$k.cvt" $k || fail "tests/info_box.py doc $k"; done
infrun() {      # infrun <name> <wallpaper|none> <view> <junk|clean> <open|cancel|none>
	R=$OUT/run/info-$1
	folder "$R" probe "$([ "$2" = none ] && echo Dusk || echo "$2")"
	[ "$2" != none ] || rm -f "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
	cp "$I/$4.cvt" "$R/DOCUMENTS/letter.cvt"
	$PY tests/info_box.py script "$R" $3 $5 || fail "tests/info_box.py script $1"
	run "$R" "$ROM"
	png "$R/dump.bin" "$OUT/info-$1.png"
}
for c in "tiles:Sunroom Tiles:name" "dusk:Dusk:icon" "plain:none:name"; do
	IFS=: read n wp view <<< "$c"
	infrun "$n" "$wp" $view junk open
	infrun "$n-ref" "$wp" $view clean open
	$PY tests/info_box.py check "$OUT/run/info-$n/dump.bin" "$OUT/run/info-$n-ref/dump.bin" "$I/junk.cvt" \
		> "$I/$n.txt" || { cat "$I/$n.txt"; fail "the Info box ($n): $OUT/info-$n.png"; }
done
infrun cancel "Sunroom Tiles" name junk cancel
infrun none "Sunroom Tiles" name junk none
$PY tests/info_box.py same "$OUT/run/info-cancel/dump.bin" "$OUT/run/info-none/dump.bin" > "$I/cancel.txt" \
	|| { cat "$I/cancel.txt"; fail "after the Info box's Cancel: $OUT/info-cancel.png"; }
ok "Get Info on a geoWrite document with junk in its info block: the box as with the junk taken out, its colour icon, no noise (Sunroom Tiles, Dusk, the plain desktop); after Cancel the screen as before: $OUT/info-*.png"

R=$OUT/run/closed
folder "$R" closed Dusk
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 || fail "after the window moved and closed, the menu and the box"
png "$R/dump.bin" "$OUT/closed.png"
ok "window 0 moved and closed, the menu opened and closed, About and its OK: the whole desktop the picture: $OUT/closed.png"
$CHK times "$R/console.txt" "DESKTOP_FILL=260000,DESKTOP_COLOURS=230000,MOVED=2000000,REPAINT=1400000,ALL=4300000" \
	> "$OUT/times.txt" || { cat "$OUT/times.txt"; fail "the times"; }
sed 's/^/      /' "$OUT/times.txt"

R=$OUT/run/dark
folder "$R" probe Dusk "5 13 4 0 129"
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 1 --skip $WIN0 || fail "dark mode"
png "$R/dump.bin" "$OUT/desktop-dark.png"
ok "dark mode: the dark rows, the same tiles and map: $OUT/desktop-dark.png"
$CHK chrome "$R/dump.bin" "$W/Dusk.cvt" 1 --win $WIN0C --desk > /dev/null || fail "the colour chrome in dark mode"
ok "dark mode: the colour chrome (its shades from the dark accent)"

# ---------------------------------------------------------------- programs
R=$OUT/run/app
folder "$R" app Dusk "" plain
run "$R" "$ROM"
$CHK app "$R/console.txt" "$R/dump.bin" "$W/Dusk.cvt" || fail "a program started from the tile desktop"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip $WIN0 >/dev/null || fail "the shell after the program"
ok "the shell again after it: tile mode, the picture"
R=$OUT/run/aside
folder "$R" aside Dusk "" aside
run "$R" "$ROM"
$CHK app "$R/console.txt" "$R/dump.bin" "$W/Dusk.cvt" aside || fail "a program put aside and brought back"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip $WIN0 >/dev/null || fail "the shell after the program"
R=$OUT/run/asideshot
folder "$R" asideshot Dusk "" aside
run "$R" "$ROM"
$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 --skip $WIN0 --any 30,50,50,59 >/dev/null || fail "the shell with TileApp aside"
grep -a -q "SHELL SHOT 0" "$R/console.txt" && $CHK shot "$R/dump.bin" "$R/SHOT.BMP" >/dev/null || fail "the export with the dock"
png "$R/dump.bin" "$OUT/aside.png"
ok "the shell with TileApp aside (its dock item) in tile mode; exported: $OUT/aside.png"
$CHK chrome "$R/dump.bin" "$W/Dusk.cvt" 0 --win $WIN0C --dock 33,53,46,58 --accent 3 || fail "the dock's chrome"

# ---------------------------------------------------------------- R49
if [ -f "$R49" ]; then
	for s in probe closed menu; do
		R=$OUT/run/r49-$s
		folder "$R" $s Dusk
		run "$R" "$R49"
		cov=
		[ $s != menu ] || cov="--covered $MENU"
		sk="--skip $WIN0"
		[ $s != closed ] || sk=
		$CHK desk "$R/dump.bin" "$W/Dusk.cvt" 0 $sk $cov >/dev/null || fail "R49: $s"
	done
	png "$OUT/run/r49-probe/dump.bin" "$OUT/desktop-r49.png"
	$CHK times "$OUT/run/r49-closed/console.txt" > "$OUT/times-r49.txt"
	ok "under the R49 ROM: the desktop, the menu, the window moved and closed: $OUT/desktop-r49.png; times:"
	sed 's/^/      /' "$OUT/times-r49.txt"
fi

# ---------------------------------------------------------------- the whole APPS folder
# (V156) a package's APPS (34 programs; APPS=<folder>, default the newest
# ~/Projects/veranda-dist/pkg-*/VERANDA/APPS) in the Apps window, icon
# view, light: on the plain desktop both pages, every program with a colour
# icon (its own or the library's) in colour, the others their 1-bit
# picture alone; on the dusk scene (352 tiles: about 25 icons; Dusk until
# V175) a program with one in colour or, when the tiles ran out, Look 2's
# tile (as the earlier packages), never bare; on Dusk (V175: 113 tiles) and Still Water
# (V162: 104) every one in colour, the desktop's icons too (--all 1). (V175,
# from the user's X16: on the old Dusk "letter", a geoWrite document,
# PhotoMgr, Preferences, the printer and the trash were Look 2's tiles)
# the user's document letter (class Write Image) in the folder and the
# dock's six default pins (tests/apps_icons.py)
APPS=${APPS:-$(ls -td "$HOME"/Projects/veranda-dist/pkg-*/VERANDA/APPS 2>/dev/null | head -1)}
if [ -d "$APPS" ]; then
	$PY tests/apps_icons.py files "$APPS" > "$OUT/apps-files.txt" || { cat "$OUT/apps-files.txt"; fail "the APPS folder's colour icons"; }
	echo "      $(sed 's/^ *//' "$OUT/apps-files.txt")"
	$PY - "$W/letter.cvt" <<'EOF'
import sys
sys.path.insert(0, 'tests')
import shell_subst
open(sys.argv[1], 'wb').write(shell_subst.cvt('letter', 'Write Image V2.1', 'geoWrite    V2.1', {0: b'Dear Ada\r\0'}))
EOF
	for c in plain:0:Dusk: plain:1:Dusk: picture:0:Scene: picture:0:Dusk:1 "picture:0:Still Water:1"; do
		IFS=: read k pg wp all <<< "$c"
		R="$OUT/run/apps-$k-$pg-${wp// /}"
		folder "$R" probe "$wp"
		[ $k = plain ] && rm -f "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
		mkdir -p "$R/VERANDA/APPS"
		cp "$APPS"/*.cvt "$W/letter.cvt" "$R/VERANDA/APPS/"
		touch "$R/PINS.DEF"
		$PY tests/apps_icons.py script "$R" $pg || fail "tests/apps_icons.py script"
		run "$R" "$ROM"
		png "$R/dump.bin" "$OUT/apps-$k-$pg-${wp// /}.png"
		grep -a -q "SHELL PINS DEFAULT 6" "$R/console.txt" || fail "the dock's six default pins ($wp)"
		$PY tests/apps_icons.py check "$R/dump.bin" "$R/VERANDA/APPS" $k $pg --all "${all:-0}" > "$R/check.txt" \
			|| { cat "$R/check.txt"; fail "the APPS folder's icons ($k, page $((pg + 1)), $wp): $OUT/apps-$k-$pg-${wp// /}.png"; }
		lbl=$k
		[ $k = plain ] || lbl=$wp
		echo "      $lbl: $(sed 's/^ *//' "$R/check.txt")"
	done
	# (V161, from the user's X16 with pkg-0.9.0-30e824d: "the Preferences
	# icon has disappeared") each cell pixel for pixel the icon it should
	# show (tests/apps_icons.py pixels), light and dark, the plain desktop,
	# Dusk and the V162 pictures (on those every program of a page in
	# colour), both pages; the dock's pins; the list's small
	# icons; and after Preferences changed the desktop (the cache started
	# again: every program with its own icon was its bare 1-bit picture)
	H=$TOP/$OUT/h
	$PY tests/wall_script.py prefs "$H" || fail "tests/wall_script.py prefs"
	for s in wall1 wall2; do
		mkdir -p "$OUT/$s"
		make -s -C apps/prefs SDK="$SDK" OUT="$TOP/$OUT/$s" test TESTFLAGS="-I$H/$s" >"$OUT/$s/build.log" 2>&1 \
			|| { cat "$OUT/$s/build.log"; fail "Preferences ($s)"; }
	done
	PINS="Paint,Disk Tools,Archive,Bird Watch"   # (applications on page 1: SID Player and Term went to page 2 with Colour Paint, V173)
	DARK="3 14 5 5 129"
	# name wallpaper page dark least pins view prefs
	# (Preferences' wall2 chooses the second picture of WALLPAPERS: Dusk,
	# Still Water)
	# (V175) on every picture (all drawn as tiles) no Look 2 tile, the
	# desktop's icons in colour (--all 1); pix-dusk-def*: the user's letter
	# and the six default pins (the dock's pixel for pixel)
	DEFPINS="Veranda Write,Veranda Edit,Paint,Veranda Gemini,Veranda Ask,Term"
	for c in "pix-plain-0:none:0::0:::" "pix-plain-1-dark:none:1:d:0:::" "pix-dusk-0:Dusk:0::19:::" \
		"pix-dusk-def:Dusk:0::19:def::" "pix-dusk-def-dark:Dusk:0:d:19:def::" \
		"pix-water-0:Still Water:0::19:::" "pix-water-1:Still Water:1::15:::" "pix-hills-0-dark:Low Hills:0:d:19:::" \
		"pix-tiles-0:Sunroom Tiles:0::19:::" "pix-dusk-1-dark:Dusk:1:d:15:::" "pix-dock-plain:none:0::0:$PINS::" \
		"pix-dock-tiles-dark:Sunroom Tiles:0:d:19:$PINS::" "pix-list:none:0::0::name:" \
		"pix-prefs-plain:Dusk:0::0:::wall1" "pix-prefs-water:none:0::19:::wall2"; do
		IFS=: read n wp pg dk least pins view pf <<< "$c"
		R=$OUT/run/$n
		folder "$R" probe "$([ "$wp" = none ] && echo "Still Water" || echo "$wp")" "${dk:+$DARK}"
		cp "$W/Dusk.cvt" "$W/Still Water.cvt" "$R/VERANDA/WALLPAPERS/"
		[ "$wp" != none ] || rm -f "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
		mkdir -p "$R/VERANDA/APPS"
		cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
		[ -z "$pf" ] || cp "$OUT/$pf/Preferences.cvt" "$R/VERANDA/APPS/"
		ppins=$pins
		if [ "$pins" = def ]; then
			cp "$W/letter.cvt" "$R/VERANDA/APPS/"
			touch "$R/PINS.DEF"
			pins= ppins=$DEFPINS
		fi
		k=plain
		[ "$wp" != none ] && k=picture
		case $pf in wall1) k=plain ;; wall2) k=picture ;; esac
		$PY tests/apps_icons.py script "$R" $pg --pins "$pins" --view "$view" --prefs "${pf:+1}" \
			|| fail "tests/apps_icons.py script ($n)"
		run "$R" "$ROM"
		png "$R/dump.bin" "$OUT/$n.png"
		if [ -n "$view" ]; then
			$PY tests/apps_icons.py small "$R/dump.bin" "$R/VERANDA/APPS" > "$R/check.txt"
		else
			$PY tests/apps_icons.py pixels "$R/dump.bin" "$R/VERANDA/APPS" $k $pg --pins "$ppins" --least $least \
				--all $([ $k = picture ] && echo 1 || echo 0) > "$R/check.txt"
		fi || { cat "$R/check.txt"; fail "the APPS folder's icons, pixel for pixel ($n): $OUT/$n.png"; }
		echo "      $n: $(sed 's/^ *//' "$R/check.txt")"
	done
	ok "the APPS folder ($(ls "$APPS"/*.cvt | wc -l) programs, $APPS): every colour icon shown, on the dusk scene (352 tiles) Look 2's tile when none are left, on Dusk (V175) and the V162 pictures none left out, the desktop's icons too: $OUT/apps-*.png"
	# (V180, from the user's X16: "dock icons are not looking good in lower
	# res") Dusk chosen, the six default pins and MOD Player and Bird Watch
	# pinned, the list, then 640 x 240 and 320 x 240 (the picture becomes
	# the plain tile desktop, the cache starts again), light and dark: every
	# pin pixel for pixel its colour icon (Paint, Veranda Gemini, Ask and
	# Term were their 1-bit pictures, each on a grey block, the shadow a
	# dither)
	for m in 640x240 320x240; do
		for dk in "" d; do
			R="$OUT/run/dock-$m${dk:+-dark}"
			folder "$R" probe Dusk "${dk:+$DARK}"
			mkdir -p "$R/VERANDA/APPS"
			cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
			touch "$R/PINS.DEF"
			$PY tests/apps_icons.py script "$R" 0 --pins "MOD Player,Bird Watch" --view name --mode $m \
				|| fail "tests/apps_icons.py script (dock $m)"
			run "$R" "$ROM"
			$PY tests/apps_icons.py dock "$R/dump.bin" "$R/VERANDA/APPS" --pins "$DEFPINS,MOD Player,Bird Watch" --mode $m \
				> "$R/check.txt" || { cat "$R/check.txt"; fail "the dock at $m${dk:+, dark}"; }
			echo "      $(sed 's/^ *//' "$R/check.txt")${dk:+ (dark)}"
		done
	done
	ok "the dock at 640 x 240 and 320 x 240, light and dark: every pin its colour icon (V180)"
	# (V180, the user's X16 at 640 x 480 on Sunroom Tiles, right after
	# Preferences changed the desktop: the same four pins 1-bit) the desktop
	# changed by Preferences (a desk accessory: wall1 Dusk to the plain
	# desktop, wall2 the plain desktop to Still Water), and the shell again
	# after a program (TileApp): the six default pins pixel for pixel
	# (V180) and Preferences from Options > Preferences... (the folder not
	# opened first)
	for c in prefs1:Dusk:wall1 prefs2:none:wall2 prefsmenu:Dusk:wall1 app:Dusk:; do
		IFS=: read n wp pf <<< "$c"
		R="$OUT/run/dock-$n"
		if [ $n = app ]; then
			folder "$R" app Dusk "" plain
		else
			folder "$R" probe "$([ "$wp" = none ] && echo "Still Water" || echo "$wp")"
			cp "$W/Dusk.cvt" "$W/Still Water.cvt" "$R/VERANDA/WALLPAPERS/"
			[ "$wp" != none ] || rm -f "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
		fi
		mkdir -p "$R/VERANDA/APPS"
		cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
		[ -z "$pf" ] || cp "$OUT/$pf/Preferences.cvt" "$R/VERANDA/APPS/"
		touch "$R/PINS.DEF"
		[ $n = app ] || $PY tests/apps_icons.py script "$R" 0 --prefs $([ $n = prefsmenu ] && echo menu || echo 1) \
			|| fail "tests/apps_icons.py script (dock $n)"
		run "$R" "$ROM"
		png "$R/dump.bin" "$OUT/dock-$n.png"
		[ $n = app ] || grep -a -q "PREFS DESKTOP" "$R/console.txt" || fail "dock $n: Preferences did not change the desktop"
		$PY tests/apps_icons.py dock "$R/dump.bin" "$R/VERANDA/APPS" --pins "$DEFPINS" --mode 640x480 > "$R/check.txt" \
			|| { cat "$R/check.txt"; fail "the dock after $n: $OUT/dock-$n.png"; }
		echo "      after $n: $(sed 's/^ *//' "$R/check.txt")"
	done
	ok "the dock after Preferences changed the desktop and after a program: every pin its colour icon (V180)"
	# (V176) no saved choice: the list (LIST.DEF: the gates' scripts keep
	# the icons without it), its small icons pixel for pixel
	R=$OUT/run/listdef
	folder "$R" probe Dusk
	mkdir -p "$R/VERANDA/APPS"
	cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
	touch "$R/LIST.DEF"
	$PY tests/apps_icons.py script "$R" 0 || fail "tests/apps_icons.py script (listdef)"
	run "$R" "$ROM"
	png "$R/dump.bin" "$OUT/listdef.png"
	$PY tests/apps_icons.py small "$R/dump.bin" "$R/VERANDA/APPS" > "$R/check.txt" \
		|| { cat "$R/check.txt"; fail "no saved choice: not the list: $OUT/listdef.png"; }
	ok "no saved choice: Apps opened in the list (V176): $(sed 's/^ *//' "$R/check.txt"): $OUT/listdef.png"
	# (V176, the user's rule: "we should not include backgrounds which will
	# break icons") every wallpaper the package ships (tools/mkdist.sh's
	# /VERANDA/WALLPAPERS, read from it: one added there and not made here
	# fails) under 150 tiles, and with the whole APPS folder, letter and the
	# dock's six default pins, light and dark, pages 1 and 2: every program,
	# the desktop's icons and the dock's pins in colour, pixel for pixel (no
	# Look 2 tile)
	ships=$(sed -n 's|.*"\$V/WALLPAPERS/\([^"]*\)\.cvt".*|\1|p' tools/mkdist.sh)
	[ "$(echo "$ships" | wc -l)" -ge 4 ] || fail "tools/mkdist.sh's wallpapers not found ($ships)"
	while IFS= read -r wp; do
		[ -f "$W/$wp.cvt" ] || fail "mkdist ships $wp.cvt: gate tile does not make it (add it to part 1)"
		n=$($PY "$SDK/tools/mkwall.py" --check "$W/$wp.cvt" | sed -n '1s/^version 3, variant 0: \([0-9]*\) tiles.*/\1/p')
		[ -n "$n" ] && [ "$n" -lt 150 ] || fail "$wp.cvt: $n tiles (the shipped wallpapers: under 150)"
		for pg in 0 1; do
			for dk in "" d; do
				R="$OUT/run/ship-${wp// /}-$pg${dk:+-dark}"
				folder "$R" probe "$wp" "${dk:+$DARK}"
				mkdir -p "$R/VERANDA/APPS"
				cp "$APPS"/*.cvt "$W/letter.cvt" "$R/VERANDA/APPS/"
				touch "$R/PINS.DEF"
				$PY tests/apps_icons.py script "$R" $pg || fail "tests/apps_icons.py script (ship $wp)"
				run "$R" "$ROM"
				png "$R/dump.bin" "$OUT/ship-${wp// /}-$pg${dk:+-dark}.png"
				$PY tests/apps_icons.py pixels "$R/dump.bin" "$R/VERANDA/APPS" picture $pg --pins "$DEFPINS" --all 1 > "$R/check.txt" \
					|| { cat "$R/check.txt"; fail "the shipped wallpaper $wp breaks icons (page $((pg + 1))${dk:+, dark}): $OUT/ship-${wp// /}-$pg${dk:+-dark}.png"; }
			done
		done
		echo "      shipped $wp: $n tiles; pages 1 and 2, light and dark: every icon, the desktop's and the dock's six in colour"
	done <<< "$ships"
	ok "every wallpaper the package ships (tools/mkdist.sh) under 150 tiles and breaks no icon: $OUT/ship-*.png"
	# (V157) the user's card: its root of about 60 entries, mostly folders, on
	# Low Hills (V162: 145 tiles, the most of the three) and on Dusk, after both of the Apps window's pages (more
	# icons than a picture's tiles hold): the folders the one colour folder
	# icon, the desktop's icons in colour
	for wp in "Low Hills" Dusk; do
		R="$OUT/run/root-${wp// /}"
		folder "$R" probe "$wp"
		mkdir -p "$R/VERANDA/APPS"
		cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
		for d in BASIC-DEMOS c64 CORES DOCS ftp GAMES-ARCADE GAMES-PUZZLE GAMES-RPG GAMES-SHMUP MODS MUSIC PC \
			TILEHW ASM BIN BOOT CC65 DEMOS EMU FONTS GRAPHICS HELP IMAGES LIB MISC NET OLD PROGS RETRO ROMS \
			SAVES SCRATCH SOUNDS SRC TEMP TEST TOOLS UTILS VIDEO WORK X16 ZIP; do mkdir -p "$R/$d"; done
		for f in README.TXT NOTES.TXT GAME.PRG DEMO.PRG HELLO.BAS TEST.BAS SONG.MOD PIC.BMP DATA.BIN; do
			echo x > "$R/$f"
		done
		$PY tests/apps_icons.py root "$R" || fail "tests/apps_icons.py root"
		run "$R" "$ROM"
		png "$R/dump.bin" "$OUT/root-${wp// /}.png"
		$PY tests/apps_icons.py rootcheck "$R/dump.bin" "$R" > "$R/check.txt" \
			|| { cat "$R/check.txt"; fail "the card's root on $wp: $OUT/root-${wp// /}.png"; }
		echo "      $wp: $(sed 's/^ *//' "$R/check.txt")"
	done
	ok "the card's root on Low Hills and Dusk after the APPS folder: its folders and the desktop's icons in colour: $OUT/root-*.png"
	# (V165, from the user's X16: "the basic icons appear first, then the
	# colour icons replace them ... moving a window is very slow") the speed
	# on an SD card image (tools/vcard.py: CMDR-DOS reads the card as on the
	# X16; the host folder costs no cycles), the dock's default pins, the
	# plain desktop and Dusk: the Apps window drawn, its pages turned and a
	# row scrolled by the scroll bar, the window dragged, each within its
	# limit (cycles at 8 MHz), and never the whole screen drawn again after
	# a folder is shown (V161's restart of the colour icons' cache); at the
	# end every program of page 1 pixel for pixel (on Dusk, with the six
	# default pins, all 19 in colour and the desktop's icons: V175; at
	# least 15 on the old Dusk)
	for c in plain:0:"open=15500000,page=3800000,scroll=3800000,move=2900000" \
		Dusk:19:"open=16000000,page=7600000,scroll=7600000,move=2900000"; do
		IFS=: read wp least lim <<< "$c"
		R=$OUT/run/speed-$wp
		folder "$R" probe Dusk
		[ "$wp" = plain ] && rm -f "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
		mkdir -p "$R/VERANDA/APPS"
		cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
		touch "$R/PINS.DEF"
		$PY tests/apps_icons.py speed "$R" || fail "tests/apps_icons.py speed"
		rm -rf "$R.sd"
		mkdir -p "$R.sd"
		$PY tools/vcard.py make --mb 64 "$R.sd/sd.img" "$R" >/dev/null || fail "vcard make ($wp)"
		cp build/VERANDA.PRG "$R.sd/"
		(cd "$R.sd" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		grep -a -q "SHELL DONE" "$R.sd/console.txt" || fail "the speed session ($wp) did not end"
		png "$R.sd/dump.bin" "$OUT/speed-$wp.png"
		$PY tests/apps_icons.py times "$R.sd/console.txt" "$lim" > "$R.sd/times.txt" \
			|| { cat "$R.sd/times.txt"; fail "the speed on the SD card ($wp)"; }
		k=plain
		[ "$wp" = plain ] || k=picture
		$PY tests/apps_icons.py pixels "$R.sd/dump.bin" "$R/VERANDA/APPS" $k 0 --least $least \
			--all $([ $k = picture ] && echo 1 || echo 0) > "$R.sd/check.txt" \
			|| { cat "$R.sd/check.txt"; fail "the speed session's icons ($wp): $OUT/speed-$wp.png"; }
		echo "      speed, $wp, SD card: $(cat "$R.sd/times.txt"); $(sed 's/^ *//' "$R.sd/check.txt")"
	done
	ok "the speed (SD card): the Apps window drawn once, pages, a row, a drag within their limits; no restart of the icons' cache: $OUT/speed-*.png"
else
	echo "      (no package's APPS folder: the whole APPS folder not checked; APPS=<folder>)"
fi
echo "gate tile: ok"
