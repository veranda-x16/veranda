#!/bin/bash
# Gate ask (DECISIONS V116): Veranda Ask (apps/ask) under ROM R49, through
# vrnet and the emulator's Zimodem back-end, against a fake of OpenAI's
# sign-in and API on localhost (tests/fake_openai.py; the real servers are
# never called) and the real sign-in helper (tools/chatgpt_signin.py, its
# browser a script: tests/fake_browser.py). The test build
# (tests/ask_play.c) plays the mouse and the keys (tests/term_play.s).
#
#   tools/gate_ask.sh     (OUT=... where the results go, default build/gate/ask)
#
# EMU_NET, R49: as gate claude (an emulator whose modem knows ATCS makes it
# plain TCP and logs SECURE; an older one gets the test's plain ATC).
#
# 1. the helper on its own (tests/test_chatgpt_signin.py under python3 -I)
# 2. the kernel, the SDK, Veranda Ask (and its test build); the sizes
# 3. main: ASK.CFG with the fake's hosts, no credentials: the Settings page;
#    the helper's address and a wrong code (its box); the right code: the
#    sign-in through the helper (OAuth with the fake, the id_token checked),
#    the credential set to the X16, ASK.CFG written; the plan's notice, Got
#    it; two turns streamed (the Responses API's SSE); the access token
#    refused (401): renewed (the refresh token rotated, ASK.CFG written
#    before the turn is sent again), the turn again; the usage limit, not
#    eligible (their boxes); Esc mid-reply; Alt+Tab mid-reply; a failed
#    reply; an interrupted one; the sign-in ended (a dead refresh token):
#    sign in again; Settings, OpenAI API key: a turn with the key
# 4. renew (V129): signed in from the start (the fake's seed pair), the
#    X16's clock set to the PC's (UTC); a renewal's reply in each style a
#    real server may use (tests/fake_openai.py's STYLES: Content-Length and
#    close, keep-alive, chunks of 1-3 bytes, a 4,200-character access token
#    with a 6 KB id_token, odd spacing and unknown keys, escapes, not
#    rotated): each kept, the turn sent again; an access token longer than
#    the X16 keeps: its precise box, its new refresh token kept, the next
#    turn renewed first; a token due by its exp: renewed before the turn;
#    the clock at 1 January 2000: not trusted (the 401 renews), its hint in
#    the status bar; ASK.LOG with no token and no cookie in it. Not warped
#    (the X16's clock must keep the PC's time)
#    (V131: then a fresh token refused while the clock is trusted: not
#    renewed, kept, its box)
# 5. tokens (V131): an access token of 2,048, 4,096 and 5,119 characters in
#    ASK.CFG: the fake receives it byte for byte (SHA-256), the request is
#    byte for byte what chatgpt_signin.py --check builds, ASK.LOG gives its
#    length and sum
# 6. request (V199): another program's AI help on its text (apps/ask/rq.c,
#    docs/AIREQ.md; tests/check_aireq.py prepares and checks each run):
#    every action (one by keys, one with Try again, one with the ChatGPT
#    plan's sign-in, the others an API key), Cancel after the answer, Esc
#    before anything is sent, not signed in, a text over 8,192 bytes, an
#    unknown action; the fake's requests (the system prompt, the one
#    message), AI.OUT and AI.RES, AI.REQ and AI.IN deleted, no chat saved,
#    ASK.CFG unchanged; then the hand-off: the real desktop starts a
#    stand-in for Veranda Write (tests/ai_standin.c) from a START.REQ, it
#    asks, goes aside, the desktop starts Veranda Ask, Send, Use this, the
#    stand-in back with the answer; (V201) once each with Ask set up by an
#    API key, the ChatGPT plan, an access token expired an hour before
#    (the clock not set: a 401, renewed, sent again; the clock set:
#    renewed before the turn; the new tokens in ASK.CFG), and in Fast mode
#    with the stand-in holding all but 24 RAM banks (vrnet gets none:
#    "error network", not "not-set-up"); RQ_HANDOFFS picks them; the
#    nomodem run: the modem looked for again at the first Send, then
#    "error network"
# 7. nomodem: an API key, no modem on the port: the box
# Screenshots: $OUT/first.png, settings.png, notice.png, midstream.png,
# chat.png, limit.png, signedout.png, apikey.png, final.png, renew_clock.png,
# renew_final.png; (V199) rq_<run>_rq.png (the request), _stream.png,
# _preview.png (the answer), rq_handoff_preview.png; (V201)
# rq_handoff_<kind>_rq.png, _preview.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/ask}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
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

