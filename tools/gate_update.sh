#!/bin/bash
# Gate update (DECISIONS V130): Veranda Update (apps/update) under ROM R49,
# through vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem),
# against GitHub played on localhost (tests/update_fake.py: a 302 from the
# GitHub stand-in, 127.0.0.1, to another host, localhost, with a signed
# address of about 950 bytes; bodies with Content-Length and chunked) and
# the real PC source (tools/update_server.py on localhost). No real
# GitHub, no network. The program connects with ATCS (the modem's TLS):
# the emulator's modem makes that a plain TCP connection. The test build
# (tests/update_play.c) runs the steps of UPDATE.TST; every session's card
# is the same folder, so each starts where the one before left it.
#
#   tools/gate_update.sh        (OUT=... where the results go, default build/gate/update)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" whose modem knows ATCS
# (default ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM.
#
# 1. the kernel and the SDK; Veranda Update built against it (Update.cvt:
#    an application, class VerandaUpd, banked overlays, its tile) and its
#    test build; the sizes
# 2. host: (V198) mkdist's copy_dict: only SPELL.OVL of Write's DICT;
#    tests/test_mkrelease.py (the allowlist: no geoWrite, TopDesk or
#    geoChess file can enter a release; the manifest; update_server.py's
#    answers and its LAN-only rule); the fixtures (tests/check_update.py:
#    three builds of a made-up Veranda, A, B1, B2; releases A (its own
#    tag), B1 (tagged v1.0.1, as release.yml tags) and At (A on the Test
#    channel, tagged "test") by tools/mkrelease.py; the card at A with the
#    user's files). The stand-in serves each as GitHub would (V140):
#    latest/download 302 to the tag's download, then 302 to the asset
#    host; only the list's tag has assets; a pre-release is never latest
# 3. the sessions, on one card:
#      uptodate  release A: Check: "Up to date" (the list through both 302s)
#      chan      release At, the Test channel (UPDATE.CFG channel=test): Check asks
#                releases/download/test/UPDATE.LST, never .../latest/
#      crc       release B1, Paint.cvt's asset with a byte changed: Update
#                refused, the card unchanged
#      missing   release B1 without Veranda Gemini's asset (404): refused
#      drop      release B1, Gemini's connection closed half way: the card
#                unchanged, what was verified kept in .SYSTEM/UPD
#      resume    release B1: Check shows it kept; Update fetches the rest
#                (Alt+Tab half way through a file: fetched again), the
#                card at B1, the old files in .SYSTEM/OLD/<A>; screenshots
#                check.png (the list) and progress.png
#      undo      Undo last update: the card at A byte for byte
#      lan       the PC source, package B2 (system files, new files, a
#                doc-sample): the system files swapped last, Restart to finish
#      undo2     Undo: at A again, Restart to finish
#    (V198) Veranda Write's dictionaries (their own release, dict-1 of
#    veranda-x16/veranda-write, served beside release A; the card has an
#    older PL.DIC, as a package before V198 put there):
#      dcrc      UPDATE.REQ ("dict", "back Veranda Write") read and deleted
#                at the start, the dictionaries' list checked at once;
#                EN.DIC's asset with a byte changed: refused, the card
#                unchanged
#      dspace    Dictionaries for Write with 100 KB free (the test's
#                CalcBlksFree): refused before anything is fetched
#      dict      English chosen, Polish not: EN.DIC and EN.DIC.txt in
#                /VERANDA/DICT, the older PL.DIC as it was, Veranda's
#                UPDATE.LST unchanged; screenshots dict.png, dictdone.png
#      dundo     Undo: the card as it was
#      handoff   on a copy of the card with the real desktop, which
#                starts a stand-in (tests/dict_standin.c) as
#                /VERANDA/APPS/Veranda Write from a START.REQ; it writes
#                START.REQ and UPDATE.REQ as Write does and puts itself
#                aside; the shell starts Veranda Update from START.REQ;
#                English fetched; Quit brings the stand-in back
#    after each: the user's files (/DOCUMENTS, .SYSTEM's settings, an
#    application of the user's own, README.txt) checksummed against the start
# Screenshots: $OUT/check.png, progress.png, done.png, lan.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/update}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU_NET" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU_NET has no -uart modem back-end (the emulator's modem branch)"
grep -q -a "plain TCP here: no TLS" "$EMU_NET" || fail "$EMU_NET's modem has no ATCS (the modem branch from 1db040b on)"
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# 1. the application, its test build, the test desktop
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/update all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/update does not build"; }
make -s -C apps/update test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/update's test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/update.map').read()
    seg = {g[0]: int(g[3], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M)}
    end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
    o = [sum(seg.get(s % n, 0) for s in ('OVERLAY%d', 'OVL%dRO', 'OVL%dDATA', 'OVL%dBSS')) for n in (1, 2, 3)]
    return end, o
