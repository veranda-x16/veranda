#!/bin/bash
# Gate desk (docs/PLAN.md phase 9, 4.6): desk accessories and the
# application swap.
#
#   tools/gate_desk.sh          (DESK_SD=0: skip the SD card run)
#
# 1. the SDK installed; apps/calc (the Calculator, a desk accessory in
#    C: type DESK_ACC) and Paint built against it, both as test builds:
#    Paint plays tests/desk_script.h, the Calculator tests/calc_script.h
# 2. Paint (AUTOSTART.cvt) draws, opens options/accessory: the list of
#    desk accessories, OPEN; GetFile puts Paint aside (its RAM, zero page,
#    stack, system variables, bank U, VRAM, processes ...) and starts the
#    Calculator over Paint's screen; it is clicked (12 + 30 = 42) and
#    typed into (* 2 Return: 84), and its close box ends it (RstrAppl)
# 3. tests/check_desk.py: the console in order; both screens when GetFile
#    returned equal those when the accessory opened; afterwards Paint
#    draws a filled rectangle with the tool and pattern chosen before,
#    and nothing else changed
# 4. a screenshot with the Calculator open (calc.png; check_vera.py): the
#    colour map hidden while it runs, the composed display black on white
#    (DECISIONS V33); the map is back after (3.)
# 5. the same session on an SD card image
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/desk
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
TOP=$(pwd)
for s in desk calc; do
	$PY tests/${s}_script.py "$OUT/$s.h" && cmp -s "$OUT/$s.h" tests/${s}_script.h \
		|| fail "tests/${s}_script.h is not what tests/${s}_script.py writes"
done

mkdir -p "$OUT/calc" "$OUT/paint"
make -s -C apps/calc SDK="$SDK" OUT="$TOP/$OUT/calc" >"$OUT/calc/build.log" 2>&1 \
	|| { cat "$OUT/calc/build.log"; fail "the Calculator does not build"; }
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
C=$OUT/calc/Calculator.cvt
[ "$(field "$C" 'geos type')" = 5 ] && [ "$(field "$C" structure)" = sequential ] && [ "$(field "$C" mode)" = keep ] \
	|| fail "Calculator.cvt: not a sequential DESK_ACC that keeps the mode"
ok "the Calculator builds against the installed SDK: a desk accessory (DESK_ACC), $(field "$C" load)-$(field "$C" end)"
make -s -C apps/calc test SDK="$SDK" OUT="$TOP/$OUT/calc" >"$OUT/calc/test.log" 2>&1 \
	|| { cat "$OUT/calc/test.log"; fail "the Calculator's test build"; }
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$OUT/paint" TESTFLAGS=-DPAINT_DESK >"$OUT/paint/build.log" 2>&1 \
	|| { cat "$OUT/paint/build.log"; fail "Paint's test build"; }

# run $1 (Paint) with the accessory $2 in folder $3, $4 seconds at most
run() {
	mkdir -p "$3"
	cp "$1" "$3/AUTOSTART.cvt"
	cp "$2" "$3/Calculator.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$3/"
	(cd "$3" && SDL_VIDEODRIVER=dummy timeout -s INT "$4" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
R=$OUT/run
run "$OUT/paint/Paint.cvt" "$C" "$R" 120
[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "the session did not finish"; }
$PY tools/check_vera.py "$R/dump.bin" || fail "the display"
$PY tools/vram2png.py "$R/dump.bin" "$OUT/after.png" 2>/dev/null || true
echo "== the session on the host folder"
$PY tests/check_desk.py "$R" || fail "the session (host folder)"

# a screenshot with the Calculator open (its script stopped there)
shot=$(sed -n 's|^/\* shot calc \([0-9]*\) \*/|\1|p' tests/calc_script.h)
T=$OUT/shot
mkdir -p "$T"
make -s -C apps/calc test SDK="$SDK" OUT="$TOP/$T" TESTFLAGS=-DCALC_STOP=$shot >"$OUT/shot.log" 2>&1 \
	|| { cat "$OUT/shot.log"; fail "the Calculator's test build (stopped at $shot)"; }
run "$OUT/paint/Paint.cvt" "$T/Calculator.cvt" "$T/run" 60
[ -f "$T/run/dump.bin" ] || fail "no dump with the Calculator open"
$PY tools/check_vera.py "$T/run/dump.bin" || fail "the display with the Calculator open"
$PY tools/vram2png.py --color "$T/run/dump.bin" "$OUT/calc.png" 2>/dev/null || true
grep -q "CALC = 84" "$T/run/console.txt" || fail "the Calculator's session (stopped) did not get to 84"
$PY tests/check_desk.py --calc "$T/run/dump.bin" || fail "the Calculator in the normal colours"
ok "a screenshot with the Calculator open over Paint: $OUT/calc.png"

if [ "${DESK_SD:-1}" != 0 ]; then
	S=$OUT/sd
	mkdir -p "$S/card" "$S/out"
	cp "$OUT/paint/Paint.cvt" "$S/card/AUTOSTART.cvt"
	cp "$C" "$S/card/Calculator.cvt"
	cp build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: the session did not finish"; }
	mv "$S/dump.bin" "$S/out/"
	for f in PRE.RAW POST.RAW PRE.MAP POST.MAP; do
		$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null || fail "SD card: no $f"
	done
	echo "== the same on an SD card image"
	$PY tests/check_desk.py "$S/out" || fail "the session (SD card)"
fi
echo "screenshots: $OUT/calc.png (the Calculator over Paint), after.png (the end)"
echo "GATE desk: PASS"
