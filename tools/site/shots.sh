#!/bin/bash
# The website's own screenshots (DECISIONS V139), into tools/site/img/:
#   paint.png       Paint drawing tools/site/paint_picture.py's summer house
#                   with its own tools, in the emulator (Paint's test build
#                   plays the session; the screen at its end)
#   verabasic.png   VeraBASIC's editor, from gate vb_ide (colour.png: the
#                   syntax colours; run tools/gate_vb_ide.sh first)
#   birdwatch.png   Bird Watch, the application VeraBASIC made, from gate
#                   vb_ui (s/bird7; run tools/gate_vb_ui.sh first)
# The look is Sunroom, the default (no preferences in the folders).
# The games (game-*.png) come from their own repositories' gates, each run
# on a copy of its build ref against Veranda's main: Lighthouse Pinball's
# tools/gate.sh (ferry.png), Harbour Walls' tools/gate.sh (capture.png),
# Solitaire's tools/gate_veranda.sh (klondike-end.png), geoChess's
# tools/gate_veranda.sh (GC1's screen, vram2png --color).
#
#   tools/site/shots.sh            (EMU, ROM as the gates')
set -e
cd "$(dirname "$0")/../.."
TOP=$PWD
OUT=build/site-shots
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
IMG=tools/site/img
rm -rf "$OUT"
mkdir -p "$OUT/script" "$OUT/paint" "$OUT/run/VERANDA/FONTS" "$OUT/fonts"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null
$PY tools/kbuild.py >/dev/null
tools/mksdk.sh "$OUT/sdk" >/dev/null
SDK=$(cd "$OUT/sdk" && pwd)
$PY tools/site/paint_picture.py "$OUT/script"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$OUT/paint" TESTFLAGS="-DPAINT_DA -I$TOP/$OUT/script" >"$OUT/paint/build.log" 2>&1 ||
	{ cat "$OUT/paint/build.log"; exit 1; }
$PY tools/fontcvt.py testfonts "$OUT/fonts" >/dev/null
cp "$OUT/fonts/Gate Sans.cvt" "$OUT/fonts/Gate Mono.cvt" "$OUT/run/VERANDA/FONTS/"
cp "$OUT/paint/Paint.cvt" "$OUT/run/AUTOSTART.cvt"
cp build/VERANDA.PRG build/VERANDA.SYS "$OUT/run/"
(cd "$OUT/run" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$OUT/run/dump.bin" ] || { tail -5 "$OUT/run/console.txt"; echo "shots: Paint's session did not finish"; exit 1; }
$PY tools/vram2png.py --color "$OUT/run/dump.bin" "$IMG/paint.png" >/dev/null
echo "shots: $IMG/paint.png"
for s in "build/gate/vb_ide/colour.png verabasic.png" "build/gate/vb_ui/s/bird7/screen.png birdwatch.png"; do
	set -- $s
	if [ -f "$1" ]; then
		cp "$1" "$IMG/$2"
		echo "shots: $IMG/$2 (from $1)"
	else
		echo "shots: no $1 (run its gate first): $IMG/$2 kept"
	fi
done
