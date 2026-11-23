#!/bin/bash
# Gate vb_app (VeraBASIC phase 7, docs/DECISIONS.md V99): Make application,
# the made application in the shell, the manual and its listings.
#
#   tools/gate_vb_app.sh   (OUT=dir; R49=the ROM image; EMU_MOUSE=an x16emu
#                           with -mousescript; VB_SD=0: no SD card session)
#
# 1. the kernel, the SDK, VeraBASIC (its bank B10: Save program and Make
#    application within 8 KB; the calls across its banks), VeraBASIC Run,
#    the shell; vbasic.py app on Bird Watch (docs/vbasic/examples/
#    birdwatch.bas): the info block and the tile from its APP lines, the
#    program back by vbasic.py list; one with a newer record form, which
#    vbasic.py list refuses ("Made by a newer VeraBASIC")
# 2. the session (tests/vbasic/app_script.py: SHELL.TST for the shell's
#    double clicks, real mouse packets for the programs) under ROM R49 at
#    512 KB, a card in Veranda's layout: VeraBASIC opened with Bird
#    Watch.bas, File > Make application..., the Save dialog in
#    /VERANDA/APPS, Return; the shell's Apps: Bird Watch (its tile)
#    double-clicked, a bird added, put aside (ASIDE: the switcher's
#    TASK_ASIDE, as Alt+Tab); the dock brings it back (its count kept), a
#    bird, File > Save the count, File > Quit (the shell back); Documents:
#    Garden.brd (APP DOCUMENTS "BRD") double-clicked: Bird Watch with it
#    (DOCUMENT$: 42), a bird, saved (43 in Garden.brd)
#    - the application the editor wrote equals vbasic.py app's from the same
#      VeraBASIC Run, byte for byte but the date (directory entry 23-27)
#    - the same session on an SD card image
# 3. screenshots: the Save dialog of Make application, the shell's Apps
#    with Bird Watch's tile, Bird Watch running with its document,
#    VeraBASIC Run's box for an application of a newer form
# 4. the manual: every listing checks and runs (tests/vbasic/check_docs.py:
#    the chapters, the reference card, the examples; vbasic.py import);
#    vbasic.py doc: the HTML pages, the PDF, the reference card's two pages
#    (checked); MANUAL.HLP within 40 KB, and read by the editor's help
#    viewer (a session: Help > Contents > Manual > its last chapter)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_app}
PY="python3 -I -B"
EMU=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

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
$PY tools/vbgen.py >/dev/null || fail "vbgen.py"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
mkdir -p "$OUT/ide" "$OUT/run" "$OUT/pc"
make -s -C apps/vbasic SDK="$SDK" OUT="$OUT/ide" ide >"$OUT/ide/build.log" 2>&1 \
	|| { grep -v Warning "$OUT/ide/build.log" | tail; fail "VeraBASIC does not build"; }
make -s -C apps/vbasic SDK="$SDK" OUT="$OUT/run" >"$OUT/run/build.log" 2>&1 \
	|| { tail "$OUT/run/build.log"; fail "VeraBASIC Run does not build"; }