end, o = sizes(sys.argv[1])
tend, to = sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/Update.cvt', 'rb').read())
print('ok    the sizes: Update.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free; '
      'the test build to $%04X, %d free); overlay 1 (Check, Update) %d bytes (%d spare), overlay 2 (the list, the '
      'window) %d (%d spare), overlay 3 (the files, the swap, Undo) %d (%d spare); RAM banks: the overlays 3, the '
      'list 2, a text 1, the CRC table 1, vrnet 2 while the modem is on: 9'
      % (cvt, end, end - 0x801, 0x8400 - end - 1, tend, 0x8400 - tend - 1, o[0], 8192 - o[0], o[1], 8192 - o[1], o[2], 8192 - o[2]))
if end >= 0x8400 or tend >= 0x8400 or max(o + to) > 8192:
    sys.exit('FAIL  out of room')
EOF
$PY "$SDK/tools/vpack.py" --list "$A/rel/Update.cvt" > "$A/list.txt" || fail "vpack --list"
grep -q "^class *VerandaUpd *V1.0" "$A/list.txt" && grep -q "^tile *green" "$A/list.txt" || { cat "$A/list.txt"; fail "Update.cvt: its class or its tile"; }
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Update builds against the installed SDK (Update.cvt: class VerandaUpd, its green tile; and its test build)"

# 2. host
echo "== host: the release's allowlist, the manifest, the PC's update server"
mkdir -p "$OUT/host"
$PY tests/test_mkrelease.py "$OUT/host" || fail "tests/test_mkrelease.py"
TMPDIR="$OUT" tests/test_tocard.sh "$OUT/tocard" | grep "^ok\|^FAIL\|^TEST" || fail "tests/test_tocard.sh"
tests/test_publish.sh "$OUT/publish" > "$OUT/publish.log" 2>&1 || { tail -20 "$OUT/publish.log"; fail "tests/test_publish.sh"; }
grep "^ok\|^TEST" "$OUT/publish.log"
# (V198) mkdist's copy_dict (the function itself, from tools/mkdist.sh): of
# a Write build's DICT (as a build before W61 filled it) only SPELL.OVL
# goes into the package
T=$OUT/copydict
mkdir -p "$T/src" "$T/pkg"
for f in SPELL.OVL PL.DIC PL.DIC.txt EN.DIC EN.DIC.txt; do echo "$f" > "$T/src/$f"; done
(V=$T/pkg; eval "$(sed -n '/^copy_dict() {/,/^}/p' tools/mkdist.sh)"; copy_dict "$T/src") || fail "mkdist's copy_dict"
[ "$(ls "$T/pkg/DICT" | tr '\n' ' ')" = "SPELL.OVL " ] || fail "mkdist's copy_dict put $(ls "$T/pkg/DICT" | tr '\n' ' ')in the package"
ok "mkdist: of a Write build's DICT only SPELL.OVL goes into the package; the dictionaries and their licences do not (V198)"
FX=$OUT/fx
$PY tests/check_update.py fixture "$FX" "$A/SHELL.cvt" || fail "the fixtures"
CARD=$OUT/card
cp -r "$FX/card0" "$CARD"

