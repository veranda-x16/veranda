#!/bin/bash
# Gate irc (DECISIONS V111): Veranda Chat (apps/irc) under ROM R49, through
# vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem: the user's
# UART emulator's "modem" branch), against a small IRC server on localhost
# (tests/irc_server.py: Python's socket module). The test build
# (tests/irc_play.c) plays the mouse and the keys through mouseSource
# (tests/term_play.s), as gates ftp and gopher do.
#
#   tools/gate_irc.sh        (OUT=... where the results go, default build/gate/irc)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" (default
# ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM
# (~/Downloads/Release.R49.ROM.Image/rom.bin).
#
# 1. the kernel and the SDK; Veranda Chat built against it (Chat.cvt: an
#    application, class VerandaChat, banked overlays, its tile); the sizes
# 2. main: no CHAT.SERVERS: the Servers page with the defaults; New, the
#    fields typed (the gate's server, nick "veranda", alternative
#    "verandax", channels "#retro #x16"), Connect: "veranda" is in use, the
#    alternative taken; PASS-less registration (NICK, USER); one JOIN for
#    both; names and topics; PING answered; messages in (formatting codes
#    stripped, UTF-8 folded, Latin-1 kept); messages out and /me (the
#    server's lines exact, Latin-1 typed sent as UTF-8); a private message
#    opens its window (the sound); JOIN, PART, NICK, QUIT, MODE in the nick
#    list; a mention (the line marked, the sound, the other channel's tab
#    "!"); Tab's nick completion; a long line split under 512 bytes; CTCP
#    VERSION answered; /topic, /msg, /raw; the history (Up); /nick, /join,
#    /part, /query, /close; 400 lines: the scrollback's cap (the oldest
#    dropped), PgUp to its top; Alt+Tab while lines come (the connection
#    kept); the server's ERROR and close: the box; CHAT.SERVERS written;
#    the main loop's longest gap; nothing lost in the UART
# 3. reread: CHAT.SERVERS read back (main's): PgDn to the gate's server,
#    Return: registered, the channels joined
# 4. closedport: a server whose port nothing listens on, the modem answering
#    as the real firmware does (noanswer: NO ANSWER, not ERROR; V113): Connect: the box
# 5. nomodem (-uart 9FE0 file:, no modem): Connect: the box
# 6. welcome (V179: on the user's X16 the link dropped in Libera's and
#    SDF's welcome): a big network's welcome (NOTICEs, 001-005, 250-266, a
#    MOTD of 120 lines with ASCII art) written at once, the modem at 115200
#    (the rate vrnet finds first on the TexElec card): every line shown, the
#    channel joined after it, nothing lost in the UART, no bad CRC
# 7. big (V178: the user's X16 stopped after joining Libera's #linux and
#    EFnet's #freebsd): channels of 2,400 and 600 people (NAMES in 353
#    lines of up to 512 bytes, topics of 453 bytes with URLs) joined while
#    the tabs and the list are clicked: 190 nicks kept, every person
#    counted, the status bar's count; PART, QUIT, KICK, JOIN of nicks kept
#    and not; lines past 512 bytes (IRCv3 tags of 1,000 bytes, PRIVMSGs of
#    700 and 3,000, a NOTICE of 1,200, a TOPIC of 600, a KICK with nicks of
#    40, a CTCP PING of 600, a MODE of 20 parameters); more windows than
#    there is room for; the list's end ("and N more"); 600 lines of a busy
#    channel; the NAMES' time, the main loop's longest gap
# Screenshots: $OUT/servers.png, joined.png, msgs.png, menu.png (V149: the
# Window menu), mention.png,
# flood.png, scroll.png, aside.png, closed.png, servers2.png; (V178) big.png,
# long.png, nickend.png, storm.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/irc}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
# (the modem answering NO ANSWER as the firmware does, if this emulator has
# the option: an older build knows only ERROR, V113)
NA=; grep -q -a noanswer "$EMU_NET" 2>/dev/null && NA=noanswer,
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end (the emulator's modem branch)"
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
make -s -C apps/irc all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/irc does not build"; }
make -s -C apps/irc test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/irc's test build"; }
$PY - "$A/rel" <<'EOF' || fail "the sizes"
import re, sys
d = sys.argv[1]
m = open(d + '/chat.map').read()
seg = {g[0]: int(g[3], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M)}
end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
def mod(name):
    i = m.find(name + ':')
    c = re.search(r'CODE\s+Offs=\w+\s+Size=(\w+)', m[i:i + 400])
    return int(c.group(1), 16) if c else 0
net = mod('veranda.lib(vrnet.o)') + mod('veranda.lib(vrser.o)') + mod('veranda.lib(vrserc.o)') + mod('veranda.lib(vrsync.o)')
o = [sum(seg.get(s % n, 0) for s in ('OVERLAY%d', 'OVL%dRO', 'OVL%dDATA', 'OVL%dBSS')) for n in (1, 2, 3, 4, 5)]
cvt = len(open(d + '/Chat.cvt', 'rb').read())
print('ok    the sizes: Chat.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free), '
      'of it vrnet with the serial driver %d bytes of code; overlay 1 (the interface) %d bytes, overlay 2 (IRC) %d, '
      'overlay 3 (the servers) %d, overlay 4 (the commands, the window chrome) %d, overlay 5 (the scroll bars, '
      'the menus: V149) %d; RAM banks: 7 (7 scrollbacks of 4 KB, 6 nick lists of 4 KB, the history), vrnet 2, '
      'the overlays 5' % (cvt, end, end - 0x801, 0x8400 - end - 1, net, o[0], o[1], o[2], o[3], o[4]))
if end >= 0x8400 or max(o) > 8192:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Chat builds against the installed SDK (and its test build)"

# the server: its folder; sets SPORT, CPORT (a port nothing listens on)
server() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/irc_server.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the IRC server does not start"
	read -r SPORT CPORT < "$1/ready"
}
server_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session in folder $1: CHAT.TST $2, at most $3 seconds, the UART's back-end $4
run() {
	local dir=$1 tst=$2 secs=$3 uart=$4
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/test/Chat.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	echo "$tst" > "$dir/CHAT.TST"
	local t0=$(date +%s.%N)
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "$uart" \
		> console.txt 2>&1) || true
	tr '\r' '\n' < "$dir/console.txt" > "$dir/log.txt"
	echo "      ($(basename "$dir"): $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
}
shots() {
	for s in "$@"; do
		[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png"
	done
	rm -f "$R"/*.RAW
}

echo "== main: the Servers page, registration, channels, messages, the nick list, commands, the scrollback, Alt+Tab, the close"
R=$OUT/main
server "$R/srv"
run "$R" "main $SPORT" 900 "modem:baud=57600,log=$R/modem.log"
server_end
[ -f "$R/dump.bin" ] || { grep "^IR" "$R/log.txt" | tail -30; fail "main: the session did not end"; }
grep -q "^IR END$" "$R/log.txt" || { grep "^IR" "$R/log.txt" | grep -v "^IR LINE" | tail -30; fail "main: the test failed"; }
shots SERVERS JOINED MSGS MENU MENTION FLOOD SCROLL ASIDE CLOSED FAIL
$PY tests/check_irc.py main "$R" "$SPORT" || fail "main"

echo "== reread: CHAT.SERVERS read back"
R2=$OUT/reread
server "$R2/srv"
mkdir -p "$R2/VERANDA/.SYSTEM"
MPORT=$(cut -d' ' -f1 "$R/srv/ready")
sed "s/,$MPORT,/,$SPORT,/" "$R/VERANDA/.SYSTEM/CHAT.SERVERS" > "$R2/VERANDA/.SYSTEM/CHAT.SERVERS"   # (this server's port)
R=$R2
run "$R" "reread $SPORT" 120 "modem:baud=57600,log=$R/modem.log"
server_end
grep -q "^IR END$" "$R/log.txt" || { grep "^IR" "$R/log.txt" | grep -v "^IR LINE" | tail -30; fail "reread: the test failed"; }
shots SERVERS2 FAIL
$PY tests/check_irc.py reread "$R" "$SPORT" || fail "reread"

echo "== closedport: a server on a port nothing listens on"
R=$OUT/closedport
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'Gate,127.0.0.1,%s,veranda,verandax,Gate tester,,#retro\r\n' "$CPORT" > "$R/VERANDA/.SYSTEM/CHAT.SERVERS"
run "$R" "closedport $CPORT" 120 "modem:${NA}baud=57600,log=$R/modem.log"
grep -q "^IR END$" "$R/log.txt" || { grep "^IR" "$R/log.txt" | tail -30; fail "closedport: the test failed"; }
$PY tests/check_irc.py closedport "$R" "$CPORT" || fail "closedport"

echo "== nomodem: no modem on the port"
R=$OUT/nomodem
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'Gate,127.0.0.1,6667,veranda,verandax,Gate tester,,#retro\r\n' > "$R/VERANDA/.SYSTEM/CHAT.SERVERS"
run "$R" "nomodem 6667" 120 "file:,$R/out.bin"
grep -q "^IR END$" "$R/log.txt" || { grep "^IR" "$R/log.txt" | tail -30; fail "nomodem: the test failed"; }
$PY tests/check_irc.py nomodem "$R" 0 || fail "nomodem"

echo "== welcome: a big network's welcome in one write, at 115200 baud (V179)"
R=$OUT/welcome
server "$R/srv"
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'Burst,127.0.0.1,%s,veranda,verandax,Gate burst,,#retro\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CHAT.SERVERS"
run "$R" "welcome $SPORT" 300 "modem:baud=115200,log=$R/modem.log"
server_end
grep -q "^IR END$" "$R/log.txt" || { grep "^IR" "$R/log.txt" | grep -v "^IR LINE" | tail -30; fail "welcome: the test failed"; }
$PY tests/check_irc.py welcome "$R" "$SPORT" || fail "welcome"

echo "== big: channels of 2,400 and 600 people, long topics, lines past 512 bytes, more windows than room (V178)"
R=$OUT/big
server "$R/srv"
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'Gate,127.0.0.1,%s,veranda,verandax,Gate tester,,#big #huge\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/CHAT.SERVERS"
run "$R" "big $SPORT" 900 "modem:baud=57600,log=$R/modem.log"
server_end
grep -q "^IR END$" "$R/log.txt" || { grep "^IR\|PANIC" "$R/log.txt" | grep -v "^IR LINE\|^IR NICK " | tail -30; shots FAIL; fail "big: the test failed"; }
shots BIG LONG NICKEND STORM FAIL
$PY tests/check_irc.py big "$R" "$SPORT" || fail "big"
rm -f "$OUT"/*/dump.bin

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE irc: PASS"
