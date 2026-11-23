#!/bin/bash
# Gate claude_bridge (DECISIONS V115): Veranda Claude (apps/claude) with
# "Claude Code on my PC": the emulator's Veranda Claude (ROM R49, vrnet,
# the emulator's Zimodem back-end) talks to the real tools/claude_bridge.py
# on localhost, which runs a fake Claude Code (tests/fake_claude.py: its
# stream-json as the real one prints it; it records its argv). The real
# Claude Code is never run here.
#
#   tools/gate_claude_bridge.sh     (OUT=... where the results go, default build/gate/claude_bridge)
#
# EMU_NET, R49: as gate claude.
#
# 1. the bridge on its own (tests/test_claude_bridge.py under python3 -I):
#    the private-address filter, the password, the session map, the
#    no-tools flags, SSE out, the errors, busy, Claude Code killed when the
#    client hangs up
# 2. the kernel, the SDK, Veranda Claude's test build; the sizes
# 3. bridge: Settings, Claude Code on my PC, the address and a wrong
#    password (the 401 box), the right one; two turns through the bridge
#    (the second resumes Claude Code's session: --resume; the no-tools
#    flags on both; --model); the usage limit and not signed in (their
#    boxes); a slow reply stopped with Esc (Claude Code killed); a closed
#    port (the refused box); back to the Anthropic API (its key kept)
# Screenshots: $OUT/setbridge.png (Settings in bridge mode), bridge.png (a
# conversation through the bridge).
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/claude_bridge}
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
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

echo "== the bridge on its own (python3 -I, the fake Claude Code)"
$PY tests/test_claude_bridge.py "$OUT/host" 2> "$OUT/host.log" | tee "$OUT/host.txt" | grep -v '^ok' || true
grep -q "^test_claude_bridge: PASS" "$OUT/host.txt" || { cat "$OUT/host.log"; fail "the bridge's own test"; }
ok "the bridge's own test: $(grep -c '^ok' "$OUT/host.txt") checks"

$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/claude all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/claude does not build"; }
make -s -C apps/claude test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/claude's test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def end(d):
    m = open(d + '/claude.map').read()
    e = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
    o = {}
    for g in re.findall(r'^(OVERLAY|OVL)(\d)(RO|BSS|DATA)?\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M):
        o[int(g[1])] = o.get(int(g[1]), 0) + int(g[5], 16)
    return e, o
e, o = end(sys.argv[1])
te, to = end(sys.argv[2])
print('ok    the sizes: main RAM to $%04X (%d bytes free below the C stack; the test build to $%04X, %d free); '
      'overlays %s (of 8192 each)' % (e, 0x8400 - e - 1, te, 0x8400 - te - 1,
                                     ', '.join('%d: %d' % (k, v) for k, v in sorted(to.items()))))
if e >= 0x8400 or te >= 0x8400 or max(list(o.values()) + list(to.values())) > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Claude builds against the installed SDK (and its test build)"

echo "== bridge: Settings (Claude Code on my PC), the 401 box, turns through the bridge, its errors, Stop, refused, back to the API"
R=$OUT/bridge
mkdir -p "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS" "$R/br/work"
# (a port nothing listens on)
CPORT=$($PY -c "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
FAKE_CLAUDE_LOG=$R/br/fake.jsonl CLAUDE_BRIDGE_READY=$R/br/ready ANTHROPIC_API_KEY=sk-gate-not-for-the-child \
	$PY tools/claude_bridge.py --bind 127.0.0.1 --port 0 --password gate-bridge-pass \
	--claude "$PWD/tests/fake_claude.py" --workdir "$R/br/work" > "$R/br/stdout.txt" 2> "$R/br/bridge.log" &
BRPID=$!
for _ in $(seq 50); do [ -s "$R/br/ready" ] && break; sleep 0.1; done
[ -s "$R/br/ready" ] || { cat "$R/br/bridge.log"; fail "the bridge does not start"; }
BPORT=$(cat "$R/br/ready")
printf 'key=sk-ant-gate-0000-dummy-key-for-tests-WXYZ\r\nhost=127.0.0.1\r\nport=9\r\ntls=0\r\n' > "$R/VERANDA/.SYSTEM/CLAUDE.CFG"
cp "$A/test/Claude.cvt" "$R/AUTOSTART.cvt"
cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$R/"
cp "$A/SHELL.cvt" "$R/VERANDA/"
echo "bridge $BPORT $CPORT" > "$R/CLAUDE.TST"
t0=$(date +%s)
(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 600 "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$R/modem.log" > console.txt 2>&1) || true
echo "      (bridge: $(( $(date +%s) - t0 )) s)"
kill "$BRPID" 2>/dev/null || true
wait "$BRPID" 2>/dev/null || true
tr '\r' '\n' < "$R/console.txt" > "$R/log.txt"
for s in SETBRIDGE BRIDGE FAIL; do
	[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png"
done
rm -f "$R"/*.RAW "$R/dump.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; cat "$R/br/bridge.log"; fail "bridge: the test failed"; }
$PY tests/check_claude_bridge.py "$R" "$BPORT" "$CPORT" || { cat "$R/br/bridge.log"; fail "bridge"; }

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE claude_bridge: PASS"
