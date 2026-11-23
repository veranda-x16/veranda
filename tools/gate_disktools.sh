#!/bin/bash
# Gate disktools (DECISIONS V119): Disk Tools (apps/disktools) under ROM R49
# at 512 KB, on the emulator's host folder and on SD card images
# (tools/vcard.py). The test build (tests/disktools_play.c, make test)
# drives the program from its main loop and answers its boxes through
# mouseSource (tests/term_play.s); tests/check_disktools.py reads the
# console's "DT ..." lines against what the host computes.
#
#   tools/gate_disktools.sh        (OUT=... where the results go, default build/gate/disktools)
#
# 1. the kernel and the SDK; Disk Tools built against it (DiskTools.cvt: an
#    application, banked overlays, its tile) and its test build; the sizes
# 2. host: a folder made here (DOCUMENTS with a big file and folders, 60
#    folders in MANY, a trash with a file and a folder, the four kinds of
#    leftover and two look-alikes that are not); the card (Host folder);
#    Space use of the top, of /DOCUMENTS (Down, Return) and of the top
#    again (Backspace), each folder's total against the host's; a count
#    stopped by Esc; a count stopped by Alt+Tab (TaskCtl TASK_ASIDE: the
#    test desktop tests/term_desk.s brings it back after 3 s) and counted
#    again; Check's box (no FAT); the trash: Cancel, then OK (emptied, its
#    folder kept); leftovers found and deleted kind by kind (the Font
#    Editor's kept after Cancel); the host's folder after: what was
#    deleted and nothing else
# 3. sdcheck: an SD card image (64 MB, 4 KB clusters) with faults planted
#    by check_disktools.py plant (a chain cut short, chains crossing, a
#    chain past the end, a file longer than its size, a chain into a free
#    cluster, a sector of the second FAT changed): Check's fault lines and
#    summary equal to the host's own walk of the image; the image's
#    SHA-256 the same before and after (nothing written)
# 4. sdmod: an SD card image: Rename (R-H: the volume label X16CARD in the
#    image), Space use against the host, the trash emptied, then Check
#    after the DOS's own writes: no problems
# Screenshots: $OUT/card.png, space.png, clean.png (host), check.png
# (sdcheck's results), sdmod.png.
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/disktools}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU=${EMU:-$HOME/Projects/x16-emulator-modem/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
[ -x "$EMU" ] || fail "no emulator at $EMU"
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
make -s -C apps/disktools all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/disktools does not build"; }
make -s -C apps/disktools test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/disktools' test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/disktools.map').read()
    seg = {g[0]: (int(g[1], 16), int(g[2], 16)) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+[0-9A-F]{6}', m, re.M)}
    end = max(seg[s][1] for s in ('CODE', 'RODATA', 'DATA', 'BSS'))
    return end, seg['OVERLAY1'][1] - 0x9FFF, seg['OVERLAY2'][1] - 0x9FFF
r, t = sizes(sys.argv[1]), sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/DiskTools.cvt', 'rb').read())
print('ok    the sizes: DiskTools.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 1 KB below $8800: %d free; '
      'the test build to $%04X); overlay 1 (clean up, the window chrome) %d bytes, overlay 2 (space use, the card '
      'tab, the check drawn, card.c) %d bytes; RAM banks while working: 2 overlays, the walk 2, space use 1, '
      'clean up 2, the check 3 and one per 65,536 clusters' % (cvt, r[0], r[0] - 0x801, 0x8400 - r[0] - 1, t[0], r[1], r[2]))
if t[0] >= 0x8400 or max(r[1], r[2], t[1], t[2]) > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
ok "Disk Tools builds against the installed SDK (and its test build)"

# a session: folder $1 (the host folder, or where an SD card image's run
# keeps its console), $2 seconds at most, then the emulator's arguments
run() {
	local dir=$1 secs=$2
	shift 2
	local t0=$(date +%s.%N)
	(cd "$dir" && SDL_VIDEODRIVER=dummy timeout -s INT "$secs" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V -rtc -ram 512 "$@" > console.txt 2>&1) || true
	echo "      ($(basename "$dir"): $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
	[ -f "$dir/dump.bin" ] || { tr '\r' '\n' < "$dir/console.txt" | grep -a -o 'DT .*\|BOX .*' | tail -20; fail "$(basename "$dir"): the session did not end"; }
}
# the tree both kinds of run start from: $1 the folder
tree() {
	local R=$1
	# (.SYSTEM/TASKS: the switcher makes it at start, V145; made here so the card is not written)
	mkdir -p "$R/VERANDA/.SYSTEM/TRASH/Old" "$R/VERANDA/.SYSTEM/TASKS" "$R/VERANDA/FONTS" "$R/DOCUMENTS/Big" "$R/DOCUMENTS/Small" "$R/MANY"
	for i in $(seq 1 60); do mkdir -p "$R/MANY/F$i"; echo "$i" > "$R/MANY/F$i/x.txt"; done
	head -c 200000 /dev/urandom > "$R/DOCUMENTS/Big/big.bin"
	head -c 3000 /dev/urandom > "$R/DOCUMENTS/Small/s.txt"
	head -c 1234 /dev/urandom > "$R/DOCUMENTS/note.txt"
	echo hi > "$R/VERANDA/.SYSTEM/TRASH/a.txt"
	echo old > "$R/VERANDA/.SYSTEM/TRASH/Old/b.txt"
	cp "$A/SHELL.cvt" "$R/VERANDA/"
	cp build/VERANDA.SYS "$R/"
}

echo "== host: the card, Space use, Esc, Alt+Tab, Check's box, the trash, leftovers"
R=$OUT/host
tree "$R"
echo t > "$R/DOCUMENTS/~VEDIT.TMP"
echo t > "$R/DOCUMENTS/Small/~VBASIC.TMP"
echo f > "$R/VERANDA/FONTS/Gate Sans.cvt"
echo f > "$R/VERANDA/FONTS/Gate Sans.tmp"
echo o > "$R/DOCUMENTS/Orphan.tmp"
echo c > "$R/VERANDA/.SYSTEM/ASK.CFG"
echo c > "$R/VERANDA/.SYSTEM/ASK.TMP"
echo c > "$R/DOCUMENTS/ASK.TMP"
cp "$A/test/DiskTools.cvt" "$R/AUTOSTART.cvt"
cp "$A/SHELL.cvt" build/VERANDA.PRG "$R/"
echo host > "$R/DT.TST"
cp -r "$R" "$OUT/host.before"
run "$R" 300
$PY tests/check_disktools.py log host "$R/console.txt" "$R" "$OUT/host.before" || fail "host"
# the folder after: the trash empty (its folder kept), the leftovers gone
# but the Font Editor's, nothing else changed
$PY - "$OUT/host.before" "$R" <<'EOF' || fail "the host folder after the session"
import os, sys
def files(top):
    out = set()
    for d, ds, fs in os.walk(top):
        for x in fs + [y + '/' for y in ds]:
            out.add(os.path.relpath(os.path.join(d, x), top))
    return out
b, a = files(sys.argv[1]), files(sys.argv[2])
gone = sorted(b - a)
new = sorted(x for x in a - b if not x.endswith('.RAW') and x not in ('console.txt', 'dump.bin'))
want = sorted(['DOCUMENTS/~VEDIT.TMP', 'DOCUMENTS/Small/~VBASIC.TMP', 'VERANDA/.SYSTEM/ASK.TMP',
               'VERANDA/.SYSTEM/TRASH/a.txt', 'VERANDA/.SYSTEM/TRASH/Old', 'VERANDA/.SYSTEM/TRASH/Old/b.txt'])
if gone != want or new:
    sys.exit('FAIL  gone %s (want %s), new %s' % (gone, want, new))
print('ok    the host folder after: the trash empty (TRASH kept), ~VEDIT.TMP, ~VBASIC.TMP and .SYSTEM/ASK.TMP gone; '
      'Gate Sans.tmp (Cancel), Orphan.tmp (no .cvt) and DOCUMENTS/ASK.TMP (not the data folder) kept; nothing else changed')
EOF
for s in CARD SPACE CLEAN; do
	[ -f "$R/$s.RAW" ] || fail "no $s.RAW"
	$PY tests/ftp_shot.py "$R/$s.RAW" "$OUT/$(echo $s | tr A-Z a-z).png"
done

echo "== sdcheck: an SD card image with faults planted, Check (read only)"
S=$OUT/sdcheck
mkdir -p "$S/card/DOCUMENTS/BAD"
tree "$S/card"
rm "$S/card/VERANDA/SHELL.cvt"
cp "$A/test/DiskTools.cvt" "$S/card/AUTOSTART.cvt"
echo sdcheck > "$S/card/DT.TST"
head -c 12000 /dev/urandom > "$S/card/DOCUMENTS/BAD/SHORT.TXT"
head -c 8000 /dev/urandom > "$S/card/DOCUMENTS/BAD/CROSS.TXT"
head -c 16000 /dev/urandom > "$S/card/DOCUMENTS/BAD/VICTIM.TXT"
head -c 8000 /dev/urandom > "$S/card/DOCUMENTS/BAD/PAST.TXT"
head -c 100 /dev/urandom > "$S/card/DOCUMENTS/BAD/LONG.TXT"
head -c 8000 /dev/urandom > "$S/card/DOCUMENTS/BAD/FREE.TXT"
head -c 5000 /dev/urandom > "$S/card/DOCUMENTS/BAD/GOOD.TXT"
$PY tools/vcard.py make --mb 64 --cluster-kb 4 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
$PY tests/check_disktools.py plant "$S/sd.img" | sed 's/^/      /' || fail "the faults planted"
cp build/VERANDA.PRG "$S/"
sum0=$(sha256sum < "$S/sd.img")
run "$S" 300 -sdcard sd.img
sum1=$(sha256sum < "$S/sd.img")
$PY tests/check_disktools.py log sdcheck "$S/console.txt" "$S/sd.img" || fail "sdcheck"
[ "$sum0" = "$sum1" ] || fail "the image changed during the check (SHA-256 ${sum0%% *} -> ${sum1%% *})"
ok "the image unchanged by the session and its check: SHA-256 ${sum0:0:16}... before and after"
$PY tools/vram2png.py --color "$S/dump.bin" "$OUT/check.png" 2>/dev/null || fail "check.png"

echo "== sdmod: an SD card image: Rename, Space use, the trash emptied, Check after"
M=$OUT/sdmod
tree "$M/card"
rm "$M/card/VERANDA/SHELL.cvt"
cp "$A/test/DiskTools.cvt" "$M/card/AUTOSTART.cvt"
echo sdmod > "$M/card/DT.TST"
$PY tools/vcard.py make --mb 64 --cluster-kb 4 "$M/sd.img" "$M/card" >/dev/null || fail "vcard make"
cp "$M/sd.img" "$M/before.img"
cp build/VERANDA.PRG "$M/"
run "$M" 300 -sdcard sd.img
$PY tests/check_disktools.py log sdmod "$M/console.txt" "$M/sd.img" "$M/before.img" || fail "sdmod"
$PY tools/vram2png.py --color "$M/dump.bin" "$OUT/sdmod.png" 2>/dev/null || fail "sdmod.png"
rm -f "$M/before.img"

echo "screenshots: $OUT/card.png space.png clean.png check.png sdmod.png"
echo "GATE disktools: PASS"
