#!/bin/bash
# Gate audio (DECISIONS V52): VERA's PCM fed from the AFLOW interrupt
# through intFirstVector (V41), and the kernel's audio guards.
#
#   tools/gate_audio.sh         (AUDIO_SD=0: skip the SD card runs)
#
# tests/audio/main.c with tests/audio/aud.s (a synthetic mixer: BURN cycles
# a frame of fake mixing, 1024-frame batches with interrupts on):
# 1. 0 underruns while Veranda fills the screen, copies half of it
#    (CopyRect), writes it full of PutCards and reads 64 KB, at BURN 62
#    (332 cycles a frame, 66 % of the CPU) and BURN 82 (432, 87 %), on the
#    host folder and on an SD card image; the slowdowns logged
# 2. VSYNC kept: a vr_set_irq routine counts the frames of 8 M cycles
#    (134,584 cycles a frame), within one
# 3. an accessory opened while it plays (K2, DaRun): AFLOW is off while
#    the accessory runs; back, it plays on with 0 underruns
# 4. a quit with AFLOW on and the routine set (K3, LdApplic): the next
#    program (DESKTOP.cvt, V46) finds AFLOW off, the FIFO empty, the
#    vector clear, and its main loop runs (no interrupt storm)
# 5. control: a kernel built with -D NO_AUDIO_GUARD fails 3 and 4 (V91: or
#    3 alone, the machine stuck in AFLOW's storm before the accessory)
# Audio gates run with sound on through SDL's dummy driver: under
# -sound none the emulator never drains the FIFO, so AFLOW never fires.
# The results: build/gate/audio.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/audio
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
T=tests/audio
CC="cl65 -t none --cpu 65C02 -O -I $SDK/include"

build() {       # build <dir> <name> <hdr> <sources...>
	local d=$1 n=$2 h=$3
	shift 3
	$CC -C "$SDK/cfg/app-c.cfg" -o "$d/$n.bin" "$@" "$SDK/lib/veranda.lib" >"$d/$n.log" 2>&1 \
		|| { cat "$d/$n.log"; fail "$n does not build"; }
	(cd $T && $PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OLDPWD/$d/$n.cvt" "$(basename "$h")" "$OLDPWD/$d/$n.bin") \
		>/dev/null || fail "$n does not pack"
}
B=$OUT/bin
mkdir -p "$B"
for burn in 62 82; do
	build "$B" app$burn $T/app.hdr -DBURN=$burn $T/main.c $T/aud.s
done
build "$B" AudDA $T/da.hdr $T/da.c
build "$B" AudChk $T/chk.hdr $T/chk.c
head -c 65536 /dev/urandom > "$B/data.bin"
ok "the test application (BURN 62, 82), its accessory and the checking desktop build against the SDK"

stage() {       # stage <dir> <burn>: the card's or folder's files
	mkdir -p "$1"
	cp "$B/app$2.cvt" "$1/AUTOSTART.cvt"
	cp "$B/AudDA.cvt" "$B/AudChk.cvt" "$B/data.bin" "$1/"
	mv "$1/AudChk.cvt" "$1/DESKTOP.cvt"
}
waitfor() {     # waitfor <console> <text> <seconds> <pid>
	local i=0
	while [ $i -lt $(($3 * 4)) ]; do
		grep -q "$2" "$1" 2>/dev/null && return 0
		kill -0 "$4" 2>/dev/null || return 1
		sleep 0.25
		i=$((i + 1))
	done
	return 1
}
runit() {       # runit <dir> <kernel dir> [sd] [seconds]: until the desktop's main loop, at most 120 s
	local d=$1 k=$2 sd=$3 secs=${4:-120}
	cp "$k/VERANDA.PRG" "$d/"
	[ -n "$sd" ] || cp "$k/VERANDA.SYS" "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy exec "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -echo ${sd:+-sdcard sd.img} > console.txt 2>&1) &
	local pid=$!
	waitfor "$d/console.txt" "AUDCHK MAINLOOP" $secs $pid || true
	sleep 0.5
	kill $pid 2>/dev/null || true
	wait $pid 2>/dev/null || true
}
val() { sed -n "s/^.*AUD $2 \([0-9]*\).*/\1/p" "$1/console.txt" | tail -1; }
K=$OUT/kernel
mkdir -p "$K"
cp build/VERANDA.PRG build/VERANDA.SYS "$K/"

