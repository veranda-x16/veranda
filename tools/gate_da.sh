#!/bin/bash
# Gate da: Veranda's native desk accessories (apps/dex, apps/calendar,
# apps/prefs, the toolkit apps/daui) and the kernel's settings and alarms
# (SysPrefs, DECISIONS V56).
#
#   tools/gate_da.sh          (DA_SD=0: skip the SD card runs)
#
# 1. the SDK installed; the three accessories, Paint, Veranda Term and a
#    test desktop (tests/da_desk.c) built against it; the accessories are
#    sequential DESK_ACC files that keep the mode
# 2. Dex over Paint (tests/da_script.py writes the sessions): three cards
#    typed and saved, "bo" searched (one found), Export, the first card
#    copied, Connect (YES): DEX.TEL written next to Veranda Term in the
#    system folder and Term started with it (GetFile, ST_LD_DATA). Checked
#    on the host (tests/check_da.py): "Dex Cards.cvt" (three records, in
#    name order), DEX.CSV (RFC 4180, as Veranda Calc reads it), the Text
#    Scrap, DEX.TEL; Term's log (the document, the dial). With the UART
#    emulator (EMU_UART) Term dials the fake BBS of gate term and gets
#    online; without it, the dial's start
# 3. the Calendar over a test program (tests/dadesk): the clock set to
#    2026-11-16 11:59:30 (the test build), an appointment typed on that day
#    at the time it offers (12:00, the next minute) with its alarm; the
#    Calendar
#    closed: "Appointments.cvt" and "Veranda Alarms.cvt" checked on the
#    host; in the test program, at 12:00, the kernel's box ("Alarm 12:00",
#    the text) and the beep (PSG voice 15, as the program's interrupt
#    sees it), OK, the program goes on
# 4. Preferences over Paint: the blanking delay, the paper and ink, the
#    beep off, the pointer's speed, the desktop TopDesk (a test desktop
#    as TopDesk.cvt), Save: "Veranda Prefs.cvt" and DESKTOP.cvt checked;
#    Veranda started again (the reboot): the test desktop starts, and
#    finds the settings applied (SysPrefs, blankDelay, palette entries 0
#    and 1, the kernel's flags); then Preferences again: the desktop back
#    to the shell (DESKTOP.cvt gone)
# 5. screenshots (the composed display): dex.png, cal.png, alarm.png,
#    prefs.png in build/gate/da
# 5a. the theme (DECISIONS V65): Preferences over the shell, its Theme
#    page, the preset Graphite, Save, closed: the console has the block
#    saved with the theme (Look 2's colours, V74), the shell takes it at
#    once (its title bars on Graphite's chrome in the colour map:
#    tests/check_theme.py); Veranda
#    started again: the shell in Graphite from the start; Preferences
#    again, the preset Classic: the shell has no colour map at all, and
#    none after a new start either. theme.png (the Theme page over the
#    shell), theme-graphite.png, theme-classic.png
# 6. 2-4 on an SD card image (no /VERANDA there: the root is the system
#    folder)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/da
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
EMU_UART=${EMU_UART:-$HOME/Projects/x16-emulator-uart/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
skip() { echo "SKIP  $*"; }

rm -rf "$OUT"
mkdir -p "$OUT/h"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
H=$TOP/$OUT/h
$PY tests/da_script.py "$H" || fail "tests/da_script.py"
UART=1
[ -x "$EMU_UART" ] && "$EMU_UART" -h 2>&1 | grep -q -- "-uart <address>" || UART=0

# build: $1 the app's folder, $2 the output folder, the rest make's
build() {
	local d=$1 o=$2
	shift 2
	mkdir -p "$o"
	make -s -C "apps/$d" SDK="$SDK" OUT="$TOP/$o" "$@" >"$o/build.log" 2>&1 || { cat "$o/build.log"; fail "apps/$d: $*"; }
}
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
for a in dex:Dex calendar:Calendar prefs:Preferences; do
	d=${a%%:*}
	n=${a#*:}
	build "$d" "$OUT/rel/$d"
	C=$OUT/rel/$d/$n.cvt
	[ "$(field "$C" 'geos type')" = 5 ] && [ "$(field "$C" structure)" = sequential ] && [ "$(field "$C" mode)" = keep ] \
		|| fail "$n.cvt: not a sequential DESK_ACC that keeps the mode"
	ok "$n builds against the installed SDK: a desk accessory, $(field "$C" load)-$(field "$C" end)"
done
build paint "$OUT/paint" test TESTFLAGS="-DPAINT_DA -I$H/paint"
build term "$OUT/term" test
build dex "$OUT/dex" test TESTFLAGS="-I$H/dex"
build calendar "$OUT/cal" test TESTFLAGS="-I$H/cal"
build prefs "$OUT/prefs1" test TESTFLAGS="-I$H/prefs1"
build prefs "$OUT/prefs2" test TESTFLAGS="-I$H/prefs2"
build prefs "$OUT/prefs3" test TESTFLAGS="-I$H/prefs3"
build prefs "$OUT/prefs4" test TESTFLAGS="-I$H/prefs4"
mkdir -p "$OUT/shell"
cp shell/*.c shell/*.h shell/*.s shell/*.inc shell/Makefile shell/app.hdr shell/icon.pbm shell/icons3.txt shell/icons3s.txt "$OUT/shell/"
make -s -C "$OUT/shell" SDK="$SDK" >"$OUT/shell/build.log" 2>&1 || { cat "$OUT/shell/build.log"; fail "the shell"; }
mkdir -p "$OUT/desk"
make -s -C tests/dadesk SDK="$SDK" OUT="$TOP/$OUT/desk" >"$OUT/desk/build.log" 2>&1 \
	|| { cat "$OUT/desk/build.log"; fail "the test program (tests/dadesk)"; }
ok "the test builds: Paint, Veranda Term, the accessories' sessions, the test program"

EMULATOR=$EMU
# run folder $1 for at most $2 seconds (more arguments: the emulator's)
run() {
	local d=$1 secs=$2
	shift 2
	cp build/VERANDA.PRG build/VERANDA.SYS "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMULATOR" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump RV "$@" > console.txt 2>&1) || true
}
# the same on an SD card image made of folder $1/card; the files named
# after $2 fetched back into $1 (the dump and the console are there)
runsd() {
	local d=$1 secs=$2 f
	shift 2
	cp build/VERANDA.SYS "$d/card/"
	$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump RV > console.txt 2>&1) || true
	for f in "$@"; do
		$PY tools/vcard.py get "$d/sd.img" "$f" "$d/$f" >/dev/null 2>&1 || true
	done
}
png() { $PY tools/vram2png.py --color "$1" "$2" 2>/dev/null || true; }
freeport() { $PY -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
shot() { sed -n "s|^/\* shot $2 \([0-9]*\) \*/|\1|p" "$H/$1/da_script.h"; }
CHK="$PY tests/check_da.py"
TOPDESK=$OUT/desk/DADesk.cvt            # (TopDesk's stand-in: the test program)

# the folders: $1 the folder, $2 the system folder in it ("VERANDA" or "."),
# $3 the session: dex, cal, prefs1, prefs2 (AUTOSTART: Paint, else the test
# program), $4 the accessory's build folder. With /VERANDA the layout of
# DECISIONS V71: the accessories, Term and TopDesk in VERANDA/APPS, the
# files they write in VERANDA/.SYSTEM (the accessories make it); without
# it (the SD card's runs) everything in the root.
folder() {
	local d=$1 s=$2 what=$3 b=$4 a
	a=$([ "$s" = . ] && echo . || echo "$s/APPS")
	mkdir -p "$d/$a"
	case $what in
	dex)
		cp "$OUT/paint/Paint.cvt" "$d/AUTOSTART.cvt"
		cp "$b/Dex.cvt" "$d/$a/"
		cp "$OUT/term/Term.cvt" "$d/$a/Veranda Term.cvt"
		echo "dex end" > "$d/$a/TERM.TST" ;;
	cal)
		cp "$TOPDESK" "$d/AUTOSTART.cvt"
		cp "$b/Calendar.cvt" "$d/"      # (the test desktop starts it from its own folder)
		echo "cal" > "$d/DADESK.TST" ;;
	calpaint)
		cp "$OUT/paint/Paint.cvt" "$d/AUTOSTART.cvt"
		cp "$b/Calendar.cvt" "$d/$a/" ;;
	prefs*)
		cp "$OUT/paint/Paint.cvt" "$d/AUTOSTART.cvt"
		cp "$b/Preferences.cvt" "$d/$a/"
		cp "$TOPDESK" "$d/$a/TopDesk.cvt" ;;
	esac
}

