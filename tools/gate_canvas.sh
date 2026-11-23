#!/bin/bash
# Gate canvas (DECISIONS V166): the kernel's canvas mode (bank C,
# kernel/c/canvas.s; ColorRect COLOR_CANVAS) and the SDK's vrcanvas.h:
# a picture of one byte a pixel in the 320 x 240 mode.
#
#   tools/gate_canvas.sh
#
# 1. the kernel (bank C), the SDK installed (vrcanvas.h, vrcanvas.s);
#    tests/canvas_app.c (CanvApp), tests/canvas_da.c (CanvDA, a desk
#    accessory) and tests/canvas_desk.c (a test desktop) built against it
# 2. shots (CanvApp as AUTOSTART, its script stopped there; the dump,
#    tests/check_canvas.py): the File menu open, the SDK's Open box over
#    the picture: VERA's registers (layer 0 the 8 bpp bitmap at $02800,
#    layer 1 the 1 bpp screen); every byte of the picture CanvApp's but
#    on the covered cards, which are 0 and are the menu's (the box's)
#    cards; PNGs composed at 2x
# 3. the session at 512 KB on the host folder in Fast mode, and in Roomy
#    mode with CanvApp holding every bank it may (-D HUGE: it goes onto
#    the card): its console (tests/check_canvas.py console): the canvas on;
#    the menu covered cards and gave every byte back; after the Open box,
#    after CanvDA (which saw the picture hidden: the 1 bpp screen on
#    layer 0) and after Alt + Tab and back the picture and the palette as
#    CanvApp drew them; put aside it held few banks (Fast) or a small
#    file besides its own banks (Roomy); after it quit palette entries
#    16-255 as before it started
# 4. (V177) the same session with desktops of mode "keep" (the settings'
#    mode "as it is"): at 640 x 480, and one that sets 640 x 240 itself:
#    the desktop back in its mode after Alt + Tab and after CanvApp quit
#    (it came back in CanvApp's 320 x 240)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/canvas
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
kb=$($PY tools/kbuild.py) || fail "the kernel does not build"
ok "the kernel's room: $(echo "$kb" | sed -n 's/.*banks (bytes used): \([^;]*\);.*/\1/p') of 8192 (G to 7998: IDX_COPY; T's code to \$BC00, then its TAIL)"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
[ -f "$SDK/include/vrcanvas.h" ] || fail "the SDK has no vrcanvas.h"
$PY tests/canvas_script.py "$OUT/canvas_script.h" && cmp -s "$OUT/canvas_script.h" tests/canvas_script.h \
	|| fail "tests/canvas_script.h is not what tests/canvas_script.py writes"
shot() { sed -n "s|^/\* shot $1 \([0-9]*\) \*/|\1|p" tests/canvas_script.h; }

A=$OUT/app
mkdir -p "$A"
CC="cl65 -t none --cpu 65C02 -O -I $SDK/include -I tests --asm-include-dir $SDK/include"
build() {       # build <name> <source> <header lines> [defines]
	nm=$1 src=$2 hdr=$3
	shift 3
	# shellcheck disable=SC2086
	$CC "$@" -C "$SDK/cfg/app-c.cfg" -m "$A/$nm.map" -o "$A/$nm.bin" "$src" tests/sdk_play.s "$SDK/lib/veranda.lib" \
		> "$A/$nm.log" 2>&1 || { cat "$A/$nm.log"; fail "$src ($nm) does not build"; }
	printf "$hdr\nicon = %s\n" "$SDK/template/c/icon.pbm" > "$A/$nm.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/$nm.cvt" "$A/$nm.hdr" "$A/$nm.bin" >/dev/null || fail "vpack $nm"
}
APPH='name = CanvApp\nclass = CanvApp\nmode = 320x240\napi = 7'
build CanvApp tests/canvas_app.c "$APPH"
build CanvHuge tests/canvas_app.c "$APPH" -D HUGE
build CanvMenu tests/canvas_app.c "$APPH" -D STOP="$(shot menu)" -D NOASIDE
build CanvClosed tests/canvas_app.c "$APPH" -D STOP="$(shot closed)" -D NOASIDE
build CanvBox tests/canvas_app.c "$APPH" -D STOP="$(shot dialog)" -D NOASIDE
build CanvDA tests/canvas_da.c 'name = CanvDA\nclass = CanvDA\ntype = deskacc\nmode = keep\napi = 1'
build SHELL tests/canvas_desk.c 'name = SHELL\nclass = CanvDesk\nmode = 640x480\napi = 7'
# (V177) desktops of mode "keep", as Veranda's shell: the settings' mode
# none ("as it is"), the desktop at 640 x 480 from the start, or setting
# 640 x 240 itself
build SHELLK tests/canvas_desk.c 'name = SHELL\nclass = CanvDesk\nmode = keep\napi = 7'
build SHELLK240 tests/canvas_desk.c 'name = SHELL\nclass = CanvDesk\nmode = keep\napi = 7' -D DESKMODE=1
ok "CanvApp ($(stat -c %s "$A/CanvApp.bin") bytes), CanvDA and the test desktop built against the SDK"

# ---------------------------------------------------------------- 2. shots
for s in menu:CanvMenu closed:CanvClosed dialog:CanvBox; do
	w=${s%%:*}
	R=$OUT/run/$w
	mkdir -p "$R"
	cp "$A/${s#*:}.cvt" "$R/AUTOSTART.cvt"
	cp "$A/CanvDA.cvt" "$R/"
	cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$R/dump.bin" ] || { tail -20 "$R/console.txt"; fail "the $w shot: no dump"; }
	$PY tests/check_canvas.py shot "$R/dump.bin" "$w" || fail "the $w shot"
	$PY tools/vram2png.py --color --scale 2 "$R/dump.bin" "$OUT/$w.png" 320 240 || fail "vram2png"
	ok "the $w shot: $OUT/$w.png"
done

# ---------------------------------------------------------------- 3. sessions
prefs() {       # prefs <dir> <bits>: Veranda Prefs.cvt with PREFS_SWITCH (V145)
	$PY -c 'import sys; d=bytearray(open("tests/sound_prefs_v65.cvt","rb").read()); d[508+6] = (d[508+6] & ~0x30) | int(sys.argv[2]); open(sys.argv[1],"wb").write(d)' "$1/Veranda Prefs.cvt" "$2"
}
session() {     # session <name> <app> <switcher bits> [<desktop>]
	R=$OUT/run/$1
	mkdir -p "$R/VERANDA/.SYSTEM"
	cp "$A/$2.cvt" "$R/VERANDA/CanvApp.cvt"
	cp "$A/CanvDA.cvt" "$R/VERANDA/"
	cp "$A/${4:-SHELL}.cvt" "$R/VERANDA/SHELL.cvt"
	prefs "$R/VERANDA" "$3"
	cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$ROM" -ram 512 -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	echo "== $1"
	$PY tests/check_canvas.py console "$R/console.txt" "$1" || { tr -d '\r' < "$R/console.txt" | grep -a "CANV\|TASK" | tail -30; fail "the $1 session"; }
	$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/$1-end.png" 2>/dev/null || true
}
session fast CanvApp 16
session roomy CanvHuge 32
session keep480 CanvApp 16 SHELLK
session keep240 CanvApp 16 SHELLK240
echo "GATE canvas: PASS"
