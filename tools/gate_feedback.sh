#!/bin/bash
# Gate feedback (DECISIONS V51): the pointer's shapes, the system beep,
# blanking the screen.
#
#   tools/gate_feedback.sh
#
# tests/feedback.s (TEST.PRG) sets each pointer shape, makes a long call
# (the busy pointer by itself), beeps, lets the screen blank after 2 s of
# no input and wakes it with a key and with a press (neither passed on),
# then clicks; a monitor in the interrupt logs sprite 0's picture,
# DC_VIDEO, palette entry 0 and PSG voice 15 whenever they change.
# tests/check_feedback.py checks the log and the dump (sprite 0's slot
# and attributes) and writes the shapes as PNGs (ptr-*.png).
#
# Part 2 (V96): the real shell (release build) under ROM R49 at 512 KB
# with real PS/2 input (EMU_MOUSE: x16emu's branch with -mousescript), a
# blankDelay of 3 s from the settings file, on the Dusk wallpaper, on the
# plain pattern and in Paint: the screen blanks (the display window
# closed, DC_VIDEO as it was); a mouse move (moved back) and a key each
# wake it, and the dump then equals a session that stayed blanked as long
# but for the display window and palette entry 0, back as before (VRAM,
# the colour map, the palette, the layers, the sprites); after a wake a
# click on the bar's File opens its menu (tests/check_blank.py). The bug
# it guards: the ROM's mouse_scan turns the sprites on (DC_VIDEO bit 6)
# at every mouse packet, and the wake took that for a video mode set
# while blanked and left the layers off: a black screen for good.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/feedback
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/run"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
ca65 --cpu 65C02 -I build/gen -I inc tests/feedback.s -o "$OUT/feedback.o" || fail "tests/feedback.s"
ca65 tests/prghdr.s -o "$OUT/prghdr.o"
ld65 -C cfg/testprg.cfg "$OUT/prghdr.o" "$OUT/feedback.o" -o "$OUT/run/TEST.PRG" || fail "tests/feedback.s does not link"
cp build/VERANDA.PRG build/VERANDA.SYS "$OUT/run/"
(cd "$OUT/run" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$OUT/run/dump.bin" ] || { tail -20 "$OUT/run/console.txt"; fail "the session did not end (no dump)"; }
$PY tests/check_feedback.py "$OUT/run" "$OUT" || fail "feedback"
$PY tools/check_vera.py "$OUT/run/dump.bin" || fail "the display after the session"

# ---------------------------------------------------------------- part 2: the real shell, R49, real input
EMUM=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || fail "no ROM R49 at $R49"
{ "$EMUM" -help 2>&1 || true; } | grep -q -- -mousescript || fail "$EMUM has no -mousescript (the emulator's branch mousescript)"
TOP=$(pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
cp -r shell "$OUT/shsrc"
rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || { tail "$OUT/shsrc/build.log"; fail "the shell does not build"; }
mkdir -p "$OUT/paint"
make -s -C apps/paint SDK="$SDK" OUT="$TOP/$OUT/paint" >"$OUT/paint/build.log" 2>&1 || { tail "$OUT/paint/build.log"; fail "Paint does not build"; }
$PY "$SDK/tools/mkwall.py" -o "$OUT/Dusk.cvt" --dusk 2>/dev/null || fail "mkwall --dusk"
BL=$(sed -n 's/^al 00\([0-9A-F]*\) \.kBlanked$/\1/p' build/k/resident.lab)
[ -n "$BL" ] || fail "kBlanked not in build/k/resident.lab"
# $1 the session, $2 the desktop (dusk|plain|paint), $3 the input after the
# blanking (mousescript lines, frames from the blanking); the dump in
# $OUT/blank/$1
blank_run() {
	local d=$OUT/blank/$1 pre="0 id 3"
	rm -rf "$d"
	mkdir -p "$d/VERANDA/WALLPAPERS" "$d/VERANDA/.SYSTEM"
	cp build/VERANDA.SYS build/VERANDA.PRG "$d/"
	# the settings: the paper $FFF, blankDelay 3 s, Look 2's theme
	$PY -c 'import sys; open(sys.argv[1], "wb").write(bytes(508) + bytes([0xFF, 0x0F, 0x23, 0x02, 3, 0, 0, 0xFF, 0, 0, 5, 13, 4, 0x80, 0x80, 0]))' \
		"$d/VERANDA/.SYSTEM/Veranda Prefs.cvt"
	if [ "$2" = paint ]; then
		# the shell's flat layout: its SHELL.TST double-clicks Paint
		cp "$OUT/shsrc/SHELL.cvt" "$OUT/paint/Paint.cvt" "$d/"
		mv "$d/VERANDA/.SYSTEM/Veranda Prefs.cvt" "$d/"
		rm -r "$d/VERANDA"
		$PY tests/check_blank.py tst "$d" Paint.cvt || fail "SHELL.TST"
		pre="$pre"$'\n'"200 move 0 0"
	else
		cp "$OUT/shsrc/SHELL.cvt" "$d/VERANDA/"
		[ "$2" = plain ] || cp "$OUT/Dusk.cvt" "$d/VERANDA/WALLPAPERS/"
	fi
	printf '%s\nwait %s 80\n%s\n' "$pre" "$BL" "$3" > "$d/mouse.txt"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMUM" -rom "$R49" -ram 512 -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -mousescript mouse.txt > console.txt 2>&1) || true
	[ -f "$d/dump.bin" ] || { tail -5 "$d/console.txt"; fail "blank $1: the session did not end (no dump)"; }
}
REF=$'190 exit'
MOVE=$'60 move 5 5\n70 move -5 -5\n190 exit'
KEY=$'60 type x\n190 exit'
FILE=$'70 move -2000 -2000\n90 move 93 6\n100 down 1\n104 up 1\n164 exit'
for desk in dusk plain paint; do
	blank_run "$desk-ref" $desk "$REF"
	$PY tests/check_blank.py blanked "$OUT/blank/$desk-ref/dump.bin" >/dev/null || fail "$desk: not blanked"
	for w in move key; do
		if [ $w = move ]; then in=$MOVE; else in=$KEY; fi
		blank_run "$desk-$w" $desk "$in"
		$PY tests/check_blank.py same "$OUT/blank/$desk-ref/dump.bin" "$OUT/blank/$desk-$w/dump.bin" 0FFF \
			>/dev/null || fail "$desk: woken by a $w"
		[ $desk != paint ] || continue
		if [ $w = move ]; then in='60 move 5 5'; else in='60 type x'; fi
		blank_run "$desk-$w-file" $desk "$in"$'\n'"$FILE"
		$PY tests/check_blank.py menu "$OUT/blank/$desk-ref/dump.bin" "$OUT/blank/$desk-$w-file/dump.bin" \
			>/dev/null || fail "$desk: after a $w the shell does not answer"
	done
	m=""
	[ $desk = paint ] || m="; a click on File after either opens its menu"
	ok "R49, real input, $desk: blanked (DC_VSTOP 0, DC_VIDEO as awake); a mouse move and a key each wake it: the display, VRAM, the colour map, the palette, the layers and the sprites as before$m"
	$PY tools/vram2png.py --color "$OUT/blank/$desk-move/dump.bin" "$OUT/blank-$desk.png" 2>/dev/null || true
done
echo "pointer shapes: $OUT/ptr-arrow.png, ptr-ibeam.png, ptr-cross.png, ptr-busy.png"
echo "GATE feedback: PASS"