# ---------------------------------------------------------------- Dex
R=$OUT/run/dex
folder "$R" VERANDA dex "$OUT/dex"
if [ $UART = 1 ]; then
	PORT=$(freeport)
	mkdir -p "$R/bbs"
	$PY tests/term_bbs.py "$PORT" "$R/bbs" > "$R/bbs/log.txt" 2>&1 &
	BBSPID=$!
	for _ in $(seq 50); do [ -f "$R/bbs/ready" ] && break; sleep 0.1; done
	EMULATOR=$EMU_UART run "$R" 180 -uartclock 14.7456 -uart 9FE0 tcp:127.0.0.1:$PORT
	EMULATOR=$EMU
	for _ in $(seq 100); do kill -0 "$BBSPID" 2>/dev/null || break; sleep 0.1; done
	kill "$BBSPID" 2>/dev/null || true
	wait "$BBSPID" 2>/dev/null || true
	DIAL=online
else
	skip "no emulator with -uart ($EMU_UART): Term's dial is checked as far as its start"
	run "$R" 180
	DIAL=dial
fi
echo "== Dex over Paint, on the host folder (the system folder /VERANDA)"
$CHK dex "$R" VERANDA $DIAL || fail "Dex (host folder)"
T=$OUT/shot/dex
build dex "$T" test TESTFLAGS="-I$H/dex -DDA_STOP=$(shot dex dex)"
folder "$T/run" VERANDA dex "$T"
run "$T/run" 120
[ -f "$T/run/dump.bin" ] || fail "no dump with Dex open"
png "$T/run/dump.bin" "$OUT/dex.png"
ok "a screenshot with Dex open over Paint, three cards: $OUT/dex.png"

