#!/bin/bash
# Gate vb_quit (docs/DECISIONS.md V95): every example program and the
# tutorial's seven steps started from the shell and quit every way they
# have, under ROM R49 at 512 KB with the real shell, VeraBASIC and
# VeraBASIC Run (release builds) and real mouse input; the shell must come
# back each time (SHELL DONE at its next start), with no panic box and no
# hang.
#
#   tools/gate_vb_quit.sh   (OUT=dir; R49=the ROM image; EMU_MOUSE=an
#                            x16emu with -mousescript; VB_JOBS=n;
#                            VB_SD=0: no SD card sessions)
#
# 1. the kernel, the SDK, VeraBASIC, VeraBASIC Run, the shell; each
#    program as a .bas and as a program document (tools/vbasic.py build)
# 2. the sessions (tests/vbasic/quit_script.py: SHELL.TST and the mouse
#    script): path ide, a double click on the .bas starts VeraBASIC, Run >
#    Run, the program quit, then the editor's File > Quit; path run, a
#    double click on the program document starts VeraBASIC Run; the ways:
#    the window's close glyph, the program's own Quit item (both end in a
#    handler's END), Stop (as Ctrl+C), VeraBASIC Run's own Quit
# 3. the same for the programs with timers, on an SD card image (loads are
#    slow there: V76)
# The bug it guards (V95): a TIMER's process stayed installed after the
# program ended; back in the editor the kernel called its overlay-1 address
# in the editor's bank, and the machine ran wild (a hang, or a panic box)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_quit}
PY="python3 -I -B"
EMU=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
JOBS=${VB_JOBS:-6}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
{ "$EMU" -help 2>&1 || true; } | grep -q -- -mousescript || fail "$EMU has no -mousescript (the emulator's branch mousescript)"
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TOP=$(pwd)

# 1. the builds
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
mkdir -p "$OUT/ide" "$OUT/run" "$OUT/progs"
make -s -C apps/vbasic SDK="$SDK" OUT="$OUT/ide" ide >"$OUT/ide/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/ide/build.log" | tail; fail "VeraBASIC does not build"; }
make -s -C apps/vbasic SDK="$SDK" OUT="$OUT/run" >"$OUT/run/build.log" 2>&1 \
	|| { tail "$OUT/run/build.log"; fail "VeraBASIC Run does not build"; }
cp -r shell "$OUT/shsrc"
rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || { tail "$OUT/shsrc/build.log"; fail "the shell does not build"; }
PROGS="bird1 bird2 bird3 bird4 bird5 bird6 bird7 notes dice addressbook tiles"
for p in $PROGS; do
	src=tests/vbasic/ui/$p.bas
	[ -f "$src" ] || src=docs/vbasic/examples/$p.bas
	cp "$src" "$OUT/progs/$p.bas"
	$PY tools/vbasic.py build "$src" -o "$OUT/progs/$p.cvt" >/dev/null || fail "vbasic.py build $p"
done
ok "the kernel, the SDK, VeraBASIC, VeraBASIC Run, the shell; 11 programs as .bas and as program documents"

# 2, 3. a session: $1 program, $2 path (ide|run), $3 way, $4 sd|-
session() {
	local p=$1 path=$2 way=$3 sd=$4
	local d=$OUT/s/$p-$path-$way
	[ "$sd" != sd ] || d=$d-sd
	local C=$d/card
	rm -rf "$d"
	mkdir -p "$C"
	cp "$OUT/shsrc/SHELL.cvt" "$TOP/build/VERANDA.SYS" "$TOP/build/VERANDA.PRG" "$C/"
	cp "$OUT/ide/ide/VeraBASIC.cvt" "$C/VeraBASIC.cvt"
	cp "$OUT/run/VBRun.cvt" "$C/VeraBASIC Run.cvt"
	if [ "$path" = ide ]; then cp "$OUT/progs/$p.bas" "$C/"; map=$OUT/ide/ide/vbide.map
	else cp "$OUT/progs/$p.cvt" "$C/"; map=$OUT/run/vbrun.map; fi
	$PY "$TOP/tests/vbasic/quit_script.py" "$C" "$p" "$path" "$way" || { echo script > "$d/fail"; return; }
	$PY "$TOP/tests/vbasic/ui_mouse.py" "$C/quit.ms" "$map" "$C/mouse.txt" || { echo ui_mouse > "$d/fail"; return; }
	if [ "$sd" = sd ]; then
		mkdir -p "$d/sd"
		$PY "$TOP/tools/vcard.py" make --mb 64 "$d/sd/sd.img" "$C" >/dev/null
		cp "$C/VERANDA.PRG" "$C/mouse.txt" "$d/sd/"
		C=$d/sd
		(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V -mousescript mouse.txt > console.txt 2>&1) || true
		rm -f "$C/sd.img"
	else
		(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 240 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V -mousescript mouse.txt > console.txt 2>&1) || true
	fi
	tr '\r' '\n' < "$C/console.txt" > "$d/console.txt"
	echo done > "$d/done"
}
export -f session
export OUT TOP EMU R49 PY
{
	for path in ide run; do
		$PY tests/vbasic/quit_script.py --ways $path | sed "s/\$/ -/; s/ / $path /"
	done
	if [ "${VB_SD:-1}" != 0 ]; then
		for p in bird4 bird7; do echo "$p ide close sd"; echo "$p run close sd"; done
	fi
} > "$OUT/sessions.txt"
xargs -P "$JOBS" -L 1 bash -c 'session "$@"' _ < "$OUT/sessions.txt" || true
n=0
while read -r p path way sd; do
	s=$p-$path-$way
	[ "$sd" != sd ] || s=$s-sd
	d=$OUT/s/$s
	[ -f "$d/fail" ] && fail "$s: $(cat "$d/fail")"
	if grep -a -q "^PANIC" "$d/console.txt"; then
		fail "$s: $(grep -a '^PANIC' "$d/console.txt" | head -1)"
	fi
	[ "$(grep -a -c '^SHELL STARTED' "$d/console.txt")" -ge 2 ] && grep -a -q '^SHELL DONE' "$d/console.txt" \
		|| fail "$s: the shell did not come back (a hang: $d/console.txt)"
	n=$((n + 1))
done < "$OUT/sessions.txt"
ok "$n sessions: each program started from the shell (VeraBASIC with its .bas, VeraBASIC Run with its document),"
ok "  quit by its close glyph, its Quit item, Stop, or VeraBASIC Run's Quit; the shell came back each time"
ok "  ($( [ "${VB_SD:-1}" != 0 ] && echo "bird4 and bird7, their timers running, on an SD card image too; " )no panic box, no hang)"
echo "GATE vb_quit: PASS"
