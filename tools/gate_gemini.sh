#!/bin/bash
# Gate gemini (DECISIONS V118): Veranda Gemini (apps/gemini) under ROM R49,
# through vrnet and the emulator's Zimodem back-end (-uart 9FE0 modem: the
# user's UART emulator's "modem" branch), against a small Gemini server on
# localhost (tests/gemini_server.py: Python's socket module; no real server
# is contacted). The program connects with ATCS (the modem's TLS); the
# emulator's modem makes that a plain TCP connection (and logs SECURE), so
# the server speaks Gemini without TLS. The test build
# (tests/gemini_play.c) plays the mouse and the keys through mouseSource
# (tests/term_play.s), as gates gopher and claude do.
#
#   tools/gate_gemini.sh        (OUT=... where the results go, default build/gate/gemini)
#
# EMU_NET: an x16emu with "-uart <addr> ... modem" whose modem knows ATCS
# (default ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM
# (~/Downloads/Release.R49.ROM.Image/rom.bin).
#
# 1. the kernel and the SDK; Veranda Gemini built against it (Gemini.cvt:
#    an application, class VerandaGemi, banked overlays, its tile); the
#    sizes
# 2. main: no GEMINI.MARKS: the bookmarks page with the defaults; the
#    root's address typed (gemini://127.0.0.1:<port>/); the root (every
#    kind of gemtext line, UTF-8 folded) equal to the checker's model; a
#    relative link; Back and Forward (from the page cache); Tab to a link,
#    Return: a question (10) answered (percent-encoded); a sensitive one
#    (11); a redirect (30, relative); another host's (31: the box, Yes); a
#    loop of redirects (the box after 5); 51; 60; the web and mail links'
#    boxes; text/plain; ISO-8859-1; a binary (its box, Yes) with Alt+Tab
#    at 20,000 bytes: equal byte for byte; a page that stalls, Esc;
#    File > Find...; Bookmarks > Add this page; Go > Home; a bookmark
#    removed (Tab, Bookmarks > Remove..., Yes): GEMINI.MARKS; dark mode;
#    every connection ATCS; the main loop's longest gap; nothing lost
#    (V128: the server is also Gemipedia's stand-in, GEMINI.CFG's wiki=:
#    Go > Wikipedia..., "wp <text>" and "w <text>" typed, a redirect to its
#    search, File > Settings...'s language pl, "wp" alone; the requests)
#    (V138: Gemipedia's image gallery, its links the media route's: the
#    first connection refused and tried again, a link of 281 characters,
#    a picture shown by its MIME type, the JPEG's box, a closed port's box
#    with the address; every ATCS after the one before's ATH)
# 2b. launch (V128): Wikipedia.cvt (the release build's launcher: its
#    class, parent, data, tile) in /DOCUMENTS of the real shell (built
#    here, as gate tile does; Veranda Gemini's test build in
#    /VERANDA/APPS): a screenshot of its tile (launcher.png); double-clicked
#    (tests/gemini_launch.py's SHELL.TST): Veranda Gemini started with it,
#    the box "Look up in Wikipedia:" at once, the article
# 3. nomodem (-uart 9FE0 file:, no modem): the address typed: the box
# Screenshots: $OUT/book.png, page.png, page2.png, input.png, plain.png,
# xfer.png, stall.png, menu.png (V149: File open), find.png, marks.png, end.png, wiki.png, dark.png,
# launcher.png, launch.png, gallery.png, picflag.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/gemini}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU_NET=${EMU_NET:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

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