# ---------------------------------------------------------------- the Calendar
R=$OUT/run/cal
folder "$R" VERANDA cal "$OUT/cal"
run "$R" 180
echo "== the Calendar and its alarm over a test program, on the host folder"
$CHK cal "$R" VERANDA || fail "the Calendar (host folder)"
T=$OUT/shot/alarm
folder "$T" VERANDA cal "$OUT/cal"
echo "cal 2300" > "$T/DADESK.TST"
run "$T" 180
[ -f "$T/dump.bin" ] || fail "no dump with the alarm's box"
$CHK alarmshot "$T/dump.bin" || fail "the alarm's box"
png "$T/dump.bin" "$OUT/alarm.png"
ok "a screenshot with the alarm's box over the test program: $OUT/alarm.png"
T=$OUT/shot/cal
build calendar "$T" test TESTFLAGS="-I$H/cal -DDA_STOP=$(shot cal cal)"
folder "$T/run" VERANDA calpaint "$T"
run "$T/run" 120
[ -f "$T/run/dump.bin" ] || fail "no dump with the Calendar open"
grep -q "CAL SAVED 1" "$T/run/console.txt" || fail "the Calendar over Paint: the appointment not saved"
png "$T/run/dump.bin" "$OUT/cal.png"
ok "a screenshot with the Calendar open over Paint, the appointment saved: $OUT/cal.png"

