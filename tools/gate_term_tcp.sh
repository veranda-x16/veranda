#!/bin/bash
# Gate term_tcp (DECISIONS V112): Veranda Term's TCP sessions through the
# Zimodem modem's command mode (apps/term/tcp.c, hosts.c), under ROM R49
# with the emulator's Zimodem back-end (-uart 9FE0 modem, as gate net),
# against test hosts on localhost (tests/term_tcp_server.py, Python's
# socket module). The serial terminal's own sessions are gate term's.
#
#   tools/gate_term_tcp.sh      (OUT=... where the results go, default build/gate/term_tcp)
#
# The test build (tests/term_test.c, session "net"; TERM.TST "net <stop>
# 38400 UTC <port>") plays the menu, the Hosts page and its boxes:
#  tel     "ATI" typed first (the serial terminal: the modem answers);
#          Connection > Connect..., C, 127.0.0.1, the port, Telnet. The
#          host: DO NAWS, DO TERMINAL-TYPE, WILL ECHO, WILL SGA, WILL and
#          DO BINARY; the replies (WILL NAWS with SB NAWS 0 80 0 55, WILL
#          TERMINAL-TYPE, DO ECHO, DO SGA, DO and WILL BINARY), SB
#          TERMINAL-TYPE IS "ANSI"; WILL ECHO again not answered; an ANSI
#          page with 0xFF in it: the model equals the reference terminal
#          (tests/check_term.py's); 256 bytes 0-255 sent by Term (0xFF
#          doubled) arrive whole; a block of 0-255 back (0xFF doubled):
#          the capture equals what the host meant; XMODEM (CRC, 1 KB
#          blocks, 20,000 bytes with runs of 0xFF, every one doubled):
#          equal; the host closes: the box "The host closed the
#          connection"
#  raw     Hosts page: N, "Echo", 127.0.0.1, the port, raw: TERM.HOSTS
#          written (the five defaults and Echo); the host's line, 256
#          bytes echoed as they are: the capture equal; XMODEM with
#          nothing doubled: equal; Disconnect: ATH, ATZ (the modem's own
#          profile back); "ATI" typed: the modem answers in the window
#  hosts   TERM.HOSTS (raw's) read back: the page shows it (screenshot)
#  fail    TERM.HOSTS read back, its Echo entry (6) chosen: the port is
#          closed now: the box "Could not connect (refused, or no such
#          host)", ATZ
#  nomodem nothing on the line (-uart 9FE0 file:): the box "The modem
#          does not answer"
# Screenshots (tools/vram2png.py --color) in $OUT: tel.png, raw.png,
# hosts.png, refused.png, nomodem.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/term_tcp}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end (the emulator's modem branch)"
rm -rf "$OUT"
mkdir -p "$OUT/test" "$OUT/app"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
make -s -C apps/term SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "Veranda Term does not build"; }
make -s -C apps/term test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
mkdir -p "$OUT/testui"
make -s -C apps/term test SDK="$SDK" OUT="$TOP/$OUT/testui" TESTFLAGS=-DTERM_UI >"$OUT/testui/build.log" 2>&1 \
	|| { cat "$OUT/testui/build.log"; fail "the idle and mouse test build does not build"; }
end() { sed -n "s/^BSS *[0-9A-F]* *\([0-9A-F]*\).*/\1/p" "$1"; }
ok "Veranda Term and its test build: main RAM to \$$(end "$OUT/app/term.map") and \$$(end "$OUT/test/term.map") (the C stack from \$8400); Term.cvt $(stat -c %s "$OUT/app/Term.cvt") bytes"
T=$OUT/test/Term.cvt