# the GitHub stand-in: $1 its folder, $2 the release, $3 the JSON's rest; sets GPORT
fake() {
	mkdir -p "$1"
	rm -f "$1/ready"
	printf '{"repo": "veranda-x16/veranda", "release": "%s"%s}\n' "$2" "$3" > "$1/fake.json"
	$PY tests/update_fake.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the GitHub stand-in does not start"
	read -r GPORT _ < "$1/ready"
}
lan() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tools/update_server.py "$2" --port 0 --bind 127.0.0.1 --ready "$1/ready" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "update_server.py does not start"
	read -r GPORT < "$1/ready"
}
server_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session: $1 its name, $2 the steps, $3 UPDATE.CFG's text; the card's
# folder is the emulator's host folder
run() {
	local s=$1 steps=$2 R=$OUT/$1
	mkdir -p "$R" "$CARD/VERANDA/.SYSTEM"
	printf '%b' "$3" > "$CARD/VERANDA/.SYSTEM/UPDATE.CFG"
	cp "$A/test/Update.cvt" "$CARD/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$CARD/"
	echo "run $steps" > "$CARD/UPDATE.TST"
	rm -f "$CARD"/*.RAW "$CARD/dump.bin"
	local t0=$(date +%s.%N)
	(cd "$CARD" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$R/modem.log" \
		> "$R/console.txt" 2>&1) || true
	tr '\r' '\n' < "$R/console.txt" > "$R/log.txt"
	echo "      ($s: $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
	for f in "$CARD"/*.RAW; do
		[ -f "$f" ] && mv "$f" "$R/"
	done
	[ -f "$CARD/dump.bin" ] && mv "$CARD/dump.bin" "$R/"
	rm -f "$CARD/AUTOSTART.cvt" "$CARD/UPDATE.TST" "$CARD/VERANDA.PRG" "$CARD/VERANDA.SYS"
	grep -a -q "UP END" "$R/log.txt" || { grep -a "^UP\|^BOX" "$R/log.txt" | tail -30; fail "$s: the session did not end"; }
}
# (no repo=: the default, veranda-x16/veranda, the only one the stand-in
# answers; GHOLD: a card that saved the repository before, sandlbn/veranda-x16,
# which Veranda Update reads as the new one: DECISIONS V139)
GH='source=github\r\ngithub=127.0.0.1:%s\r\n'
GHOLD='source=github\r\nrepo=sandlbn/veranda-x16\r\ngithub=127.0.0.1:%s\r\n'

echo "== the sessions (one card): up to date, a CRC mismatch, a missing file, a dropped connection, resumed, undo, the PC source, undo"
for s in uptodate crc missing drop resume undo; do
	case $s in
	uptodate) fake "$OUT/$s/srv" "$FX/relA" ""; steps="check" ;;
	crc) fake "$OUT/$s/srv" "$FX/relB1" ', "corrupt": ["'$($PY -c "import zlib,sys; print('%08x.bin' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$FX/pkgB1/VERANDA/APPS/Paint.cvt")'"]'; steps="check update" ;;
	missing) fake "$OUT/$s/srv" "$FX/relB1" ', "missing": ["'$($PY -c "import zlib,sys; print('%08x.bin' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$FX/pkgB1/VERANDA/APPS/Veranda Gemini.cvt")'"]'; steps="check update" ;;
	drop) fake "$OUT/$s/srv" "$FX/relB1" ', "drop": ["'$($PY -c "import zlib,sys; print('%08x.bin' % (zlib.crc32(open(sys.argv[1],'rb').read()) & 0xffffffff))" "$FX/pkgB1/VERANDA/APPS/Veranda Gemini.cvt")'"]'; steps="check update" ;;
	resume) fake "$OUT/$s/srv" "$FX/relB1" ""; steps="check snap:CK aside:8 prog:20 update snap:DN" ;;
	undo) fake "$OUT/$s/srv" "$FX/relB1" ""; steps="undo" ;;
	esac
	g=$GH
	case $s in crc | missing) g=$GHOLD ;; esac
	run $s "$steps" "$(printf "$g" "$GPORT")"
	server_end
	$PY tests/check_update.py check $s "$FX" "$CARD" "$OUT/$s/log.txt" "$OUT/$s/srv/requests.log" || { grep -a "^UP\|^BOX" "$OUT/$s/log.txt" | tail -30; fail "$s"; }
done
s=chan
fake "$OUT/$s/srv" "$FX/relAt" ""
run $s "check" "$(printf "$GH" "$GPORT")channel=test\r\n"
server_end
$PY tests/check_update.py check $s "$FX" "$CARD" "$OUT/$s/log.txt" "$OUT/$s/srv/requests.log" || { grep -a "^UP\|^BOX" "$OUT/$s/log.txt" | tail -30; fail "$s"; }
s=lan
lan "$OUT/$s/srv" "$FX/pkgB2"
run $s "check update snap:LAN" "source=pc\r\nrepo=veranda-x16/veranda\r\npc=127.0.0.1:$GPORT\r\n"
server_end
$PY tests/check_update.py check $s "$FX" "$CARD" "$OUT/$s/log.txt" "$OUT/$s/srv/none.log" || { grep -a "^UP\|^BOX" "$OUT/$s/log.txt" | tail -30; fail "$s"; }
grep -q "UPDATE.LST" "$OUT/$s/srv/server.log" || fail "lan: update_server.py logged no request"
s=undo2
run $s "undo" "source=pc\r\nrepo=veranda-x16/veranda\r\npc=127.0.0.1:1\r\n"
$PY tests/check_update.py check $s "$FX" "$CARD" "$OUT/$s/log.txt" "$OUT/$s/none.log" || { grep -a "^UP\|^BOX" "$OUT/$s/log.txt" | tail -30; fail "$s"; }

echo "== (V198) Veranda Write's dictionaries: requested, a CRC mismatch, no room, English chosen, undo, the hand-off"
REQ='dict\r\nback Veranda Write\r\n'
DREPO=', "repos": {"veranda-x16/veranda-write": "'$FX/relD'"}'
for s in dcrc dspace dict dundo; do
	case $s in
	dcrc) printf "$REQ" > "$CARD/VERANDA/.SYSTEM/UPDATE.REQ"; fake "$OUT/$s/srv" "$FX/relA" "$DREPO"', "corrupt": ["EN.DIC"]'; steps="update" ;;
	dspace) fake "$OUT/$s/srv" "$FX/relA" "$DREPO"; steps="dict free:100 update" ;;
	dict) fake "$OUT/$s/srv" "$FX/relA" "$DREPO"; steps="dict snap:DCK nos:2 update snap:DDN" ;;
	dundo) fake "$OUT/$s/srv" "$FX/relA" "$DREPO"; steps="undo" ;;
	esac
	run $s "$steps" "$(printf "$GH" "$GPORT")"
	server_end
	$PY tests/check_update.py check $s "$FX" "$CARD" "$OUT/$s/log.txt" "$OUT/$s/srv/requests.log" || { grep -a "^UP\|^BOX" "$OUT/$s/log.txt" | tail -30; fail "$s"; }
done
# the hand-off: the real shell (from a copy of shell/), the stand-in, on a copy of the card
s=handoff
R=$OUT/$s
mkdir -p "$R"
cp -r shell "$R/shell"
rm -f "$R/shell"/*.cvt "$R/shell"/*.bin "$R/shell"/*.map "$R/shell"/*.o
make -s -C "$R/shell" SDK="$SDK" > "$R/shell.log" 2>&1 || { tail "$R/shell.log"; fail "handoff: the shell does not build"; }
printf 'name = Veranda Write\nclass = DictStandIn\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$R/standin.hdr"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$R/standin.bin" tests/dict_standin.c "$SDK/lib/veranda.lib" \
	> "$R/standin.log" 2>&1 || { cat "$R/standin.log"; fail "handoff: the stand-in does not build"; }
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$R/standin.cvt" "$R/standin.hdr" "$R/standin.bin" >/dev/null || fail "vpack the stand-in"
H=$OUT/card_h
cp -r "$CARD" "$H"
cp "$R/shell/SHELL.cvt" "$H/VERANDA/SHELL.cvt"
cp "$A/test/Update.cvt" "$H/VERANDA/APPS/Veranda Update.cvt"
cp "$R/standin.cvt" "$H/VERANDA/APPS/Veranda Write.cvt"
# (the desktop starts the stand-in from a START.REQ too: a program put
# aside is known by the name it was started by, as Write is by the shell)
printf '/VERANDA/APPS/Veranda Write\r\n' > "$H/VERANDA/.SYSTEM/START.REQ"
: > "$H/VERANDA/.SYSTEM/LAYOUT.LOG"
fake "$R/srv2" "$FX/relA" "$DREPO"
printf '%b' "$(printf "$GH" "$GPORT")" > "$H/VERANDA/.SYSTEM/UPDATE.CFG"
echo "run nos:2 update quit" > "$H/UPDATE.TST"
cp build/VERANDA.PRG build/VERANDA.SYS "$H/"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 180 "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$R/modem.log" \
	> "$R/console.txt" 2>&1) || true
tr '\r' '\n' < "$R/console.txt" > "$R/log.txt"
server_end
# (the card's own files back as they were, for the check: the shell, Update, the stand-in, the test's)
cp "$CARD/VERANDA/SHELL.cvt" "$H/VERANDA/SHELL.cvt"
rm -f "$H/VERANDA/APPS/Veranda Update.cvt" "$H/VERANDA/APPS/Veranda Write.cvt" "$H/UPDATE.TST" "$H/VERANDA.PRG" "$H/VERANDA.SYS" "$H/dump.bin"
for f in $(cd "$H/VERANDA/.SYSTEM" && ls -A); do
	[ -e "$CARD/VERANDA/.SYSTEM/$f" ] || case $f in OLD | UPD | START.REQ | UPDATE.REQ) ;; *) rm -rf "${H:?}/VERANDA/.SYSTEM/$f" ;; esac
done
$PY tests/check_update.py check $s "$FX" "$H" "$R/log.txt" "$R/srv2/requests.log" || { grep -a "^UP\|^BOX\|^STANDIN\|^SHELL" "$R/log.txt" | tail -30; fail "$s"; }
grep -q "SECURE" "$OUT/resume/modem.log" || fail "resume: the modem's log has no ATCS connection"

$PY tests/ftp_shot.py "$OUT/resume/CK.RAW" "$OUT/check.png" || fail "check.png"
$PY tests/ftp_shot.py "$OUT/resume/PROG.RAW" "$OUT/progress.png" || fail "progress.png"
$PY tests/ftp_shot.py "$OUT/resume/DN.RAW" "$OUT/done.png" || fail "done.png"
$PY tests/ftp_shot.py "$OUT/lan/LAN.RAW" "$OUT/lan.png" || fail "lan.png"
$PY tests/ftp_shot.py "$OUT/dict/DCK.RAW" "$OUT/dict.png" || fail "dict.png"
$PY tests/ftp_shot.py "$OUT/dict/DDN.RAW" "$OUT/dictdone.png" || fail "dictdone.png"
rm -f "$OUT"/*/dump.bin
echo "screenshots: $OUT/check.png progress.png done.png lan.png dict.png dictdone.png"
echo "GATE update: PASS"