# ---------------------------------------------------------------- Preferences
R=$OUT/run/prefs
folder "$R" VERANDA prefs1 "$OUT/prefs1"
run "$R" 120
echo "== Preferences over Paint, on the host folder"
$CHK prefs1 "$R" VERANDA || fail "Preferences (host folder)"
cp "$R/dump.bin" "$R/dump1.bin"
cp "$R/console.txt" "$R/console1.txt"
rm "$R/AUTOSTART.cvt" "$R/dump.bin"
run "$R" 60
echo "== Veranda started again (no AUTOSTART: EnterDeskTop starts DESKTOP.cvt)"
$CHK reboot "$R" || fail "the settings after a new start (host folder)"
cp "$R/console.txt" "$R/console2.txt"
rm -f "$R/dump.bin" "$R/PRE.RAW" "$R/POST.RAW"
folder "$R" VERANDA prefs2 "$OUT/prefs2"
run "$R" 120
echo "== Preferences again: the desktop back to the shell"
$CHK prefs2 "$R" VERANDA || fail "Preferences, the shell again (host folder)"
T=$OUT/shot/prefs
build prefs "$T" test TESTFLAGS="-I$H/prefs1 -DDA_STOP=$(shot prefs1 prefs)"
folder "$T/run" VERANDA prefs1 "$T"
run "$T/run" 120
[ -f "$T/run/dump.bin" ] || fail "no dump with Preferences open"
png "$T/run/dump.bin" "$OUT/prefs.png"
ok "a screenshot with Preferences open over Paint, the paper and ink previewed: $OUT/prefs.png"

# ---------------------------------------------------------------- the theme
# over the shell: $1 the folder (the system folder: its root), $2 the
# Preferences build or "" (none), $3 the shell's script (desk, probe), the
# rest: names the listing will have besides the folder's (shell_script.py)
TH="$PY tests/check_theme.py"
tfolder() {
	mkdir -p "$1"
	cp "$OUT/shell/SHELL.cvt" build/VERANDA.SYS "$1/"
	rm -f "$1/SHELL.STP" "$1/SHELL.TST" "$1/Preferences.cvt"
	[ -z "$2" ] || cp "$2/Preferences.cvt" "$1/"
	$PY tests/shell_script.py --theme "$1" "$3" "${@:4}" || fail "the shell's script"
}
trun() {                # $1 run folder (host), $2 the build, $3 the script
	rm -f "$1/dump.bin"
	tfolder "$1" "$2" "$3" console.txt VERANDA.PRG
	run "$1" 120
	[ -f "$1/dump.bin" ] || { tail -5 "$1/console.txt"; fail "$1: the session did not end"; }
	grep -a -q "SHELL DONE" "$1/console.txt" || fail "$1: the shell's script did not end"
}
# (B: blankDelay's two bytes, as the running system has it)
tlog() { tr -d '\r' < "$1" | grep -a -o -E "$2" | sed -E 's/^(PREFS SAVED 255 15 35 2) [0-9]+ [0-9]+/\1 B/' | tr '\n' ',' ; }
G=$OUT/run/theme
echo "== the theme: Preferences over the shell, Graphite"
trun "$G" "$OUT/prefs3" desk
got=$(tlog "$G/console.txt" 'SHELL THEME [0-9 ]*|PREFS (SAVED|CLOSED)[0-9 ]*')
want="SHELL THEME 3 14 5,PREFS SAVED 255 15 35 2 B 0 255 0 0 2 3 2 130 128 0,PREFS CLOSED,SHELL THEME 2 3 2,"
[ "$got" = "$want" ] || fail "the console has $got"
ok "the shell in Veranda (no settings file); Preferences' Theme page, Graphite, saved (bytes 10-14: 2 3 2 \$82 \$80, Look 2's colours), closed; the shell takes it at once"
$TH bars "$G/dump.bin" 2 3 2 || fail "the shell's colours after Preferences"
png "$G/dump.bin" "$OUT/theme-after.png"
rm -f "$G/dump.bin"
tfolder "$G" "" probe console.txt VERANDA.PRG
run "$G" 60
grep -a -q "SHELL THEME 2 3 2" "$G/console.txt" || fail "after a new start: the shell's theme"
$TH bars "$G/dump.bin" 2 3 2 || fail "after a new start: the shell's colours"
png "$G/dump.bin" "$OUT/theme-graphite.png"
ok "Veranda started again: the shell in Graphite from the start (Veranda Prefs read at start-up): $OUT/theme-graphite.png"
echo "== Preferences again: Classic"
trun "$G" "$OUT/prefs4" desk
got=$(tlog "$G/console.txt" 'SHELL THEME [0-9 ]*|PREFS (SAVED|CLOSED)[0-9 ]*')
want="SHELL THEME 2 3 2,PREFS SAVED 255 15 35 2 B 0 255 0 0 0 0 0 129 128 0,PREFS CLOSED,SHELL THEME 0 0 0,"
[ "$got" = "$want" ] || fail "the console has $got"
$TH none "$G/dump.bin" || fail "Classic: the shell after Preferences"
rm -f "$G/dump.bin"
tfolder "$G" "" probe console.txt VERANDA.PRG
run "$G" 60
$TH none "$G/dump.bin" || fail "Classic after a new start"
png "$G/dump.bin" "$OUT/theme-classic.png"
ok "Classic: the shell's colour map hidden at once, and none after a new start (the old look): $OUT/theme-classic.png"
T=$OUT/shot/theme
build prefs "$T" test TESTFLAGS="-I$H/prefs3 -DDA_STOP=$(shot prefs3 theme)"
tfolder "$T/run" "$T" desk console.txt VERANDA.PRG
run "$T/run" 120
[ -f "$T/run/dump.bin" ] || fail "no dump with the Theme page open"
png "$T/run/dump.bin" "$OUT/theme.png"
ok "a screenshot with Preferences' Theme page over the shell, Graphite previewed: $OUT/theme.png"

