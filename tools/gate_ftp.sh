#!/bin/bash
# Gate ftp (DECISIONS V100): Veranda FTP (apps/ftp) under ROM R49, through
# vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem: the user's
# UART emulator's "modem" branch), against a small FTP server on localhost
# (tests/ftp_server.py: Python's socket module, no pyftpdlib). The test
# build (tests/ftp_play.c) plays the mouse and the keys through
# mouseSource (tests/term_play.s): menus, the Sites page, clicks and double
# clicks in the panes, the boxes.
#
#   tools/gate_ftp.sh           (OUT=... where the results go, default build/gate/ftp)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" (default
# ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM
# (~/Downloads/Release.R49.ROM.Image/rom.bin).
#
# 1. the kernel and the SDK; Veranda FTP built against it (FTP.cvt: an
#    application, class VerandaFTP, banked overlays, its tile); the sizes
# 2. main: the card (a host folder) laid out as Veranda's (/VERANDA,
#    /VERANDA/.SYSTEM with FTP.SITES: three servers, /DOCUMENTS with
#    upload.bin); the server's /pub: big.bin (40,960 bytes), dosdir (its
#    listing in DOS's form), ghost.bin (listed, its RETR refused: 550), a
#    long name, an old file (a year in its date). The session:
#      Connection > Sites..., the first server (anonymous, /pub), Connect:
#        USER, PASS, TYPE I, FEAT, CWD /pub, PWD, PASV, LIST; the pane's
#        names, sizes and dates equal the server's
#      a double click into dosdir (DOS lines parsed), ".." back
#      big.bin, File > Download; at 20,000 bytes Alt+Tab (switchReq): put
#        aside (the file closed), the test desktop 3 s, back (the file
#        opened again at its place), on to the end: equal byte for byte
#      upload.bin, File > Upload: equal on the server
#      File > New folder "newdir"; Rename upload.bin to renamed.bin;
#        Delete renamed.bin (DELE), newdir (RMD)
#      ghost.bin, File > Download: the box "The download failed: 550 ...";
#        no ghost.bin left on the card
#      Connection > Disconnect (QUIT)
#      the second server (sand, a wrong password): the box "The login
#        failed: 530 Login incorrect."
#      the third (its FEAT names MLSD): the listing through MLSD
#    the main loop never waited (its longest gap); nothing lost in the
#    UART, no bad CRC
# 3. (V211) timing: the time of a download and an upload of 300 KB
#    (t300.bin from the server, t300up.bin from the card, 307,200 bytes
#    each) through the emulated modem at 57600: the emulated X16's
#    seconds from File > Download (Upload) to its end and of its data,
#    vrnet's XONs, packets and sends (FTP TIME ...); both files equal.
#    On an SD card image (tools/vcard.py: CMDR-DOS writes and reads the
#    card as on the X16; a host folder costs no cycles). The emulated
#    modem answers at once: what it measures is this side, the card and
#    the line. ONLY=timing: this session only; ONLY=main: that one only.
#    (V213) MODEM=real: through tests/zimreal.py (Zimodem as its firmware
#    behaves, a Wi-Fi's latency; tools/zimreal.inc.sh), in real time.
# Screenshots: $OUT/sites.png, $OUT/connected.png, $OUT/transfer.png,
# $OUT/end.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/ftp}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

. tools/zimreal.inc.sh
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
TOP=$(pwd)

# 1. the application, the test build, the test desktop
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/ftp all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/ftp does not build"; }
make -s -C apps/ftp test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/ftp's test build"; }
$PY - "$A/rel" <<'EOF' || fail "the sizes"
import re, sys
d = sys.argv[1]
m = open(d + '/ftp.map').read()
seg = {g[0]: int(g[2], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M) for g in [(g[0], g[1], g[3])]}
end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
def mod(name):
    i = m.find(name + ':')
    c = re.search(r'CODE\s+Offs=\w+\s+Size=(\w+)', m[i:i + 400])
    return int(c.group(1), 16) if c else 0
net = mod('veranda.lib(vrnet.o)') + mod('veranda.lib(vrser.o)') + mod('veranda.lib(vrserc.o)') + mod('veranda.lib(vrsync.o)')
o1 = seg.get('OVERLAY1', 0)
o2 = seg.get('OVERLAY2', 0) + seg.get('OVL2BSS', 0)
o3 = sum(seg.get(k, 0) for k in ('OVERLAY3', 'OVL3RO', 'OVL3DATA', 'OVL3BSS'))
cvt = len(open(d + '/FTP.cvt', 'rb').read())
print('ok    the sizes: FTP.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free), '
      'of it vrnet with the serial driver %d bytes of code; overlay 1 (the interface) %d bytes, overlay 2 '
      '(the Sites page, the window chrome, the sites table) %d bytes, overlay 3 (the panes drawn, the scroll bars: V149) '
      '%d bytes' % (cvt, end, end - 0x801, 0x8400 - end - 1, net, o1, o2, o3))