echo "== the sign-in helper on its own (python3 -I, the fake OpenAI, the fake browser)"
$PY tests/test_chatgpt_signin.py "$OUT/host" > "$OUT/host.txt" 2> "$OUT/host.log" || true
grep -v '^ok' "$OUT/host.txt" || true
grep -q "^test_chatgpt_signin: PASS" "$OUT/host.txt" || { cat "$OUT/host.log"; fail "the helper's own test"; }
ok "the helper's own test: $(grep -c '^ok' "$OUT/host.txt") checks"

$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/ask all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/ask does not build"; }
make -s -C apps/ask test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/ask's test build"; }
mkdir -p "$A/ctest"
make -s -C apps/ask test SDK="$SDK" OUT="$A/ctest" TESTFLAGS=-DCODE_SESSION > "$A/ctest.log" 2>&1 || { cat "$A/ctest.log"; fail "apps/ask's code test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/ask.map').read()
    end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
    o = {}
    for g in re.findall(r'^(OVERLAY|OVL)(\d+)(RO|BSS|DATA)?\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M):
        o[int(g[1])] = o.get(int(g[1]), 0) + int(g[5], 16)
    return end, o
e, o = sizes(sys.argv[1])
te, to = sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/Ask.cvt', 'rb').read())
print('ok    the sizes: Ask.cvt %d bytes; main RAM $0801-$%04X (%d bytes free below the C stack; the test build to '
      '$%04X, %d free); overlays %s (the test build %s; of 8192 each); RAM banks: 6 (the conversation, its rows, '
      'the font), 2 (the credentials), vrnet 2, the overlays 11 (V123: code.c, file.c, conv.c, hist.c; V129: '
      'log.c; V149: the scroll bar and the menus, sbar.c, beside it; V199: rq.c, a request, overlay 11; 21 in all; '
      'the test build'"'"'s player overlay 12, 22)'
      % (cvt, e, 0x8400 - e - 1, te, 0x8400 - te - 1, ', '.join('%d: %d' % kv for kv in sorted(o.items())),
         ', '.join('%d: %d' % kv for kv in sorted(to.items()))))
if e >= 0x8400 or te >= 0x8400 or max(list(o.values()) + list(to.values())) > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Ask builds against the installed SDK (and its test build); Veranda Claude's sources unchanged for Claude"

run() {                 # folder, ASK.TST, seconds, the UART's back-end
	local dir=$1 tst=$2 secs=$3 uart=$4
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/${TB:-test}/Ask.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	# (V145) the switcher's mode (SWMODE 16 Fast, 32 Roomy; none: the machine's, Roomy at 512 KB)
	[ -n "${SWMODE:-}" ] && $PY -c 'import sys; d=bytearray(open("tests/sound_prefs_v65.cvt","rb").read()); d[508+6] = (d[508+6] & ~0x30) | int(sys.argv[2]); open(sys.argv[1],"wb").write(d)' "$dir/VERANDA/.SYSTEM/Veranda Prefs.cvt" "$SWMODE"
	echo "$tst" > "$dir/ASK.TST"
	local t0=$(date +%s)
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		${WARP--warp} -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 $uart > console.txt 2>&1) || true
	tr '\r' '\n' < "$dir/console.txt" > "$dir/log.txt"
	echo "      ($(basename "$dir"): $(( $(date +%s) - t0 )) s)"
}

# (ONLY=main, code (with chats), renew, tokens or request: that session alone)
# (V145) twice: the switcher in Roomy mode (Alt+Tab puts Ask onto the card
# when RAM is short) and in Fast mode (RAM only); ASK_MODES to pick
for SWNAME in ${ASK_MODES-roomy fast}; do
if [ -z "${ONLY:-}" ] || [ "$ONLY" = main ]; then
SWMODE=32
[ "$SWNAME" = fast ] && SWMODE=16
echo "== main ($SWNAME switcher): the sign-in through the PC's helper, the plan's notice, turns, the renewal, the plan's errors, Esc, Alt+Tab, signed out, an API key"
R=$OUT/main-$SWNAME
mkdir -p "$R/srv" "$R/helper"
$PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
SRVPID=$!
for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
read -r SPORT CPORT < "$R/srv/ready"
B=http://127.0.0.1:$SPORT
CBPORT=$($PY -c "import socket; s = socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1])")
CHATGPT_SIGNIN_READY=$R/helper/ready $PY tools/chatgpt_signin.py --bind 127.0.0.1 --port 0 --code 271828 \
	--issuer "$B" --authorize-url "$B/api/accounts/authorize" --token-url "$B/api/accounts/oauth/token" \
	--revoke-url "$B/api/accounts/oauth/revoke" --jwks-url "$B/.well-known/jwks.json" --models-url "$B/v1/models" \
	--callback-port "$CBPORT" --browser "python3 -I -B $PWD/tests/fake_browser.py" --keepalive 2 \
	> "$R/helper/stdout.txt" 2> "$R/helper/helper.log" &
HPID=$!
for _ in $(seq 50); do [ -s "$R/helper/ready" ] && break; sleep 0.1; done
[ -s "$R/helper/ready" ] || { cat "$R/helper/helper.log"; fail "the helper does not start"; }
HPORT=$(cat "$R/helper/ready")
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'api=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG"
run "$R" "main $SPORT $HPORT $PLAIN" 900 "modem:baud=57600,log=$R/modem.log"
kill "$SRVPID" "$HPID" 2>/dev/null || true
wait "$SRVPID" "$HPID" 2>/dev/null || true
GL=0
[ -f "$R/FINAL.RAW" ] && $PY tests/check_glyphs.py "$R/FINAL.RAW" "$ROM" "Polish (V143), typed" \
	"api please Zażółć gęślą jaźń ZAŻÓŁĆ GĘŚLĄ JAŹŃ" || GL=1
[ -f "$R/FINAL.RAW" ] && $PY tests/check_glyphs.py "$R/FINAL.RAW" "$ROM" "Polish (V143), in the reply (raw UTF-8)" \
	"Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ." || GL=1
for s in FIRST SETTINGS NOTICE MIDSTREAM CHAT LIMIT SIGNEDOUT APIKEY FINAL FAIL; do
	[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png"
done
rm -f "$R"/*.RAW "$R/dump.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; cat "$R/helper/helper.log"; fail "main: the test failed"; }
[ "$GL" = 0 ] || fail "the Polish glyphs"
$PY tests/check_ask.py main "$R" "$SPORT" "$PLAIN" || { cat "$R/helper/helper.log"; fail "main"; }
grep -a -o "TASK \(ASIDE\|CARD\) AUTOSTART [0-9A-F]*\|TASK BACK AUTOSTART [0-9A-F]*" "$R/log.txt" | sed 's/^/ok    ('"$SWNAME"') /'
SWMODE=

fi
done
if [ -z "${ONLY:-}" ] || [ "$ONLY" = code ]; then
echo "== code: code blocks (Copy, Save, Save .PRG), Remember, old code shortened, a file attached and saved back, compaction, short answers (an OpenAI API key)"
R=$OUT/code
mkdir -p "$R/srv" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
$PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
SRVPID=$!
for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
read -r SPORT CPORT < "$R/srv/ready"
printf 'server=api\r\nkey=sk-gate-0000-openai-dummy-key-for-tests-ABCD\r\napi=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG"
printf '5 PRINT "{93}"\n10 PRINT "GAME"\n20 X=5\n30 PRINT "SCORE";X+\n40 END\n' > "$R/game.txt"
$PY tools/x16basic.py tok "$R/game.txt" "$R/DOCUMENTS/GAME.PRG" || fail "GAME.PRG"
TB=ctest run "$R" "code $SPORT 9 $PLAIN" 900 "modem:baud=57600,log=$R/modem.log"
kill "$SRVPID" 2>/dev/null || true
wait "$SRVPID" 2>/dev/null || true
for s in CODE ATTACH SHORT COMPACT FINAL FAIL; do
	[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/code_$(echo $s | tr A-Z a-z).png"
done
rm -f "$R"/*.RAW "$R/dump.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; fail "code: the test failed"; }
$PY tests/check_code.py ask "$R" || fail "code"

echo "== chats: saved after each turn; the program started again: the Chats page, refused files, a chat opened and continued, Rename, Delete"
R=$OUT/chats
for k in 1 2; do
	mkdir -p "$R/srv$k" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
	$PY tests/fake_openai.py "$R/srv$k" > "$R/srv$k/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$R/srv$k/ready" ] && break; sleep 0.1; done
	[ -f "$R/srv$k/ready" ] || fail "the fake OpenAI does not start"
	read -r SPORT CPORT < "$R/srv$k/ready"
	printf 'server=api\r\nkey=sk-gate-0000-openai-dummy-key-for-tests-ABCD\r\napi=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG"
	if [ $k = 2 ]; then
		mv "$R/log.txt" "$R/log1.txt"
		cp "$R/DOCUMENTS/Chats/Ask/0001 plain one.chat" "$R/chat1.chat" || fail "chats: no chat file after two turns"
		printf 'VERANDA CHAT 1\r\napp=Ask\r\ntitle=broken\r\n\r\nu 99\r\nshort\r\n' > "$R/DOCUMENTS/Chats/Ask/0005 broken.chat"
		printf 'VERANDA CHAT 3\r\napp=Ask\r\ntitle=future\r\n\r\nend\r\n' > "$R/DOCUMENTS/Chats/Ask/0006 future.chat"
		TB=ctest run "$R" "2 $SPORT 9 $PLAIN" 300 "modem:baud=57600,log=$R/modem2.log"
	else
		TB=ctest run "$R" "h $SPORT 9 $PLAIN" 300 "modem:baud=57600,log=$R/modem1.log"
	fi
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
	grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; fail "chats: run $k failed"; }
done
for s in CHATS OPENED FAIL; do
	[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/chats_$(echo $s | tr A-Z a-z).png"
done
rm -f "$R"/*.RAW "$R/dump.bin"
$PY tests/check_hist.py ask "$R" || fail "chats"

fi
if [ -z "${ONLY:-}" ] || [ "$ONLY" = renew ]; then
echo "== renew: a renewal's reply as real servers send it, kept every time; one too long: said precisely; the clock trusted, and not"
R=$OUT/renew
mkdir -p "$R/srv" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
FAKE_SEED=1 FAKE_TOKSTYLE=clen,keepalive,chunkka,big,escaped,norefresh,toolong,clen,soon,chunked,stale,chunked \
	$PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
SRVPID=$!
for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
read -r SPORT CPORT < "$R/srv/ready"
$PY - "$R/srv/seed.json" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG" <<'EOF' || fail "the seed"
import json, sys
s = json.load(open(sys.argv[1]))
p = sys.argv[2]
sys.stdout.write('\r\n'.join(['server=plan', 'model=gpt-6.2-sol', 'host_id=urn:uuid:12345678-1234-4234-8234-123456789abc',
    'client_id=' + s['client_id'], 'login=gate@example.com', 'expires=3600', 'm=gpt-6.2-sol GPT-6.2 Sol', 'notice=1',
    'api=127.0.0.1:' + p, 'auth=127.0.0.1:' + p, 'access=' + s['access'], 'refresh=' + s['refresh'], '']))
EOF
WARP= run "$R" "r $SPORT 9 $PLAIN utc=$(date -u +%y%m%d%H%M%S)" 600 "modem:baud=57600,log=$R/modem.log"
kill "$SRVPID" 2>/dev/null || true
wait "$SRVPID" 2>/dev/null || true
for s in CLOCK FINAL FAIL; do
	[ -f "$R/$s.RAW" ] && $PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/renew_$(echo $s | tr A-Z a-z).png"
done
rm -f "$R"/*.RAW "$R/dump.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -40; fail "renew: the test failed"; }
$PY tests/check_ask.py renew "$R" "$SPORT" "$PLAIN" || fail "renew"

fi
if [ -z "${ONLY:-}" ] || [ "$ONLY" = tokens ]; then
echo "== tokens (V131): an access token of 2,048, 4,096 and 5,119 characters in ASK.CFG, as the fake receives it"
for n in 2048 4096 5119; do
	R=$OUT/tokens$n
	mkdir -p "$R/srv" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
	FAKE_SEED=1 FAKE_SEEDSIZE=$n $PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
	[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
	read -r SPORT CPORT < "$R/srv/ready"
	$PY - "$R/srv/seed.json" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG" <<'EOF' || fail "the seed"
import json, sys
s = json.load(open(sys.argv[1]))
p = sys.argv[2]
sys.stdout.write('\r\n'.join(['server=plan', 'model=gpt-6.2-sol', 'host_id=urn:uuid:12345678-1234-4234-8234-123456789abc',
    'client_id=' + s['client_id'], 'expires=3600', 'm=gpt-6.2-sol GPT-6.2 Sol', 'notice=1',
    'api=127.0.0.1:' + p, 'auth=127.0.0.1:' + p, 'access=' + s['access'], 'refresh=' + s['refresh'], '']))
EOF
	run "$R" "t $SPORT 9 $PLAIN" 300 "modem:baud=57600,log=$R/modem.log"
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
	[ -f "$R/FAIL.RAW" ] && $PY tests/ftp_shot.py "$R/FAIL.RAW" "$OUT/tokens${n}_fail.png"
	rm -f "$R"/*.RAW "$R/dump.bin"
	grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; fail "tokens $n: the test failed"; }
	$PY tests/check_ask.py tokens "$R" "$SPORT" "$PLAIN" || fail "tokens $n"
done

fi
if [ -z "${ONLY:-}" ] || [ "$ONLY" = request ]; then
echo "== request (V199): another program's AI help on its text (AI.REQ, AI.IN; docs/AIREQ.md): each action, Try again, Cancel, Esc, not set up, too long, a bad request; the hand-off from a stand-in for Veranda Write"
for s in ${RQ_RUNS:-$($PY tests/check_aireq.py runs)}; do
	R=$OUT/rq/$s
	mkdir -p "$R/srv" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
	MODE=$($PY tests/check_aireq.py prep "$s" "$R") || fail "request $s: prep"
	SEED=
	[ "$s" = trans_pl ] && SEED=1           # (the ChatGPT plan, signed in: the fake's seed pair)
	FAKE_SEED=$SEED $PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
	[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
	read -r SPORT CPORT < "$R/srv/ready"
	if [ "$s" = notsetup ]; then
		printf 'server=plan\r\napi=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG"
	elif [ -n "$SEED" ]; then
		$PY - "$R/srv/seed.json" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG" <<'EOF2' || fail "the seed"
import json, sys
s = json.load(open(sys.argv[1]))
p = sys.argv[2]
sys.stdout.write('\r\n'.join(['server=plan', 'model=gpt-6.2-sol', 'host_id=urn:uuid:12345678-1234-4234-8234-123456789abc',
    'client_id=' + s['client_id'], 'expires=3600', 'm=gpt-6.2-sol GPT-6.2 Sol', 'notice=1',
    'api=127.0.0.1:' + p, 'auth=127.0.0.1:' + p, 'access=' + s['access'], 'refresh=' + s['refresh'], '']))
EOF2
	else
		printf 'server=api\r\nkey=sk-gate-0000-openai-dummy-key-for-tests-ABCD\r\nanswers=short\r\napi=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/ASK.CFG"
	fi
	cp "$R/VERANDA/.SYSTEM/ASK.CFG" "$R/ASK.CFG.before"
	UART="modem:baud=57600,log=$R/modem.log"
	[ "$s" = nomodem ] && UART="file:,$R/out.bin"      # (no modem on the port)
	run "$R" "q $SPORT 9 $PLAIN m=$MODE" 300 "$UART"
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
	for f in RQ STREAM FIRST PREVIEW FAIL; do
		[ -f "$R/$f.RAW" ] && $PY tests/ftp_shot.py "$R/$f.RAW" "$OUT/rq_${s}_$(echo $f | tr A-Z a-z).png"
	done
	rm -f "$R"/*.RAW "$R/dump.bin"
	grep -q "TEST STUCK\|TEST FAILED" "$R/log.txt" && { grep -a "^CL" "$R/log.txt" | tail -30; fail "request $s: the test stopped"; }
	$PY tests/check_aireq.py check "$s" "$R" || { grep -a "^CL\|^TERMDESK" "$R/log.txt" | tail -30; fail "request $s"; }
	cmp -s "$R/ASK.CFG.before" "$R/VERANDA/.SYSTEM/ASK.CFG" || fail "request $s: ASK.CFG changed"
done
ok "request: ASK.CFG as it was after every run (the user's settings, short answers on: not applied to a request)"

echo "== request handoff: the real desktop, a stand-in for Veranda Write (tests/ai_standin.c), Veranda Ask's test build in /VERANDA/APPS; (V201) set up with an API key, the ChatGPT plan, an expired access token (renewed: after a 401, and before the turn by the clock), no RAM banks for vrnet"
HS=$OUT/rq/shell
mkdir -p "$OUT/rq"
cp -r shell "$HS"
rm -f "$HS"/*.cvt "$HS"/*.bin "$HS"/*.map "$HS"/*.o
make -s -C "$HS" SDK="$SDK" > "$OUT/rq/shell.log" 2>&1 || { tail "$OUT/rq/shell.log"; fail "handoff: the shell does not build"; }
for K in ${RQ_HANDOFFS:-$($PY tests/check_aireq.py handoffs)}; do
R=$OUT/rq/handoff-$K
H=$R/card
mkdir -p "$R/srv" "$H/VERANDA/APPS" "$H/VERANDA/.SYSTEM" "$H/DOCUMENTS"
printf 'name = Veranda Write\nclass = AiStandIn\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$R/standin.hdr"
HOGF=
[ "$K" = mem ] && HOGF=-DHOG=24         # (V201: the stand-in holds all but 24 banks, as a big Write does)
cl65 -t none --cpu 65C02 -O $HOGF -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$R/standin.bin" tests/ai_standin.c "$SDK/lib/veranda.lib" \
	> "$R/standin.log" 2>&1 || { cat "$R/standin.log"; fail "handoff: the stand-in does not build"; }
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$R/standin.cvt" "$R/standin.hdr" "$R/standin.bin" >/dev/null || fail "vpack the stand-in"
cp "$HS/SHELL.cvt" "$H/VERANDA/SHELL.cvt"
cp "$A/test/Ask.cvt" "$H/VERANDA/APPS/Veranda Ask.cvt"
cp "$R/standin.cvt" "$H/VERANDA/APPS/Veranda Write.cvt"
printf '/VERANDA/APPS/Veranda Write\r\n' > "$H/VERANDA/.SYSTEM/START.REQ"
: > "$H/VERANDA/.SYSTEM/LAYOUT.LOG"
# (V201: mem in Fast mode: the stand-in stays aside in RAM, nothing is put onto the card for Ask)
[ "$K" = mem ] && $PY -c 'import sys; d=bytearray(open("tests/sound_prefs_v65.cvt","rb").read()); d[508+6] = (d[508+6] & ~0x30) | 16; open(sys.argv[1],"wb").write(d)' "$H/VERANDA/.SYSTEM/Veranda Prefs.cvt"
SEED=
case $K in plan) SEED=1 ;; renew*) SEED=expired ;; esac
FAKE_SEED=$SEED $PY tests/fake_openai.py "$R/srv" > "$R/srv/server.log" 2>&1 &
SRVPID=$!
for _ in $(seq 50); do [ -f "$R/srv/ready" ] && break; sleep 0.1; done
[ -f "$R/srv/ready" ] || fail "the fake OpenAI does not start"
read -r SPORT CPORT < "$R/srv/ready"
if [ -n "$SEED" ]; then
	$PY - "$R/srv/seed.json" "$SPORT" > "$H/VERANDA/.SYSTEM/ASK.CFG" <<'EOF2' || fail "the seed"
import json, sys
s = json.load(open(sys.argv[1]))
p = sys.argv[2]
sys.stdout.write('\r\n'.join(['server=plan', 'model=gpt-6.2-sol', 'host_id=urn:uuid:12345678-1234-4234-8234-123456789abc',
    'client_id=' + s['client_id'], 'login=gate@example.com', 'expires=3600', 'm=gpt-6.2-sol GPT-6.2 Sol', 'notice=1',
    'api=127.0.0.1:' + p, 'auth=127.0.0.1:' + p, 'access=' + s['access'], 'refresh=' + s['refresh'], '']))
EOF2
else
	printf 'server=api\r\nkey=sk-gate-0000-openai-dummy-key-for-tests-ABCD\r\napi=127.0.0.1:%s\r\nauth=127.0.0.1:%s\r\n' "$SPORT" "$SPORT" > "$H/VERANDA/.SYSTEM/ASK.CFG"
fi
UTC=
[ "$K" = renewclk ] && UTC="utc=$(date -u +%y%m%d%H%M%S)"   # (the clock to trust: the token due by its exp)
echo "q $SPORT 9 $PLAIN m=s $UTC" > "$H/ASK.TST"
cp build/VERANDA.PRG build/VERANDA.SYS "$H/"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$R/modem.log" \
	> "$R/console.txt" 2>&1) || true
tr '\r' '\n' < "$R/console.txt" > "$R/log.txt"
kill "$SRVPID" 2>/dev/null || true
wait "$SRVPID" 2>/dev/null || true
[ -f "$H/PREVIEW.RAW" ] && $PY tests/ftp_shot.py "$H/PREVIEW.RAW" "$OUT/rq_handoff_${K}_preview.png"
[ -f "$H/RQ.RAW" ] && $PY tests/ftp_shot.py "$H/RQ.RAW" "$OUT/rq_handoff_${K}_rq.png"
[ "$K" = api ] && [ -f "$OUT/rq_handoff_api_preview.png" ] && cp "$OUT/rq_handoff_api_preview.png" "$OUT/rq_handoff_preview.png"
rm -f "$H"/*.RAW "$H/dump.bin"
cp -r "$H/VERANDA" "$R/VERANDA"
cp "$R/srv/requests.jsonl" "$R/srv/requests.jsonl" 2>/dev/null || true
$PY tests/check_aireq.py handoff "$R" "$K" || { grep -a "^CL\|^STANDIN\|^SHELL" "$R/log.txt" | tail -30; fail "request handoff $K"; }
done

fi
echo "== nomodem: no modem on the port"
R=$OUT/nomodem
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'server=api\r\nkey=sk-gate-0000-openai-dummy-key-for-tests-ABCD\r\napi=127.0.0.1:9\r\n' > "$R/VERANDA/.SYSTEM/ASK.CFG"
run "$R" "nomodem 9 9" 120 "file:,$R/out.bin"
rm -f "$R/dump.bin"
grep -q "^CL END$" "$R/log.txt" || { grep "^CL" "$R/log.txt" | tail -30; fail "nomodem: the test failed"; }
$PY tests/check_ask.py nomodem "$R" 0 || fail "nomodem"

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE ask: PASS"