check() {       # check <dir> <label>
	local d=$1 c=$1/console.txt
	grep -q "AUD QUIT" "$c" || { tail -5 "$c"; fail "$2: the session did not reach its quit"; }
	[ "$(val "$d" underruns)" = 0 ] || fail "$2: $(val "$d" underruns) underruns while Veranda drew and read"
	local bt; bt=$(val "$d" batches)
	[ "$bt" -ge 20 ] || fail "$2: only $bt batches"
	local vs vc ve; vs=$(val "$d" vsyncs); vc=$(val "$d" vsync_cycles)
	ve=$($PY -c "print('%.1f' % ($vc / 134584))")
	$PY -c "import sys; sys.exit(0 if abs($vs - $vc / 134584) <= 1.0 else 1)" \
		|| fail "$2: $vs VSYNCs in $vc cycles ($ve expected)"
	grep -q "AUDDA AFLOW OFF" "$c" || fail "$2: AFLOW was on while the accessory ran"
	[ "$(val "$d" da_ret)" = 0 ] || fail "$2: GetFile of the accessory returned $(val "$d" da_ret)"
	[ "$(val "$d" da_batches_after)" -gt 0 ] || fail "$2: no batches after the accessory"
	[ "$(val "$d" da_underruns)" = 0 ] || fail "$2: underruns around the accessory"
	grep -q "AUDCHK AFLOW OFF" "$c" || fail "$2: the quit left AFLOW on"
	grep -q "AUDCHK FIFO EMPTY" "$c" || fail "$2: the quit left the FIFO with data"
	grep -q "AUDCHK VECTOR CLEAR" "$c" || fail "$2: the quit left intFirstVector set"
	grep -q "AUDCHK MAINLOOP" "$c" || fail "$2: the desktop's main loop does not run"
	local q p
	echo "      $2: $bt batches, 0 underruns, $vs VSYNCs in $vc cycles ($ve frames); slowdown while playing:"
	for m in fill copy cards read64k; do
		q=$(sed -n "/AUD quiet/,/AUD playing/s/^.*AUD ${m}_cyc \([0-9]*\).*/\1/p" "$c")
		p=$(sed -n "/AUD playing/,\$s/^.*AUD ${m}_cyc \([0-9]*\).*/\1/p" "$c")
		printf "        %-8s %10d -> %10d cycles (x%s)\n" $m "$q" "$p" "$($PY -c "print('%.2f' % ($p / $q))")"
	done
}

for burn in 62 82; do
	H=$OUT/host$burn
	stage "$H" $burn
	runit "$H" "$K"
	check "$H" "host folder, BURN $burn"
done
ok "host folder: 0 underruns at 66 % and 87 % of the CPU; VSYNC kept; AFLOW off for an accessory and after a quit"

if [ "${AUDIO_SD:-1}" != 0 ]; then
	for burn in 62 82; do
		S=$OUT/sd$burn
		stage "$S/card" $burn
		cp build/VERANDA.SYS "$S/card/"
		$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
		runit "$S" "$K" sd
		check "$S" "SD card, BURN $burn"
	done
	ok "SD card image: the same"
fi

# the control: no guards in DaRun, LdApplic, StateReset
$PY tools/kbuild.py -D NO_AUDIO_GUARD >/dev/null || fail "the control kernel does not build"
N=$OUT/control
mkdir -p "$N/kernel"
cp build/VERANDA.PRG build/VERANDA.SYS "$N/kernel/"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"     # (build/: the real one again)
stage "$N/run" 62
runit "$N/run" "$N/kernel" "" 40
# (V91: DaRun stops the application's interrupt routines before it packs
# it; without the guard AFLOW then storms from there and the accessory
# never starts: that fails 3 as well as AFLOW on in the accessory would)
if grep -q "AUDDA AFLOW ON" "$N/run/console.txt"; then
	grep -q "AUDCHK MAINLOOP" "$N/run/console.txt" && fail "control: without the guard the quit left a working desktop"
	ok "control (-D NO_AUDIO_GUARD): AFLOW stays on in the accessory, and after the quit the desktop never runs"
else
	grep -q "AUDDA" "$N/run/console.txt" && fail "control: without the guard AFLOW was off in the accessory too"
	ok "control (-D NO_AUDIO_GUARD): with AFLOW left on, the accessory never starts (the interrupt storm from DaRun's packing on)"
fi
echo "GATE audio: PASS"
