#!/bin/bash
# Gate term: Veranda Term (apps/term), a terminal for a 16C550 UART with a
# Wi-Fi modem behind it; the kernel's intFirstVector (DECISIONS V41) and
# SetClock (V42).
#
#   tools/gate_term.sh          (TERM_SD=0: skip the SD card runs)
#
# EMU is the emulator (the X16's own build); EMU_UART an x16emu with the
# general UART (-uart <addr> tcp:host:port, the "uart" branch of the
# emulator: UART.md there), default ~/Projects/x16-emulator-uart/build/x16emu.
# Without it the parts that need a serial line report SKIP.
#
# 1. the kernel, the SDK installed into build/gate/term/sdk; apps/term
#    built against it: an application (VRND, API 2, its overlay banked);
#    it starts with no UART (the X16's emulator) and finds the one at
#    $9FE0 (EMU_UART: its scratch register)
# 2. the test build (tests/term_test.c, tests/term_play.s; TERM.TST picks
#    the session):
#    page   the script back-end (no serial port): the ANSI test page
#           (tests/term_bbs.py --page) played at 9600 baud and captured; the
#           model, the window and the colour map equal a reference
#           terminal's (tests/check_term.py); CAPPAGE.TXT equals the page
#    bbs    a fake Zimodem and BBS on localhost (tests/term_bbs.py) through
#           the emulator's UART: connect/dial typed into the dial box,
#           Telnet negotiated (ECHO, SGA, TERMINAL-TYPE "ANSI", NAWS
#           80 x 55: the replies checked), the ANSI page, "hello veranda"
#           typed and echoed, file/about over the coloured window; the
#           screen as the reference's; stopped with the menu open, with
#           the box open (the cards under them on the normal paper,
#           their colours kept), and after PgUp (the scrollback)
#    speed  9600 baud for 10 s of data: captured, equal, none lost
#    xmodem two downloads (CRC and 1 KB blocks, 70,000 bytes, one bad
#           block; checksum and 128-byte blocks, 5,000 bytes), equal to the
#           files sent
#    clock  connect/clock from network: the daytime line, time zone +1,
#           the box's YES: the RTC and Veranda's clock hold it
#    speed aside  (V91) put aside (TaskCtl) while the BBS streams, the
#           UART's interrupt on: asideVector turns it off, a test desktop
#           (tests/term_desk.s) runs 3 s and brings Term back; it arms the
#           port again and takes the rest of the stream (no capture: a
#           stream open would make the switcher ask to quit it)
# The UART runs at the TexElec card's 14.7456 MHz (-uartclock, V91).
# 3. page and speed again on an SD card image (tools/vcard.py)
# Screenshots (the composed display, tools/vram2png.py --color) in
# build/gate/term: page.png, settings.png, addr.png (V149: the pages),
# bbs.png, bbsmenu.png, bbsdlg.png, bbsback.png.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/term
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
EMU_UART=${EMU_UART:-$HOME/Projects/x16-emulator-uart/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
skip() { echo "SKIP  $*"; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
# (V91) the UART's crystal: the TexElec card's 14.7456 MHz, Term's default
UCLK="-uartclock 14.7456"
UART=1
[ -x "$EMU_UART" ] && "$EMU_UART" -h 2>&1 | grep -q -- "-uart <address>" || UART=0

# 1. the application
mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/term SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Veranda Term does not build"; }
A=$OUT/app/Term.cvt
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] \
	|| fail "Term.cvt: type, VRND or mode"
[ "$(field "$A" api)" = 2 ] || fail "Term.cvt: API level $(field "$A" api)"
ok "Veranda Term builds against the installed SDK: an application, API 2, 640x480, records $(field "$A" records), flags $(field "$A" flags) (the overlay banked)"

# run CVT $1 as AUTOSTART.cvt in folder $2 with TERM.TST $3 for at most $4
# seconds on emulator $5 (more arguments: the emulator's)
run() {
	local cvt=$1 dir=$2 tst=$3 secs=$4 emu=$5
	shift 5
	mkdir -p "$dir"
	cp "$cvt" "$dir/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	[ -n "$tst" ] && echo "$tst" > "$dir/TERM.TST"
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$emu" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V "$@" > console.txt 2>&1) || true
}
freeport() { $PY -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# a fake BBS on a free port for one run: $1 its folder; sets PORT
bbs() {
	PORT=$(freeport)
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/term_bbs.py "$PORT" "$1" > "$1/log.txt" 2>&1 &
	BBSPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the fake BBS does not start"
}
# (it ends when the emulator closes the line; killed after 10 s)
bbs_end() {
	for _ in $(seq 100); do kill -0 "$BBSPID" 2>/dev/null || break; sleep 0.1; done
	kill "$BBSPID" 2>/dev/null || true
	wait "$BBSPID" 2>/dev/null || true
}
png() { $PY tools/vram2png.py --color "$1" "$2" 2>/dev/null || true; }

run "$A" "$OUT/app/run" "" 15 "$EMU"
grep -q "TERM RUNNING (NO UART)" "$OUT/app/run/console.txt" || { tail -3 "$OUT/app/run/console.txt"; fail "Veranda Term does not start"; }
ok "it starts through the loader with no serial port (the X16's emulator): \"no UART\""
if [ $UART = 1 ]; then
	run "$A" "$OUT/app/run2" "" 15 "$EMU_UART" $UCLK -uart 9FE0 file:,"$TOP/$OUT/app/run2/out.bin"
	grep -q "TERM RUNNING$" "$OUT/app/run2/console.txt" || { tail -3 "$OUT/app/run2/console.txt"; fail "Veranda Term does not find the UART at \$9FE0"; }
	ok "with the emulator's UART at \$9FE0 it finds it (the scratch register) and starts"
else
	skip "no emulator with -uart ($EMU_UART): the serial line's sessions"
fi

# 2. the test build
make -s -C apps/term test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
T=$OUT/test/Term.cvt
CHK="$PY tests/check_term.py"

echo "== page: the script back-end (no serial port)"
R=$OUT/page
mkdir -p "$R"
$PY tests/term_bbs.py --page "$R/TERM.IN"
run "$T" "$R" "page end 4 0" 60 "$EMU"
[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "page: the session did not end"; }
$PY tools/check_vera.py "$R/dump.bin" || fail "page: the display"
$CHK screen "$R" "$R/TERM.IN" "$ROM" --title page || fail "page: the screen"
cmp -s "$R/CAPPAGE.TXT" "$R/TERM.IN" || fail "page: CAPPAGE.TXT is not the page"
ok "capture: CAPPAGE.TXT equals the $(stat -c %s "$R/TERM.IN") bytes received"
grep -q "TERM LOST 0" "$R/console.txt" || fail "page: bytes lost"
png "$R/dump.bin" "$OUT/page.png"
# (V149) the settings and address book pages after the page: screenshots
for pg in settings addr; do
	R=$OUT/page-$pg
	mkdir -p "$R"
	cp "$OUT/page/TERM.IN" "$R/"
	run "$T" "$R" "page $pg 4 0" 60 "$EMU"
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "page $pg: the session did not end"; }
	png "$R/dump.bin" "$OUT/$pg.png"
done
ok "the settings and address book pages: settings.png, addr.png"

if [ $UART = 1 ]; then
	for stop in end menu dlg back; do
		echo "== bbs ($stop): a fake Zimodem and BBS over TCP"
		R=$OUT/bbs-$stop
		bbs "$R/bbs"
		run "$T" "$R" "bbs $stop 4 0" 120 "$EMU_UART" $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
		bbs_end
		[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "bbs $stop: the session did not end"; }
		$PY tools/check_vera.py "$R/dump.bin" || fail "bbs $stop: the display"
		$PY - "$R/bbs/bbs.json" <<-'EOF' || fail "bbs $stop: Telnet"
		import json, sys
		r = json.load(open(sys.argv[1]))
		ev = [tuple(e) if e[0] != 'SB' else ('SB', tuple(e[1])) for e in r['telnet']]
		want = [('DO', 1), ('DO', 3), ('WILL', 24), ('WILL', 31), ('SB', (31, 0, 80, 0, 55)), ('SB', (24, 0) + tuple(b'ANSI'))]
		miss = [w for w in want if w not in ev]
		if miss or not r['telnet_ok']:
		    sys.exit('FAIL  Telnet replies missing: %s (got %s)' % (miss, ev))
		# (V94) the modem's rate first: "AT" at 115200 answered (the fake
		# answers at any rate), so "ATB9600" moves it to settings/B
		if r['commands'][:4] != ['AT', 'ATB9600', 'ATV1', 'ATDTbbs.test:23']:
		    sys.exit('FAIL  the modem got %s' % r['commands'])
		if r.get('typed') != 'hello veranda':
		    sys.exit('FAIL  typed: %r' % r.get('typed'))
		print('ok    the modem got AT and ATB9600 (its rate found, moved to 9600: V94), ATV1 (the init string) and ATDTbbs.test:23; Telnet: DO ECHO, DO SGA, WILL '
		      'TERMINAL-TYPE (IS "ANSI"), WILL NAWS (80 x 55); "hello veranda" typed reached the BBS')
		EOF
		$CHK screen "$R" "$R/bbs/sent.bin" "$ROM" --stop $stop --title bbs.test:23 || fail "bbs $stop: the screen"
		png "$R/dump.bin" "$OUT/bbs$([ $stop = end ] || echo $stop).png"
	done

	echo "== speed: 9600 baud, 10 s of data, captured"
	R=$OUT/speed
	bbs "$R/bbs"
	run "$T" "$R" "speed end 4 0" 120 "$EMU_UART" $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
	bbs_end
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "speed: the session did not end"; }
	$CHK speed "$R" "$R/bbs" || fail "speed"

	echo "== xmodem: two downloads at 38400 baud"
	R=$OUT/xmodem
	bbs "$R/bbs"
	run "$T" "$R" "xmodem end 6 0" 300 "$EMU_UART" $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
	bbs_end
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "xmodem: the session did not end"; }
	$CHK xmodem "$R" "$R/bbs" || fail "xmodem"

	echo "== clock: the daytime service, UTC+1, into the RTC"
	R=$OUT/clock
	bbs "$R/bbs"
	run "$T" "$R" "clock end 4 4" 120 "$EMU_UART" $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
	bbs_end
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "clock: the session did not end"; }
	grep -q "TERM CLOCK SET" "$R/console.txt" || fail "clock: not set"
	V=$(sed -n 's/^TERM VARS //p' "$R/console.txt")
	C=$(sed -n 's/^TERM RTC //p' "$R/console.txt")
	case "$V" in 2031-05-17\ 14:4[5-9]:*) ;; *) fail "clock: Veranda's clock $V, want 2031-05-17 14:45 and some seconds" ;; esac
	case "$C" in 2031-05-17\ 14:4[5-9]:*) ;; *) fail "clock: the RTC $C" ;; esac
	ok "clock: the daytime line 31-05-17 13:45:00 (UTC) asked about, YES: the RTC (clock_get_date_time) $C, Veranda's clock $V"
	grep -q "^TERM END" "$R/console.txt" || fail "clock: clicks after the box (where its YES was, and in the window) stopped it"
	ok "clicks after the box closed, where its YES was and in the window, do nothing (V40)"
	echo "== aside: Term put aside while the line is busy, brought back (V91)"
	R=$OUT/aside
	mkdir -p "$R"
	ca65 --cpu 65C02 -I "$SDK/include" -o "$OUT/test/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
	ld65 -C "$SDK/cfg/app.cfg" -o "$OUT/test/desk.bin" "$OUT/test/desk.o" || fail "the test desktop does not link"
	printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$OUT/test/desk.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$R/SHELL.cvt" "$OUT/test/desk.hdr" "$OUT/test/desk.bin" >/dev/null \
		|| fail "vpack the test desktop"
	bbs "$R/bbs"
	run "$T" "$R" "speed aside 4 0" 120 "$EMU_UART" -ram 2048 $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
	bbs_end
	[ -f "$R/dump.bin" ] || { tail -8 "$R/console.txt"; fail "aside: the session did not end"; }
	$PY - "$R/console.txt" "$R/bbs/sent.bin" <<-'EOF' || fail "aside"
	import os, re, sys
	con = open(sys.argv[1], 'rb').read().decode('latin-1').replace('\r', '\n')
	sent = os.path.getsize(sys.argv[2])
	want = ['TERM ASIDE', 'TASK ASIDE', 'TERMDESK', 'TERMDESK WAITED', 'TASK BACK', 'TERM BACK', 'TERM BYTES', 'TERM END']
	at, miss = 0, []
	for w in want:
	    i = con.find(w, at)
	    if i < 0:
	        miss.append(w)
	    else:
	        at = i + len(w)
	n = re.search(r'TERM BYTES (\d+)', con)
	n = int(n.group(1)) if n else 0
	if miss or not 1500 <= n <= sent - 1000:
	    sys.exit('FAIL  aside: the console in order (missing %s); %d bytes of %d received' % (miss, n, sent))
	print('ok    aside: put aside (TaskCtl) after 500 bytes, with the UART\'s interrupt on and the BBS sending: '
	      'asideVector turned it off, the desktop ran its 3 s, Term came back, armed the port again and took the '
	      'rest: %d bytes of %d (what came while it was aside lost)' % (n, sent))
	EOF
	R=$OUT/clock-dlg
	bbs "$R/bbs"
	run "$T" "$R" "clock dlg 4 4" 60 "$EMU_UART" $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT
	bbs_end
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "clock: no dump with the box open"; }
	png "$R/dump.bin" "$OUT/clockdlg.png"