freeport() { $PY -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
# session $1 (stop) in $OUT/$2; $3 the server's mode (or ""); $4 the port;
# $5 the UART back-end; $6 seconds
run() {
	local stop=$1 R=$OUT/$2 mode=$3 port=$4 uart=$5 secs=$6 sp=
	mkdir -p "$R"
	cp "${TCVT:-$T}" "$R/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
	echo "${SESS:-net} $stop 6 0 $port" > "$R/TERM.TST"
	if [ -n "$mode" ]; then
		$PY tests/term_tcp_server.py "$mode" "$port" "$R/srv" > "$R/srv.log" 2>&1 &
		sp=$!
		for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
		[ -f "$R/srv/ready" ] || fail "$2: the test host does not start"
	fi
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "$uart" > console.txt 2>&1) || true
	if [ -n "$sp" ]; then
		for _ in $(seq 100); do kill -0 $sp 2>/dev/null || break; sleep 0.1; done
		kill $sp 2>/dev/null || true
		wait $sp 2>/dev/null || true
	fi
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "$2: the session did not end"; }
	tr '\r' '\n' < "$R/console.txt" > "$R/log.txt"
}
png() { $PY tools/vram2png.py --color "$1" "$2" 2>/dev/null || true; }
inlog() { grep -q "^$2" "$OUT/$1/log.txt" || fail "$1: no \"$2\" in the log"; }

echo "== tel: Telnet to a test host"
P=$(freeport)
run tel tel telnet "$P" "modem:log=$TOP/$OUT/tel/modem.log" 150
for l in "TERM TCP OPEN" "TERM XM 1110" "TERM TCP CLOSED"; do inlog tel "$l"; done
$PY - "$OUT/tel" "$ROM" <<-'EOF' || fail "tel"
import json, os, sys
sys.path.insert(0, 'tests')
from check_term import VT, ROWS, COLS
r = sys.argv[1]
res = json.load(open(os.path.join(r, 'srv', 'tcp.json')))
def need(c, m):
    if not c:
        sys.exit('FAIL  tel: ' + m)
need(res.get('telnet_ok'), 'the Telnet replies: %s' % res.get('events'))
need(res['naws'] == [[0, 80, 0, 55]], 'NAWS %s' % res['naws'])
need(res['ttype'] == ['ANSI'], 'TERMINAL-TYPE %s' % res['ttype'])
need(not res['again_answered'], 'WILL ECHO again was answered: %s' % res['again_answered'])
print('ok    Telnet: WILL NAWS, SB NAWS 0 80 0 55 (80 x 55), WILL TERMINAL-TYPE and IS "ANSI", DO ECHO, DO SGA, '
      'DO and WILL BINARY; WILL ECHO again (on already) not answered')
need(res['up'] and res['up_raw_ff'], 'the 256 bytes Term sent: %s' % res.get('up_got', res['up_len']))
print('ok    256 bytes 0-255 sent through net_send (as keys and Send text file send): arrived whole, 0xFF as IAC IAC on the wire')
cap = open(os.path.join(r, 'CAPTCP.BIN'), 'rb').read()
need(cap == open(os.path.join(r, 'srv', 'CAP.REF'), 'rb').read(), 'the capture (%d bytes) is not what the host meant' % len(cap))
print('ok    the capture (%d bytes: the page, a block of 0-255 with 0xFF doubled) equals what the host sent, '
      'Telnet\'s commands and doubling taken out' % len(cap))
x = res['xmodem']
need(isinstance(x, dict) and open(os.path.join(r, 'DLT.BIN'), 'rb').read() == open(os.path.join(r, 'srv', 'DLT.REF'), 'rb').read(),
     'XMODEM: %s' % x)
print('ok    XMODEM over Telnet: %d bytes in %d 1 KB blocks (CRC), every 0xFF doubled both ways, equal; %d NAKs'
      % (x['size'], x['blocks'], x['naks']))
vt = VT()
for b in open(os.path.join(r, 'srv', 'PAGE.REF'), 'rb').read():
    vt.put(b)
m = open(os.path.join(r, 'TERM.SCR'), 'rb').read()
bad = [(row, c) for row in range(ROWS) for c in range(COLS)
       if (m[row * 160 + c], m[row * 160 + COLS + c]) != vt.rows[row][c]]
