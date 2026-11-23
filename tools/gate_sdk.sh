#!/bin/bash
# Gate sdk (docs/PLAN.md phase 5): the SDK, installed, builds applications.
#
#   tools/gate_sdk.sh
#
# 1. make api, the kernel, tools/mksdk.sh into build/sdk
# 2. both templates (C, assembly) built against the INSTALLED copy only
#    (copied out of the tree, SDK=build/sdk: no build/gen, no inc/)
# 3. each CVT: type APPLICATION, its class, load and start $0801, VRND,
#    API level 1, mode 640x480 (tools/vpack.py --list)
# 4. the C program's map: cc65's zero page within $A9-$FF, nothing at or
#    above $8800
# 5. they run: the kernel's loader starts each CVT (as AUTOSTART.cvt) and it
#    logs its line; a C test of the callbacks (as TEST.PRG)
#    (tests/sdk_irq.c: a C function in the interrupt, one as appMain)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/sdk
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
ok "the SDK installs ($OUT/sdk)"

# field value from vpack --list
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }

check_cvt() {           # cvt class
	[ "$(field "$1" 'geos type')" = 6 ] || fail "$1: not an APPLICATION"
	[ "$(field "$1" class)" = "$2" ] || fail "$1: class $(field "$1" class)"
	[ "$(field "$1" load)" = '$0801' ] && [ "$(field "$1" start)" = '$0801' ] || fail "$1: load or start"
	[ "$(field "$1" veranda)" = True ] && [ "$(field "$1" api)" = 1 ] || fail "$1: no VRND or API level 1"
	[ "$(field "$1" mode)" = 640x480 ] || fail "$1: mode"
	end=$(field "$1" end)
	[ $((16#${end#\$})) -le $((16#8800)) ] || fail "$1: ends at $end"
}

# run a raw program ($0801) as TEST.PRG; $2: the line it must log
run_raw() {
	d=$(dirname "$1")/run
	mkdir -p "$d"
	$PY -c "import sys; d=open(sys.argv[1],'rb').read(); open(sys.argv[2],'wb').write(bytes([1,8])+d)" "$1" "$d/TEST.PRG"
	cp build/VERANDA.PRG build/VERANDA.SYS "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 20 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo > console.txt 2>&1) || true
	grep -q "$2" "$d/console.txt" || { tail -3 "$d/console.txt"; fail "$1 did not log \"$2\""; }
}

for t in c asm; do
	W=$OUT/$t
	cp -r "$SDK/template/$t" "$W"
	make -s -C "$W" SDK="$SDK" >"$W/build.log" 2>&1 || { cat "$W/build.log"; fail "template $t does not build"; }
	grep -q -e "build/gen" -e "/inc " "$W/build.log" && fail "template $t used the source tree"
	check_cvt "$W/app.cvt" "$([ $t = c ] && echo 'HelloC      V1.0' || echo 'HelloAsm    V1.0')"
	ok "template $t: builds against the installed SDK; its CVT is a Veranda application (\$0801, API 1)"
done

M=$OUT/c/app.map
zp=$(sed -n 's/^ZEROPAGE *\(00[0-9A-F]*\) *\(00[0-9A-F]*\).*/\1 \2/p' "$M" | head -1)
set -- $zp
[ $((16#$1)) -ge $((16#A9)) ] && [ $((16#$2)) -le $((16#FF)) ] || fail "cc65's zero page at $1-$2"
top=$(sed -n '/^Segment list/,/^$/s/^[A-Z]* *[0-9A-F]* *\([0-9A-F]*\).*/\1/p' "$M" | sort | tail -1)
[ $((16#$top)) -lt $((16#8800)) ] || fail "the C program reaches \$$top"
ok "C: cc65's zero page at \$$1-\$$2; the program ends at \$$top (below \$8800)"

# run an application CVT through the loader: VERANDA.PRG starts it as
# AUTOSTART.cvt (docs/APPFORMAT.md); $2: the line it must log
run_cvt() {
	d=$(dirname "$1")/runcvt
	rm -rf "$d"
	mkdir -p "$d"
	cp "$1" "$d/AUTOSTART.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 20 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo > console.txt 2>&1) || true
	grep -q "$2" "$d/console.txt" || { tail -3 "$d/console.txt"; fail "$1 did not log \"$2\" (loaded as AUTOSTART.cvt)"; }
}
run_cvt "$OUT/c/app.cvt" "TEMPLATE C RUNNING"
run_cvt "$OUT/asm/app.cvt" "TEMPLATE ASM RUNNING"
ok "both templates load and start through the kernel's loader (AUTOSTART.cvt) and log their line"

T=$OUT/irq
mkdir -p "$T"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$T/app.bin" tests/sdk_irq.c \
	"$SDK/lib/veranda.lib" || fail "tests/sdk_irq.c does not build"
run_raw "$T/app.bin" "SDK IRQ OK"
ok "C callbacks: a C function in the interrupt (vr_set_irq) and one as appMain"
# a VLIR application: its overlay (record 1) read into banks at the start,
# copied to $4000 by LoadOverlay and called
O=$OUT/ovl
mkdir -p "$O"
ca65 --cpu 65C02 -I "$SDK/include" -o "$O/main.o" tests/ovl/main.s || fail "tests/ovl/main.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$O/main.bin" "$O/main.o" || fail "tests/ovl/main.s does not link"
ca65 --cpu 65C02 -I "$SDK/include" -o "$O/one.o" tests/ovl/one.s || fail "tests/ovl/one.s"
ld65 -C tests/ovl/one.cfg -o "$O/one.bin" "$O/one.o" || fail "tests/ovl/one.s does not link"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$O/app.cvt" tests/ovl/app.hdr "$O/main.bin" "$O/one.bin" >/dev/null \
	|| fail "vpack (VLIR)"
run_cvt "$O/app.cvt" "OVL ONE"
grep -q "OVL OK" "$O/runcvt/console.txt" || { tail -3 "$O/runcvt/console.txt"; fail "the overlay application"; }
ok "a VLIR application: its overlay loaded (LoadOverlay) and called; a missing record is INV_RECORD"
# C overlays that run in place (API 2): sdk/cfg/app-c-ovl.cfg, each record
# at $A000 of a bank of its own (app.hdr: overlays = banked), mapped by a
# store to $00; they call the kernel and a resident routine that maps
# another bank (tests/ovlc)
O=$OUT/ovlc
mkdir -p "$O"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c-ovl.cfg" -m "$O/app.map" -o "$O/app.bin" \
	tests/ovlc/main.c tests/ovlc/one.c tests/ovlc/two.c "$SDK/lib/veranda.lib" || fail "tests/ovlc does not build"
[ -s "$O/app.bin.1" ] && [ -s "$O/app.bin.2" ] || fail "tests/ovlc: no overlay files"
zp=$(sed -n 's/^ZEROPAGE *\(00[0-9A-F]*\) *\(00[0-9A-F]*\).*/\1 \2/p' "$O/app.map" | head -1)
set -- $zp
[ $((16#$1)) -ge $((16#50)) ] && [ $((16#$2)) -le $((16#7F)) ] || fail "app-c-ovl.cfg: cc65's zero page at $1-$2"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$O/app.cvt" tests/ovlc/app.hdr "$O/app.bin" "$O/app.bin.1" "$O/app.bin.2" >/dev/null \
	|| fail "vpack (banked overlays)"
[ "$(field "$O/app.cvt" flags)" = 1 ] && [ "$(field "$O/app.cvt" api)" = 2 ] || fail "vpack: flags or API level"
run_cvt "$O/app.cvt" "OVLC 0175 [0-9A-F]* OK"
for l in "OVLC ONE" "OVLC TWO" "OVLC ONE AGAIN"; do
	grep -q "^$l" "$O/runcvt/console.txt" || fail "tests/ovlc: no \"$l\""
done
ok "C overlays in place: two records at \$A000 in consecutive banks, run there; they call the kernel and a heap accessor; their data stays (cc65's zero page at \$$1-\$$2)"
# a C program with a menu and a dialog box, played by a script
U=$OUT/cui
mkdir -p "$U"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" --asm-include-dir "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$U/app.bin" tests/sdk_ui.c \
	tests/sdk_play.s "$SDK/lib/veranda.lib" || fail "tests/sdk_ui.c does not build"
run_raw "$U/app.bin" "C PRESS AFTER THE BOX"
grep -q "C DIALOG 01 AC$" "$U/run/console.txt" || fail "tests/sdk_ui.c: no \"C DIALOG 01 AC\""
ok "C: a menu action opens a dialog box; the script types A, B, Backspace, C into its field and presses OK; DoDlgBox returns OK to C, the field's text \"AC\" 0-terminated (V39); a press where its OK icon was reaches otherPressVec (V40)"
echo "GATE sdk: PASS"
