#!/bin/bash
# Gate vb_ide (VeraBASIC phase 5, docs/DECISIONS.md V93): VeraBASIC, the
# editor and the runtime in one application, built from Veranda Edit's
# textkit (sdk/lib/textkit).
#
#   tools/gate_vb_ide.sh   (OUT=dir; R49=the ROM image; VB_SD=0: no SD card
#                           image; VB_EDIT=0: not gate edit again;
#                           VB_GOLDEN=1: the screens' goldens written anew;
#                           VB_JOBS=n)
#
# 1. the kernel and the SDK (textkit in src/textkit); VeraBASIC built
#    against it: an application (VRND, 640x480, API 6, documents BAS), its
#    main RAM part (LOW) within the interpreter's code's place, every bank
#    and overlay within 8 KB, main RAM's room for a program's names (2,048
#    at least), every call to another bank through xcall
#    (tests/vbasic/check_ide_banks.py); VeraBASIC Run still the same size;
#    the help files (vbgen.py: KEYWORDS, ERRORS, TUTORIAL, EDITOR.HLP) as
#    committed; the test build (IDE_TEST: tests/edit_play.s plays IDE.PLY)
# 2. the session under ROM R49 (tests/vbasic/ide_script.py; the help in
#    VERANDA/HELP): a long-named .bas opened through the Open dialog, a
#    program typed, Check finds the planted error and jumps to it, fixed,
#    checked, Run (its console as tools/vbasic.py run's), a key back, a
#    loop added, Run, Ctrl+C: stopped and marked, Save: the file on the host
#    equals the text typed; F1 on PRINT: its page; Format: the canonical
#    form, saved through the Save dialog under a new long name: it equals
#    tools/vbtokens.py's canon (tests/vbasic/check_ide.py); the same on an
#    SD card image
# 3. the screens: the session stopped on the way (VRAM dumps): the
#    colouring and the error's line, light and dark (Veranda Prefs: dark
#    mode), against goldens (tests/vbasic/ide/golden.txt: the bitmap, the
#    colour map, the palette); screenshots of those, the help page, the
#    program's console, the line stopped at, Format's result
# 3c. (V215) scrolling's speed: tests/scroll_speed.py's session timed (a
#    line within 50 ms, a page within 300 ms at 8 MHz) and again with the
#    redraw check after every step (the window against a full drawing)
# 4. the shell: a double click on a long-named .bas starts VeraBASIC with
#    it, in a folder with VeraBASIC Run too (Run no longer says BAS)
#    and the switcher (2 MB of RAM: tests/vbasic/ide_aside.py): put aside
#    and back while editing and while a program runs
# 5. gate edit (textkit's guard)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_ide}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
JOBS=${VB_JOBS:-6}
G=tests/vbasic/ide

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
rm -rf "$OUT"
mkdir -p "$OUT"
TOP=$(pwd)

# 1. the builds
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
# the sessions' kernel: this build's, kept here (V106: another gate's kbuild
# meanwhile does not change what the sessions copy)
mkdir -p "$OUT/k"
cp build/VERANDA.SYS build/VERANDA.PRG "$OUT/k/"
K=$OUT/k
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
for f in textkit.h buf.s text.c ops.c undo.c view.c find.c scrap.c file.c; do
	[ -f "$SDK/src/textkit/$f" ] || fail "the SDK has no src/textkit/$f"
done
$PY tools/vbgen.py --out "$OUT/gen" >/dev/null || fail "vbgen.py"
for f in KEYWORDS ERRORS TUTORIAL EDITOR; do
	cmp -s "$OUT/gen/vbasic/gen/HELP/$f.HLP" "vbasic/gen/HELP/$f.HLP" || fail "vbasic/gen/HELP/$f.HLP is not what vbgen.py makes"
done
cmp -s "$OUT/gen/vbasic/gen/idekw.h" vbasic/gen/idekw.h || fail "vbasic/gen/idekw.h is not what vbgen.py makes"
ok "the SDK with textkit (src/textkit); the help files and the editor's tables as vbgen.py makes them"
mkdir -p "$OUT/app" "$OUT/run"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/app" ide >"$OUT/app/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/app/build.log" | tail; fail "VeraBASIC does not build"; }
A=$OUT/app/ide/VeraBASIC.cvt
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] \
	|| fail "VeraBASIC.cvt: not an application (VRND, 640x480)"