need(not bad, 'the page: %d cells differ from the reference (the first %s)' % (len(bad), bad[:1]))
need((m[-5], m[-4]) == (vt.x, vt.y), 'the cursor at %d,%d, want %d,%d' % (m[-5], m[-4], vt.x, vt.y))
print('ok    the ANSI page (colours, bold, reverse, CUP, 0xFF glyphs) as the reference terminal has it, cell for cell')
ml = open(os.path.join(r, 'modem.log'), encoding='latin-1').read()
order = ['ATI', 'ATE0V1X1Q0&M&D', 'ATS40=254S45=0S0=0', 'ATF3', 'ATH0', 'ATC"127.0.0.1:', 'ATZ']
at = 0
for w in order:
    i = ml.find(w, at)
    need(i >= 0, 'the modem log: %s missing after %d' % (w, at))
    at = i
print('ok    the modem: ATI typed in the window first (the serial terminal), then the profile, ATC, ATT and XONs; '
      'closed by the host: ATZ')
EOF
png "$OUT/tel/dump.bin" "$OUT/tel.png"

echo "== raw: raw TCP from a new Hosts entry, Disconnect"
P=$(freeport)
RAWPORT=$P
run r raw raw "$P" "modem:log=$TOP/$OUT/raw/modem.log" 150
for l in "TERM TCP OPEN" "TERM HOSTS WRITTEN" "TERM XM 1110" "TERM TCP ENDED" "TERM TCP IDLE" "TERM END"; do inlog raw "$l"; done
$PY - "$OUT/raw" "$P" <<-'EOF' || fail "raw"
import json, os, sys
r, port = sys.argv[1], sys.argv[2]
def need(c, m):
    if not c:
        sys.exit('FAIL  raw: ' + m)
res = json.load(open(os.path.join(r, 'srv', 'tcp.json')))
need(res['up'], 'the echo: %s' % res)
cap = open(os.path.join(r, 'CAPTCP.BIN'), 'rb').read()
need(cap == open(os.path.join(r, 'srv', 'CAP.REF'), 'rb').read(), 'the capture (%d bytes)' % len(cap))
need(b'\xff\xff' not in open(os.path.join(r, 'srv', 'recv.bin'), 'rb').read()[:300], '0xFF doubled in raw mode')
print('ok    raw: the host\'s line and 256 bytes 0-255 echoed: the capture equal; nothing doubled')
x = res['xmodem']
need(isinstance(x, dict) and open(os.path.join(r, 'DLT.BIN'), 'rb').read() == open(os.path.join(r, 'srv', 'DLT.REF'), 'rb').read(),
     'XMODEM: %s' % x)
print('ok    XMODEM over raw TCP: %d bytes, %d blocks, equal; %d NAKs' % (x['size'], x['blocks'], x['naks']))
need(res['closed_by'] == 'term', 'the connection was not closed by Term: %s' % res['closed_by'])
h = open(os.path.join(r, 'TERM.HOSTS'), 'rb').read().decode('latin-1').split('\r\n')
need(len(h) == 7 and h[5] == 'Echo|127.0.0.1:%s|raw' % port and h[0].endswith('|telnet') and h[6] == '',
     'TERM.HOSTS: %r' % h)
print('ok    TERM.HOSTS written: the five defaults and "%s"' % h[5])
ml = open(os.path.join(r, 'modem.log'), encoding='latin-1').read()
i = ml.find('ATH1')
j = ml.find('ATZ', i)
k = ml.find('ATI', j)
need(0 <= i < j < k, 'the modem log: ATH1, ATZ, ATI not in order')
m = open(os.path.join(r, 'TERM.SCR'), 'rb').read()
cy = m[-4]
rows = [m[y * 160:y * 160 + 80].decode('latin-1') for y in range(max(0, cy - 4), cy + 1)]
need(any('ZIMODEM ESP32 FIRMWARE' in t for t in rows), 'ATI after Disconnect: no answer in the window: %r' % rows)
print('ok    Disconnect: ATH1, then ATZ (the modem\'s own profile), the session over; "ATI" typed: the modem\'s '
      'answer in the window (the serial terminal as before)')
EOF
png "$OUT/raw/dump.bin" "$OUT/raw.png"

echo "== hosts: TERM.HOSTS read back"
mkdir -p "$OUT/hosts" "$OUT/fail"
cp "$OUT/raw/TERM.HOSTS" "$OUT/hosts/"
run h hosts "" 1 "modem:log=$TOP/$OUT/hosts/modem.log" 90
inlog hosts "TERM HOSTS READ"
ok "hosts: TERM.HOSTS read (the page: hosts.png)"
png "$OUT/hosts/dump.bin" "$OUT/hosts.png"

