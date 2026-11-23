#!/bin/bash
# Gate bar (DECISIONS V120): the menu bar's clock and sound clicked open
# Preferences, in the shell and in a native program, through the X16's
# real mouse path (the emulator's -mousescript, tests/bar_script.py) on an
# SD card image in V71's layout, under R49, 512 KB.
#
#   tools/gate_bar.sh        (MEMU: an x16emu with -mousescript and keydown;
#                             ROM: default R49's release image)
#
# 1. the kernel, the SDK, the shell, Preferences and Paint (release builds)
# 2. boot: the desktop; the bar's speaker found in its picture (bar-boot.png)
# 3. clock: the clock clicked in the shell: Preferences with the Date and
#    Time rows marked (the console's PREFS CLOCK ROWS; the rows' cards in
#    the highlight colour), bar-clock.png
# 4. time: then the hour's > and Set clock, Esc: the clock set (PREFS
#    CLOCK SET hh:mm), the kernel's time (hour, minutes in the dump) the
#    one set, Preferences closed (deskNote 0 again)
# 5. popup: the speaker clicked: the volume pop-up (PREFS POPUP), its
#    picture bar-popup.png
# 6. volume: the knob dragged from 63 to about 20 (PREFS VOLUME n), Mute
#    (PREFS VOLUME MUTED n), a click outside: saved (PREFS SAVED VOLUME),
#    closed; the screen as before the pop-up (run boot) pixel for pixel
#    but the bar's sound and clock, the speaker now crossed out
#    (bar-volume.png); on the card "Veranda Prefs.cvt" in /VERANDA/.SYSTEM
#    with the volume and the sounds off; the kernel's kPrefs, kSndAtt
# 7. restart: Veranda started again from that card: the settings read
#    back (kPrefs bit 7, kSndAtt 63 - the volume), the speaker crossed out from the
#    start (bar-restart.png)
# 8. Paint (AUTOSTART.cvt in /VERANDA): the clock clicked: Preferences
#    over Paint (bar-prefs-paint.png); Esc; the speaker: the pop-up; Esc
set -e -o pipefail
cd "$(dirname "$0")/.."
OUT=build/gate/bar
PY="python3 -I -B"
MEMU=${MEMU:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
[ -f "$R49" ] || R49=$HOME/Projects/x16-rom/build/x16/rom.bin
ROM=${ROM:-$R49}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

if ! { "$MEMU" -help 2>&1 || true; } | grep -q -- -mousescript \
	|| ! grep -q keydown "$(dirname "$MEMU")/../src/mousescript.c" 2>/dev/null; then
	echo "SKIP  $MEMU has no -mousescript with keydown (branch mousescript-keys)"
	echo "GATE bar: SKIP"
	exit 0
fi
rm -rf "$OUT"
mkdir -p "$OUT"
TOP=$(pwd)
echo "      ROM: $ROM"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
cp -r shell "$OUT/shell"
rm -f "$OUT/shell"/*.cvt "$OUT/shell"/*.bin "$OUT/shell"/*.map
make -s -C "$OUT/shell" SDK="$SDK" >"$OUT/shell.log" 2>&1 || { cat "$OUT/shell.log"; fail "the shell does not build"; }
for a in prefs paint; do
	mkdir -p "$OUT/b-$a"
	make -s -C "apps/$a" SDK="$SDK" OUT="$TOP/$OUT/b-$a" >"$OUT/$a.log" 2>&1 || { cat "$OUT/$a.log"; fail "apps/$a"; }
done
ok "the kernel, the shell, Preferences and Paint build"
LAB=build/k/resident.lab
lab() { printf '%d' "0x$(sed -n "s/^al 00\([0-9A-F]*\) \.$1\$/\1/p" "$LAB")"; }
KPREFS=$(lab kPrefs)
KSNDATT=$(lab kSndAtt)

# run $1 (tests/bar_script.py's), speaker at $2, Paint as AUTOSTART if $3;
# $4: a card image to use (else made); the dump and console in $OUT/$1
run() {
	local d=$OUT/$1
	rm -rf "$d"
	mkdir -p "$d/card/VERANDA/APPS" "$d/card/VERANDA/.SYSTEM" "$d/card/DOCUMENTS"
	if [ -n "$4" ]; then
		mv "$4" "$d/sd.img"
	else
		cp build/VERANDA.PRG build/VERANDA.SYS "$OUT/shell/SHELL.cvt" "$d/card/VERANDA/"
		cp "$OUT/b-prefs/Preferences.cvt" "$OUT/b-paint/Paint.cvt" "$d/card/VERANDA/APPS/"
		[ -n "$3" ] && cp "$OUT/b-paint/Paint.cvt" "$d/card/VERANDA/AUTOSTART.cvt"
		echo "V71" > "$d/card/VERANDA/.SYSTEM/LAYOUT.LOG"
		$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || fail "vcard make"
	fi
	$PY tests/bar_script.py "$1" "$2" > "$d/mouse.txt" || fail "tests/bar_script.py $1"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$MEMU" -rom "$ROM" -sdcard sd.img -ram 512 \
		-warp -sound none -echo -mousescript mouse.txt -dump RV > console.txt 2>&1) || true
	[ -f "$d/dump.bin" ] || { tr -d '\r' < "$d/console.txt" | tail -20; fail "$1: no dump (the script did not end)"; }
	! grep -a -q 'BDIZC' "$d/console.txt" || { tail -20 "$d/console.txt"; fail "$1: the ROM's monitor (a BRK)"; }
	$PY tools/vram2png.py --color "$d/dump.bin" "$OUT/bar-$1.png" >/dev/null || fail "$1: vram2png"
}
has() { tr -d '\r' < "$OUT/$1/console.txt" | grep -a -q "$2" || { tr -d '\r' < "$OUT/$1/console.txt" | grep -a "PREFS\|SHELL" | tail -12; fail "$1: no \"$2\" in the console"; }; }
dumpb() { $PY -c 'import sys; d = open(sys.argv[1], "rb").read(); print(d[int(sys.argv[2])])' "$OUT/$1/dump.bin" "$2"; }

# the speaker's left in the bar of run $1 (its rows 6-9: $7F $08, or
# crossed out: $7F $24 / $18), and which
speaker() {
	$PY - "$OUT/$1/dump.bin" <<-'EOF'
	import sys
	sys.path.insert(0, 'tools')
	from vram2png import section
	v = section(sys.argv[1])
	row = lambda y, c: (v[y * 80 + c], v[y * 80 + c + 1])
	for c in range(40, 79):
	    if [row(y, c) for y in range(6, 10)] == [(0x7F, 0x08)] * 4:
	        print(c * 8, 'sound'); break
	    if [row(y, c) for y in range(6, 10)] == [(0x7F, 0x24), (0x7F, 0x18), (0x7F, 0x18), (0x7F, 0x24)]:
	        print(c * 8, 'muted'); break
	else:
	    print(0, 'none')
	EOF
}

run boot 0
read -r SX KIND <<<"$(speaker boot)"
[ "$KIND" = sound ] || fail "boot: no speaker in the bar ($KIND)"
ok "boot (R49, 512 KB, the card in V71's layout): the desktop, the bar's speaker at x $SX: $OUT/bar-boot.png"

run clock "$SX"
has clock "PREFS RUNNING"
has clock "PREFS CLOCK ROWS"
has clock "PREFS CLOCK UNSET"
# the Date and Time rows' label cards (x 88-255, y 328-375: cards 11-31,
# rows 41-46) in the highlight colour (the colour map: not 0)
$PY - "$OUT/clock/dump.bin" <<-'EOF' || fail "clock: the Date and Time rows are not marked"
	import sys
	sys.path.insert(0, 'tools')
	from vram2png import section
	v = section(sys.argv[1])
	c = {v[0x1AC00 + r * 256 + x * 2 + 1] >> 4 for r in range(41, 47) for x in range(11, 32)}
	assert len(c) == 1 and 0 not in c, c
	EOF
ok "the clock clicked in the shell: Preferences over it, the Date and Time rows marked; the clock reads 2000: \"The clock is not set\" (V127): $OUT/bar-clock.png"

run time "$SX"
has time "PREFS CLOCK SET"
has time "PREFS CLOCK TOOK IT"
has time "PREFS CLOSED"
set=$(tr -d '\r' < "$OUT/time/console.txt" | grep -a -o "PREFS CLOCK SET [0-9:]*" | head -1 | sed 's/.* //')
h=$(dumpb time $((0x0552)))
m=$(dumpb time $((0x0553)))
[ "$(dumpb time $((0x057D)))" = 0 ] || fail "time: deskNote not cleared"
$PY -c 'import sys; h, m = map(int, sys.argv[1].split(":")); t = h * 60 + m; k = int(sys.argv[2]) * 60 + int(sys.argv[3]); sys.exit(0 if 0 <= k - t <= 1 else 1)' \
	"$set" "$h" "$m" || fail "time: the kernel's time $h:$m is not the one set ($set)"
ok "then the hour's >, Return (Save sets the clock, V127), Esc: the clock set to $set and read back (the kernel's time $h:$m), Preferences closed, deskNote 0"

# (V127) the day picked by the bar's clock, typed into: 21 11 2026 0945,
# Up: 09:46; Return; the kernel's date and time
run typed "$SX"
has typed "PREFS CLOCK SET 09:46"
has typed "PREFS CLOCK TOOK IT"
dt=$($PY -c 'import sys; d = open(sys.argv[1], "rb").read(); print(*d[0x54F:0x554])' "$OUT/typed/dump.bin")
read -r Y MO D H MI <<<"$dt"
[ "$Y $MO $D $H" = "26 11 21 9" ] && [ "$MI" -ge 46 ] && [ "$MI" -le 47 ] \
	|| fail "typed: the kernel's date and time $dt, not 26 11 21 9 46"
ok "typed (V127): 21, 11, 2026, 0945 into the picked parts, Up, Return: the clock set to 2026-11-21 09:46 and read back (the kernel's $dt): $OUT/bar-typed.png"

run now "$SX"
has now "PREFS CLOCK NOW"
! tr -d '\r' < "$OUT/now/console.txt" | grep -a -q "PREFS CLOCK SET" || fail "now: the clock was set"
[ "$(dumpb now $((0x054F)))" = 0 ] || fail "now: the year changed"
ok "now (V127): the hour's > left it pending, Now put the clock's time back, Esc: the clock not set"

run tick "$SX"
has tick "PREFS CLOCK SET 09:45"
has tick "PREFS CLOCK TICK 09:4[6-7]"
ok "tick (V127): the rows not edited tick with the clock (set to 09:45, a minute later 09:46): $OUT/bar-tick.png"

run popup "$SX"
has popup "PREFS POPUP 392"
has popup "PREFS VOLUME 63"
ok "the speaker clicked: the volume pop-up under it (x 392, y 16), 63: $OUT/bar-popup.png"

run volume "$SX"
N=$(tr -d '\r' < "$OUT/volume/console.txt" | grep -a -o "PREFS VOLUME [0-9][0-9]*" | tail -1 | sed 's/.* //')
[ -n "$N" ] && [ "$N" -ge 15 ] && [ "$N" -le 25 ] || fail "volume: the knob dragged to $N, not about 20"
has volume "PREFS VOLUME MUTED $N"
has volume "PREFS SAVED VOLUME"
has volume "PREFS CLOSED"
read -r SX2 KIND <<<"$(speaker volume)"
[ "$KIND" = muted ] && [ "$SX2" = "$SX" ] || fail "volume: the bar's speaker is not crossed out ($KIND at $SX2)"
# the screen as before the pop-up (run boot) but the bar's sound and clock
$PY - "$OUT/boot/dump.bin" "$OUT/volume/dump.bin" "$SX" <<-'EOF' || fail "volume: the screen under the pop-up did not come back: $OUT/bar-boot.png, $OUT/bar-volume.png"
	import sys
	sys.path.insert(0, 'tools')
	from vram2png import section, compose
	a, b = (compose(section(f)) for f in sys.argv[1:3])
	sx = int(sys.argv[3])
	bad = [(x, y) for y in range(480) for x in range(640) if a[y][x] != b[y][x] and not (y < 15 and x >= sx)]
	if bad:
	    xs, ys = [p[0] for p in bad], [p[1] for p in bad]
	    print(len(bad), 'pixels differ in', min(xs), min(ys), max(xs), max(ys))
	    sys.exit(1)
	EOF
$PY tools/vcard.py get "$OUT/volume/sd.img" "VERANDA/.SYSTEM/Veranda Prefs.cvt" "$OUT/prefs.cvt" >/dev/null \
	|| fail "volume: no Veranda Prefs.cvt in /VERANDA/.SYSTEM"
$PY - "$OUT/prefs.cvt" "$N" <<-'EOF' || fail "volume: the settings file"
	import sys
	d = open(sys.argv[1], 'rb').read()
	b = d[508:508 + 16]
	n = int(sys.argv[2])
	assert len(b) == 16 and b[15] == 0x80 | (63 - n) and b[6] & 0x80, list(b)
	print('      Veranda Prefs.cvt: byte 6 $%02X (the sounds off), byte 15 $%02X (PREFS_VOLSET + 63 - %d)' % (b[6], b[15], n))
	EOF
[ "$(( $(dumpb volume "$KPREFS") & 128 ))" = 128 ] && [ "$(dumpb volume "$KSNDATT")" = $((63 - N)) ] \
	|| fail "volume: kPrefs $(dumpb volume "$KPREFS"), kSndAtt $(dumpb volume "$KSNDATT")"
ok "the knob dragged to $N, Mute, a click outside: saved, closed; the screen as before pixel for pixel but the bar's right, the speaker crossed out: $OUT/bar-volume.png"

mv "$OUT/volume/sd.img" "$OUT/card.img"
run boot2 "$SX" "" "$OUT/card.img"
read -r SX3 KIND <<<"$(speaker boot2)"
cp "$OUT/bar-boot2.png" "$OUT/bar-restart.png"
[ "$KIND" = muted ] || fail "restart: the speaker is not crossed out ($KIND)"
[ "$(( $(dumpb boot2 "$KPREFS") & 128 ))" = 128 ] && [ "$(dumpb boot2 "$KSNDATT")" = $((63 - N)) ] \
	|| fail "restart: kPrefs $(dumpb boot2 "$KPREFS"), kSndAtt $(dumpb boot2 "$KSNDATT")"
ok "Veranda started again from that card: the sounds off and the volume $N read back, the speaker crossed out: $OUT/bar-restart.png"

run paintclk "$SX" paint
has paintclk "PREFS CLOCK ROWS"
cp "$OUT/bar-paintclk.png" "$OUT/bar-prefs-paint.png"
run paint "$SX" paint
has paint "PREFS CLOCK ROWS"
has paint "PREFS POPUP 392"
[ "$(tr -d '\r' < "$OUT/paint/console.txt" | grep -a -c "PREFS CLOSED")" = 2 ] || fail "paint: Preferences not closed twice"
ok "in Paint: the clock clicked: Preferences over Paint ($OUT/bar-prefs-paint.png), Esc; the speaker: the pop-up, Esc"
rm -f "$OUT"/*/sd.img
echo "GATE bar: PASS"