cp -r shell "$OUT/shsrc"
rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || { tail "$OUT/shsrc/build.log"; fail "the shell does not build"; }
seg() { sed -n "s/^$2  *\([0-9A-F]*\)  *\([0-9A-F]*\).*/\1 \2/p" "$1"; }
e10=0
for sg in B10CODE B10RO B10BSS; do
	x=$(seg "$OUT/ide/ide/ide.map" $sg | cut -d' ' -f2)
	[ -n "$x" ] && [ $((16#$x)) -gt $e10 ] && e10=$((16#$x))
done
[ $e10 -gt 0 ] && [ $e10 -le $((0xBFFF)) ] || fail "the bank B10 (Save program, Make application) runs to $e10"
$PY tests/vbasic/check_ide_banks.py apps/vbasic >/dev/null || fail "the editor's calls across its banks"
end=$(seg "$OUT/run/vbrun.map" BSS | cut -d' ' -f2)
room=$(( 0x8800 - 0x200 - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "VeraBASIC Run: $room bytes of main RAM for a program's names"
ok "VeraBASIC builds: B10 (Save program, Make application) $(( e10 - 0xA000 + 1 )) bytes, every call to another bank"
ok "  through xcall; VeraBASIC Run, $room bytes of main RAM for a program's names (an application's too); the shell"

RUN="$OUT/run/VBRun.cvt"
BW=docs/vbasic/examples/birdwatch.bas
$PY tools/vbasic.py app "$BW" --run "$RUN" -o "$OUT/pc/Bird Watch.cvt" || fail "vbasic.py app"
$PY tools/vpack.py --list "$OUT/pc/Bird Watch.cvt" > "$OUT/pc/list.txt" || fail "vpack.py --list"
for want in "class        BirdWatch   V1.0" "author       Veranda" "flags        3" "documents    BRD" \
		"description  Counts the birds at the feeder." "tile         sky, 123 ink pixels"; do
	grep -q "^$want" "$OUT/pc/list.txt" || fail "the application's info block: no '$want' ($OUT/pc/list.txt)"
done
$PY tools/vbasic.py list "$OUT/pc/Bird Watch.cvt" > "$OUT/pc/back.bas" || fail "vbasic.py list (an application)"
$PY tools/vbasic.py canon "$BW" -o "$OUT/pc/canon.bas"
cmp -s "$OUT/pc/back.bas" "$OUT/pc/canon.bas" || fail "the program inside the application is not the source's"
$PY - "$OUT/pc/Bird Watch.cvt" "$OUT/pc/Newer.cvt" <<'EOF' || fail "the newer application"
import sys
d = bytearray(open(sys.argv[1], 'rb').read())
t, pos = d[508:762], 762
for i in range(12):
    pos += t[2 * i] * 254
assert d[pos:pos + 4] == b'VBAP'
d[pos + 4] = 2                      # a later form of the records
d[3:19] = b'Newer'.ljust(16, b'\xa0')
open(sys.argv[2], 'wb').write(d)
EOF
$PY tools/vbasic.py list "$OUT/pc/Newer.cvt" >/dev/null 2>"$OUT/pc/newer.txt" && fail "vbasic.py list read a newer application"
ok "vbasic.py app: Bird Watch's info block (class, author, flags, BRD, description) and its tile (SKY) from its"
ok "  APP lines; vbasic.py list gives the program back (its canonical form)"

# 2. the sessions: $1 name, $2 how (full|make|apps|newer), $3 sd|-
card() {
	local C=$1
	mkdir -p "$C/VERANDA/APPS" "$C/DOCUMENTS"
	cp "$OUT/shsrc/SHELL.cvt" "$C/VERANDA/"
	cp "$TOP/build/VERANDA.SYS" "$TOP/build/VERANDA.PRG" "$C/"
	cp "$OUT/ide/ide/VeraBASIC.cvt" "$C/VERANDA/APPS/"
	cp "$RUN" "$C/VERANDA/APPS/VeraBASIC Run.cvt"
	cp "$TOP/$BW" "$C/DOCUMENTS/Bird Watch.bas"
	printf '42\n' > "$C/DOCUMENTS/Garden.brd"
}
session() {
	local d=$OUT/s/$1 how=$2 sd=$3
	local C=$d/card
	rm -rf "$d"
	mkdir -p "$C"
	card "$C"
	[ "$how" = apps ] && cp "$OUT/pc/Bird Watch.cvt" "$C/VERANDA/APPS/"
	if [ "$how" = help ]; then          # Help > Contents, Manual, The ROM maths (its last chapter)
		mkdir -p "$C/VERANDA/HELP"
		cp "$TOP"/vbasic/gen/HELP/*.HLP "$C/VERANDA/HELP/"
		$PY "$TOP/tests/vbasic/app_script.py" "$C" make "$OUT/ide/ide/vbide.map" "$OUT/run/vbrun.map" || fail "$1: the script"
		printf 'map %s\nhold 1500\nbar "VeraBASIC" "File" "Edit" "Search" "Run" "Help"\npick 5 1\nhold 400\nhome\nclick 404 291\nhold 600\nhome\nclick 40 107\nhold 400\nexit\n' \
			"$OUT/ide/ide/vbide.map" > "$C/app.ms"
	fi
	if [ "$how" = newer ]; then
		cp "$OUT/pc/Newer.cvt" "$C/VERANDA/APPS/"
		$PY "$TOP/tests/vbasic/app_script.py" "$C" apps "$OUT/ide/ide/vbide.map" "$OUT/run/vbrun.map" || fail "$1: the script"
		$PY - "$C" <<'EOF'
import os, sys
sys.path.insert(0, 'tests')
import shell_script as S
d = sys.argv[1]
apps = ['..'] + S.listing([], sorted(os.listdir(os.path.join(d, 'VERANDA/APPS'))))
p = S.Part()
p.wait(30)
p.click(*S.place(1))
p.wait(60)
p.dbl(*S.cell(apps.index('Newer.cvt')))
p.end(S.END_STOP)
S.write(os.path.join(d, 'SHELL.TST'), [p])
open(os.path.join(d, 'app.ms'), 'w').write('hold 1200\nexit\n')
EOF
	elif [ "$how" != help ]; then
		APP_SLOW=$([ "$sd" = sd ] && echo 3 || echo 1) \
			$PY "$TOP/tests/vbasic/app_script.py" "$C" "$how" "$OUT/ide/ide/vbide.map" "$OUT/run/vbrun.map" || fail "$1: the script"
	fi
	[ "$how" = apps ] && echo 'hold 400
exit' > "$C/app.ms"
	$PY "$TOP/tests/vbasic/ui_mouse.py" "$C/app.ms" "$OUT/run/vbrun.map" "$C/mouse.txt" || fail "$1: ui_mouse"
	if [ "$sd" = sd ]; then
		mkdir -p "$d/sd"
		$PY "$TOP/tools/vcard.py" make --mb 64 "$d/sd/sd.img" "$C" >/dev/null
		cp "$C/VERANDA.PRG" "$C/mouse.txt" "$d/sd/"
		(cd "$d/sd" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V -mousescript mouse.txt > console.raw 2>&1) || true
		tr '\r' '\n' < "$d/sd/console.raw" > "$d/console.txt"
		[ -f "$d/sd/dump.bin" ] && cp "$d/sd/dump.bin" "$d/"
		$PY "$TOP/tools/vcard.py" get "$d/sd/sd.img" "/VERANDA/APPS/Bird Watch.cvt" "$d/Bird Watch.cvt" >/dev/null 2>&1 || true
		$PY "$TOP/tools/vcard.py" get "$d/sd/sd.img" "/DOCUMENTS/Garden.brd" "$d/Garden.brd" >/dev/null 2>&1 || true
		$PY "$TOP/tools/vcard.py" get "$d/sd/sd.img" "/DOCUMENTS/Sightings.brd" "$d/Sightings.brd" >/dev/null 2>&1 || true
		rm -f "$d/sd/sd.img"
	else
		(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT 400 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V -mousescript mouse.txt > console.raw 2>&1) || true
		tr '\r' '\n' < "$C/console.raw" > "$d/console.txt"
		[ -f "$C/dump.bin" ] && cp "$C/dump.bin" "$d/"
		[ -f "$C/VERANDA/APPS/Bird Watch.cvt" ] && cp "$C/VERANDA/APPS/Bird Watch.cvt" "$d/"
		[ -f "$C/DOCUMENTS/Sightings.brd" ] && cp "$C/DOCUMENTS/Sightings.brd" "$d/"
		cp "$C/DOCUMENTS/Garden.brd" "$d/"
	fi
	return 0
}
export -f session card
export OUT TOP EMU R49 PY RUN BW
{
	echo "full full -"
	echo "make make -"
	echo "apps apps -"
	echo "newer newer -"
	echo "help help -"
	[ "${VB_SD:-1}" != 0 ] && echo "fullsd full sd"
} > "$OUT/sessions.txt"
xargs -P 5 -L 1 bash -c 'session "$@"' _ < "$OUT/sessions.txt" || true

# (V165: at 512 KB, one bank fewer, Bird Watch may go aside onto the card,
# TASK CARD, rather than into RAM: either is "put aside"; it must come
# back the same, the count it keeps across the switch below)
trail() {
	tr -d '\r' < "$1" | grep -a -o -E 'SHELL READY [0-9] IN [/A-Za-z]*|TASK (ASIDE|CARD) Bird Watch|TASK BACK Bird Watch|SHELL DOCK RESUME Bird Watch|TASK ASK [A-Z]* Bird Watch|PANIC' \
		| sed 's/^TASK CARD /TASK ASIDE /' | tr '\n' ','
}
want="SHELL READY 0 IN /DOCUMENTS,SHELL READY 1 IN /DOCUMENTS,TASK ASIDE Bird Watch,SHELL READY 2 IN /VERANDA/APPS,"
want="${want}SHELL DOCK RESUME Bird Watch,TASK BACK Bird Watch,SHELL READY 3 IN /VERANDA/APPS,"
check_full() {
	local s=$1 d=$OUT/s/$1
	[ -f "$d/dump.bin" ] || { tail -20 "$d/console.txt"; fail "$s: the session did not end (no dump)"; }
	[ "$(trail "$d/console.txt")" = "$want" ] || { tail -20 "$d/console.txt"; fail "$s: the console has $(trail "$d/console.txt")"; }
	[ -f "$d/Bird Watch.cvt" ] || fail "$s: Make application wrote no /VERANDA/APPS/Bird Watch.cvt"
	$PY - "$d/Bird Watch.cvt" "$OUT/pc/Bird Watch.cvt" <<'EOF' || fail "$s: the editor's application is not vbasic.py app's"
import sys
sys.path.insert(0, 'tools')
import vbapp
a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
if not vbapp.same(a, b):
    d = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
    sys.exit('%d and %d bytes; they differ at %s' % (len(a), len(b), d[:12]))
EOF
	[ "$(tr -d ' \r\n' < "$d/Sightings.brd" 2>/dev/null)" = 2 ] || fail "$s: /DOCUMENTS/Sightings.brd is not 2 (the count kept across the switch)"
	[ "$(tr -d ' \r\n' < "$d/Garden.brd")" = 43 ] || fail "$s: Garden.brd is not 43 (DOCUMENT$ read and written)"
}
check_full full
ok "Make application in VeraBASIC (File > Make application..., the Save dialog in /VERANDA/APPS, Return):"
ok "  /VERANDA/APPS/Bird Watch.cvt equals vbasic.py app's from the same VeraBASIC Run, byte for byte but the date"
ok "the made application under ROM R49 at 512 KB, real mouse input: double-clicked in the shell's Apps; put aside"
ok "  (TASK_ASIDE, as Alt+Tab) and back from the dock with its count; File > Quit: the shell; Garden.brd (.BRD,"
ok "  APP DOCUMENTS) opens it: DOCUMENT\$ read 42, a bird, saved 43; Sightings.brd 2; no panic"
if [ "${VB_SD:-1}" != 0 ]; then
	check_full fullsd
	ok "the same session on an SD card image"
fi
for s in make apps newer help; do
	[ -f "$OUT/s/$s/dump.bin" ] || { tail -20 "$OUT/s/$s/console.txt"; fail "$s: the session did not end (no dump)"; }
	grep -a -q '^PANIC' "$OUT/s/$s/console.txt" && fail "$s: a panic"
done
grep -a -q "TASK ASIDE\|TASK BACK" "$OUT/s/newer/console.txt" && fail "newer: the program ran"
cp "$OUT/s/full/dump.bin" "$OUT/s/app.bin"
for s in make:make apps:apps newer:newer full:running help:help; do
	$PY "$SDK/tools/vram2png.py" --color "$OUT/s/${s%%:*}/dump.bin" "$OUT/${s##*:}.png" >/dev/null || fail "vram2png ${s%%:*}"
done
ok "screenshots: $OUT/make.png (Make application's Save dialog), apps.png (the shell's Apps, Bird Watch's tile),"
ok "  running.png (Bird Watch with Garden.brd), newer.png (VeraBASIC Run: Made by a newer VeraBASIC), help.png"
ok "  (the editor's Help > Contents > Manual > The ROM maths: MANUAL.HLP read whole beside KEYWORDS.HLP)"

# 4. the manual
$PY tests/vbasic/check_docs.py "$OUT/docs" "$R49" || fail "the manual's listings"
$PY tools/vbasic.py doc "$OUT/manual" > "$OUT/manual.txt" 2>&1 || { cat "$OUT/manual.txt"; fail "vbasic.py doc"; }
pages=$(grep -o 'VeraBASIC-manual.pdf: [0-9]* pages' "$OUT/manual.txt" | grep -o '[0-9]*')
n=$(ls "$OUT/manual/html"/*.html | wc -l)
hs=$(wc -c < vbasic/gen/HELP/MANUAL.HLP)
[ "$hs" -le 40960 ] || fail "MANUAL.HLP is $hs bytes (40 KB at most: 5 banks beside KEYWORDS.HLP)"
ok "the manual: $OUT/manual/VeraBASIC-manual.pdf ($pages pages), $n HTML pages ($OUT/manual/html), the reference card"
ok "  ($OUT/manual/VeraBASIC-reference-card.pdf, 2 pages), checked; MANUAL.HLP $hs bytes"
echo "GATE vb_app: PASS"