echo "== fail: the Echo entry again, its port closed now"
cp "$OUT/raw/TERM.HOSTS" "$OUT/fail/"
run f fail "" 1 "modem:log=$TOP/$OUT/fail/modem.log" 90
for l in "TERM HOSTS READ" "TERM TCP REFUSED"; do inlog fail "$l"; done
grep -q "ATC\"127.0.0.1:$RAWPORT\"" "$OUT/fail/modem.log" || fail "fail: ATC to the saved entry"
ok "refused: entry 6 from the file read back (ATC\"127.0.0.1:$RAWPORT\"), the box \"Could not connect (refused, or no such host)\""
png "$OUT/fail/dump.bin" "$OUT/refused.png"

echo "== nomodem: nothing on the line"
mkdir -p "$OUT/nomodem"
run n nomodem "" 1 "file:,$TOP/$OUT/nomodem/out.bin" 120
inlog nomodem "TERM TCP NO MODEM"
ok "no modem: the rates tried again, the profile's AT unanswered: the box \"The modem does not answer\""
png "$OUT/nomodem/dump.bin" "$OUT/nomodem.png"

# (V194, V195) the second test build (TERM_UI): idle, and the pages with the mouse
export TCVT=$OUT/testui/Term.cvt
echo "== idle: 10 s with nothing happening (V194)"
SESS=idle run i idle "" 1 "modem:log=$TOP/$OUT/idle/modem.log" 90
grep -q "^TERM IDLE 10S STATUS 0 PARTS 0 CURSOR 0 TX 0$" "$OUT/idle/log.txt" \
	|| fail "idle: drawn or sent while nothing happened: $(grep '^TERM IDLE 10S' "$OUT/idle/log.txt")"
ok "idle 10 s, the modem found: the status bar drawn 0 times (whole or in part), the cursor 0 times, 0 bytes sent"
grep -q "^TERM IDLE CAPTURE STATUS 0 PARTS 1 CURSOR 0 TX 0$" "$OUT/idle/log.txt" \
	|| fail "idle: Capture on: $(grep '^TERM IDLE CAPTURE' "$OUT/idle/log.txt")"
ok "Capture on: the status bar drawn once, in part (from the change on), not cleared whole"
$PY - "$OUT/idle/modem.log" <<-'EOF' || fail "idle: the modem log"
import sys
l = [x for x in open(sys.argv[1], encoding='latin-1').read().splitlines() if x]
want = ['START 115200', '@115200 AT', '@115200 ATB38400', 'BAUD 38400']
if l != want:
    sys.exit('FAIL  idle: the modem got %r, want only the rate found %r' % (l, want))
print('ok    the modem log: only the rate found (AT, ATB38400), then nothing in 11 s')
EOF
png "$OUT/idle/dump.bin" "$OUT/idle.png"

echo "== mouse: the Hosts page and the address book with the mouse (V195)"
P1=$(freeport); P2=$(freeport); P3=$(freeport)
for d in mouse-h mouse-d mouse-a mouse-b mouse-e; do
	mkdir -p "$OUT/$d"
	printf 'First|127.0.0.1:%s|raw\r\nSecond|127.0.0.1:%s|raw\r\nThird|127.0.0.1:%s|raw\r\n' $P1 $P2 $P3 > "$OUT/$d/TERM.HOSTS"
	printf 'Mine|127.0.0.1:%s\nTheirs|127.0.0.1:%s\n' $P1 $P2 > "$OUT/$d/TERM.BOOK"
