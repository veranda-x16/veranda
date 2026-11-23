#!/bin/bash
# Gate vb_ui (VeraBASIC phase 3, docs/DECISIONS.md V89): the Veranda
# extensions, part 1 (events, windows, menus, graphics, text, colour, the
# mouse, the keys, timers, sound) in VeraBASIC Run, against
# tools/vbasic.py run --replay, the reference.
#
#   tools/gate_vb_ui.sh       (OUT=dir; R49=the ROM image; EMU_MOUSE=an
#                              x16emu with -mousescript; VB_GOLDEN=1 writes
#                              tests/vbasic/ui/golden.txt anew)
#
# 1. the kernel and the SDK; VeraBASIC Run (release: main RAM's room for a
#    program's names, every overlay in its bank) and its test build; the
#    test desktop (tests/vbasic/vb_desk.s) for the switcher
# 2. the example programs and the tutorial's seven steps
#    (tests/vbasic/ui/*.bas; the tutorial's listings in
#    docs/vbasic/manual/tutorial.md must be bird1-7.bas), each a session of
#    the test build under ROM R49 with real mouse input (NAME.ms through
#    tests/vbasic/ui_mouse.py: PS/2 packets, the KERNAL's mouse_scan),
#    keys typed (the same script) or given to keyVector (NAME.lst "!key")
# 3. each: Run's log (its statements "VB>", its functions' values "VB=",
#    its events "VB EVENT", its console "VB|") equals the reference's run
#    on Run's values and events; its events (but the timers') equal
#    NAME.events; its screen (VRAM, the colour map, the palette) equals the
#    golden (tests/vbasic/ui/golden.txt: a hash of the picture, the bar's
#    clock and the TIME$ status bands masked)
# 4. counting: put aside (TaskCtl TASK_ASIDE) in the middle of its loop,
#    brought back by the test desktop, it counts on to its end; busy: a
#    menu opened and an item chosen while BASIC runs its loop; menuopen: a
#    menu open (menuNumber 1, the pointer on its title or in it: V137) with
#    a program waiting
# 5. the extensions chapter's listings (docs/vbasic/manual/extensions.md)
#    run in one session and log as the reference
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_ui}
PY="python3 -I -B"
EMU=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
JOBS=${VB_JOBS:-6}
U=tests/vbasic/ui

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
{ "$EMU" -help 2>&1 || true; } | grep -q -- -mousescript || fail "$EMU has no -mousescript (the emulator's branch mousescript)"
rm -rf "$OUT"
mkdir -p "$OUT"
TOP=$(pwd)