$PY "$SDK/tools/vpack.py" --list "$A" | grep -q "BAS" || fail "VeraBASIC.cvt: no documents BAS"
seg() { sed -n "s/^$2  *\([0-9A-F]*\)  *\([0-9A-F]*\).*/\1 \2/p" "$1"; }
M=$OUT/app/ide/vbide.map
end=$(seg "$M" BSS | cut -d' ' -f2)
room=$(( 0x8800 - 0x200 - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for a program's names (2048 at least)"
lb=$OUT/app/ide/vbide.lbl
s0=$(sed -n 's/^al 00\([0-9A-F]*\) \._ide_s0$/\1/p' "$lb")
s1=$(sed -n 's/^al 00\([0-9A-F]*\) \._ide_s1$/\1/p' "$lb")
lowend=$(seg "$OUT/app/ide/ide.map" BSS | cut -d' ' -f2)
low=$(( 16#$lowend - 16#$s0 + 1 ))
place=$(( 16#$s1 - 16#$s0 ))
[ "$low" -le "$place" ] || fail "the editor's main RAM part: $low bytes, its place $place"
sizes=""
for n in 1 2 3 4 5 6 7 8 9 12; do
	e=$(seg "$M" "OVL${n}BSS" | cut -d' ' -f2)
	[ -n "$e" ] || e=$(seg "$M" "OVERLAY$n" | cut -d' ' -f2)
	[ -n "$e" ] || { sizes="$sizes $n:-"; continue; }   # (5: vbfloat.s is in overlay 8, V149)
	s=$(( 16#$e - 0xA000 + 1 ))
	[ "$s" -le 8192 ] || fail "overlay $n: $s bytes with its BSS"
	sizes="$sizes $n:$s"
done
banks=""
for n in 1 2 3 4 5 6 7 8 9; do
	e=0
	for sg in B${n}CODE B${n}RO B${n}BSS; do
		x=$(seg "$OUT/app/ide/ide.map" $sg | cut -d' ' -f2)
		[ -n "$x" ] && [ $((16#$x)) -gt $e ] && e=$((16#$x))
	done
	s=$(( e - 0xA000 + 1 ))
	[ "$s" -le 8192 ] || fail "the editor's bank $n: $s bytes"
	banks="$banks B$n:$s"
done
dyn=$(( 0x8600 - 16#$end - 1 ))
$PY tests/vbasic/check_ide_banks.py apps/vbasic || fail "the editor's calls across its banks"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/run" >"$OUT/run/build.log" 2>&1 || fail "VeraBASIC Run does not build"
rend=$(seg "$OUT/run/vbrun.map" BSS | cut -d' ' -f2)
rroom=$(( 0x8800 - 0x200 - 16#$rend - 1 ))
ok "VeraBASIC builds: main RAM to \$$end, $room bytes for a program's procedures and names (VeraBASIC Run: $rroom);"
ok "  its main RAM part (LOW) $low bytes in the interpreter's code's place (\$$s0-\$$s1, $place bytes);"
ok "  overlays with their BSS:$sizes; the editor's banks:$banks"
mkdir -p "$OUT/test"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/test" idetest >"$OUT/test/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/test/build.log" | tail; fail "the test build does not build"; }
T=$OUT/test/idetest/VeraBASIC.cvt
ok "the test build (IDE_TEST)"

# 2, 3. the sessions: $1 the folder's name, $2 the stop (or -), $3 dark|-, $4 sd|-
session() {
	local d=$OUT/s/$1 st=$2 dk=$3 sd=$4
	rm -rf "$d"
	mkdir -p "$d/card/VERANDA/HELP"
	local C=$d/card
	cp "$T" "$C/AUTOSTART.cvt"
	cp "$K/VERANDA.SYS" "$C/"
	cp vbasic/gen/HELP/*.HLP "$C/VERANDA/HELP/"
	[ "$dk" = dark ] && $PY tests/check_theme.py prefs "$C/Veranda Prefs.cvt" 5 13 4 0 129
	$PY tests/vbasic/ide_script.py "$C" $( [ "$st" != - ] && echo --stop "$st") || { echo script > "$d/fail"; return; }
	if [ "$sd" = sd ]; then
		cp "$C/expect.json" "$d/"
		$PY tools/vcard.py make --mb 64 "$d/sd.img" "$C" >/dev/null
		cp "$K/VERANDA.PRG" "$d/"
		(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
		mkdir -p "$d/out"
		cp "$d/expect.json" "$d/console.txt" "$d/out/"
		for f in "Counting the birds at the feeder in 2026.bas" "Birds formatted by VeraBASIC.bas"; do
			$PY tools/vcard.py get "$d/sd.img" "$f" "$d/out/$f" >/dev/null 2>&1 || true
		done
		rm -f "$d/sd.img"
	else
		cp "$K/VERANDA.PRG" "$C/"
		(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		[ -f "$C/dump.bin" ] && mv "$C/dump.bin" "$d/"
	fi
	echo done > "$d/done"
}
export -f session
export OUT T EMU R49 PY K
SESS=("full - - -" "colour colour - -" "error error - -" "colourdark colour dark -" "errordark error dark -"
	"help help - -" "console console - -" "stopped stopped - -" "format format - -")
[ "${VB_SD:-1}" != 0 ] && SESS+=("sd - - sd")
printf '%s\n' "${SESS[@]}" | xargs -P "$JOBS" -L 1 bash -c 'session "$@"' _
ok "${#SESS[@]} sessions run (ROM R49, $JOBS at a time)"
for s in "${SESS[@]}"; do
	n=${s%% *}
	[ -f "$OUT/s/$n/fail" ] && fail "$n: $(cat "$OUT/s/$n/fail")"
	if [ "$n" = sd ]; then continue; fi
	[ -f "$OUT/s/$n/dump.bin" ] || { grep -a "IDE\|HUNG" "$OUT/s/$n/card/console.txt" | tail -5; fail "$n: the session did not end"; }
done
$PY tests/vbasic/check_ide.py "$OUT/s/full/card" --rom "$R49" || fail "the session (host folder)"
for s in colour error colourdark errordark help console stopped format; do
	$PY tests/vbasic/check_ide.py "$OUT/s/$s/card" --partial > "$OUT/s/$s/check.txt" || { cat "$OUT/s/$s/check.txt"; grep -a "IDE " "$OUT/s/$s/card/console.txt" | tail -8; fail "the session stopped at $s"; }
	$PY "$SDK/tools/vram2png.py" --color "$OUT/s/$s/dump.bin" "$OUT/$s.png" >/dev/null || fail "vram2png $s"
done
if [ -d "$OUT/s/sd" ]; then
	grep -a -q "IDE STATE 10" "$OUT/s/sd/console.txt" || { tail -5 "$OUT/s/sd/console.txt"; fail "SD card: the session did not end"; }
	$PY tests/vbasic/check_ide.py "$OUT/s/sd/out" --rom "$R49" || fail "the session (SD card image)"
fi
grep -a -q "IDE HELP PRINT" "$OUT/s/help/card/console.txt" || fail "F1: PRINT's page"
ok "screenshots: $OUT/colour.png (the colouring), error.png (Check's error, red), colourdark.png, errordark.png"
ok "  (dark mode), help.png (F1 on PRINT), console.png (the program's), stopped.png (Ctrl+C), format.png"
GOLD=$G/golden.txt
$PY tests/vbasic/check_ui.py "$OUT/s" "$GOLD" colour error colourdark errordark || fail "the screens' goldens"
ok "the colour map's goldens, light and dark (the colouring, the error's line): $GOLD"

# 3b. editing after scrolling (V214; tests/vbasic/ide_scroll.py): 200
# numbered lines scrolled by Down, Page Down, the wheel, the scroll bar's
# arrow and track, keys that come together; a line clicked or reached,
# characters typed and deleted, Return: the saved program as the model's,
# the cursor's lines; the screen the one F1 and Esc's full redraw shows
for v in scroll scrollredraw; do
	C=$OUT/s/$v
	rm -rf "$C"
	mkdir -p "$C/VERANDA/HELP"
	cp "$T" "$C/AUTOSTART.cvt"
	cp "$K/VERANDA.SYS" "$K/VERANDA.PRG" "$C/"
	cp vbasic/gen/HELP/*.HLP "$C/VERANDA/HELP/"
	$PY tests/vbasic/ide_scroll.py "$C" $( [ $v = scrollredraw ] && echo --redraw) || fail "tests/vbasic/ide_scroll.py"
	(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) &
done
wait
for v in scroll scrollredraw; do
	[ -f "$OUT/s/$v/dump.bin" ] || { grep -a "IDE\|HUNG" "$OUT/s/$v/console.txt" | tail -5; fail "$v: the session did not end"; }
done
$PY tests/vbasic/ide_scroll.py check "$OUT/s/scroll" "$OUT/s/scrollredraw" || fail "editing after scrolling"
$PY "$SDK/tools/vram2png.py" --color "$OUT/s/scroll/dump.bin" "$OUT/scroll.png" >/dev/null || fail "vram2png scroll"
ok "editing after scrolling (Down, Page Down, the wheel, the scroll bar, keys together): each change at the line"
ok "  clicked or reached, the saved program as the model's, the screen as a full redraw's: $OUT/scroll.png"

# 3b2. a click on an empty line (V216; tests/vbasic/ide_blank.py): every
# fourth line empty; clicks on them at the top, after the wheel and the
# scroll bar, a character typed at each: the cursor's lines, the saved file
C=$OUT/s/blank
rm -rf "$C"
mkdir -p "$C/VERANDA/HELP"
cp "$T" "$C/AUTOSTART.cvt"
cp "$K/VERANDA.SYS" "$K/VERANDA.PRG" "$C/"
cp vbasic/gen/HELP/*.HLP "$C/VERANDA/HELP/"
$PY tests/vbasic/ide_blank.py "$C" || fail "tests/vbasic/ide_blank.py"
(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1)
$PY tests/vbasic/ide_blank.py check "$C" || fail "a click on an empty line"
ok "a click on an empty line (at the top, after the wheel, after the scroll bar): the cursor there, the typing there"

# 3c. scrolling's speed (V215; tests/scroll_speed.py): a 200-line program
# in colour, each way of scrolling timed exactly at 8 MHz (from the record
# played to the text drawn: the status bar waits while keys come), a line
# within 50 ms and a page within 300 ms; the same session again with the
# redraw check after every step (the window as the steps drew it against
# a full drawing, view_all: each text row's bitmap and colour map)
for v in speed speedcheck; do
	C=$OUT/s/$v
	rm -rf "$C"
	mkdir -p "$C/VERANDA/HELP"
	cp "$T" "$C/AUTOSTART.cvt"
	cp "$K/VERANDA.SYS" "$K/VERANDA.PRG" "$C/"
	cp vbasic/gen/HELP/*.HLP "$C/VERANDA/HELP/"
	$PY tests/scroll_speed.py ide "$C" $( [ $v = speedcheck ] && echo --check) || fail "tests/scroll_speed.py"
	(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) &
done
wait
$PY tests/scroll_speed.py report "$OUT/s/speed" --max 50,300 > "$OUT/speed.txt" || { cat "$OUT/speed.txt"; fail "scrolling's speed"; }
$PY tests/scroll_speed.py report "$OUT/s/speedcheck" --check > "$OUT/speedcheck.txt" \
	|| { cat "$OUT/speedcheck.txt"; fail "the redraw check"; }
ok "scrolling's speed (R49, 8 MHz; $OUT/speed.txt): $(sed -n 's/^Down at the last row: a line *//p' "$OUT/speed.txt") a line,"
ok "  $(sed -n 's/^Page Down *//p' "$OUT/speed.txt") a page; $(tail -1 "$OUT/speedcheck.txt")"

# 4. the shell: a double click on a .bas
S=$OUT/shell
mkdir -p "$S"
cp -r shell "$OUT/shsrc"
rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || { cat "$OUT/shsrc/build.log"; fail "the shell does not build"; }
cp "$OUT/shsrc/SHELL.cvt" "$K/VERANDA.SYS" "$S/"
cp "$T" "$S/VeraBASIC.cvt"
cp "$OUT/run/VBRun.cvt" "$S/VeraBASIC Run.cvt"
cp tests/vbasic/shell/hello.bas "$S/Hello from VeraBASIC on the card.bas"
$PY tests/vbasic/ide_shell_script.py "$S" console.txt || fail "the shell's script"
cp "$K/VERANDA.PRG" "$S/"
(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -a -q "SHELL DONE" "$S/console.txt" || { tail -5 "$S/console.txt"; fail "the shell's session did not end"; }
n=$(wc -c < "$S/Hello from VeraBASIC on the card.bas")
grep -a -q "IDE STATE 1 1 1 $n .* Hello from VeraBASIC on the card.bas" "$S/console.txt" \
	|| { grep -a "IDE\|SHELL" "$S/console.txt"; fail "the shell: VeraBASIC did not open the .bas"; }
ok "the shell: a double click on \"Hello from VeraBASIC on the card.bas\" started VeraBASIC with it ($n bytes), and Quit went back"

# 4b. the switcher (V83): Alt+Tab while the editor shows and while its
# program runs; the test desktop (tests/vbasic/vb_desk.s) brings it back;
# the program goes on and Ctrl+C stops it. With 2 MB of RAM: at 512 KB the
# application's 29 banks and the 18 the switcher keeps free for the
# desktop do not fit with its packed RAM (the switcher's box says so)
D=$OUT/aside
mkdir -p "$D/desk" "$D/card"
ca65 --cpu 65C02 -I "$SDK/include" -o "$D/desk/desk.o" tests/vbasic/vb_desk.s || fail "tests/vbasic/vb_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$D/desk/desk.bin" "$D/desk/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = VbDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$D/desk/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$D/card/SHELL.cvt" "$D/desk/desk.hdr" "$D/desk/desk.bin" >/dev/null || fail "vpack the test desktop"
cp "$T" "$D/card/AUTOSTART.cvt"
cp "$K/VERANDA.SYS" "$K/VERANDA.PRG" "$D/card/"
$PY tests/vbasic/ide_aside.py "$D/card" || fail "tests/vbasic/ide_aside.py"
(cd "$D/card" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -ram 2048 -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
got=$(tr -d '\r' < "$D/card/console.txt" | grep -a -o -E 'IDE STATE [0-9]+ [0-9 ]+|DESK RESUME|TASK (ASIDE|BACK)|IDE ANSWER 4' | sed 's/ *$//')
want=$(printf '%s\n' "IDE STATE 1 4 7 27 4 1 0 0" "TASK ASIDE" "DESK RESUME" "TASK BACK" "IDE STATE 2 4 7 27 4 1 0 0" \
	"TASK ASIDE" "DESK RESUME" "TASK BACK" "IDE ANSWER 4")
[ "$(echo "$got" | head -9)" = "$want" ] || { echo "$got"; fail "the switcher"; }
echo "$got" | tail -1 | grep -q "^IDE STATE 3 [2-4] 1 27 4 1 0 [2-4]$" || { echo "$got"; fail "the switcher: stopped after"; }
ok "the switcher (2 MB): VeraBASIC put aside and back while editing (its text and cursor as they were) and while its program ran (it went on; Ctrl+C stopped it)"

# 5. gate edit
if [ "${VB_EDIT:-1}" != 0 ]; then
	tools/gate_edit.sh > "$OUT/gate_edit.log" 2>&1 || { tail -5 "$OUT/gate_edit.log"; fail "gate edit"; }
	ok "gate edit: $(tail -1 "$OUT/gate_edit.log")"
fi
echo "GATE vb_ide: PASS"