# ---------------------------------------------------------------- the whole package
# (V209) the theme's session over the shell as a user's card has it: the
# card's layout (DECISIONS V71), a package's whole APPS folder (APPS=, else
# the newest ~/Projects/veranda-dist/pkg-*/VERANDA/APPS, as gate tile),
# Dusk, 512 KB; Preferences double-clicked in the Apps window: it starts
# beside the desktop (it did not since V197: NO_BANKS), saves Graphite,
# closes, the shell takes it
APPS=${APPS:-$(ls -td "$HOME"/Projects/veranda-dist/pkg-*/VERANDA/APPS 2>/dev/null | head -1)}
if [ -d "$APPS" ]; then
	G=$OUT/run/package
	rm -rf "$G"
	mkdir -p "$G/VERANDA/APPS" "$G/VERANDA/WALLPAPERS" "$G/VERANDA/.SYSTEM" "$G/DOCUMENTS"
	cp "$OUT/shell/SHELL.cvt" "$G/VERANDA/"
	$PY "$SDK/tools/mkwall.py" -o "$G/VERANDA/WALLPAPERS/Dusk.cvt" --dusk 2>/dev/null || fail "mkwall --dusk"
	$PY - "$G/VERANDA/.SYSTEM/WALLPAPER.CFG" <<'EOF'
