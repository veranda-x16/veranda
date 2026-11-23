#!/bin/bash
# Gate gopher (DECISIONS V109): Veranda Gopher (apps/gopher) under ROM R49,
# through vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem: the
# user's UART emulator's "modem" branch), against a small Gopher server on
# localhost (tests/gopher_server.py: Python's socket module). The test
# build (tests/gopher_play.c) plays the mouse and the keys through
# mouseSource (tests/term_play.s), as gate ftp does: the address line, the
# toolbar, items, menus, the boxes.
#
#   tools/gate_gopher.sh        (OUT=... where the results go, default build/gate/gopher)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" (default
# ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM
# (~/Downloads/Release.R49.ROM.Image/rom.bin).
#
# 1. the kernel and the SDK; Veranda Gopher built against it (Gopher.cvt:
#    an application, class VerandaGoph, banked overlays, its tile); the
#    sizes
# 2. main: no GOPHER.MARKS: the bookmarks page with the defaults; the
#    root's address typed (gopher://127.0.0.1:<port>/1); the root menu
#    (info lines, an empty one, CP437; 1, 0, 7, 9, g, h, 3 items, their
#    marks); a submenu, Back (the toolbar), Go > Forward, an item with no
#    host (the page's server); a text (tabs, wrapped at spaces, a long word
#    cut, CR LF and LF, CP437); a long text (80,000 bytes: cut at 48 KB, the
#    note at its end, End); a search (the box, "veranda": the selector, a
#    tab, the query); a web link (the box with its URL); an error line (the
#    box); a port nothing listens on (the box); a menu that stalls, Esc;
#    the binary (40,960 bytes) with Alt+Tab at 20,000 (put aside, the file
#    closed, the test desktop 3 s, back, reopened, on to the end): equal
#    byte for byte; the picture (Down, File > Download): equal; Bookmarks >
#    Add this page; Go > Home; Bitreich removed (Down, Bookmarks > Remove...,
#    Yes): GOPHER.MARKS has the four other defaults and the new one; a long
#    menu (V110: /many, every kind of item, a box of CP437 lines) as the
#    server sent it, and the timings (a page drawn, a page scrolled: a
#    text's and a menu's; at most 17 frames a page); the main loop's
#    longest gap; nothing lost in the UART, no bad CRC
# 3. reread: a GOPHER.MARKS written as on a PC (LF only, a line that is not
#    an item): the page lists its items; the gate's bookmark followed
# 4. nomodem (-uart 9FE0 file:, no modem): the address typed: the box
# Screenshots: $OUT/book.png, menu.png, menus.png (V149: Go open), text.png, long.png, longend.png,
# search.png, xfer.png, marks.png, end.png, many.png, dark.png (the long
# menu in dark mode: Look 2's palette swapped), marks2.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/gopher}
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
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# 1. the application, the test build, the test desktop
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/gopher all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/gopher does not build"; }
make -s -C apps/gopher test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/gopher's test build"; }
$PY - "$A/rel" <<'EOF' || fail "the sizes"
import re, sys
d = sys.argv[1]
m = open(d + '/gopher.map').read()
seg = {g[0]: int(g[3], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M)}
end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
def mod(name):
    i = m.find(name + ':')
    c = re.search(r'CODE\s+Offs=\w+\s+Size=(\w+)', m[i:i + 400])
    return int(c.group(1), 16) if c else 0
net = mod('veranda.lib(vrnet.o)') + mod('veranda.lib(vrser.o)') + mod('veranda.lib(vrserc.o)') + mod('veranda.lib(vrsync.o)')
o1 = seg.get('OVERLAY1', 0)
o2 = seg.get('OVERLAY2', 0) + seg.get('OVL2BSS', 0)
cvt = len(open(d + '/Gopher.cvt', 'rb').read())
print('ok    the sizes: Gopher.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free), '
      'of it vrnet with the serial driver %d bytes of code; overlay 1 (the interface) %d bytes, overlay 2 '
      '(the bookmarks, the window chrome, the scroll bar, the table) %d bytes; RAM banks: 8 (the page 6, its lines 1, the history 1), '
      'vrnet 2, the overlays 2' % (cvt, end, end - 0x801, 0x8400 - end - 1, net, o1, o2))
if end >= 0x8400 or o1 > 8191 or o2 > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Gopher builds against the installed SDK (and its test build)"

# the server: its folder; sets SPORT, CPORT (a port nothing listens on)
server() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/gopher_server.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the Gopher server does not start"
	read -r SPORT CPORT < "$1/ready"
}
server_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session in folder $1: GOPHER.TST $2, at most $3 seconds, the UART's back-end $4
run() {
	local dir=$1 tst=$2 secs=$3 uart=$4
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/test/Gopher.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	echo "$tst" > "$dir/GOPHER.TST"
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

echo "== main: the bookmarks, the address, menus, Back and Forward, texts, a search, the boxes, Stop, downloads with Alt+Tab, bookmarks"
R=$OUT/main
S=$R/srv
server "$S"
run "$R" "main $SPORT" 900 "modem:baud=57600,log=$R/modem.log"
server_end
[ -f "$R/dump.bin" ] || { tail -30 "$R/log.txt"; fail "main: the session did not end"; }
grep -q "^GO END$" "$R/log.txt" || { grep "^GO" "$R/log.txt" | tail -30; fail "main: the test failed"; }
$PY tests/check_glyphs.py "$R/MENU.RAW" "$ROM" "the root menu's Polish line (UTF-8, V143)" \
	"Polish (V143): Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ" || fail "the Polish glyphs"
$PY tests/check_glyphs.py "$R/TEXT.RAW" "$ROM" "the text's UTF-8 and Latin-1 (V143)" \
	"Polish: Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ" "Latin-1: café crème à la française" || fail "the Polish glyphs"
shots BOOK MENU MENUS TEXT LONG LONGEND SEARCH XFER MARKS END MANY DARK
$PY tests/check_gopher.py main "$R" "$SPORT" "$CPORT" || fail "main"

echo "== reread: GOPHER.MARKS read back (written as on a PC: LF only)"
R=$OUT/reread
S=$R/srv
server "$S"
mkdir -p "$R/VERANDA/.SYSTEM"
printf '1Gate root\t\t127.0.0.1\t%s\n# not an item\n0Gate text\t/text.txt\t127.0.0.1\t%s\n' "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/GOPHER.MARKS"
run "$R" "reread $SPORT" 300 "modem:baud=57600,log=$R/modem.log"
server_end
grep -q "^GO END$" "$R/log.txt" || { grep "^GO" "$R/log.txt" | tail -30; fail "reread: the test failed"; }
shots MARKS2
$PY tests/check_gopher.py reread "$R" "$SPORT" "$CPORT" || fail "reread"

echo "== nomodem: no modem on the port"
R=$OUT/nomodem
mkdir -p "$R"

run "$R" "nomodem 70" 300 "file:,$R/out.bin"
grep -q "^GO END$" "$R/log.txt" || { grep "^GO" "$R/log.txt" | tail -30; fail "nomodem: the test failed"; }
$PY tests/check_gopher.py nomodem "$R" 0 0 || fail "nomodem"
rm -f "$OUT"/*/dump.bin

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE gopher: PASS"
