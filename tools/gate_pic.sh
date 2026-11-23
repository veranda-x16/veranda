#!/bin/bash
# Gate pic (a program's full-colour picture: the SDK's vr_pic, vrpic.h,
# and mkwall.py --tiles; DECISIONS V105)
#
#   tools/gate_pic.sh
#
# 1. mkwall.py --tiles: Sunroom Tiles' picture (tools/wall_tiles.py, 13
#    colours; the Meadow's before V162) in palette rows 4-13 and, with it, the same
#    mirrored (two pictures, the same
#    tiles and rows, a map each): the records (VRAM chunks: record 1 the
#    rows alone) rebuild the rows, the tiles and the first map; each
#    picture exact (tests/check_pic.py files)
# 2. tests/pic_app.c (C, against the installed SDK) started under the R49
#    ROM (AUTOSTART), -D DUMP: tile mode, tiles 0-15 solid, its tiles, map
#    and rows in VRAM, row 15 the paper; the screen as VERA shows it equal
#    to the picture pixel for pixel on every card without ink; its line of
#    ink on both screens, the back screen otherwise clear
# 3. -D ASIDE from the shell (the card's layout, tests/tile_script.py
#    picaside): put aside (TaskCtl TASK_ASIDE, as Alt + Tab), the shell's
#    tile desktop with it in the dock, brought back from the dock:
#    vr_pic_back() 1, its rows again, tiles, map and rows as it left them;
#    vr_pic_off: tile mode off, palette entries 32-255 as it found them; it
#    quits: the shell's picture again, VRAM_TILEPAL the rows it found;
#    twice: Dusk named in WALLPAPER.CFG (the picture again), and no
#    WALLPAPER.CFG (V132: the plain desktop, in tile mode since V133: the
#    plain tile again, tests/check_wall.py plain)
# PNGs: build/gate/pic/*.png
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/pic
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
[ -f "$SDK/include/vrpic.h" ] || fail "the SDK has no vrpic.h"

# ---------------------------------------------------------------- 1. mkwall --tiles
P=$OUT/pic
mkdir -p "$P"
$PY tools/wall_tiles.py "$P/tiles.cvt" "$P/tiles" >/dev/null || fail "tools/wall_tiles.py"
mv "$P/tiles-light.png" "$P/picture.png"
$PY - "$P/picture.png" "$P/mirror.png" <<'EOF'
import sys
from PIL import Image
Image.open(sys.argv[1]).transpose(Image.FLIP_LEFT_RIGHT).save(sys.argv[2])
EOF
t0=$(date +%s%N)
$PY "$SDK/tools/mkwall.py" --tiles "$P/m" --rows 4-13 "$P/picture.png" > "$P/m.log" || fail "mkwall --tiles"
t1=$(date +%s%N)
$PY "$SDK/tools/mkwall.py" --tiles "$P/m2" --rows 4-13 "$P/picture.png" "$P/mirror.png" > "$P/m2.log" || fail "mkwall --tiles, two pictures"
grep -q exact "$P/m.log" && grep -q exact "$P/m2.log" || { cat "$P/m.log" "$P/m2.log"; fail "not exact"; }
$PY tests/check_pic.py files "$P/m" "$P/picture.png" || fail "the files of one picture"
$PY tests/check_pic.py files "$P/m2" "$P/picture.png" "$P/mirror.png" || fail "the files of two pictures"
ok "mkwall --tiles in $(( (t1 - t0) / 1000000 )) ms: $(sed 's/^mkwall --tiles: //' "$P/m.log"); two pictures: $(sed 's/^mkwall --tiles: //' "$P/m2.log")"