fi

# 3. the SD card
if [ "${TERM_SD:-1}" != 0 ]; then
	echo "== page on an SD card image"
	S=$OUT/sd-page
	mkdir -p "$S/card" "$S/out"
	cp "$T" "$S/card/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$S/card/"
	cp "$OUT/page/TERM.IN" "$S/card/"
	echo "page end 4 0" > "$S/card/TERM.TST"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: the session did not end"; }
	mv "$S/dump.bin" "$S/out/"
	for f in TERM.SCR CAPPAGE.TXT; do
		$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null || fail "SD card: no $f"
	done
	$CHK screen "$S/out" "$S/card/TERM.IN" "$ROM" --title page || fail "SD card: the screen"
	cmp -s "$S/out/CAPPAGE.TXT" "$S/card/TERM.IN" || fail "SD card: CAPPAGE.TXT"
	ok "SD card: CAPPAGE.TXT equals the page"
	if [ $UART = 1 ]; then
		echo "== speed on an SD card image"
		S=$OUT/sd-speed
		mkdir -p "$S/card" "$S/out"
		cp "$T" "$S/card/AUTOSTART.cvt"
		cp build/VERANDA.SYS "$S/card/"
		echo "speed end 4 0" > "$S/card/TERM.TST"
		$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$S/"
		bbs "$S/bbs"
		(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU_UART" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump V $UCLK -uart 9FE0 tcp:127.0.0.1:$PORT > out/console.txt 2>&1) || true
		bbs_end
		[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card speed: the session did not end"; }
		$PY tools/vcard.py get "$S/sd.img" SPEED.TXT "$S/out/SPEED.TXT" >/dev/null || fail "SD card: no SPEED.TXT"
		$CHK speed "$S/out" "$S/bbs" || fail "SD card: speed"
	fi
fi
echo "screenshots: $OUT/page.png (the script back-end), settings.png, addr.png, bbs.png (the BBS), bbsmenu.png (a menu open),"
echo "             bbsdlg.png (a dialog box open), bbsback.png (the scrollback), clockdlg.png (the clock's box)"
echo "GATE term: PASS"