if end >= 0x8400 or o1 > 8191 or o2 > 8191 or o3 > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda FTP builds against the installed SDK (and its test build)"

# the server: its folder; sets SPORT
server() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/ftp_server.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the FTP server does not start"
	read -r SPORT < "$1/ready"
}
server_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session in folder $1: FTP.TST $2, at most $3 seconds
run() {
	local dir=$1 tst=$2 secs=$3
	shift 3
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/test/FTP.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	echo "$tst" > "$dir/FTP.TST"
	zim_uart "$dir" "modem:baud=57600,log=$dir/modem.log"
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$((secs * ZMUL))" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		$WARP -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "$UART" \
		> console.txt 2>&1) || true
	zim_end
	tr '\r' '\n' < "$dir/console.txt" > "$dir/log.txt"
}

if [ "$ONLY" != timing ]; then
echo "== main: log in, list, folders, a download with Alt+Tab, an upload, a folder made, a rename, deletes, the errors"
R=$OUT/main
S=$R/srv
mkdir -p "$S/root/pub/dosdir/sub" "$R/DOCUMENTS"
$PY - "$S/root/pub" "$R/DOCUMENTS" <<'EOF'
import os, random, sys
pub, docs = sys.argv[1], sys.argv[2]
r = random.Random(100)
open(os.path.join(pub, 'big.bin'), 'wb').write(bytes(r.randrange(256) for _ in range(40960)))
open(os.path.join(pub, 'ghost.bin'), 'wb').write(b'listed, but RETR says 550\n')
open(os.path.join(pub, 'A long file name on the server.txt'), 'wb').write(b'x' * 1234)
open(os.path.join(pub, 'oldfile.txt'), 'wb').write(b'old\n')
open(os.path.join(pub, 'Zażółć gęślą jaźń.txt'), 'wb').write(b'zolw\n')     # (V143: a name in UTF-8)
open(os.path.join(pub, 'dosdir', 'readme.txt'), 'wb').write(b'a DOS listing\r\n' * 7)
open(os.path.join(docs, 'upload.bin'), 'wb').write(bytes(r.randrange(256) for _ in range(12345)))
open(os.path.join(docs, 'A long local name for a note.txt'), 'wb').write(b'note\n')
EOF
server "$S"
printf 'Gate server,127.0.0.1,%s,,,/pub\r\nWrong password,127.0.0.1,%s,sand,wrong,\r\nMLSD server,127.0.0.1,%s,mlsd,x,/pub\r\n' \
	"$SPORT" "$SPORT" "$SPORT" > "$R/sites.txt"
mkdir -p "$R/VERANDA/.SYSTEM"
cp "$R/sites.txt" "$R/VERANDA/.SYSTEM/FTP.SITES"
run "$R" "main $(date +'%y %m %d %H %M')" 1500
server_end
[ -f "$R/dump.bin" ] || { tail -30 "$R/log.txt"; fail "main: the session did not end"; }
grep -q "^FTP END$" "$R/log.txt" || { grep "^FTP" "$R/log.txt" | tail -30; fail "main: the test failed"; }
for s in SITES CONN XFER END; do
	$PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png" 2>/dev/null || true
done
[ -f "$OUT/conn.png" ] && mv "$OUT/conn.png" "$OUT/connected.png"
# (V143) the server's UTF-8 name shown in Veranda's set, the ROM's ISO-8859-16 glyphs
$PY tests/check_l10_text.py --raw "$R/CONN.RAW" "$ROM" --cp437 "Zażółć gęślą" || fail "the UTF-8 name on the screen"
[ -f "$OUT/xfer.png" ] && mv "$OUT/xfer.png" "$OUT/transfer.png"
$PY tests/check_ftp.py "$R" || fail "main"
fi