import sys
c = bytearray(64)
c[0:3] = b'WP\x01'
c[8:12] = b'Dusk'
d = b'/VERANDA/WALLPAPERS'
c[32:32 + len(d)] = d
open(sys.argv[1], 'wb').write(bytes(c))
EOF
	cp "$APPS"/*.cvt "$G/VERANDA/APPS/"
	cp "$OUT/prefs3/Preferences.cvt" "$G/VERANDA/APPS/"
	echo "a note" > "$G/DOCUMENTS/Note.txt"
	$PY tests/apps_icons.py script "$G" 0 --prefs 1 || fail "tests/apps_icons.py script"
	run "$G" 120 -ram 512
	grep -a -q "SHELL DONE" "$G/console.txt" || fail "the whole package: the shell's script did not end"
	png "$G/dump.bin" "$OUT/package.png"
	got=$(tlog "$G/console.txt" 'SHELL THEME [0-9 ]*|PREFS (RUNNING|SAVED|CLOSED)[0-9 ]*')
	want="SHELL THEME 3 14 5,PREFS RUNNING,PREFS SAVED 255 15 35 2 B 0 255 0 0 2 3 2 130 128 0,PREFS CLOSED,SHELL THEME 2 3 2,"
	[ "$got" = "$want" ] || fail "the whole package ($(ls "$APPS"/*.cvt | wc -l) programs, 512 KB): the console has $got: $OUT/package.png"
	ok "Preferences beside the desktop with the whole package ($(ls "$APPS"/*.cvt | wc -l) programs, $APPS), Dusk, 512 KB: started from the Apps window, Graphite saved, the shell takes it: $OUT/package.png"
else
	skip "no package's APPS folder: Preferences with the whole package not run (APPS=<folder>)"
fi

# ---------------------------------------------------------------- an SD card
if [ "${DA_SD:-1}" != 0 ]; then
	S=$OUT/sd/dex
	folder "$S/card" . dex "$OUT/dex"
	runsd "$S" 180 "Dex Cards.cvt" DEX.CSV "Text  Scrap.cvt" DEX.TEL
	echo "== Dex on an SD card image (the root is the system folder)"
	$CHK dex "$S" . dial || fail "Dex (SD card)"
	S=$OUT/sd/cal
	folder "$S/card" . cal "$OUT/cal"
	runsd "$S" 180 Appointments.cvt "Veranda Alarms.cvt"
	echo "== the Calendar and its alarm on an SD card image"
	$CHK cal "$S" . || fail "the Calendar (SD card)"
	S=$OUT/sd/prefs
	folder "$S/card" . prefs1 "$OUT/prefs1"
	runsd "$S" 120 "Veranda Prefs.cvt" DESKTOP.cvt TopDesk.cvt PRE.RAW POST.RAW
	echo "== Preferences on an SD card image"
	$CHK prefs1 "$S" . || fail "Preferences (SD card)"
	# the new start: the card as Preferences left it, without AUTOSTART
	S2=$OUT/sd/reboot
	mkdir -p "$S2/card"
	cp "$S/Veranda Prefs.cvt" "$S/DESKTOP.cvt" "$S/TopDesk.cvt" "$S2/card/"
	runsd "$S2" 60
	echo "== started again from the SD card"
	$CHK reboot "$S2" || fail "the settings after a new start (SD card)"
	S=$OUT/sd/theme
	tfolder "$S/card" "$OUT/prefs3" desk
	runsd "$S" 120 "Veranda Prefs.cvt"
	echo "== the theme on an SD card image: Preferences over the shell, Graphite"
	got=$(tlog "$S/console.txt" 'SHELL THEME [0-9 ]*|PREFS (SAVED|CLOSED)[0-9 ]*')
	[ "$got" = "SHELL THEME 3 14 5,PREFS SAVED 255 15 35 2 B 0 255 0 0 2 3 2 130 128 0,PREFS CLOSED,SHELL THEME 2 3 2," ] \
		|| fail "SD card: the console has $got"
	$TH bars "$S/dump.bin" 2 3 2 || fail "SD card: the shell after Preferences"
	S2=$OUT/sd/theme2
	mkdir -p "$S2/card"
	cp "$S/Veranda Prefs.cvt" "$S2/card/"
	tfolder "$S2/card" "" probe
	runsd "$S2" 60
	$TH bars "$S2/dump.bin" 2 3 2 || fail "SD card: Graphite after a new start"
	ok "SD card: Graphite saved, the shell at once and after a new start"
fi
echo "screenshots: $OUT/dex.png, cal.png, alarm.png, prefs.png, theme.png, theme-graphite.png, theme-classic.png"
echo "GATE da: PASS"