done
SESS=mouse run h mouse-h "" 1 "modem:log=$TOP/$OUT/mouse-h/modem.log" 90
inlog mouse-h "TERM HOSTS SEL 1"
grep -A3 "^TERM HOSTS SEL 1" "$OUT/mouse-h/log.txt" | grep -q "^TERM HOSTS SEL 2" || fail "mouse-h: the 3rd row's click"
png "$OUT/mouse-h/dump.bin" "$OUT/hosts-click.png"
SESS=mouse run a mouse-a "" 1 "modem:log=$TOP/$OUT/mouse-a/modem.log" 90
inlog mouse-a "TERM BOOK SEL 9"
png "$OUT/mouse-a/dump.bin" "$OUT/book-click.png"
$PY - "$OUT/hosts-click.png" 2 "$OUT/book-click.png" 9 <<-'EOF' || fail "mouse: the selection on the screen"
import sys
from PIL import Image
def dark(im, y0):
    px = im.load()
    n = sum(1 for y in range(y0 + 2, y0 + 14) for x in range(16, 600, 2) if sum(px[x, y][:3]) < 200)
    return n / (12 * 292)
for png, row in ((sys.argv[1], int(sys.argv[2])), (sys.argv[3], int(sys.argv[4]))):
    im = Image.open(png).convert('RGB')
    d = [round(dark(im, 88 + 16 * r), 2) for r in range(row + 2)]
    if d[row] < 0.6 or max(d[:row] + d[row + 1:]) > 0.4:
        sys.exit('FAIL  %s: the rows\' ink %s, row %d not the one inverted' % (png, d, row))
print('ok    on the screen the clicked row inverted, no other (hosts-click.png row 3, book-click.png row 9)')
EOF
$PY - "$OUT/idle.png" "$OUT/hosts-click.png" <<-'EOF' || fail "idle: the status bar drawn in parts"
import sys
from PIL import Image
a, b = (Image.open(p).convert('RGB').crop((0, 464, 640, 480)).tobytes() for p in sys.argv[1:])
if a != b:
    sys.exit('FAIL  idle: "Offline" after Capture on and off (drawn in part twice) differs from the bar drawn whole')
print('ok    the status bar after Capture on and off (drawn in part twice) equals the bar drawn whole, pixel for pixel')
EOF
ok "a click selects: the Hosts page's 2nd then 3rd host (TERM HOSTS SEL 1, 2), the address book's row 9"
SESS=mouse run d mouse-d "" 1 "modem:log=$TOP/$OUT/mouse-d/modem.log" 90
inlog mouse-d "TERM TCP REFUSED"
grep -q "ATC\"127.0.0.1:$P3\"" "$OUT/mouse-d/modem.log" || fail "mouse-d: no ATC to the 3rd host"
grep -q "ATC\"127.0.0.1:\($P1\|$P2\)\"" "$OUT/mouse-d/modem.log" && fail "mouse-d: ATC to another host"
ok "a double click on the 3rd host connects to it: ATC\"127.0.0.1:$P3\" only (refused: nothing listens there)"
SESS=mouse run b mouse-b "" 1 "modem:log=$TOP/$OUT/mouse-b/modem.log" 90
grep -q "ATDT127.0.0.1:$P2" "$OUT/mouse-b/modem.log" || fail "mouse-b: no ATDT to row 9 ($(grep ATD "$OUT/mouse-b/modem.log"))"
grep -q "ATDT127.0.0.1:$P1" "$OUT/mouse-b/modem.log" && fail "mouse-b: ATDT to row 8"
ok "a double click on the address book's row 9 dials it: ATDT127.0.0.1:$P2"
SESS=mouse run e mouse-e "" 1 "modem:log=$TOP/$OUT/mouse-e/modem.log" 90
inlog mouse-e "TERM BOOK SEL 8"
grep -q "ATDT127.0.0.1:$P1" "$OUT/mouse-e/modem.log" || fail "mouse-e: no ATDT to row 8 ($(grep ATD "$OUT/mouse-e/modem.log"))"
ok "row 8 clicked, then the Dial button: ATDT127.0.0.1:$P1"
unset TCVT

for f in tel raw hosts refused nomodem idle hosts-click book-click; do [ -s "$OUT/$f.png" ] || fail "no screenshot $f.png"; done
echo "screenshots: $OUT/tel.png (Telnet, closed by the host), raw.png (after Disconnect, ATI),"
echo "             hosts.png (the Hosts page), refused.png, nomodem.png, idle.png (10 s idle, then Capture on),"
echo "             hosts-click.png (the 3rd host clicked), book-click.png (the address book's row 9 clicked)"
echo "GATE term_tcp: PASS"
