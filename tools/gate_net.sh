#!/bin/bash
# Gate net (DECISIONS V98): vrnet, the SDK's TCP sockets through a Zimodem
# Wi-Fi modem, under ROM R49, with the emulator's Zimodem back-end
# (-uart 9FE0 modem: the "modem" branch of the user's UART emulator, its
# UART.md); the test application tests/net_app.c against test servers on
# localhost (tests/net_servers.py: an echo server, a file server).
#
#   tools/gate_net.sh           (OUT=... where the results go, default build/gate/net)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" (default
# ~/Projects/x16-emulator-modem/build/x16emu, else the UART emulator's);
# R49: the ROM (~/Downloads/Release.R49.ROM.Image/rom.bin).
#
# 1. the kernel and the SDK (vrser, vrnet in lib/veranda.lib; vrnet.h,
#    vrser.h; docs/NET.md); the test application built against it
# 2. main (57600): the emulated modem starts at 38400 (as if a program left
#    it there): vrnet tries AT at 115200 and 57600 (noise), 38400 answers,
#    ATB57600, its OK at 57600; Packet16's profile (ATE0V1X1Q0&M&D,
#    ATS40=254S45=0S0=0, ATF3, ATH0); two sockets at once: the echo
#    server gets 16,384 bytes (every byte value, "+++", "NO CARRIER 1",
#    XON, XOFF, a packet header, pseudo-random bytes) and sends them back,
#    the file server sends 65,536 bytes and closes; every byte checked
#    both ways (in the program, and the echo server's copy here); Alt+Tab
#    (switchReq) while the file comes: put aside, the test desktop
#    (tests/term_desk.s) 3 s, brought back, both go on; then a host that
#    never answers (the modem's stall=): NET_ETIMEOUT after 15 s, the
#    main loop never blocked (the longest gap between its passes < 20
#    frames, the busy pointer's 1/3 s), the modem asked again until it
#    answers; a closed port: NET_ERR; the echo again
# 3. main at 115200 (the modem's own rate: no ATB; 16 polls a frame)
# 4. nomodem: nothing on the line (-uart 9FE0 file:): the five rates
#    tried, NET_FAULT with NET_ENOMODEM, the main loop running
# 5. nocard: no UART: net_start returns NET_ENOCARD
# Screenshot: $OUT/net.png (the composed display, tools/vram2png.py).
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/net}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
[ -x "$EMU_NET" ] || EMU_NET=${EMU_UART:-$HOME/Projects/x16-emulator-uart/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end (the emulator's modem branch)"
rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
for f in include/vrnet.h include/vrser.h docs/NET.md src/vrsync.c; do
	[ -f "$SDK/$f" ] || fail "the SDK has no $f"
done
for o in vrnet.o vrserc.o vrser.o vrsync.o; do
	ar65 t "$SDK/lib/veranda.lib" | grep -qx "$o" || fail "veranda.lib has no $o"
done
ok "the SDK installs vrnet.h, vrser.h, docs/NET.md and src/vrsync.c; veranda.lib holds vrnet, vrser"

# 1. the test application and the test desktop
A=$OUT/app
mkdir -p "$A"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -m "$A/net.map" -o "$A/net.bin" \
	tests/net_app.c "$SDK/lib/veranda.lib" > "$A/build.log" 2>&1 || { cat "$A/build.log"; fail "tests/net_app.c does not build"; }
printf 'name = NetTest\nclass = NetTest\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/app.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/NetTest.cvt" "$A/app.hdr" "$A/net.bin" >/dev/null || fail "vpack the test application"
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "tests/net_app.c builds against the installed SDK ($(stat -c %s "$A/net.bin") bytes)"

freeport() { $PY -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# the servers for one run, in folder $1; sets EPORT, FPORT
servers() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/net_servers.py "$1" > "$1/servers.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the test servers do not start"
	read -r EPORT FPORT < "$1/ready"
}
servers_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# run the test application in folder $1 with NET.TST $2 for at most $3
# seconds (more arguments: the emulator's)
run() {
	local dir=$1 tst=$2 secs=$3
	shift 3
	mkdir -p "$dir"
	cp "$A/NetTest.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	echo "$tst" > "$dir/NET.TST"
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V "$@" > console.txt 2>&1) || true
	tr '\r' '\n' < "$dir/console.txt" > "$dir/log.txt"
}
val() { sed -n "s/^$2 //p" "$1/log.txt" | head -1; }

# 2, 3. the main session
main_session() {
	local name=$1 rate=$2 mrate=$3
	echo "== $name: two sockets at $rate baud (the modem left at $mrate), Alt+Tab, a host that never answers"
	local R=$OUT/$name
	servers "$R/srv"
	local STALL
	STALL=$(freeport)
	run "$R" "main $EPORT $FPORT $STALL $((rate / 100))" 400 \
		-uartclock 14.7456 -uart 9FE0 "modem:baud=$mrate,stall=$STALL,ctimeout=20,log=$TOP/$R/modem.log"
	servers_end
	[ -f "$R/dump.bin" ] || { tail -12 "$R/log.txt"; fail "$name: the session did not end"; }
	grep -q "^NET END$" "$R/log.txt" || { grep "^NET" "$R/log.txt" | tail -12; fail "$name: the test application failed"; }
	$PY - "$R" "$rate" "$mrate" <<-'EOF' || fail "$name"
	import json, os, re, sys
	sys.path.insert(0, 'tests')
	import net_servers as ns
	r, rate, mrate = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
	log = open(os.path.join(r, 'log.txt'), encoding='latin-1').read().split('\n')
	net = {}
	for l in log:
	    m = re.match(r'^(NET [A-Z+ ]+?) (-?\d+)$', l)
	    if m:
	        net.setdefault(m.group(1), int(m.group(2)))
	def need(c, msg):
	    if not c:
	        sys.exit('FAIL  ' + msg)
	# the modem's side: the rate looked for, the profile, the commands
	ml = open(os.path.join(r, 'modem.log'), encoding='latin-1').read().split('\n')
	cmds = [(int(m.group(1)), m.group(2)) for m in (re.match(r'^@(\d+) (.*)$', l) for l in ml) if m]
	ats = [c for b, c in cmds if c.startswith('AT')]
	ratecmds = [c for c in ats if c.startswith('ATB')]
	if rate == mrate:
	    need(not ratecmds, 'no ATB wanted at the modem\'s own rate: %s' % ratecmds)
	    need(ats[0] == 'AT', 'the first command %r' % ats[:2])
	else:
	    need(ratecmds == ['ATB%d' % rate], 'ATB: %s' % ratecmds)
	    tried = sum(1 for l in ml if l.startswith('@%d ' % mrate) and l.endswith(' AT'))
	    need(tried >= 1, 'AT at the modem\'s rate')
	prof = ['ATE0V1X1Q0&M&D', 'ATS40=254S45=0S0=0', 'ATF3', 'ATH0']
	i = ats.index(prof[0])
	need(ats[i:i + 4] == prof, 'the profile: %s' % ats[i:i + 4])
	need(all(b == rate for b, c in cmds[cmds.index((rate, prof[0])):]), 'every command after the sync at %d' % rate)
	conns = [l for l in ml if l.startswith('CONNECT ')]
	need(len(conns) == 3, 'three connections made: %s' % conns)
	need(any(l.startswith('STALL ') for l in ml) and any('timeout' in l for l in ml), 'the stalled connect, its ERROR after ctimeout')
	need(any('Connection refused' in l for l in ml), 'the closed port refused')
	att = [c for c in ats if c.startswith('ATT')]
	need(max(int(c[3:]) for c in att) == 254, 'ATT at most 254 bytes')
	# both ways, byte for byte
	sent = ns.echo_bytes()
	e1 = open(os.path.join(r, 'srv', 'echo1.bin'), 'rb').read()
	need(e1 == sent, 'the echo server got %d bytes, %s' % (len(e1), 'equal' if e1 == sent else 'not equal to what was sent'))
	e2 = open(os.path.join(r, 'srv', 'echo2.bin'), 'rb').read()
	need(e2 == b'after', 'the second echo: %r' % e2)
	need(net.get('NET ECHO OK') == len(sent), 'the program\'s check of the echo: %s' % net.get('NET ECHO OK'))
	need(net.get('NET FILE OK') == 65536 and net.get('NET FILE EOF') == 65536, 'the file: %s' % net.get('NET FILE OK'))
	# Alt+Tab
	text = '\n'.join(log)
	at = 0
	for w in ['NET ALT+TAB AT', 'TASK ASIDE', 'TERMDESK WAITED', 'TASK BACK', 'NET BACK AT', 'NET FILE EOF']:
	    k = text.find(w, at)
	    need(k >= 0, 'Alt+Tab: %r not in order' % w)
	    at = k
	# the timeout, the main loop
	need(net.get('NET STALL FAILED') == -2, 'the stall: %s' % net.get('NET STALL FAILED'))
	sf = net.get('NET STALL FRAMES', 0)
	need(880 <= sf <= 960, 'NET_ETIMEOUT after %d frames (15 s wanted)' % sf)
	need(net.get('NET REFUSED') == -1, 'the closed port: %s' % net.get('NET REFUSED'))
	gap = net.get('NET MAXGAP', 999)
	need(gap < 20, 'the main loop\'s longest gap %d frames' % gap)
	need(net.get('NET LOST', 1) == 0, 'bytes lost in the UART or the ring: %s' % net.get('NET LOST'))
	need(net.get('NET BADCRC', 1) == 0, 'bad CRCs: %s' % net.get('NET BADCRC'))
	fr = net.get('NET BOTH FRAMES', 1)
	ff = net.get('NET FILE FRAMES', 1)
	print('ok    the modem\'s rate: %s; Packet16\'s profile, then every command at %d' %
	      ('AT at %d answered, no ATB' % rate if rate == mrate else
	       'the modem found at %d (AT from 115200 down; noise at the rates above it), ATB%d, its OK at the new rate' % (mrate, rate), rate))
	print('ok    two sockets at once: the echo server got all %d bytes sent (every byte value, "+++", "NO CARRIER 1", XON, XOFF, a header) '
	      'and the program got them back, equal; the file, 65,536 bytes, equal, then NET_ECLOSED' % len(sent))
	print('ok    %d frames for both (%.1f s; the file alone %.1f s: %d bytes/s); %d XONs, %d packets, %d empty, %d ATT, %d XON retries; '
	      'nothing lost in the UART or the ring, no bad CRC' % (fr, fr / 60, ff / 60, 65536 * 60 // ff, net['NET PULLS'],
	      net['NET PACKETS'], net['NET EMPTIES'], net['NET SENDS'], net['NET XONRETRY']))
	print('ok    Alt+Tab at byte %d of the file: put aside (asideVector: the packet arriving taken whole), the desktop\'s 3 s, '
	      'brought back at byte %d: both transfers went on to the end' % (net['NET ALT+TAB AT'], net['NET BACK AT']))
	print('ok    a host that never answers: NET_FAILED, NET_ETIMEOUT after %d frames (%.1f s); the main loop never waited '
	      '(longest gap %d frames); the modem answered again after %d frames; a closed port NET_ERR; the echo again: "after"' %
	      (sf, sf / 60, gap, net.get('NET RECOVERED FRAMES', 0), ))
	EOF
}
main_session main 57600 38400
$PY tools/vram2png.py --color "$OUT/main/dump.bin" "$OUT/net.png" 2>/dev/null || true
main_session main2 57600 115200

echo "== nomodem: nothing on the line"
R=$OUT/nomodem
run "$R" "nomodem 0 0 0 576" 120 -uartclock 14.7456 -uart 9FE0 "file:,$TOP/$R/out.bin"
[ -f "$R/dump.bin" ] || { tail -8 "$R/log.txt"; fail "nomodem: the session did not end"; }
[ "$(val "$R" "NET NOMODEM")" = -6 ] || { grep "^NET" "$R/log.txt"; fail "nomodem: not NET_ENOMODEM"; }
F=$(val "$R" "NET FRAMES")
GAP=$(val "$R" "NET MAXGAP")
[ "$GAP" -lt 20 ] || fail "nomodem: the main loop's longest gap $GAP frames"
N=$($PY -c 'import sys; print(open(sys.argv[1], "rb").read().count(b"AT\r"))' "$R/out.bin")
[ "$N" = 5 ] || fail "nomodem: AT sent $N times, want 5 (one a rate)"
ok "nomodem: AT at each of the five rates, then NET_FAULT, NET_ENOMODEM, after $F frames; the main loop's longest gap $GAP frames"

echo "== nocard: no UART"
R=$OUT/nocard
run "$R" "nocard 0 0 0 576" 60
grep -q "NET START -7$" "$R/log.txt" && grep -q "^NET END$" "$R/log.txt" || { grep "^NET" "$R/log.txt"; fail "nocard"; }
ok "nocard: net_start returns NET_ENOCARD at once"

echo "screenshot: $OUT/net.png (the main session's end)"
echo "GATE net: PASS"
