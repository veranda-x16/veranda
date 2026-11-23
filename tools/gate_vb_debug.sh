#!/bin/bash
# Gate vb_debug (VeraBASIC phase 6, docs/DECISIONS.md V97): the debugger in
# VeraBASIC, the editor: breakpoints, STOP, Step, Step over, Step out, the
# pane (the call stack, the variables, watches, a value changed, arrays'
# elements), the program's screen kept over a break, TRON's trace pane, the
# error messages.
#
#   tools/gate_vb_debug.sh   (OUT=dir; R49=the ROM image; VB_SD=0: no SD card
#                             image; VB_JOBS=n)
#
# 1. the kernel and the SDK; VeraBASIC and its test build (IDE_TEST) built
#    against it: overlay 12 (the runtime's side, vbdbg.s) below DI_BASE
#    ($B000: what the two sides share is above it), the debugger's bank B9
#    within 8 KB, main RAM's room for a program's names (2,048 at least)
# 2. the sessions under ROM R49 at 512 KB (tests/vbasic/debug_script.py):
#    debug, screen_a, screen_b, trace, error, kerror; debug again on an SD
#    card image; tests/vbasic/check_debug.py: the breaks in order with
#    their call stacks, the variables' and watches' values, the change of a
#    local, the arrays' elements, the console after Continue; screen_b's
#    screen (a break, steps, a dialog box, Continue) equal to screen_a's
#    (no break): the bitmap, the colour map, the palette, sprites 2-7; the
#    trace pane's 200 lines the last of tools/vbasic.py run --trace's; the
#    error messages (the statement in canonical form, the procedure, the
#    kernel's code)
# 3. the RAM banks VeraBASIC holds at rest and while a program is stopped
#    (the test build's "IDE BANKS" log); screenshots: a break with the
#    variables and watches, the call stack four FUNCTION calls deep, the
#    trace pane, an error's message
# 4. the manual's chapter (docs/vbasic/manual/debugging.md): its listings
#    check and run in the reference
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_debug}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
JOBS=${VB_JOBS:-6}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
rm -rf "$OUT"
mkdir -p "$OUT"
TOP=$(pwd)

