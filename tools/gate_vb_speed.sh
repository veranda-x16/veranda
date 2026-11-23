#!/bin/bash
# Gate vb_speed (VeraBASIC phase 1, docs/DECISIONS.md V86): the plan's
# section 3.3 speed table, and the Rugg/Feldman benchmarks BM1-BM8 against
# the X16 ROM's own BASIC in the same emulator (8 MHz, ROM R49, the
# interrupt on). Timed with the emulator's cycle counter ($9FB8-$9FBB),
# which both BASICs PEEK.
#
#   tools/gate_vb_speed.sh      (OUT=dir; R49=the ROM image)
#
# 1. VeraBASIC Run's test build (gate vb_core's build) runs
#    tests/vbasic/speed/table.bas, bm1-8.bas (as written: floats) and
#    bm1i-8i.bas (integer variables)
# 2. x16emu -bas types rom_bm1-8.txt into the ROM's BASIC
# 3. tests/vbasic/speed_report.py: the table, each target met or missed and
#    by how much; BM1-BM8 against the ROM's BASIC. The targets met since
#    V107 are checks (a miss fails the gate: FOR i%, the float multiply,
#    the cached GOTO, BM1-BM8 as written, BM1-BM7 with integers 3 times
#    the ROM's speed); the others (a% = a% + b% * 2, a SUB call, LEFT$ and
#    a join, BM8 with integers: the ROM's LOG and SIN) are reported only
# 4. the same programs' results equal the reference interpreter's (the
#    timings left out), so the speed is not bought with wrong answers
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_speed}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
rm -rf "$OUT"
mkdir -p "$OUT/run" "$OUT/rom" "$OUT/test"
TOP=$(pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
make -s -C apps/vbasic test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/build.log" 2>&1 \
	|| { cat "$OUT/build.log"; fail "the test build does not build"; }

S=tests/vbasic/speed
: > "$OUT/run/VBTEST.LST"
for n in table bm1 bm2 bm3 bm4 bm5 bm6 bm7 bm8 bm1i bm2i bm3i bm4i bm5i bm6i bm7i bm8i; do
	$PY tools/vbasic.py build "$S/$n.bas" -o "$OUT/run/$n.cvt" >/dev/null || fail "build $n"
	echo "$n" >> "$OUT/run/VBTEST.LST"
done
cp "$OUT/test/VBRun.cvt" "$OUT/run/AUTOSTART.cvt"
cp build/VERANDA.PRG build/VERANDA.SYS "$OUT/run/"
(cd "$OUT/run" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
grep -a -q "VB DONE" "$OUT/run/console.txt" || fail "VeraBASIC Run's session did not finish"
ok "VeraBASIC Run: the table and BM1-BM8 (floats and integers) timed"

for i in 1 2 3 4 5 6 7 8; do
	SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -bas "$S/rom_bm$i.txt" -run -warp \
		-sound none -echo >> "$OUT/rom/console.txt" 2>&1 || true
done
[ "$(grep -a -c "T BM" "$OUT/rom/console.txt")" = 8 ] || fail "the ROM's BASIC: BM1-BM8 not all timed"
ok "the X16 ROM's BASIC: BM1-BM8 timed"

# the answers: the X16's console lines but the timings, as the reference's
$PY - "$OUT/run/console.txt" <<'EOF' || fail "the benchmarks' results"
import re, sys
text = open(sys.argv[1], 'rb').read().decode('latin-1')
bad = [l for l in text.split('\n') if 'VB| ' in l and not re.search(r'VB\| T \w+', l)]
errs = [l for l in text.split('\n') if 'VB ERROR' in l]
if errs or bad:
    print('FAIL  %s %s' % (errs, bad))
    sys.exit(1)
EOF
rc=0
$PY tests/vbasic/speed_report.py "$OUT/run/console.txt" "$OUT/rom/console.txt" > "$OUT/report.txt" || rc=$?
cat "$OUT/report.txt"
[ "$rc" = 0 ] || fail "the report (a checked target missed, or a time missing)"
echo "GATE vb_speed: PASS (the checked targets met; the other misses above are the measured result)"
