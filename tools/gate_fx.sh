#!/bin/bash
# Gate fx (docs/PLAN.md phase 9, 5.4): the span engine's fills with VERA FX
# 32-bit cache writes, and the fallback.
#
#   tools/gate_fx.sh
#
# 1. the emulator's VERA has FX (DCSEL 63: "V" and a version of 0.3.1 or
#    later; tests/fxver.s logs it), so the kernel uses it
# 2. gates gfx1 and gfx (GEOS 64's scene byte for byte) with the FX
#    kernel; again with a kernel built with -D NOFX (FX forced off: the
#    plain engine); both pass
# 3. gfx1's VRAM (both screens: rectangles, frames, lines, the copy, the
#    scroll, text) and that of tests/fxfill.s (300 random rectangles) are
#    the same byte for byte from both kernels
# 4. the full-screen fill time from both, and FX faster
# The results: build/gate/fx (fx/, nofx/: each run's gfx1 and gfx).
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/fx
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/ver"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
V=$OUT/ver
ca65 --cpu 65C02 -I build/gen -I inc tests/fxver.s -o "$V/fxver.o" || fail "tests/fxver.s does not assemble"
ca65 tests/prghdr.s -o "$V/prghdr.o"
ld65 -C cfg/testprg.cfg "$V/prghdr.o" "$V/fxver.o" -o "$V/TEST.PRG" || fail "tests/fxver.s does not link"
cp build/VERANDA.PRG build/VERANDA.SYS "$V/"
(cd "$V" && SDL_VIDEODRIVER=dummy timeout -s INT 30 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
ver=$(sed -n 's/.*VERA FX [A-Z]* \([0-9.]*\).*/\1/p' "$V/console.txt" | head -1)
grep -q "VERA FX YES" "$V/console.txt" || { cat "$V/console.txt"; fail "the emulator's VERA has no FX ($ver)"; }
ok "the VERA has FX cache writes: DCSEL 63 reads \"V\", $ver (0.3.1 or later needed)"

for k in fx nofx; do
	echo "== kernel: $k"
	defs=
	[ $k = nofx ] && defs="-D NOFX"
	for g in gfx1 gfx; do
		KDEFS="$defs" GATE_OUT="$OUT/$k" tools/gate.sh $g > "$OUT/$k-$g.log" 2>&1 \
			|| { cat "$OUT/$k-$g.log"; fail "gate $g with the $k kernel"; }
		tail -1 "$OUT/$k-$g.log" | sed "s/^/      ($k) /"
		grep -q "GATE $g: SKIP" "$OUT/$k-$g.log" && echo "      (no GEOS 64 reference: gfx skipped)"
	done
	grep "fill\|text:" "$OUT/$k-gfx1.log" | sed "s/^ */      ($k) /"
	# tests/fxfill.s with this kernel (build/ holds it now)
	F=$OUT/$k/fxfill
	mkdir -p "$F"
	ca65 --cpu 65C02 -I build/gen -I inc tests/fxfill.s -o "$F/fxfill.o" || fail "tests/fxfill.s does not assemble"
	ca65 tests/prghdr.s -o "$F/prghdr.o"
	ld65 -C cfg/testprg.cfg "$F/prghdr.o" "$F/fxfill.o" -o "$F/TEST.PRG" || fail "tests/fxfill.s does not link"
	cp build/VERANDA.PRG build/VERANDA.SYS "$F/"
	(cd "$F" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$F/dump.bin" ] || { tail "$F/console.txt"; fail "tests/fxfill.s did not finish ($k)"; }
done
ok "gates gfx1 and gfx pass with FX and with FX forced off (-D NOFX)"
$PY - "$OUT/fx/gfx1/dump.bin" "$OUT/nofx/gfx1/dump.bin" <<'EOF' || fail "gfx1's screens differ between the kernels"
import sys
a, b = (open(f, 'rb').read() for f in sys.argv[1:3])
v = lambda d: d[len(d) - 132878:][:0x12C00]
n = sum(1 for x, y in zip(v(a), v(b)) if x != y)
print('ok    gfx1: both screens (76,800 bytes) equal from both kernels' if n == 0 else 'FAIL  %d bytes differ' % n)
sys.exit(1 if n else 0)
EOF
$PY - "$OUT/fx/fxfill/dump.bin" "$OUT/nofx/fxfill/dump.bin" <<'EOF' || fail "tests/fxfill.s: the screens differ between the kernels"
import sys
a, b = (open(f, 'rb').read() for f in sys.argv[1:3])
v = lambda d: d[len(d) - 132878:][:0x12C00]
n = sum(1 for x, y in zip(v(a), v(b)) if x != y)
ink = sum(bin(x).count('1') for x in v(a))
print('ok    300 random rectangles (spans long and short, mid-card edges, whole rows, either screen): '
      'both screens equal from both kernels (%d ink pixels)' % ink if n == 0 else 'FAIL  %d bytes differ' % n)
sys.exit(1 if n else 0)
EOF
t() { sed -n 's/.*full-screen fill (38,400 bytes): \([0-9.]*\) ms/\1/p' "$OUT/$1-gfx1.log"; }
fx=$(t fx)
plain=$(t nofx)
echo "      full-screen fill: $fx ms with FX, $plain ms without"
$PY -c "import sys; sys.exit(0 if float('$fx') < float('$plain') / 2 else 1)" || fail "FX is not faster"
ok "FX fills: the full-screen fill takes less than half the time"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"     # (build/: the FX kernel again)
echo "GATE fx: PASS"