# 1. the builds
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/app" ide >"$OUT/app/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/app/build.log" | tail; fail "VeraBASIC does not build"; }
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/test" idetest >"$OUT/test/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/test/build.log" | tail; fail "the test build does not build"; }
seg() { sed -n "s/^$2  *\([0-9A-F]*\)  *\([0-9A-F]*\).*/\1 \2/p" "$1"; }
M=$OUT/app/ide/vbide.map
e12=$(seg "$M" OVL12BSS | cut -d' ' -f2)
[ -n "$e12" ] && [ $((16#$e12)) -lt $((0xB000)) ] || fail "overlay 12 runs to \$$e12, into DI (\$B000)"
e9=0
for sg in B9CODE B9RO B9BSS; do
	x=$(seg "$OUT/app/ide/ide.map" $sg | cut -d' ' -f2)
	[ -n "$x" ] && [ $((16#$x)) -gt $e9 ] && e9=$((16#$x))
done
[ $e9 -le $((0xBFFF)) ] || fail "the debugger's bank B9 runs to $e9"
end=$(seg "$M" BSS | cut -d' ' -f2)
room=$(( 0x8800 - 0x200 - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for a program's names (2048 at least)"
$PY tests/vbasic/check_ide_banks.py apps/vbasic >/dev/null || fail "the editor's calls across its banks"
ok "VeraBASIC builds: overlay 12 (the runtime's side) to \$$e12 (DI from \$B000), the debugger's bank B9 $(( e9 - 0xA000 + 1 )) bytes,"
ok "  $room bytes of main RAM for a program's names; the test build (IDE_TEST)"
T=$OUT/test/idetest/VeraBASIC.cvt

# 2, 3. the sessions: $1 the folder's name, $2 the session, $3 the stop (or -), $4 sd|-
session() {
	local d=$OUT/s/$1 ss=$2 st=$3 sd=$4
	rm -rf "$d"
	mkdir -p "$d/card"
	local C=$d/card
	cp "$T" "$C/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$C/"
	$PY tests/vbasic/debug_script.py "$ss" "$C" $( [ "$st" != - ] && echo --stop "$st") || { echo script > "$d/fail"; return; }
	if [ "$sd" = sd ]; then
		$PY tools/vcard.py make --mb 64 "$d/sd.img" "$C" >/dev/null
		cp build/VERANDA.PRG "$d/"
		(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
		rm -f "$d/sd.img"
	else
		cp build/VERANDA.PRG "$C/"
		(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		cp "$C/console.txt" "$d/"
		[ -f "$C/dump.bin" ] && mv "$C/dump.bin" "$d/"
	fi
	echo done > "$d/done"
}
export -f session
export OUT T EMU R49 PY
SESS=("debug debug - -" "screen_a screen_a - -" "screen_b screen_b - -" "trace trace - -" "error error - -"
	"kerror kerror - -" "brk debug brk -" "stack debug stack -" "tracepane trace trace -" "errorpane error error -")
[ "${VB_SD:-1}" != 0 ] && SESS+=("sd debug - sd")
printf '%s\n' "${SESS[@]}" | xargs -P "$JOBS" -L 1 bash -c 'session "$@"' _
ok "${#SESS[@]} sessions run (ROM R49, 512 KB, $JOBS at a time)"
for s in "${SESS[@]}"; do
	n=${s%% *}
	[ -f "$OUT/s/$n/fail" ] && fail "$n: $(cat "$OUT/s/$n/fail")"
	grep -a -q "HUNG" "$OUT/s/$n/console.txt" && { grep -a "IDE" "$OUT/s/$n/console.txt" | tail -5; fail "$n: hung"; }
done
$PY tests/vbasic/check_debug.py "$OUT/s" "$R49" || fail "the sessions"
if [ -d "$OUT/s/sd" ]; then
	mkdir -p "$OUT/sdchk/debug"
	cp "$OUT/s/sd/console.txt" "$OUT/sdchk/debug/"
	$PY -c "import sys; sys.path.insert(0, 'tests/vbasic'); import check_debug as c; c.check_debug(sys.argv[1]); [print('FAIL  sd: ' + e) for e in c.errors]; sys.exit(1 if c.errors else 0)" "$OUT/sdchk" \
		|| fail "the debug session on an SD card image"
	ok "the debug session on an SD card image: the same breaks, stacks, values and console"
fi
# Continue's time (the test build: "VB RESUME whole screen", the emulator's
# cycles in hex: from ide_go, and the screen's part, at 8 MHz)
ms=$(grep -a -h "VB RESUME" "$OUT/s/debug/console.txt" "$OUT/s/screen_b/console.txt" | tr -d '\r' \
	| while read -r _ _ a b; do echo "$(( 16#$a / 8000 )) $(( 16#$b / 8000 ))"; done | sort -n -k2 | sed -n '1p;$p' | tr '\n' ' ')
set -- $ms
[ -n "$4" ] && [ "$4" -le 150 ] || fail "Continue: the screen took ${4:-?} ms (150 at most)"
ok "Continue: the program's screen back in $2-$4 ms (its bitmap through VERA's two ports, about 46 ms of it), $1-$3 ms in all"
held() { sed -n "s/.*IDE BANKS \([0-9]*\) \([0-9]*\).*/\1 \2/p" "$OUT/s/$1/console.txt" | sed -n "$2p"; }
b0=$(held debug 1)
b1=$(held debug 2)
[ -n "$b0" ] && [ -n "$b1" ] || fail "no IDE BANKS log"
rest=$(( ${b0% *} - ${b0#* } ))
brk=$(( ${b1% *} - ${b1#* } ))
ok "RAM banks: VeraBASIC holds $rest of the ${b0% *} for programs at rest (512 KB; the test build: its player's bank one of"
ok "  them), $brk with debug.bas stopped at its first break"
for s in brk stack tracepane errorpane; do
	[ -f "$OUT/s/$s/dump.bin" ] || fail "$s: no screen"
	$PY "$SDK/tools/vram2png.py" --color "$OUT/s/$s/dump.bin" "$OUT/$s.png" >/dev/null || fail "vram2png $s"
done
$PY "$SDK/tools/vram2png.py" --color "$OUT/s/screen_b/dump.bin" "$OUT/screen.png" >/dev/null || fail "vram2png screen"
ok "screenshots: $OUT/brk.png (a break: the variables, the watches), stack.png (the call stack),"
ok "  tracepane.png (TRON's trace), errorpane.png (an error's message), screen.png (the program after a break)"

# 5. VeraBASIC Run's box when an error stops a program whose windows hide
# the console (V95's "see the console", past the box): its words in three
# lines that fit, against a golden (tests/vbasic/debug/golden.txt); the real
# shell double-clicks the program document, the mouse emulator's script
# waits and stops (tests/vbasic/runbox_script.py)
EMUM=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
if { "$EMUM" -help 2>&1 || true; } | grep -q -- -mousescript; then
	mkdir -p "$OUT/run" "$OUT/box"
	make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/run" >"$OUT/run/build.log" 2>&1 || fail "VeraBASIC Run does not build"
	cp -r shell "$OUT/shsrc"
	rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
	make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || fail "the shell does not build"
	B=$OUT/box
	N="The feeder program that stops on an error"
	$PY tools/vbasic.py build tests/vbasic/debug/boom.bas -o "$B/$N.cvt" >/dev/null || fail "vbasic.py build boom.bas"
	cp "$OUT/shsrc/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$B/"
	cp "$OUT/run/VBRun.cvt" "$B/VeraBASIC Run.cvt"
	$PY tests/vbasic/runbox_script.py "$B" "$N.cvt" || fail "runbox_script.py"
	$PY tests/vbasic/ui_mouse.py "$B/box.ms" "$OUT/run/vbrun.map" "$B/mouse.txt" || fail "ui_mouse.py"
	(cd "$B" && SDL_VIDEODRIVER=dummy timeout -s INT 240 "$EMUM" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -mousescript mouse.txt > console.txt 2>&1) || true
	[ -f "$B/dump.bin" ] || fail "VeraBASIC Run's box: no screen"
	mkdir -p "$OUT/s/runbox"
	cp "$B/dump.bin" "$OUT/s/runbox/"
	$PY tests/vbasic/check_ui.py "$OUT/s" tests/vbasic/debug/golden.txt runbox || fail "VeraBASIC Run's box"
	$PY "$SDK/tools/vram2png.py" --color "$B/dump.bin" "$OUT/runbox.png" >/dev/null
	ok "VeraBASIC Run's box when an error stops a program under its windows: the name, the error and its line,"
	ok "  its words, each line within the box (the golden; $OUT/runbox.png)"
else
	echo "skip  VeraBASIC Run's box: $EMUM has no -mousescript (the emulator's branch mousescript)"
fi

# 4. the chapter's listings
L=$OUT/listings
$PY tests/vbasic/doclistings.py "$L" docs/vbasic/manual/debugging.md > "$OUT/listings.txt" 2>/dev/null || fail "the chapter's listings"
n=0
for f in "$L"/*.bas; do
	$PY tools/vbasic.py check "$f" >/dev/null || fail "$f does not check"
	$PY tools/vbasic.py run "$f" --rom "$R49" > "${f%.bas}.out" 2>&1 || true
	if grep -q "^Error" "${f%.bas}.out"; then fail "$f: $(cat "${f%.bas}.out")"; fi
	n=$((n + 1))
done
ok "the chapter (docs/vbasic/manual/debugging.md): its $n listings check and run in the reference"
echo "GATE vb_debug: PASS"
