#!/bin/bash
# Wallpaper v2 proposal (not for main until approved): each candidate
# wallpaper in the emulator, the shell's Apps window open in icon view
# (a package's APPS), the dock and the desktop's icons, light and dark;
# tests/apps_icons.py check counts page 1's programs in full colour (and
# page 2's, light, Page > Next after page 1: the tiles given out kept).
#
#   tools/wall_v2_shots.sh <out folder> <wallpaper.cvt> ...
#
# PINS=<programs pinned to the dock first> (default Paint,Disk Tools,Term,SID Player).
# DEFPINS=1: the dock's default pins (PINS.DEF; with PINS=""); EXTRA=<files>
# copied into APPS too (V175: the user's document letter).
# APPS=<folder> (default ~/Projects/veranda-dist/pkg-0.9.0-30e824d/VERANDA/APPS).
# Out: <out>/<name>-light.png, <name>-dark.png, <name>-light-page2.png,
# <name>.counts
set -e
cd "$(dirname "$0")/.."
OUT=$1
shift
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
APPS=${APPS:-$HOME/Projects/veranda-dist/pkg-0.9.0-30e824d/VERANDA/APPS}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
B=build/wv2
PINS=${PINS-Paint,Disk Tools,Term,SID Player}
mkdir -p "$OUT" "$B"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null
$PY tools/kbuild.py >/dev/null
tools/mksdk.sh "$B/sdk" >/dev/null
rm -rf "$B/src"
cp -r shell "$B/src"
rm -f "$B/src"/*.cvt "$B/src"/*.bin "$B/src"/*.map
make -s -C "$B/src" SDK="$(realpath "$B/sdk")" > "$B/build.log" 2>&1 || { cat "$B/build.log"; exit 1; }

for wp in "$@"; do
	name=$(basename "$wp" .cvt)
	: > "$OUT/$name.counts"
	for c in light:0 dark:0 light:1; do
		mode=${c%:*} pg=${c#*:}
		R=$B/run/$name-$mode-$pg
		rm -rf "$R"
		mkdir -p "$R/VERANDA/WALLPAPERS" "$R/VERANDA/.SYSTEM" "$R/VERANDA/APPS" "$R/DOCUMENTS"
		cp "$B/src/SHELL.cvt" "$R/VERANDA/"
		cp build/VERANDA.SYS build/VERANDA.PRG "$R/"
		cp "$wp" "$R/VERANDA/WALLPAPERS/"
		$PY - "$R/VERANDA/.SYSTEM/WALLPAPER.CFG" "$name" <<'EOF'
import sys
c = bytearray(64)
c[0:3] = b'WP\x01'
c[8:8 + len(sys.argv[2])] = sys.argv[2].encode()
d = b'/VERANDA/WALLPAPERS'
c[32:32 + len(d)] = d
open(sys.argv[1], 'wb').write(bytes(c))
EOF
		[ $mode = dark ] && $PY tests/check_theme.py prefs "$R/VERANDA/.SYSTEM/Veranda Prefs.cvt" 3 14 5 5 129
		echo "a note" > "$R/DOCUMENTS/Note.txt"
		cp "$APPS"/*.cvt $EXTRA "$R/VERANDA/APPS/"
		[ -z "$DEFPINS" ] || touch "$R/PINS.DEF"
		$PY tests/apps_icons.py script "$R" $pg --pins "$PINS"
		(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		[ -f "$R/dump.bin" ] && grep -a -q "SHELL DONE" "$R/console.txt" || { echo "$name $mode: the session did not end"; exit 1; }
		png=$OUT/$name-$mode.png
		[ $pg = 0 ] || png=$OUT/$name-$mode-page$((pg + 1)).png
		$PY tools/vram2png.py --color "$R/dump.bin" "$png"
		echo "$mode: $($PY tests/apps_icons.py check "$R/dump.bin" "$R/VERANDA/APPS" picture $pg --all 1 | tr "\n" " " | sed 's/^ *//')" >> "$OUT/$name.counts"
	done
	read n r0 r1 <<< "$($PY tools/mkwall.py --check "$wp" | sed -n '1s/^version 3, variant 0: \([0-9]*\) tiles.*palette rows \([0-9]*\)-\([0-9]*\).*/\1 \2 \3/p')"
	echo "tiles $n, palette rows $r0-$r1 ($(( r1 - r0 + 1 ))), tiles left for colour icons $(( 480 - n )) + 218 in the pool" >> "$OUT/$name.counts"
	echo "$name: $(tr '\n' ' ' < "$OUT/$name.counts")"
done
