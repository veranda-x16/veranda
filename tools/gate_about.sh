#!/bin/bash
# Gate about (DECISIONS V119): About this X16 (apps/about) under ROM R49.
# The test build (tests/about_play.c, make test) logs every value it shows
# ("AB <label>=<value>") and its numbers; tests/check_about.py reads them
# against what the host knows (the ROM file's version byte, the emulator's
# RAM, the host's clock, the SD card image, the modem's log).
#
#   tools/gate_about.sh        (OUT=... where the results go, default build/gate/about)
#
# EMU: an x16emu with "-uart <addr> ... modem" (the modem branch; default
# ~/Projects/x16-emulator-modem/build/x16emu); R49: the ROM.
#
# 1. the kernel and the SDK; About this X16 built against it (About.cvt)
#    and its test build; the test desktop (tests/about_desk.c) and AbHelper
#    (tests/about_helper.c); the sizes
# 2. host, 512 KB: the values (the installed build from VERANDA/UPDATE.LST,
#    V130; the KERNAL ROM's byte, VERA and the SMC,
#    the CPU at 8 MHz, 64 banks, 43 for programs (V165), the clock, the time
#    since reset), a second of live updates, Copy (the Text Scrap), Ask the
#    modem with no card, ABOUT.RAW; Alt+Tab: the test desktop starts
#    AbHelper, which puts itself aside, and brings About back: AbHelper
#    among the programs aside, with its banks; ASIDE.RAW
# 3. 2 MB: 256 banks, 235 for programs
# 4. an SD card image: its name, size (the partition, the CSD's card) and
#    free space (FSInfo) against the image
# 5. modem (-uart 9FE0 modem): the UART found at $9FE0, Ask the modem:
#    the firmware's line from ATI; the modem's log: only AT and ATI sent
# Screenshots: $OUT/about.png, aside.png, modem.png, sd.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/about}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU=${EMU:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
"$EMU" -h 2>&1 | grep -q -- "modem\[:<options>\]" || fail "$EMU has no -uart modem back-end (the emulator's modem branch)"
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# 1. the application, the test build, the test desktop and its helper
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/about all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/about does not build"; }
make -s -C apps/about test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/about's test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def end(d):
    m = open(d + '/about.map').read()
    return max(int(g, 16) for g in re.findall(r'^(?:CODE|RODATA|DATA|BSS)\s+[0-9A-F]{6}\s+([0-9A-F]{6})', m, re.M))
r, t = end(sys.argv[1]), end(sys.argv[2])
cvt = len(open(sys.argv[1] + '/About.cvt', 'rb').read())
print('ok    the sizes: About.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 2 KB below $8800: %d free; '
      'the test build to $%04X); no overlays; RAM banks: none, one (the UART\'s ring) while the modem is asked'
      % (cvt, r, r - 0x801, 0x8000 - r - 1, t))
if t >= 0x8000:
    sys.exit('FAIL  out of room')
EOF
for t in desk helper; do
	cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$A/ab$t.bin" tests/about_$t.c "$SDK/lib/veranda.lib" \
		> "$A/$t.log" 2>&1 || { cat "$A/$t.log"; fail "tests/about_$t.c"; }
done
printf 'name = SHELL\nclass = AbDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
printf 'name = AbHelper\nclass = AbHelper\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/helper.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/abdesk.bin" >/dev/null || fail "vpack the test desktop"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/AbHelper.cvt" "$A/helper.hdr" "$A/abhelper.bin" >/dev/null || fail "vpack AbHelper"
ok "About this X16 builds against the installed SDK (and its test build, the test desktop, AbHelper)"

# a session in folder $1: AB.TST $2, RAM $3 KB, then the emulator's arguments
run() {
	local dir=$1 tst=$2 ram=$3
	shift 3
	mkdir -p "$dir/VERANDA/.SYSTEM"
	echo "$tst" > "$dir/AB.TST"
	[ -f "$dir/AUTOSTART.cvt" ] || cp "$A/test/About.cvt" "$dir/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" "$A/AbHelper.cvt" build/VERANDA.PRG build/VERANDA.SYS "$dir/"
	cp "$A/SHELL.cvt" "$dir/VERANDA/"
	local t0=$(date +%s.%N)
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -rtc -ram "$ram" "$@" > console.txt 2>&1) || true
	echo "      ($(basename "$dir"): $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
	[ -f "$dir/dump.bin" ] || { tr '\r' '\n' < "$dir/console.txt" | grep -a -o 'AB .*' | tail -20; fail "$(basename "$dir"): the session did not end"; }
}

echo "== host, 512 KB: the values, live updates, Copy, Alt+Tab with a program aside"
R=$OUT/host
mkdir -p "$R/VERANDA"
printf 'VERANDA-UPDATE 1\nbuild 1234abc 2026-11-21\nversion 1.0\nnote a test\nend 0\n' > "$R/VERANDA/UPDATE.LST"   # (V130: the installed build)
run "$R" host 512
$PY tests/check_about.py host "$R/console.txt" "$ROM" 512 "$R" || fail "host"
$PY tests/ftp_shot.py "$R/ABOUT.RAW" "$OUT/about.png" || fail "about.png"
$PY tests/ftp_shot.py "$R/ASIDE.RAW" "$OUT/aside.png" || fail "aside.png"

echo "== 2 MB"
R=$OUT/ram2m
run "$R" plain 2048
$PY tests/check_about.py plain "$R/console.txt" "$ROM" 2048 || fail "2 MB"

echo "== an SD card image"
S=$OUT/sd
mkdir -p "$S/card/VERANDA/.SYSTEM" "$S/card/DOCUMENTS"
cp "$A/test/About.cvt" "$S/card/AUTOSTART.cvt"
echo plain > "$S/card/AB.TST"
cp build/VERANDA.SYS "$S/card/"
cp "$A/SHELL.cvt" "$S/card/VERANDA/"
$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$S/"
(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -rtc -ram 512 > console.txt 2>&1) || true
[ -f "$S/dump.bin" ] || fail "sd: the session did not end"
$PY tests/check_about.py plain "$S/console.txt" "$ROM" 512 "$S/sd.img" || fail "the SD card image"
$PY tools/vram2png.py --color "$S/dump.bin" "$OUT/sd.png" 2>/dev/null || fail "sd.png"

echo "== the modem (the emulator's Zimodem at \$9FE0): Ask the modem"
R=$OUT/modem
mkdir -p "$R"
run "$R" modem 512 -uartclock 14.7456 -uart 9FE0 "modem:baud=57600,log=$R/modem.log"
$PY tests/check_about.py modem "$R/console.txt" "$ROM" 512 "$R/modem.log" || fail "modem"
$PY tests/ftp_shot.py "$R/MODEM.RAW" "$OUT/modem.png" || fail "modem.png"

echo "screenshots: $OUT/about.png aside.png modem.png sd.png"
echo "GATE about: PASS"