# ---------------------------------------------------------------- the program
A=$OUT/app
mkdir -p "$A"
n=$(ls "$P"/m.vram.* | wc -l)
recs=$(for k in $(seq 1 "$n"); do echo "$P/m.vram.$k"; done)
for v in dump:DUMP aside:ASIDE; do
	b=${v%%:*}
	cl65 -t none --cpu 65C02 -O -I "$SDK/include" --asm-include-dir "$SDK/include" -D "${v#*:}" -D PIC_RECORDS="$n" \
		-C "$SDK/cfg/app-c.cfg" -m "$A/$b.map" -o "$A/$b.bin" tests/pic_app.c "$SDK/lib/veranda.lib" > "$A/$b.log" 2>&1 \
		|| { cat "$A/$b.log"; fail "tests/pic_app.c does not build"; }
	printf 'name = PicApp\nclass = PicApp\nmode = 640x480\napi = 6\noverlays = banked\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/$b.hdr"
	mkdir -p "$A/$b"
	# shellcheck disable=SC2086
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$b/PicApp.cvt" "$A/$b.hdr" "$A/$b.bin" $recs >/dev/null || fail "vpack PicApp"
done
ok "tests/pic_app.c built against the SDK ($(stat -c %s "$A/dump.bin") bytes), $n records"

# ---------------------------------------------------------------- 2. in the program
R=$OUT/run/dump
mkdir -p "$R"
cp "$A/dump/PicApp.cvt" "$R/AUTOSTART.cvt"
cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$R/dump.bin" ] || { tail -20 "$R/console.txt"; fail "the program's run: no dump"; }
$PY tests/check_pic.py console "$R/console.txt" || fail "PicApp's lines"
$PY tests/check_pic.py shown "$R/dump.bin" "$P/m" "$P/picture.png" 4 13 || fail "the picture shown"
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/picapp.png" 2>/dev/null || true
ok "PicApp under R49: $OUT/picapp.png"

# ---------------------------------------------------------------- 3. put aside, back, quit
cp -r shell "$OUT/shell"
rm -f "$OUT/shell"/*.cvt "$OUT/shell"/*.bin "$OUT/shell"/*.map
make -s -C "$OUT/shell" SDK="$SDK" >"$OUT/shell.log" 2>&1 || { cat "$OUT/shell.log"; fail "the shell does not build"; }
# aside <run> <desktop>: dusk (named in WALLPAPER.CFG) or plain (no settings)
aside() {
	R=$OUT/run/$1
	rm -rf "$R"
	mkdir -p "$R/VERANDA/WALLPAPERS" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
	$PY "$SDK/tools/mkwall.py" -o "$R/VERANDA/WALLPAPERS/Dusk.cvt" --dusk 2>/dev/null || fail "mkwall --dusk"
	if [ "$2" = dusk ]; then        # (V132: without WALLPAPER.CFG the plain desktop: Dusk named)
		$PY -c 'import sys
c = bytearray(64)
c[0:3] = b"WP\x01"
c[8:12] = b"Dusk"
c[32:51] = b"/VERANDA/WALLPAPERS"
open(sys.argv[1], "wb").write(bytes(c))' "$R/VERANDA/.SYSTEM/WALLPAPER.CFG"
	fi
	cp "$OUT/shell/SHELL.cvt" "$R/VERANDA/"
	cp build/VERANDA.SYS build/VERANDA.PRG "$R/"
	cp "$A/aside/PicApp.cvt" "$R/DOCUMENTS/"
	echo "a note" > "$R/DOCUMENTS/Note.txt"
	$PY tests/tile_script.py "$R" picaside || fail "tests/tile_script.py picaside"
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$R/dump.bin" ] || { tail -20 "$R/console.txt"; fail "the aside run ($2): no dump"; }
	grep -a -q "SHELL DONE" "$R/console.txt" || { tail -20 "$R/console.txt"; fail "the shell's script did not end ($2)"; }
	$PY tests/check_pic.py console "$R/console.txt" aside || fail "PicApp put aside ($2)"
	$PY tests/check_pic.py kept "$R/dump.bin" "$R/console.txt" || fail "the shell after PicApp ($2)"
}
aside aside dusk
$PY tests/check_tile.py desk "$R/dump.bin" "$R/VERANDA/WALLPAPERS/Dusk.cvt" 0 --skip 2,4,62,50 >/dev/null \
	|| fail "the shell's picture after PicApp"
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/after.png" 2>/dev/null || true
ok "the shell after PicApp: its picture again ($OUT/after.png)"
aside plain plain
$PY tests/check_wall.py plain "$R/dump.bin" 14 --skip 2,4,62,50 || fail "the plain desktop after PicApp"
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/after-plain.png" 2>/dev/null || true
ok "the shell after PicApp, no settings: the plain desktop again, in tile mode ($OUT/after-plain.png)"
echo "gate pic: ok"
