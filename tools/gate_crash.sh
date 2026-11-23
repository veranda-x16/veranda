#!/bin/bash
# Gate crash (DECISIONS V50): crash recovery.
#
#   tools/gate_crash.sh          (CRASH_SD=0: skip the SD card run)
#
# 1. the kernel, the SDK, the shell; five programs that crash
#    (tests/crash_app.s): a BRK with a file open for writing and the colour
#    map on, Panic, kernel bank U overwritten then called (a BRK in the
#    kernel bank), a recursion without end (the stack overflow the
#    interrupt sees), a jump into the RAM after the program (0: a BRK).
#    Each puts Return into the ROM's keyboard queue first: the panic box's
#    OK takes it.
# 2. the shell double-clicks each in turn (SHELL.TST, tests/shell_script.py
#    --crash); each crashes, its panic box comes, OK: the shell again;
#    then SHELL DONE and a dump of the banked RAM and VRAM
# 3. tests/check_crash.py: the console in order, each panic box's name,
#    reason, address and bank; CRASH.TXT closed with its line; the kernel
#    banks' code as loaded and their copy equal to VERANDA.SYS; the
#    shell's screen (check_vera.py; crash-shell.png)
# 4. a screenshot of the panic box (a kernel built with -D PANIC_SHOT
#    dumps once the box is drawn; the program without the Return): the
#    plain display (the colour map hidden), slate ink on white (V74), the box's
#    frame where it belongs (panic.png)
# 5. the session again on an SD card image
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/crash
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }

# the programs: $1 kind, $2 name, $3 out dir, $4... ca65 defines
A=$OUT/apps
mkdir -p "$A"
app() {
	k=$1 nm=$2 d=$3
	shift 3
	ca65 --cpu 65C02 -I "$SDK/include" -D KIND=$k "$@" -o "$d/crash$k.o" tests/crash_app.s || fail "tests/crash_app.s ($k)"
	ld65 -C "$SDK/cfg/app.cfg" -o "$d/crash$k.bin" -Ln "$d/crash$k.lab" "$d/crash$k.o" || fail "crash_app $k does not link"
	printf 'name = %s\nclass = %s\nmode = 640x480\napi = 2\nicon = %s\n' $nm $nm "$SDK/template/c/icon.pbm" > "$d/crash$k.hdr"
	$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$d/$nm.cvt" "$d/crash$k.hdr" "$d/crash$k.bin" >/dev/null || fail "vpack $nm"
}
NAMES="Crash1Brk Crash2Panic Crash3Bank Crash4Stack Crash5Jump"
k=1
for nm in $NAMES; do
	app $k $nm "$A"
	k=$((k + 1))
done
ok "five programs that crash: $NAMES"

$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
files() {
	cp "$OUT/src/SHELL.cvt" build/VERANDA.SYS "$1/"
	for nm in $NAMES; do cp "$A/$nm.cvt" "$1/"; done
}

# the session on the host folder
H=$OUT/host
mkdir -p "$H"
files "$H"
cp build/VERANDA.PRG "$H/"
$PY tests/shell_script.py --crash "$H" console.txt || fail "the script"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 240 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump BV > console.txt 2>&1) || true
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "host folder: the session did not end (no dump)"; }
echo "== the session on the host folder"
$PY tests/check_crash.py "$H" build "$A" || fail "host folder"
$PY tools/check_vera.py "$H/dump.bin" || fail "host folder: the shell's display"
$PY tools/vram2png.py --color "$H/dump.bin" "$OUT/crash-shell.png" || fail "vram2png"
ok "the shell's screen after the five crashes: $OUT/crash-shell.png"

# the panic box: a kernel that dumps once it is drawn; the BRK program
# without the Return, as AUTOSTART
T=$OUT/shot
mkdir -p "$T/k" "$T/run"
app 1 Crash1Brk "$T" -D NOKEY
$PY tools/kbuild.py --out "$T/k" -D PANIC_SHOT=1 >/dev/null || fail "the PANIC_SHOT kernel does not build"
cp "$T/Crash1Brk.cvt" "$T/run/AUTOSTART.cvt"
cp "$T/k/VERANDA.PRG" "$T/k/VERANDA.SYS" "$T/run/"
(cd "$T/run" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$T/run/dump.bin" ] || { tail -10 "$T/run/console.txt"; fail "no dump with the panic box"; }
grep -a -q "PANIC AUTOSTART It ran into a BRK" "$T/run/console.txt" || fail "the screenshot run: no panic line"
$PY tools/check_vera.py "$T/run/dump.bin" || fail "the panic box: the display (the colour map must be hidden)"
$PY tools/vram2png.py --color "$T/run/dump.bin" "$OUT/panic.png" || fail "vram2png"
$PY - "$T/run/dump.bin" <<'EOF' || fail "the panic box"
import sys
v = open(sys.argv[1], 'rb').read()[-132878:]
pal = v[131072 + 256:131072 + 260]
assert pal == bytes([0xFF, 0x0F, 0x23, 0x02]), 'palette entries 0, 1: %s (want white, slate: V74)' % pal.hex()
px = lambda x, y: v[y * 80 + x // 8] >> (7 - x % 8) & 1
L, R, T, B = 144, 495, 192, 287          # kernel/s/panic.s: 352 x 96, centred
frame = all(px(x, T) and px(x, B) for x in range(L, R + 1)) and all(px(L, y) and px(R, y) for y in range(T, B + 1))
assert frame, 'no box frame at %d-%d, %d-%d' % (L, R, T, B)
inside = sum(px(x, y) for y in range(T + 2, B - 1) for x in range(L + 2, R - 1))
assert 300 < inside < 6000, 'the box holds %d ink pixels (text and OK)' % inside
print('ok    the panic box: slate ink on white, the colour map hidden, its frame at %d-%d x %d-%d, %d ink pixels in it'
      % (L, R, T, B, inside))
EOF
ok "the panic box: $OUT/panic.png"

if [ "${CRASH_SD:-1}" != 0 ]; then
	S=$OUT/sd
	mkdir -p "$S/card" "$S/out"
	files "$S/card"
	$PY tests/shell_script.py --crash "$S/card" || fail "the script (SD)"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 240 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump BV > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -20 "$S/out/console.txt"; fail "SD card: the session did not end (no dump)"; }
	mv "$S/dump.bin" "$S/out/"
	$PY tools/vcard.py get "$S/sd.img" CRASH.TXT "$S/out/CRASH.TXT" >/dev/null || true
	echo "== the same on an SD card image"
	$PY tests/check_crash.py "$S/out" build "$A" || fail "SD card"
	$PY tools/check_vera.py "$S/out/dump.bin" || fail "SD card: the shell's display"
fi
echo "screenshots: $OUT/panic.png (the panic box), crash-shell.png (the shell after the crashes)"
echo "GATE crash: PASS"