if [ "$ONLY" != main ]; then
echo "== (V211) timing: a download and an upload of 300 KB through the emulated modem at 57600"
R=$OUT/timing
S=$R/srv
mkdir -p "$S/root/pub" "$R/DOCUMENTS" "$R/VERANDA/.SYSTEM"
$PY - "$S/root/pub" "$R/DOCUMENTS" <<'EOF'
import os, random, sys
r = random.Random(211)
open(os.path.join(sys.argv[1], 't300.bin'), 'wb').write(r.randbytes(307200))
open(os.path.join(sys.argv[2], 't300up.bin'), 'wb').write(r.randbytes(307200))
EOF
server "$S"
printf 'Gate server,127.0.0.1,%s,,,/pub\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/FTP.SITES"
cp "$A/test/FTP.cvt" "$R/AUTOSTART.cvt"
cp "$A/SHELL.cvt" build/VERANDA.SYS "$R/"
cp "$A/SHELL.cvt" "$R/VERANDA/"
echo "timing $(date +'%y %m %d %H %M')" > "$R/FTP.TST"
mkdir -p "$R.sd"
$PY tools/vcard.py make --mb 64 "$R.sd/sd.img" "$R" >/dev/null || fail "vcard make (timing)"
cp build/VERANDA.PRG "$R.sd/"
zim_uart "$R" "modem:baud=57600,log=$R/modem.log"
(cd "$R.sd" && SDL_VIDEODRIVER=dummy timeout -s INT "$((1500 * ZMUL))" "$EMU_NET" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG -run \
	$WARP -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "$UART" \
	> console.txt 2>&1) || true
zim_end
tr '\r' '\n' < "$R.sd/console.txt" > "$R/log.txt"
server_end
$PY tools/vcard.py get "$R.sd/sd.img" DOCUMENTS/t300.bin "$R/got.bin" >/dev/null 2>&1 || true
rm -f "$R.sd/sd.img"
grep -q "^FTP END$" "$R/log.txt" || { grep "^FTP" "$R/log.txt" | tail -30; fail "timing: the session did not end"; }
$PY - "$R" <<'EOF' || fail "timing"
import os, re, sys
R = sys.argv[1]
log = open(os.path.join(R, 'log.txt'), encoding='latin-1').read()
def v(k):
    m = re.findall(r'^FTP %s (\d+)$' % k, log, re.M)
    if not m:
        sys.exit('FAIL  timing: no "FTP %s"' % k)
    return int(m[-1])
if not os.path.exists(os.path.join(R, 'got.bin')) or open(os.path.join(R, 'got.bin'), 'rb').read() != open(os.path.join(R, 'srv', 'root', 'pub', 't300.bin'), 'rb').read():
    sys.exit('FAIL  timing: t300.bin not equal')
if open(os.path.join(R, 'srv', 'stored', 't300up.bin'), 'rb').read() != open(os.path.join(R, 'DOCUMENTS', 't300up.bin'), 'rb').read():
    sys.exit('FAIL  timing: t300up.bin not equal on the server')
for k, w in (('DOWN', 'download'), ('UP', 'upload')):
    t, d, n = v('TIME ' + k), v('TDATA ' + k), v('TBYTES ' + k)
    pk, se = v('TPACKETS ' + k), v('TSENDS ' + k)
    print('ok    the %s: %d bytes in %.1f s of the emulated X16 (%.2f KB/s), its data %.1f s (%.2f KB/s); '
          '%d XONs, %d packets (%.1f ms a packet), %d empty, %d sends (%.1f ms a send), %d XONs again'
          % (w, n, t / 60, n / 1024 / (t / 60), d / 60, n / 1024 / (d / 60), v('TPULLS ' + k), pk,
             d / 60 * 1000 / max(1, pk) if k == 'DOWN' else 0, v('TEMPTIES ' + k), se,
             d / 60 * 1000 / max(1, se) if k == 'UP' else 0, v('TRETRIES ' + k)))
    print('      %d passes of the main loop (%.1f ms a pass); %.1f s in the status line\'s redraws, %.1f s in the card\'s calls'
          % (v('TPASSES ' + k), d / 60 * 1000 / max(1, v('TPASSES ' + k)), v('TUI ' + k) / 60, v('TFILE ' + k) / 60))
lost, oe, bad = v('LOST'), v('OE'), v('BADCRC')
print('      the main loop\'s longest gap %d frames; UART lost %d, overruns %d, bad CRC %d' % (v('MAXGAP'), lost, oe, bad))
if lost or oe or bad:
    sys.exit('FAIL  timing: bytes lost')
EOF

fi
echo "screenshots: $OUT/sites.png $OUT/connected.png $OUT/transfer.png $OUT/end.png"
echo "GATE ftp: PASS"
