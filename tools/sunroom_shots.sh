#!/bin/bash
# Look 3 "Sunroom", stage E's pictures (DECISIONS V152, V153): the shell in
# the emulator with the mockup's programs in /DOCUMENTS, four of them
# pinned, two put aside by the switcher (the dock's dots), on the plain
# desktop, on Dusk and on the V162 pictures (Still Water, Low Hills,
# Sunroom Tiles), light and dark; the dock beside the
# mockup's.
#
#   tools/sunroom_shots.sh <out folder> [<APPS folder of a package>] [<mockups folder>]
#
# "Veranda Write" and "Veranda Gemini" are the switcher's test program
# (tests/switch_app.s) under those names and classes (Gemini with its own
# colour icon, Veranda Write the library's); the others come from a
# package's VERANDA/APPS (read only), this repository's with their colour
# icon added (vpack.py --icon3). Out:
#   <what>-light.png, <what>-dark.png   desk, dusk, water, hills, tiles
#   side-dock.png                       the mockup's dock | the shell's (light)
set -e
cd "$(dirname "$0")/.."
OUT=${1:?usage: tools/sunroom_shots.sh <out folder> [<APPS>] [<mockups>]}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
APPS=${2:-$HOME/Projects/veranda-dist/pkg-9277017/VERANDA/APPS}
MOCK=${3:-$HOME/Projects/veranda-dist/plans/look3}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
B=$OUT/build
SDK=$(realpath -m "$B/sdk")

mkdir -p "$OUT" "$B"
make -s api >/dev/null
make -s all >/dev/null
tools/mksdk.sh "$SDK" >/dev/null
rm -rf "$B/src"
mkdir -p "$B/src"
cp shell/*.c shell/*.h shell/*.s shell/*.inc shell/Makefile shell/app.hdr shell/icon.pbm shell/icons3.txt shell/icons3s.txt "$B/src/"
make -s -C "$B/src" SDK="$(realpath "$SDK")" >/dev/null 2>&1 || { echo "the shell does not build"; exit 1; }
mkdir -p "$B/fonts" "$B/wall"
$PY tools/fontcvt.py testfonts "$B/fonts" >/dev/null
$PY "$SDK/tools/mkwall.py" -o "$B/wall/Dusk.cvt" --dusk >/dev/null 2>&1
$PY tools/wall_stillwater.py "$B/wall/Still Water.cvt" >/dev/null
$PY tools/wall_hills.py "$B/wall/Low Hills.cvt" >/dev/null
$PY tools/wall_tiles.py "$B/wall/Sunroom Tiles.cvt" >/dev/null
# the switcher's test program as Veranda Write and Veranda Gemini
fake() {        # fake <name> <class> <n> [icon3]
	ca65 --cpu 65C02 -I "$SDK/include" -D APPN=$3 -o "$B/fake$3.o" tests/switch_app.s
	ld65 -C "$SDK/cfg/app.cfg" -o "$B/fake$3.bin" "$B/fake$3.o"
	printf 'name = %s\nclass = %s\nmode = 640x480\napi = 6\nicon = %s\n' "$1" "$2" "$SDK/template/c/icon.pbm" > "$B/fake$3.hdr"
	[ -z "$4" ] || echo "icon3 = $(pwd)/$4" >> "$B/fake$3.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$B/$1.cvt" "$B/fake$3.hdr" "$B/fake$3.bin" >/dev/null
}
fake "Veranda Write" CmdrWrite 1
fake "Veranda Gemini" VerandaGemi 2 apps/gemini/icon.txt

PROGS=("Paint" "Veranda Calc" "Calendar" "Veranda Edit" "Veranda Claude"
       "Veranda Ask" "Preferences" "Solitaire" "MOD Player" "Disk Tools" "Veranda Update" "About this X16")
folder() {      # <dir> <wallpaper: none or its name> <dark>
	rm -rf "$1"
	mkdir -p "$1/VERANDA/.SYSTEM" "$1/VERANDA/FONTS" "$1/VERANDA/WALLPAPERS" "$1/DOCUMENTS/Letters"
	cp "$B/src/SHELL.cvt" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
	cp "$B/fonts/Gate Sans.cvt" "$1/VERANDA/FONTS/"
	cp "$B/wall/"*.cvt "$1/VERANDA/WALLPAPERS/"
	cp "$B/Veranda Write.cvt" "$B/Veranda Gemini.cvt" "$1/DOCUMENTS/"
	for p in "${PROGS[@]}"; do
		f="$APPS/$p.cvt"
		[ -f "$f" ] || continue
		hdr=$(grep -l "^name *= *$p\$" apps/*/app.hdr 2>/dev/null | head -1)
		if [ -n "$hdr" ] && [ -f "$(dirname "$hdr")/icon.txt" ]; then
			$PY tools/vpack.py -o "$1/DOCUMENTS/$p.cvt" --icon3 "$(dirname "$hdr")/icon.txt" "$f"
		else
			cp "$f" "$1/DOCUMENTS/"
		fi
	done
	echo "Dear Ada, the garden is in bloom." > "$1/DOCUMENTS/Note.txt"
	[ "$3" = dark ] && $PY tests/check_theme.py prefs "$1/VERANDA/.SYSTEM/Veranda Prefs.cvt" 3 14 5 5 129
	[ "$2" = none ] || $PY -c 'import sys
c = bytearray(64)
c[0:3] = b"WP\x01"
n = sys.argv[2]
c[8:8 + len(n)] = n.encode()
c[32:51] = b"/VERANDA/WALLPAPERS"
open(sys.argv[1], "wb").write(bytes(c))' "$1/VERANDA/.SYSTEM/WALLPAPER.CFG" "$2"
	$PY tests/sunroom_dock_script.py "$1" "Veranda Gemini.cvt"
}
for what in desk dusk water hills tiles; do
	for mode in light dark; do
		R=$B/run/$what-$mode
		case $what in desk) w=none ;; dusk) w=Dusk ;; water) w="Still Water" ;; hills) w="Low Hills" ;; tiles) w="Sunroom Tiles" ;; esac
		folder "$R" "$w" $mode
		cp build/VERANDA.PRG "$R/"
		(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -ram 512 -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; echo "$what $mode: no dump"; exit 1; }
		$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/$what-$mode.png" >/dev/null
		echo "$OUT/$what-$mode.png"
	done
done
$PY - "$OUT" "$MOCK" <<'EOF'
import sys
from PIL import Image, ImageDraw
out, mock = sys.argv[1:]
a = Image.open('%s/A-desktop.png' % mock).convert('RGB').crop((0, 400, 640, 480))
b = Image.open('%s/desk-light.png' % out).convert('RGB').crop((0, 400, 640, 480))
s = 2
im = Image.new('RGB', (640 * s, 80 * s * 2 + 40), (255, 255, 255))
im.paste(a.resize((640 * s, 80 * s), Image.NEAREST), (0, 20))
im.paste(b.resize((640 * s, 80 * s), Image.NEAREST), (0, 80 * s + 40))
d = ImageDraw.Draw(im)
d.text((4, 4), 'mockup (plans/look3/A-desktop.png), rows 400-479', fill=(0, 0, 0))
d.text((4, 80 * s + 24), 'x16emu: the shell, rows 400-479', fill=(0, 0, 0))
im.save('%s/side-dock.png' % out)
print('%s/side-dock.png' % out)
EOF