# 1. the builds
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
mkdir -p "$OUT/app" "$OUT/test" "$OUT/desk"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "VeraBASIC Run does not build"; }
end=$(sed -n 's/^BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' "$OUT/app/vbrun.map")
stk=$(sed -n 's/.*__STACKSIZE__=\(0x[0-9A-F]*\).*/\1/p' apps/vbasic/Makefile)
room=$(( 0x8800 - stk - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for the program's names (2048 at least)"
sizes=""
for n in 1 2 3 4 5 6 7; do
	e=$(sed -n "s/^OVL${n}BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p" "$OUT/app/vbrun.map")
	[ -n "$e" ] || e=$(sed -n "s/^OVERLAY${n}  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p" "$OUT/app/vbrun.map")
	s=$(( 16#$e - 0xA000 + 1 ))
	[ "$s" -le 8192 ] || fail "overlay $n: $s bytes with its BSS"
	sizes="$sizes $n:$s"
done
ok "VeraBASIC Run builds: main RAM to \$$end, $room bytes for a program's procedures and names; the overlays with their BSS:$sizes"
make -s -C apps/vbasic test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
ca65 --cpu 65C02 -I "$SDK/include" -o "$OUT/desk/desk.o" tests/vbasic/vb_desk.s || fail "tests/vbasic/vb_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$OUT/desk/desk.bin" "$OUT/desk/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = VbDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$OUT/desk/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OUT/desk/SHELL.cvt" "$OUT/desk/desk.hdr" "$OUT/desk/desk.bin" >/dev/null \
	|| fail "vpack the test desktop"
ok "the test build (VB_TEST) and the test desktop"

# the tutorial's listings are the gate's programs
$PY tests/vbasic/doclistings.py "$OUT/tut" docs/vbasic/manual/tutorial.md > "$OUT/tut.txt" 2>/dev/null \
	|| fail "the tutorial's listings"
nt=0
for f in "$OUT"/tut/*.bas; do
	nt=$((nt + 1))
	cmp -s "$f" "$U/bird$nt.bas" || fail "the tutorial's listing $nt is not $U/bird$nt.bas"
done
[ "$nt" = 7 ] || fail "the tutorial has $nt listings, not 7"
ok "the tutorial's 7 listings are $U/bird1.bas .. bird7.bas"

# 2. the sessions: $1 the session, $2 its program (default the same)
session() {
	local n=$1 p=${2:-$1} d="$TOP/$OUT/s/$1"
	mkdir -p "$d"
	{
		echo '!shot'
		local asd=0
		if [ -f "$U/$n.lst" ]; then
			while read -r l; do
				case "$l" in '!aside'*|'!stop'*) asd=1 ;; esac
				echo "$l"
			done < "$U/$n.lst"
		fi
		[ $asd = 1 ] || echo "$p"
	} > "$d/VBTEST.LST"
	$PY tools/vbasic.py build "$U/$p.bas" -o "$d/$p.cvt" >/dev/null || { echo "build $p" > "$d/fail"; return; }
	cp "$OUT/test/VBRun.cvt" "$d/AUTOSTART.cvt"
	cp "$OUT/desk/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$d/"
	local ms=()
	if [ -f "$U/$n.ms" ]; then
		$PY tests/vbasic/ui_mouse.py "$U/$n.ms" "$OUT/test/vbrun.map" "$d/mouse.txt" || { echo "ui_mouse" > "$d/fail"; return; }
		ms=(-mousescript mouse.txt)
	fi
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump RV "${ms[@]}" > console.txt 2>&1) || true
	grep -a '^VB' "$d/console.txt" > "$d/x16.log" || true
	$PY tools/vbasic.py run --rom "$R49" --log --replay "$d/x16.log" "$U/$p.bas" > "$d/ref.log" 2>&1 || true
	[ -f "$d/dump.bin" ] && $PY tools/vram2png.py --color "$d/dump.bin" "$d/screen.png" >/dev/null
	echo done > "$d/done"
}
export -f session
export OUT TOP U PY EMU R49
PROGS=(hello colours sketch fonts keys sounds timers scroll menus windows counting busy bird1 bird2 bird3 bird4 bird5 bird6 bird7)
{ for n in "${PROGS[@]}"; do echo "$n"; done; echo "menuopen bird7"; } | xargs -P "$JOBS" -L 1 bash -c 'session $0 $1'
ok "${#PROGS[@]} programs' sessions and menuopen run (R49, the host folder, $JOBS at a time)"

# 3. the logs, the events, the screens
filter() { grep -v '^VB RUN\|^VB BANKS\|^VB GC\|^VB DONE\|^VB ASIDE\|^VB TEST' "$1"; }
shots=()
for n in "${PROGS[@]}"; do
	d=$OUT/s/$n
	[ -f "$d/fail" ] && fail "$n: $(cat "$d/fail")"
	grep -q 'VB DONE' "$d/x16.log" || { tail -5 "$d/x16.log"; fail "$n: the session did not finish"; }
	filter "$d/x16.log" > "$d/x16c.log"
	cmp -s "$d/x16c.log" "$d/ref.log" || { diff "$d/x16c.log" "$d/ref.log" | head -20; fail "$n: Run's log and the reference's differ"; }
	tail -1 "$d/ref.log" | grep -q '^VB END' || fail "$n: did not end by END ($(tail -1 "$d/ref.log"))"
	if [ -f "$U/$n.events" ]; then
		grep '^VB EVENT' "$d/x16.log" | grep -v ' TIMER ' | sed 's/^VB EVENT [0-9]* //' > "$d/events"
		cmp -s "$d/events" "$U/$n.events" || { diff "$d/events" "$U/$n.events"; fail "$n: the events differ from $U/$n.events"; }
	fi
	[ -f "$d/screen.png" ] || fail "$n: no screen"
	shots+=("$n")
done
nev=$(cat "$OUT"/s/*/x16.log | grep -c '^VB EVENT')
nst=$(cat "$OUT"/s/*/x16.log | grep -c '^VB> ')
nfn=$(cat "$OUT"/s/*/x16.log | grep -c '^VB= ')
ok "${#PROGS[@]} programs log as the reference: $nst statements, $nfn function values, $nev events (the events as expected)"
$PY tests/vbasic/check_ui.py "$OUT/s" "$U/golden.txt" "${PROGS[@]}" || fail "the screens"

# 4. put aside, the menus while BASIC runs
grep -q '^VB ASIDE' "$OUT/s/counting/x16.log" || fail "counting was not put aside"
grep -q 'counted 30000' "$OUT/s/counting/x16.log" || fail "counting did not count to its end after it came back"
a=$(grep -n '^VB ASIDE' "$OUT/s/counting/x16.log" | cut -d: -f1)
b=$(grep -n 'count 1000 ' "$OUT/s/counting/x16.log" | tail -1 | cut -d: -f1)
ok "counting: put aside (TaskCtl TASK_ASIDE) in the middle of its loop, brought back by the test desktop, counted on to 30000 as the reference"
first=$(grep -n '^VB EVENT' "$OUT/s/busy/x16.log" | head -1 | cut -d: -f1)
last=$(grep -n '^VB| loop 40' "$OUT/s/busy/x16.log" | cut -d: -f1)
[ -n "$first" ] && [ "$first" -lt "$last" ] || fail "busy: the menu's item was not taken inside the loop"
ok "busy: a menu opened and its item chosen while BASIC ran its loop; the handler ran at the loop's DOEVENTS"
$PY - "$OUT/s/menuopen/dump.bin" <<-'EOF' || fail "menuopen"
	import sys
	d = open(sys.argv[1], 'rb').read()
	x, y, level = d[0x3A] | d[0x3B] << 8, d[0x560] | d[0x561] << 8, d[0x53F]
	if level != 1 or not y < 80:       # (V137: no jump to the first item: the pointer stays on the title)
	    sys.exit('menuopen: menuNumber %d, the pointer at %d, %d' % (level, x, y))
	print('ok    menuopen: a menu open over Bird Watch (menuNumber 1, the pointer at %d, %d on its title or in it)' % (x, y))
	EOF

# 5. the extensions chapter's listings, one session
L=$OUT/listings
mkdir -p "$L"
$PY tests/vbasic/doclistings.py "$L" docs/vbasic/manual/extensions.md > "$OUT/listings.txt" 2>/dev/null || fail "the chapter's listings"
{ echo '!shot'; cat "$OUT/listings.txt"; } > "$L/VBTEST.LST"
for n in $(cat "$OUT/listings.txt"); do
	$PY tools/vbasic.py build "$L/$n.bas" -o "$L/$n.cvt" >/dev/null || fail "build listing $n"
done
cp "$OUT/test/VBRun.cvt" "$L/AUTOSTART.cvt"
cp "$OUT/desk/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG "$L/"
(cd "$L" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -a -q 'VB DONE' "$L/console.txt" || fail "the listings' session did not finish"
nl=0
for n in $(cat "$OUT/listings.txt"); do
	awk -v n="VB RUN $n" '$0 == n { on = 1; next } /^VB RUN / { on = 0 } on' <(grep -a '^VB' "$L/console.txt") > "$L/$n.log"
	$PY tools/vbasic.py run --rom "$R49" --log --replay "$L/$n.log" "$L/$n.bas" > "$L/$n.ref" 2>&1 || true
	filter "$L/$n.log" > "$L/$n.x16"
	cmp -s "$L/$n.x16" "$L/$n.ref" || { diff "$L/$n.x16" "$L/$n.ref" | head; fail "listing $n: Run and the reference differ"; }
	tail -1 "$L/$n.ref" | grep -q '^VB END' || fail "listing $n: $(tail -1 "$L/$n.ref")"
	nl=$((nl + 1))
done
ok "the extensions chapter: $nl listings run on the X16 and log as the reference"
echo "screenshots: $OUT/s/<program>/screen.png (bird7, colours, menuopen ...)"
