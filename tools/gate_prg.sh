#!/bin/bash
# Gate prg (DECISIONS V197): an X16 program (.PRG) double-clicked on the
# desktop runs in BASIC, Veranda kept, and Veranda comes back by itself
# when it ends (BASIC's EXEC: shell/prg.c).
#
#   tools/gate_prg.sh
#
# Under the R49 release ROM (the user's X16), 512 KB, an SD card image in
# the V71 layout (/VERANDA with RBOOT, /DOCUMENTS), Veranda started as the
# user does (DOS"CD:VERANDA", LOAD, RUN typed: the mouse emulator's
# -mousescript); the shell plays tests/prg_gate.py's SHELL.TST:
# 1. run ask: HIGH.PRG (loads at $1000): the warning; HELLO.PRG: the
#    question, Cancel: nothing happens; again: the box (ask.png)
# 2. run run: HELLO.PRG (BASIC: a line, HELLO.TXT written, END), OK:
#    back in /DOCUMENTS, HELLO.TXT there; MLSTUB.PRG (machine code behind
#    a SYS line, RTS): back; BANKS.PRG (all of BASIC's RAM banks, 1-43,
#    filled and read back): back from the copy; GAMES/READER.PRG (reads
#    LEVEL.DAT next to it): back in /DOCUMENTS/GAMES, READER.TXT there;
#    GAMES/ERR.PRG (a BASIC error): back all the same;
#    every time EXEC's lines on the console and RBOOT's "VERANDA IS IN
#    MEMORY"; the desktop after it (run.png)
# 3. run shot: BASIC's screen while a program runs (shot.png)
# 4. run over: a program that overwrites banks 1-46 (RB, where EXEC's
#    last lines are, and the copy's first banks): EXEC reads the $AA
#    bytes as one line, BASIC refuses it (?STRING TOO LONG) and EXEC stops
#    at READY (reported; no monitor); then RBOOT typed as the manual says:
#    no intact copy, VERANDA.PRG from the card, the desktop back
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/prg
PY="python3 -I -B"
R49_ROM=${R49_ROM:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
EMUM=${EMUM:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49_ROM" ] || fail "the R49 ROM ($R49_ROM) is not there"
[ -x "$EMUM" ] || fail "the mouse emulator ($EMUM) is not there"
rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }
ok "built: VERANDA.PRG, VERANDA.SYS, RBOOT, the shell"

# the console's lines, in this order: $1 console, $2 where, $3... regexes
inorder() {
	local c=$1 where=$2
	shift 2
	tr -d '\r' < "$c" | $PY -c '
import re, sys
text = sys.stdin.read()
pos = 0
for pat in sys.argv[1:]:
    m = re.compile(pat, re.M).search(text, pos)
    if not m:
        print("      missing, after offset %d: %s" % (pos, pat))
        sys.exit(1)
    pos = m.end()
' "$@" || { tail -40 "$c"; fail "$where: the console is not as expected"; }
}

# run $1: the card, Veranda started by typing, the shell's script played
# ($2: more of the mouse script, lines split at ";")
session() {
	local D=$OUT/$1
	mkdir -p "$D/card/VERANDA/APPS" "$D/card/VERANDA/.SYSTEM" "$D/card/DOCUMENTS"
	cp "$OUT/src/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG build/RBOOT "$D/card/VERANDA/"
	echo "V71" > "$D/card/VERANDA/.SYSTEM/LAYOUT.LOG"
	$PY tests/prg_gate.py "$1" "$D/card" || fail "tests/prg_gate.py $1"
	$PY tools/vcard.py make --mb 64 "$D/sd.img" "$D/card" >/dev/null || fail "vcard make"
	printf '180 type DOS"CD:VERANDA"\\n\n300 type LOAD"VERANDA.PRG"\\n\n500 type RUN\\n\n' > "$D/mouse.txt"
	[ -z "$2" ] || printf '%s\n' "$2" | tr ';' '\n' >> "$D/mouse.txt"    # (more of it: run over)
	(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMUM" -rom "$R49_ROM" -sdcard sd.img -ram 512 \
		-warp -sound none -echo -mousescript mouse.txt -dump BV > console.txt 2>&1) || true
	[ -f "$D/dump.bin" ] || { tail -30 "$D/console.txt"; fail "run $1: no dump (the session did not end)"; }
	! grep -a -q 'BDIZC' "$D/console.txt" || { tail -30 "$D/console.txt"; fail "run $1: the ROM's monitor (a BRK)"; }
	$PY tools/vcard.py ls "$D/sd.img" > "$D/after.txt"
}

# 1. ask
session ask
C=$OUT/ask/console.txt
inorder "$C" "run ask" 'SHELL READY 0 IN /DOCUMENTS' 'Run [A-Z.]*PRG\?' 'Run [A-Z.]*PRG\?' 'SHELL DONE'
[ "$(grep -a -c 'Run [A-Z.]*PRG\?' "$C")" = 2 ] || fail "run ask: HIGH.PRG was asked about (it loads at \$1000)"
! grep -a -q 'VERANDA STAYS IN MEMORY\|SHELL READY 1' "$C" || fail "run ask: Cancel left the desktop"
$PY tools/vram2png.py --color "$OUT/ask/dump.bin" "$OUT/ask.png" >/dev/null || fail "vram2png"
ok "run ask: HIGH.PRG (loads at \$1000) refused without a question; HELLO.PRG asked, Cancel: still on the desktop (the same start); asked again ($OUT/ask.png)"

# 2. run
session run
C=$OUT/run/console.txt
inorder "$C" "run run" 'SHELL READY 0 IN /DOCUMENTS' 'Run [A-Z.]*PRG\?' \
	'DOS"CD:/DOCUMENTS"' 'LOAD"HELLO.PRG",8' 'RUN' 'DOS"CD:/VERANDA"' 'LOAD"RBOOT",8' 'RUN' \
	'VERANDA STAYS IN MEMORY' 'EXEC\$BF00,44' 'DOS"CD:/DOCUMENTS"' 'LOAD"HELLO.PRG",8' \
	'PRG HELLO START' 'PRG HELLO END' 'DOS"CD:/VERANDA"' 'LOAD"RBOOT",8' 'VERANDA IS IN MEMORY' \
	'SHELL READY 1 IN /DOCUMENTS' 'LOAD"MLSTUB.PRG",8' 'PRG MLSTUB RAN' 'LOAD"RBOOT",8' 'VERANDA IS IN MEMORY' \
	'SHELL READY 2 IN /DOCUMENTS' 'LOAD"BANKS.PRG",8' 'PRG BANKS 43.{1,4}ERRORS 0' 'LOAD"RBOOT",8' 'VERANDA IS IN MEMORY' \
	'SHELL READY 3 IN /DOCUMENTS' 'DOS"CD:/DOCUMENTS/GAMES"' 'LOAD"READER.PRG",8' 'PRG READER GOT LEVEL ONE' \
	'LOAD"RBOOT",8' 'VERANDA IS IN MEMORY' 'SHELL READY 4 IN /DOCUMENTS/GAMES' \
	'LOAD"ERR.PRG",8' 'PRG ERR START' '\?DIVISION BY ZERO {1,2}ERROR IN 10' 'LOAD"RBOOT",8' 'VERANDA IS IN MEMORY' \
	'SHELL READY 5 IN /DOCUMENTS/GAMES' 'SHELL DONE'
! grep -a -q 'NO INTACT COPY\|LOADING VERANDA.PRG\|PRG ERR NOT HERE' "$C" || { grep -a 'NO INTACT\|LOADING VERANDA\|NOT HERE' "$C"; fail "run run: a refusal"; }
[ "$(grep -a -c 'ERROR IN' "$C")" = 1 ] || { grep -a 'ERROR IN' "$C"; fail "run run: an error other than ERR.PRG's"; }
grep -q '^DOCUMENTS/HELLO.TXT' "$OUT/run/after.txt" || { cat "$OUT/run/after.txt"; fail "run run: HELLO.TXT is not in /DOCUMENTS"; }
grep -q '^DOCUMENTS/GAMES/READER.TXT' "$OUT/run/after.txt" || { cat "$OUT/run/after.txt"; fail "run run: READER.TXT is not in /DOCUMENTS/GAMES"; }
$PY tools/vcard.py get "$OUT/run/sd.img" DOCUMENTS/HELLO.TXT "$OUT/run/hello.txt" >/dev/null
grep -q HELLO "$OUT/run/hello.txt" || fail "run run: HELLO.TXT's text"
$PY tools/check_vera.py "$OUT/run/dump.bin" >/dev/null || fail "run run: the shell's display after the returns"
$PY tools/vram2png.py --color "$OUT/run/dump.bin" "$OUT/run.png" >/dev/null || fail "vram2png"
ok "run run: HELLO.PRG (BASIC, END): it ran in /DOCUMENTS, wrote HELLO.TXT there; EXEC typed RBOOT: back in /DOCUMENTS"
ok "run run: MLSTUB.PRG (machine code behind SYS2061, RTS): back; BANKS.PRG: RAM banks 1-43 filled and read back, no error: back"
ok "run run: GAMES/READER.PRG read LEVEL.DAT from its folder, wrote READER.TXT there: back in /DOCUMENTS/GAMES"
ok "run run: GAMES/ERR.PRG stopped with ?DIVISION BY ZERO ERROR: EXEC went on, back in /DOCUMENTS/GAMES ($OUT/run.png)"

# 3. shot: BASIC's screen while the program runs
session shot
C=$OUT/shot/console.txt
inorder "$C" "run shot" 'SHELL READY 0 IN /DOCUMENTS' 'LOAD"SHOT.PRG",8' 'PRG SHOT: A PROGRAM FROM THE DESKTOP'
$PY tools/text2png.py "$OUT/shot/dump.bin" "$OUT/shot.png" --want 'PRG SHOT: A PROGRAM FROM THE DESKTOP' >/dev/null \
	|| fail "run shot: BASIC's screen"
ok "run shot: BASIC's screen while SHOT.PRG runs ($OUT/shot.png)"

# 4. over: banks 1-46 overwritten (RB and the copy's first two banks)
session over '6000 type DOS"CD:/VERANDA"\n;6200 type LOAD"RBOOT",8\n;6500 type RUN\n;12000 exit'
C=$OUT/over/console.txt
inorder "$C" "run over" 'SHELL READY 0 IN /DOCUMENTS' 'LOAD"OVER.PRG",8' 'PRG OVER 46'
tr -d '\r' < "$C" | sed -n '/PRG OVER 46/,/LOADING VERANDA/p' | cut -c1-100 > "$OUT/over/after-prg.txt"
echo "      run over: after the program, the console has:"
sed 's/^/      | /' "$OUT/over/after-prg.txt"
ok "run over: banks 1-46 overwritten: no BRK; BASIC at READY after EXEC's line"
inorder "$C" "run over, RBOOT typed" 'PRG OVER 46' 'READY\.' 'NO INTACT COPY OF VERANDA IN MEMORY' 'LOADING VERANDA.PRG' \
	'SHELL READY 1 IN /DOCUMENTS' 'SHELL DONE'
ok "run over: RBOOT typed: no intact copy in RAM, VERANDA.PRG loaded from the card, the desktop back in /DOCUMENTS"
echo "GATE prg: PASS"
