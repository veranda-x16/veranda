#!/bin/bash
# Gate claude (DECISIONS V114): Veranda Claude (apps/claude) under ROM R49,
# through vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem: the
# user's UART emulator's "modem" branch), against a fake Messages API on
# localhost (tests/claude_server.py: Python's socket module; the real API
# is never called). The test build (tests/claude_play.c) plays the mouse
# and the keys through mouseSource (tests/term_play.s), as gates irc and
# gopher do.
#
#   tools/gate_claude.sh     (OUT=... where the results go, default build/gate/claude)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" (default
# ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM
# (~/Downloads/Release.R49.ROM.Image/rom.bin). An emulator whose modem
# knows ATCS (the firmware's TLS connect: there a plain TCP one, logged
# SECURE) is checked for ATCS; an older one gets the test's plain ATC.
#
# 1. the kernel and the SDK; Veranda Claude built against it (Claude.cvt:
#    an application, banked overlays, its tile); the sizes
# 2. main: CLAUDE.CFG with the gate's server and no key: the Settings page
#    at the start; the key typed, Return: CLAUDE.CFG written; a turn: the
#    request (its headers, its body: model, stream, fallbacks, effort,
#    cache_control, the system prompt, the messages), the thinking pause,
#    the text streamed in chunks (Unicode escapes, raw UTF-8, an emoji,
#    bullets folded to CP437), sent back as it was folded; a long reply; a
#    max_tokens stop (its note); a refusal (the turn left out of later
#    requests); a 529 and a 401 (their boxes, the text back in the box);
#    an error event mid-stream (the part kept, its box); a slow reply
#    stopped with Esc (the part kept, the server sees the close); Alt+Tab
#    while a reply comes; four big replies (the oldest turns dropped, the
#    history still starting with a user turn); Settings > Claude Haiku 5.5
#    (no fallbacks, no beta header); File > Save conversation (the text
#    file); File > New conversation; the main loop's longest gap; nothing
#    lost in the UART
# 3. nomodem (-uart 9FE0 file:, no modem): a message: the box
# (no UART at all: the test cannot run, its player counts ser_frames, which
# only vrnet's interrupt advances; gate net covers NET_ENOCARD)
# Screenshots: $OUT/first.png, settings.png, thinking.png, midstream.png,
# hello.png (V143: the Polish turn), long.png, story.png, error.png, menu.png
# (V149: the Settings menu), final.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/claude}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
# (the modem's ATCS, if this emulator has it: an older build has no TLS
# modifier and the test connects with a plain ATC)
PLAIN=plain; grep -q -a "plain TCP here: no TLS" "$EMU_NET" 2>/dev/null && PLAIN=
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end (the emulator's modem branch)"
[ -z "$PLAIN" ] || echo "      (this emulator's modem has no ATCS: the test connects with a plain ATC)"
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# 1. the application, the test build, the test desktop
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/claude all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/claude does not build"; }
make -s -C apps/claude test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/claude's test build"; }
mkdir -p "$A/ctest"
make -s -C apps/claude test SDK="$SDK" OUT="$A/ctest" TESTFLAGS=-DCODE_SESSION > "$A/ctest.log" 2>&1 || { cat "$A/ctest.log"; fail "apps/claude's code test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/claude.map').read()
    seg = {g[0]: int(g[3], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M)}
    end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
    def mod(name):
        i = m.find(name + ':')
        c = re.search(r'CODE\s+Offs=\w+\s+Size=(\w+)', m[i:i + 400])
        return int(c.group(1), 16) if c else 0
    net = mod('veranda.lib(vrnet.o)') + mod('veranda.lib(vrser.o)') + mod('veranda.lib(vrserc.o)') + mod('veranda.lib(vrsync.o)')
    o = [sum(seg.get(s % n, 0) for s in ('OVERLAY%d', 'OVL%dRO', 'OVL%dDATA', 'OVL%dBSS')) for n in (1, 2, 3, 4, 5, 6, 7, 8, 9)]
    return end, net, o
end, net, o = sizes(sys.argv[1])
tend, _, to = sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/Claude.cvt', 'rb').read())
print('ok    the sizes: Claude.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free; '
      'the test build to $%04X, %d free), of it vrnet with the serial driver %d bytes of code; overlay 1 (the '
      'interface) %d bytes, overlay 2 (files, the window chrome, a turn\'s end) %d, overlay 3 (the reply\'s '
      'parser, the scroll bar, the menus) %d, overlay 4 (the settings, the Settings page) %d, overlay 5 (code blocks, the clipboard) %d, '
      'overlay 6 (files) %d, overlay 7 (a turn\'s plan, compaction, the usage) %d; RAM banks: 6 (the conversation '
      '32 KB, its rows and the font), vrnet 2, the overlays 8 (15; the test build 16); overlay 8 (the chats) %d'
      % (cvt, end, end - 0x801, 0x8400 - end - 1, tend, 0x8400 - tend - 1, net, o[0], o[1], o[2], o[3], o[4], o[5], o[6], o[7]))
if end >= 0x8400 or tend >= 0x8400 or max(o + to) > 8192:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Claude builds against the installed SDK (and its test build)"

# the server: its folder; sets SPORT, CPORT (a port nothing listens on)
server() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/claude_server.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the fake API does not start"
	read -r SPORT CPORT < "$1/ready"
}
server_end() {
	sleep 0.5               # (V129: the server logs a request 0.2 s after its reply: the last one kept)
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session in folder $1: CLAUDE.TST $2, at most $3 seconds, the UART's back-end $4 (none: no UART)
run() {
	local dir=$1 tst=$2 secs=$3 uart=$4
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/${TB:-test}/Claude.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	echo "$tst" > "$dir/CLAUDE.TST"
	local t0=$(date +%s.%N) u=
	[ "$uart" = none ] || u="-uartclock 14.7456 -uart 9FE0 $uart"
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V $u > console.txt 2>&1) || true
	tr '\r' '\n' < "$dir/console.txt" > "$dir/log.txt"
	echo "      ($(basename "$dir"): $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
}
shots() {
	for s in "$@"; do
		[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png"
	done
	rm -f "$R"/*.RAW
}

if [ "${ONLY:-}" != code ]; then      # (ONLY=code: the code session alone)
echo "== main: the Settings page, turns streamed, the API's stops and errors, Stop, Alt+Tab, the oldest turns dropped, Haiku, Save, New"
R=$OUT/main
server "$R/srv"
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'host=127.0.0.1\r\nport=%s\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
run "$R" "main $SPORT $PLAIN" 900 "modem:baud=57600,log=$R/modem.log"
server_end
[ -f "$R/dump.bin" ] || { grep "^CL" "$R/log.txt" | tail -30; fail "main: the session did not end"; }
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; shots FAIL; fail "main: the test failed"; }
$PY tests/check_glyphs.py "$R/HELLO.RAW" "$ROM" "Polish (V143), typed and in the reply" \
	"Café? Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ" "Polish: Zażółć gęślą jaźń." "łódź, ZAŻÓŁĆ GĘŚLĄ JAŹŃ," || { shots HELLO; fail "the Polish glyphs"; }
shots FIRST SETTINGS THINKING MIDSTREAM HELLO LONG STORY ERROR MENU FINAL FAIL
$PY tests/check_claude.py main "$R" "$SPORT" "$PLAIN" || fail "main"

fi
echo "== code: code blocks (Copy, Save, Save .PRG), Remember, old code shortened, a file attached and saved back, compaction, the cheap model, short answers"
R=$OUT/code
server "$R/srv"
mkdir -p "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
printf 'key=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nhost=127.0.0.1\r\nport=%s\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
printf '5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n30 PRINT "SCORE";X+\n40 END\n' > "$R/game.txt"
$PY tools/x16basic.py tok "$R/game.txt" "$R/DOCUMENTS/GAME.PRG" || fail "GAME.PRG"
TB=ctest run "$R" "code $SPORT $PLAIN" 900 "modem:baud=57600,log=$R/modem.log"
server_end
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; shots FAIL; fail "code: the test failed"; }
shots CODE ATTACH SHORT COMPACT FINAL FAIL
mv "$OUT/final.png" "$OUT/code_final.png" 2>/dev/null || true
$PY tests/check_code.py claude "$R" || fail "code"
echo "== chats: saved after each turn; the program started again: the Chats page, refused files, a chat opened and continued, Rename, Delete"
R=$OUT/chats
server "$R/srv1"
mkdir -p "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
printf 'key=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nhost=127.0.0.1\r\nport=%s\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
TB=ctest run "$R" "h $SPORT $PLAIN" 300 "modem:baud=57600,log=$R/modem1.log"
server_end
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; fail "chats: the first run failed"; }
mv "$R/log.txt" "$R/log1.txt"
cp "$R/DOCUMENTS/Chats/Claude/0001 plain one.chat" "$R/chat1.chat" || fail "chats: no chat file after two turns"
printf 'VERANDA CHAT 1\r\napp=Claude\r\ntitle=broken\r\n\r\nu 99\r\nshort\r\n' > "$R/DOCUMENTS/Chats/Claude/0005 broken.chat"
printf 'VERANDA CHAT 3\r\napp=Claude\r\ntitle=future\r\n\r\nend\r\n' > "$R/DOCUMENTS/Chats/Claude/0006 future.chat"
server "$R/srv2"
printf 'key=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nhost=127.0.0.1\r\nport=%s\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
TB=ctest run "$R" "2 $SPORT $PLAIN" 300 "modem:baud=57600,log=$R/modem2.log"
server_end
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; shots FAIL; fail "chats: the second run failed"; }
shots CHATS OPENED FAIL
$PY tests/check_hist.py claude "$R" || fail "chats"

# the program saved: the ROM's BASIC loads and runs it
P=$OUT/code/prgrun
mkdir -p "$P"
cp "$OUT/code/DOCUMENTS/PROGRAM.PRG" "$P/"
(cd "$P" && SDL_VIDEODRIVER=dummy timeout -s INT 20 "$EMU_NET" -rom "$ROM" -prg PROGRAM.PRG -run -warp -sound none -echo > console.txt 2>&1) || true
tr '\r' '\n' < "$P/console.txt" | grep -q "^HELLO FROM CLAUDE" && tr '\r' '\n' < "$P/console.txt" | grep -q "^ 1.* 4.* 9" \
	&& tr '\r' '\n' < "$P/console.txt" | grep -q "^DONE" || { tail -c 600 "$P/console.txt"; fail "PROGRAM.PRG does not RUN in the ROM's BASIC"; }
ok "PROGRAM.PRG, LOADed by x16emu (-prg) and RUN by the ROM's BASIC: HELLO FROM CLAUDE, 1 4 9, DONE"

echo "== nomodem: no modem on the port"
R=$OUT/nomodem
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'key=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nhost=127.0.0.1\r\nport=9\r\n' > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
run "$R" "nomodem 9" 120 "file:,$R/out.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; fail "nomodem: the test failed"; }
$PY tests/check_claude.py nomodem "$R" 0 || fail "nomodem"

rm -f "$OUT"/*/dump.bin

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE claude: PASS"