# 1. the application, the test build, the test desktop
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/gemini all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/gemini does not build"; }
make -s -C apps/gemini test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/gemini's test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/gemini.map').read()
    seg = {g[0]: int(g[3], 16) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})', m, re.M)}
    end = max(int(g[1], 16) for g in re.findall(r'^(CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
    def mod(name):
        i = m.find(name + ':')
        c = re.search(r'CODE\s+Offs=\w+\s+Size=(\w+)', m[i:i + 400])
        return int(c.group(1), 16) if c else 0
    net = mod('veranda.lib(vrnet.o)') + mod('veranda.lib(vrser.o)') + mod('veranda.lib(vrserc.o)') + mod('veranda.lib(vrsync.o)')
    o = [sum(seg.get(s % n, 0) for s in ('OVERLAY%d', 'OVL%dRO', 'OVL%dDATA', 'OVL%dBSS')) for n in (1, 2, 3, 4, 5, 6, 7, 8)]
    return end, net, o
end, net, o = sizes(sys.argv[1])
tend, _, to = sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/Gemini.cvt', 'rb').read())
print('ok    the sizes: Gemini.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free; '
      'the test build to $%04X, %d free), of it vrnet with the serial driver %d bytes of code; overlay 1 (the '
      'interface) %d bytes (%d spare), overlay 2 (the bookmarks, small boxes) %d (%d spare), '
      'overlay 3 (URLs, the replies\' boxes) %d (%d spare), overlay 4 (web pages, Wikipedia, the picture viewer) %d (%d spare), overlay 5 (the PNG decoder) %d (%d spare), overlay 6 (the window\'s chrome, the scroll bar: V149) %d (%d spare; the test build: overlay 1 %d spare, overlay 4 %d spare); RAM banks: 7 (the page 4, its rows 1, the history and '
      'the font 1, the page cache 1), the page cache\'s other 2 the loader\'s spare ones (V125), vrnet 2, the overlays 6: 15'
      % (cvt, end, end - 0x801, 0x8400 - end - 1, tend, 0x8400 - tend - 1, net,
         o[0], 8192 - o[0], o[1], 8192 - o[1], o[2], 8192 - o[2], o[3], 8192 - o[3], o[4], 8192 - o[4], o[5], 8192 - o[5], 8192 - to[0], 8192 - to[3]))
if end >= 0x8400 or tend >= 0x8400 or max(o + to) > 8192:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Veranda Gemini builds against the installed SDK (and its test build)"

echo "== web_proxy: the PC's proxy (tools/web_proxy.py) on the host, sample pages only"
mkdir -p "$OUT/wp"
$PY tests/test_web_proxy.py "$OUT/wp" || fail "web_proxy"

echo "== png: the decoder on the host (apps/gemini/png.c, pngplan.c with gcc) against tests/png_ref.py"
mkdir -p "$OUT/png"
gcc -O2 -Wall -Wno-unused-function -DPNG_HOST -I apps/gemini -o "$OUT/png/png_host" tests/png_host.c || fail "tests/png_host.c"
$PY tests/check_png.py "$OUT/png/png_host" "$OUT/png" || fail "png on the host"

# the server: its folder; sets SPORT
server() {
	mkdir -p "$1"
	rm -f "$1/ready"
	$PY tests/gemini_server.py "$1" > "$1/server.log" 2>&1 &
	SRVPID=$!
	for _ in $(seq 50); do [ -f "$1/ready" ] && break; sleep 0.1; done
	[ -f "$1/ready" ] || fail "the Gemini server does not start"
	read -r SPORT CPORT < "$1/ready"
}
server_end() {
	kill "$SRVPID" 2>/dev/null || true
	wait "$SRVPID" 2>/dev/null || true
}
# a session in folder $1: GEMINI.TST $2, at most $3 seconds, the UART's back-end $4
run() {
	local dir=$1 tst=$2 secs=$3 uart=$4
	mkdir -p "$dir/VERANDA/.SYSTEM" "$dir/DOCUMENTS"
	cp "$A/test/Gemini.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	echo "$tst" > "$dir/GEMINI.TST"
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

# (PICS_ONLY=1: the pictures alone, session pics: a quicker run while working on them; no checks)
if [ -n "$PICS_ONLY" ]; then
	R=$OUT/pics
	server "$R/srv"
	mkdir -p "$R/VERANDA/.SYSTEM"
	printf 'pictures=56\r\n' > "$R/VERANDA/.SYSTEM/GEMINI.CFG"
	run "$R" "pics $SPORT" 600 "modem:baud=57600,log=$R/modem.log"
	server_end
	grep "GE " "$R/log.txt" | grep -v "GE L \|GE IROW" | tail -40
	exit 0
fi
echo "== main: the bookmarks, gemtext, links, Back and Forward, questions, redirects, errors, texts, a download with Alt+Tab, Stop, Find, bookmarks, web pages (NewsWaffle, the proxy)"
R=$OUT/main
server "$R/srv"
# (V124: the web's settings: the server is NewsWaffle's stand-in and, as localhost, the proxy)
mkdir -p "$R/VERANDA/.SYSTEM"
printf 'web=0\r\nproxy=localhost:%s\r\npictures=56\r\nwaffle=gemini://127.0.0.1:%s/cgi-bin/waffle.cgi/view\r\nwiki=gemini://127.0.0.1:%s/cgi-bin/wp.cgi\r\n' "$SPORT" "$SPORT" "$SPORT" > "$R/VERANDA/.SYSTEM/GEMINI.CFG"
run "$R" "main $SPORT" 900 "modem:baud=57600,log=$R/modem.log"
server_end
[ -f "$R/dump.bin" ] || { grep "^GE" "$R/log.txt" | tail -30; fail "main: the session did not end"; }
grep -q "^GE END$" "$R/log.txt" || { grep "^GE" "$R/log.txt" | tail -40; shots FAIL; fail "main: the test failed"; }
[ -f "$R/PICRGB.RAW" ] && $PY tests/pic_shot.py "$R/PICRGB.RAW" "$R/P5.DMP" "$OUT/picrgb.png"
[ -f "$R/PICCOMIC.RAW" ] && $PY tests/pic_shot.py "$R/PICCOMIC.RAW" "$R/P9.DMP" "$OUT/piccomic.png"
[ -f "$R/PICFLAG.RAW" ] && $PY tests/pic_shot.py "$R/PICFLAG.RAW" "$R/PA.DMP" "$OUT/picflag.png"
$PY tests/check_glyphs.py "$R/PAGE.RAW" "$ROM" "the root's Polish line (UTF-8, V143)" \
	"Polish (V143): Zażółć gęślą jaźń, ZAŻÓŁĆ GĘŚLĄ JAŹŃ." || { shots PAGE; fail "the Polish glyphs"; }
shots BOOK PAGE PAGE2 INPUT WEB PLAIN XFER STALL MENU FIND MARKS END WIKI DARK GALLERY FAIL
$PY tests/check_gemini.py main "$R" "$SPORT" || fail "main"

echo "== launch: the Wikipedia launcher double-clicked in the shell (V128)"
# the real shell (built here, as gate tile does) in the card's layout:
# /VERANDA/SHELL.cvt, Veranda Gemini's test build in /VERANDA/APPS, the
# launcher (the release build's Wikipedia.cvt) in /DOCUMENTS, where the
# shell starts; its script (tests/gemini_launch.py) double-clicks it
cp -r shell "$OUT/shellsrc"
rm -f "$OUT/shellsrc"/*.cvt "$OUT/shellsrc"/*.bin "$OUT/shellsrc"/*.map
make -s -C "$OUT/shellsrc" SDK="$SDK" > "$OUT/shellsrc/build.log" 2>&1 || { cat "$OUT/shellsrc/build.log"; fail "the shell does not build"; }
$PY "$SDK/tools/vpack.py" --list "$A/rel/Wikipedia.cvt" > "$A/wiki.list" || fail "vpack --list Wikipedia.cvt"
grep -q "^geos type *7$" "$A/wiki.list" && grep -q "^class *GeminiStart V1.0$" "$A/wiki.list" && grep -q "^structure *sequential$" "$A/wiki.list" \
	&& grep -q "^tile *sky," "$A/wiki.list" || { cat "$A/wiki.list"; fail "Wikipedia.cvt: not a sequential APPL_DATA document with its tile"; }
$PY - "$A/rel/Wikipedia.cvt" <<'EOF' || fail "Wikipedia.cvt's parent and data"
import sys
d = open(sys.argv[1], 'rb').read()
info = bytes(2) + d[254:508]
assert info[117:133] == b'VerandaGemi V1.0', info[117:137]
assert d[508:] == b'wp\r\n', d[508:]
EOF
ok "Wikipedia.cvt (tools/vpack.py --doc apps/gemini/wiki.hdr): a sequential APPL_DATA document, class GeminiStart V1.0, parent VerandaGemi V1.0, its tile (sky: a W on a globe, apps/gemini/wikitile.txt) and icon (wiki.pbm), its data \"wp\" CR LF"
launch_dir() {
	rm -rf "$1"
	mkdir -p "$1/VERANDA/APPS" "$1/VERANDA/.SYSTEM" "$1/DOCUMENTS"
	cp "$OUT/shellsrc/SHELL.cvt" "$1/VERANDA/"
	cp build/VERANDA.SYS build/VERANDA.PRG "$1/"
	cp "$A/test/Gemini.cvt" "$1/VERANDA/APPS/Veranda Gemini.cvt"
	cp "$A/rel/Wikipedia.cvt" "$1/DOCUMENTS/"
	$PY tests/gemini_launch.py "$1" "$2" || fail "tests/gemini_launch.py $2"
}
launch_run() {
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$2" "$EMU_NET" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -uartclock 14.7456 -uart 9FE0 "$3" > console.txt 2>&1) || true
	tr '\r' '\n' < "$1/console.txt" > "$1/log.txt"
}
R=$OUT/launchicon
launch_dir "$R" probe
launch_run "$R" 120 "file:,$R/out.bin"
[ -f "$R/dump.bin" ] && grep -a -q "SHELL DONE" "$R/console.txt" || { tail -20 "$R/log.txt"; fail "launch: the shell's probe did not end"; }
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/launcher.png" 2>/dev/null || fail "the launcher's screenshot"
ok "the shell's window on /DOCUMENTS with the launcher's tile: $OUT/launcher.png"
R=$OUT/launch
launch_dir "$R" launch
server "$R/srv"
printf 'wiki=gemini://127.0.0.1:%s/cgi-bin/wp.cgi\r\n' "$SPORT" > "$R/VERANDA/.SYSTEM/GEMINI.CFG"
echo "wiki $SPORT" > "$R/GEMINI.TST"
launch_run "$R" 300 "modem:baud=57600,log=$R/modem.log"
server_end
grep -q "^GE END$" "$R/log.txt" || { grep -a "^GE\|SHELL" "$R/log.txt" | tail -30; shots FAIL; fail "launch: the test failed"; }
shots LAUNCH
$PY tests/check_gemini.py launch "$R" "$SPORT" || fail "launch"

echo "== nomodem: no modem on the port"
R=$OUT/nomodem
mkdir -p "$R"
run "$R" "nomodem 1965" 300 "file:,$R/out.bin"
grep -q "^GE END$" "$R/log.txt" || { grep "^GE" "$R/log.txt" | tail -30; fail "nomodem: the test failed"; }
$PY tests/check_gemini.py nomodem "$R" 0 || fail "nomodem"
rm -f "$OUT"/*/dump.bin

echo "screenshots: $(ls "$OUT"/*.png | tr '\n' ' ')"
echo "GATE gemini: PASS"
