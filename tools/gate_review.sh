#!/bin/bash
# Gate review (DECISIONS V68): the findings of the kernel review, each a
# test that failed before its fix.
#
#   tools/gate_review.sh [test ...]     (default: all; KDIR=dir: the kernel
#                                        from dir/VERANDA.PRG and .SYS, not
#                                        built: an older kernel's results)
#
#   flash   a dialog box (the program's, from keyVector) opened inside a
#           menu's and an icon's flash: each action runs once, after the
#           box; nothing jumps into a menu table (tests/review_flash.s)
#   alarm   the alarm's box comes due inside a flash: it waits for it
#   leak    streams left open by a program (an SD card image): ten runs of
#           a program that opens three files and quits; the eleventh still
#           loads and opens files; a desk accessory's streams closed at
#           RstrAppl, the program's kept; more streams than the card's
#           four DOS contexts: TOO_MANY_FILES (tests/review_leak.s)
#   sprite  DrawSprite's picture address for all eight sprites
#   font    20 font sizes loaded: every handle still its font, the first
#           usable again; a record of 8193-8447 bytes gets two banks
#   rec     record files: WriteRecord at the end of its banks (to the
#           byte), OpenRecordFile with too few banks free (NO_BANKS, not a
#           write past them), UpdateRecordFile on a full card (an error,
#           the old file kept)
#   irq     the longest stretch with interrupts off during full-screen
#           fills (FX: fb_block), from the VSYNC interrupt's latency
#   wheel   wheel steps on frames the program does not read add up (put
#           into the ROM's wheel variable)
#   files   FindFTypes lists 16-character names and names with a dot
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/review
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}

ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; FAILED=1; }
die() { echo "FAIL  $*"; exit 1; }

mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || die "the API table"
if [ -z "$KDIR" ]; then
	$PY tools/kbuild.py > "$OUT/kbuild.txt" || die "the kernel does not build"
	cat "$OUT/kbuild.txt"
	KDIR=build
fi
echo "      kernel: $KDIR"

# tests/$1.s (with tests/ui.s if $3 is ui) -> $2/TEST.PRG, the kernel next to it; $4...: ca65 flags
prg() {
	local src=$1 d=$2 ui=$3
	shift 3
	rm -rf "$d"
	mkdir -p "$d"
	ca65 --cpu 65C02 -I build/gen -I inc "$@" "tests/$src.s" -o "$d/t.o" || die "tests/$src.s does not assemble"
	ca65 tests/prghdr.s -o "$d/prghdr.o"
	local o="$d/prghdr.o $d/t.o"
	if [ "$ui" = ui ]; then         # (its first byte the entry)
		ca65 --cpu 65C02 -I build/gen -I inc tests/ui.s -o "$d/ui.o"
		o="$d/prghdr.o $d/ui.o $d/t.o"
	fi
	ld65 -C cfg/testprg.cfg $o -o "$d/TEST.PRG" -Ln "$d/test.lab" || die "tests/$src.s does not link"
	cp "$KDIR/VERANDA.PRG" "$KDIR/VERANDA.SYS" "$d/"
}

# run $1 (host folder) for at most $2 seconds; $3: the dump (default V)
run() {
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$2" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump "${3:-V}" > console.txt 2>&1) || true
}

# run $1 on an SD card image made from $1/card (TEST.PRG and VERANDA.SYS
# in it); the card's files afterwards in $1/out
sdrun() {
	local d=$1
	cp "$KDIR/VERANDA.SYS" "$d/card/"
	[ -f "$d/sd.img" ] || $PY tools/vcard.py make --mb ${SDMB:-64} "$d/sd.img" "$d/card" >/dev/null || die "vcard make"
	cp "$KDIR/VERANDA.PRG" "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT "${2:-60}" "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
	mkdir -p "$d/out"
	$PY tools/vcard.py ls "$d/sd.img" | while read -r f size; do
		case "$f" in */) continue ;; esac
		mkdir -p "$d/out/$(dirname "$f")"
		$PY tools/vcard.py get "$d/sd.img" "$f" "$d/out/$f" >/dev/null
	done
}

# the console's lines that start with $2 (the emulator echoes DOS commands)
lines() { sed 's/^\\X0F//' "$1/console.txt" | grep -a "^\($2\)" || true; }

#---------------------------------------------------------------
t_flash() {
	echo "== flash: a dialog box inside a menu's and an icon's flash"
	local d=$OUT/flash
	prg review_flash "$d" ui
	run "$d" 60
	lines "$d" "ACT\|BOX\|FLASH" | sed 's/^/      /'
	local got
	got=$(lines "$d" "ACT\|BOX\|FLASH" | tr '\n' '|')
	local want="BOX|BOX END|ACT M 00|BOX|BOX END|ACT I 00|BOX|BOX END|ACT S 00|FLASH 01 01 01 "
	case "$got" in
	"$want"*) ;;
	*) fail "flash: not each action once after its box (want ${want//|/; })"; return ;;
	esac
	local on
	on=$(lines "$d" "FLASH" | awk '{print $5}')
	[ $((0x$on & 0x80)) -ne 0 ] || { fail "flash: the pointer is off at the end (mouseOn \$$on)"; return; }
	ok "flash: a box opened inside the flash of act, of the icon and of go (a sub menu): each runs once, after its box; the pointer on (mouseOn \$$on)"
}

t_flashsub() {
	local d=$OUT/flash-sub got
	prg review_flash "$d" ui -D SUB
	run "$d" 60
	lines "$d" "ACT\|BOX\|FLASH\|UI DONE" | sed 's/^/      /'
	got=$(lines "$d" "ACT\|BOX\|FLASH\|UI DONE" | tr '\n' '|')
	case "$got" in
	"BOX|BOX END|ACT S 00|FLASH 00 01 00 E0|UI DONE|") ok "flash: go alone (a sub menu's action, a box in its flash): once, after the box, to the end" ;;
	*) fail "flash: go alone: want BOX; BOX END; ACT S 00; FLASH 00 01 00 E0; UI DONE" ;;
	esac
}

t_alarm() {
	echo "== alarm: the alarm's box comes due inside a flash"
	local d=$OUT/alarm
	prg review_flash "$d" ui -D ALARM
	run "$d" 90
	lines "$d" "ACT\|ALARM\|FLASH" | sed 's/^/      /'
	local got
	got=$(lines "$d" "ACT\|ALARM\|FLASH" | sed 's/^\(ALARM [0-9:]*\).*/\1/' | tr '\n' '|')
	case "$got" in
	"ACT M 00|ALARM 12:00|FLASH 01 00 00 "*) ok "alarm: due inside the flash, its box waited for it (the action first, then the box)" ;;
	*) fail "alarm: want ACT M 00, then ALARM 12:00 (got ${got//|/; })" ;;
	esac
}

# tests/$1.s as an application (tools/vpack.py): $2 the .cvt; $3 type; $4...: ca65 flags
app() {
	local src=$1 cvt=$2 type=$3
	shift 3
	local d
	d=$(dirname "$cvt")
	local b
	b=$d/$(basename "$cvt" .cvt)
	mkdir -p "$d"
	ca65 --cpu 65C02 -I build/gen -I inc "$@" "tests/$src.s" -o "$b.o" || die "tests/$src.s does not assemble"
	ld65 -C sdk/cfg/app.cfg "$b.o" -o "$b.bin" -Ln "$b.lab" || die "tests/$src.s does not link"
	local mode=640x480
	[ "$type" = deskacc ] && mode=keep
	printf 'name = %s\nclass = %s\nmode = %s\napi = 3\ntype = %s\nicon = %s\n' \
		"$(basename "$cvt" .cvt)" Review $mode "$type" "$(pwd)/sdk/template/c/icon.pbm" > "$b.hdr"
	$PY tools/vpack.py --load 0x0801 -o "$cvt" "$b.hdr" "$b.bin" >/dev/null || die "vpack $cvt"
}

t_leak() {
	echo "== leak: streams a program leaves open (an SD card image: four DOS contexts)"
	local d
	for start in 0 10; do
		d=$OUT/leak$start
		rm -rf "$d"
		mkdir -p "$d/card"
		app review_leak "$d/card/AUTOSTART.cvt" application -D START=$start
		app review_leak "$d/card/LEAKDA.cvt" deskacc -D DA
		for f in A B C D; do echo "$f file" > "$d/card/$f.TXT"; done
		sdrun "$d" 120
		lines "$d" "LK\|DA\|AF\|OP\|GETFILE\|LEAK DONE" | sed 's/^/      /'
	done
	local got want
	got=$(lines "$OUT/leak0" "LK\|GETFILE" | tr '\n' '|')
	want=""
	for n in 0 1 2 3 4 5 6 7 8 9; do want="${want}LK 0$n 00 00 00|"; done
	if [ "$got" = "$want" ] && lines "$OUT/leak0" "LEAK DONE" | grep -q .; then
		ok "leak: ten runs left three files open each; every open and every start worked, the eleventh run too"
	else
		fail "leak: a run could not open its files or start the next (want ${want//|/; })"
	fi
	for s in 0 10; do
		got=$(lines "$OUT/leak$s" "DA\|AF\|OP" | tr '\n' '|')
		case "$got" in
		"DA 00 00|AF 41 00 00 42 43|OP 03 10 41 41 41|") ok "leak (from run $s): an accessory's two streams closed at RstrAppl, the program's kept (it still reads); three streams, the fourth TOO_MANY_FILES, each of the three reads" ;;
		*) fail "leak (from run $s): want DA 00 00; AF 41 00 00 42 43; OP 03 10 41 41 41" ;;
		esac
	done
}

misc() {        # tests/review_misc.s once: sprites and files
	[ -f "$OUT/misc/console.txt" ] && return
	prg review_misc "$OUT/misc" -
	$PY tests/review_fixture.py files "$OUT/misc" || die "review_fixture.py files"
	run "$OUT/misc" 30
}

t_sprite() {
	echo "== sprite: DrawSprite's picture address, sprites 0-7"
	misc
	local got want="" n a
	got=$(lines "$OUT/misc" "SPR" | tr '\n' '|')
	for n in 0 1 2 3 4 5 6 7; do
		a=$(( (0x16C00 + n * 0x800) >> 5 ))
		want="${want}$(printf 'SPR 0%d %02X %02X|' $n $((a & 255)) $((a >> 8)))"
	done
	lines "$OUT/misc" "SPR" | sed 's/^/      /'
	[ "$got" = "$want" ] && ok "sprite: all eight sprites' pictures at \$16C00 + n * 2048" \
		|| fail "sprite: want ${want//|/; }"
	# sprites 1-7 in the dump: the address in the attributes, the picture there
	$PY - "$OUT/misc/dump.bin" <<-'EOF' || fail "sprite: the pictures in VRAM"
	import sys
	d = open(sys.argv[1], 'rb').read()
	v = d[len(d) - 132878:][:0x20000]
	bad = []
	for n in range(1, 8):
	    a = v[0x1FC00 + 8 * n] | v[0x1FC01 + 8 * n] << 8
	    addr = (a & 0x0FFF) << 5
	    if a & 0x8000 or not 0x16C00 <= addr < 0x1AC00 or addr != 0x16C00 + n * 2048:
	        bad.append('sprite %d: its picture at $%05X (4 bpp: %s)' % (n, addr, not a & 0x8000))
	        continue
	    b = n * 37 + 5 & 255
	    row = []
	    for _ in range(3):
	        for k in range(4):
	            hi, lo = b >> (7 - 2 * k) & 1, b >> (6 - 2 * k) & 1
	            row.append(hi << 4 | lo)
	    want = bytes((row + [0] * 4) * 21 + [0] * 16 * 11)
	    if v[addr:addr + 512] != want:
	        bad.append('sprite %d: the picture at $%05X is not its own' % (n, addr))
	print(('FAIL  sprite: ' + '; '.join(bad)) if bad else
	      'ok    sprite: sprites 1-7 in the VRAM dump: each address in its own slot, its own picture there')
	sys.exit(1 if bad else 0)
	EOF
}

t_files() {
	echo "== files: FindFTypes"
	misc
	local got
	got=$(lines "$OUT/misc" "FT" | sort | tr '\n' '|')
	lines "$OUT/misc" "FT" | sed 's/^/      /'
	[ "$got" = "FT Letter 1.5|FT Plain|FT Sixteen Chars Ab|" ] \
		&& ok "files: FindFTypes lists a 16-character name and a name with a dot (and not the font)" \
		|| fail "files: want Letter 1.5, Plain, Sixteen Chars Ab"
}

t_font() {
	echo "== font: 20 sizes, the table full; a record of 8200 bytes"
	local d=$OUT/font
	prg review_font "$d" -
	$PY tests/review_fixture.py fonts "$d" || die "review_fixture.py fonts"
	run "$d" 60
	lines "$d" "BIG\|TY\|LF\|FI\|UF" | sed 's/^/      /'
	[ "$(lines "$d" "TY")" = "TY 00" ] && ok "font: Rev Tiny 9 (211 bytes) loaded (one bank, not none)" \
		|| fail "font: Rev Tiny: want TY 00"
	[ "$(lines "$d" "BIG")" = "BIG 00 00" ] && ok "font: Rev Big 9 (8200 bytes) in two banks: the bank after its first untouched" \
		|| fail "font: Rev Big: want BIG 00 00 (loaded, the guard bank intact)"
	$PY - "$d/console.txt" <<-'EOF' || fail "font: the table"
	import sys
	L = [l.split() for l in open(sys.argv[1], encoding='latin-1').read().replace('\\X0F', '').splitlines()]
	lf = {int(l[1], 16): (int(l[2], 16), int(l[3], 16)) for l in L if l and l[0] == 'LF'}
	fi = {int(l[1], 16): (int(l[2], 16), int(l[3], 16), int(l[4], 16)) for l in L if l and l[0] == 'FI'}
	uf = [l for l in L if l and l[0] == 'UF']
	bad = []
	got = [s for s in lf if lf[s][1] == 0]
	if len(got) != 13 or any(lf[s][1] not in (0, 0x0B) for s in lf):
	    bad.append('want 13 loaded (the table: 15, Rev Big and Rev Tiny two), the rest BFR_OVERFLOW')
	hs = [lf[s][0] for s in got]
	if len(set(hs)) != len(hs):
	    bad.append('a handle given twice')
	for s in got:
	    if fi.get(s, (0, 0, 1))[1:] != (s, 0):
	        bad.append('size %d: its handle now reports size %d' % (s, fi.get(s, (0, 0))[1]))
	if not uf or uf[0][1] != '00':
	    bad.append('UseFont of the first: an error')
	print(('FAIL  font: ' + '; '.join(bad)) if bad else
	      'ok    font: 13 sizes loaded, 7 BFR_OVERFLOW (no spare entry: the program uses all), every handle still its font, the first usable')
	sys.exit(1 if bad else 0)
	EOF
	# the next program: the first one's fonts spare
	d=$OUT/font2
	rm -rf "$d"
	app review_font "$d/AUTOSTART.cvt" application -D APP
	$PY tests/review_fixture.py fonts "$d" || die "review_fixture.py fonts"
	cp "$KDIR/VERANDA.PRG" "$KDIR/VERANDA.SYS" "$d/"
	run "$d" 90
	lines "$d" "LC\|FC" | sed 's/^/      /'
	$PY - "$d/console.txt" <<-'EOF' || fail "font: the next program"
	import sys
	L = [l.split() for l in open(sys.argv[1], encoding='latin-1').read().replace('\\X0F', '').splitlines()]
	lc = {int(l[1], 16): (int(l[2], 16), int(l[3], 16)) for l in L if l and l[0] == 'LC'}
	fc = {int(l[1], 16): int(l[3], 16) for l in L if l and l[0] == 'FC'}
	bad = ['size %d: error %d' % (s, lc[s][1]) for s in sorted(lc) if lc[s][1]]
	bad += ['size %d: its handle reports %s' % (s, fc.get(s)) for s in sorted(lc) if not lc[s][1] and fc.get(s) != s]
	if len(lc) != 10 or len(set(v[0] for v in lc.values())) != 10:
	    bad.append('want ten loads, ten handles')
	print(('FAIL  font: ' + '; '.join(bad)) if bad else
	      "ok    font: the next program loads Rev C 10-19 over the first one's fonts (spare): ten handles, each its font")
	sys.exit(1 if bad else 0)
	EOF
}

t_rec() {
	echo "== rec: record files at the end of their banks; written back on a full card"
	local d=$OUT/rec
	prg review_rec "$d" -
	$PY tests/review_fixture.py rec "$d" || die "review_fixture.py rec"
	run "$d" 60
	lines "$d" "OR\|O3\|WR" | sed 's/^/      /'
	[ "$(lines "$d" "OR")" = "OR 13 00" ] && ok "rec: REC3 (three banks) with two free: NO_BANKS, the bank after them untouched" \
		|| fail "rec: OpenRecordFile with too few banks: want OR 13 00 (NO_BANKS, the guard intact)"
	[ "$(lines "$d" "O3")" = "O3 00 00" ] && ok "rec: REC3 with three free: opened, its record read back equal" \
		|| fail "rec: OpenRecordFile with three banks: want O3 00 00"
	[ "$(lines "$d" "WR")" = "WR 00 00 03 03 00 00" ] \
		&& ok "rec: WriteRecord: 100 and 1 bytes past the banks' end INSUFF_SPACE, exactly to the end written, the bank after untouched" \
		|| fail "rec: WriteRecord at the end: want WR 00 00 03 03 00 00"
	# a full card
	d=$OUT/rec-full
	rm -rf "$d"
	mkdir -p "$d/card"
	prg review_rec "$d/p" - -D FULL
	cp "$d/p/TEST.PRG" "$d/card/"
	$PY tests/review_fixture.py rec "$d/card" || die "review_fixture.py rec"
	cp "$KDIR/VERANDA.SYS" "$d/card/"
	$PY tools/vcard.py make --mb 64 "$d/sd.img" "$d/card" >/dev/null || die "vcard make"
	$PY tests/review_fixture.py fill "$d/sd.img" || die "review_fixture.py fill"
	sdrun "$d" 60
	lines "$d" "UP" | sed 's/^/      /'
	local up
	up=$(lines "$d" "UP")
	if [ "$up" != "UP 00" ] && [ -n "$up" ] && cmp -s "$d/card/RECW.cvt" "$d/out/RECW.cvt" && [ ! -e "$d/out/RECW.tmp" ]; then
		ok "rec: UpdateRecordFile on a full card: an error ($up), RECW.cvt as it was, no RECW.tmp"
	else
		fail "rec: UpdateRecordFile on a full card: want an error, RECW.cvt unchanged, no RECW.tmp ($(ls "$d/out" | tr '\n' ' '))"
	fi
}

t_wheel() {
	echo "== wheel: steps on frames the program does not read add up"
	# tests/review_wheel.s puts steps into the ROM's wheel: its address
	local sym
	sym=$(dirname "$ROM")/kernal.sym
	if [ -f "$sym" ] && ! grep -q "^al 00A88F .wheel" "$sym"; then
		fail "wheel: the ROM's wheel is not at \$A88F ($sym): change WHEEL in tests/review_wheel.s"
		return
	fi
	local d=$OUT/wheel
	prg review_wheel "$d" -
	run "$d" 30
	lines "$d" "WHEEL" | sed 's/^/      /'
	[ "$(lines "$d" "WHEEL")" = "WHEEL 03" ] && ok "wheel: three steps on three frames, read later: GetMouse gives 3" \
		|| fail "wheel: want WHEEL 03"
}

t_irq() {
	echo "== irq: the longest stretch with interrupts off, full-screen fills"
	local d=$OUT/irq
	prg review_irq "$d" -
	run "$d" 60
	local l
	l=$(lines "$d" "IRQ")
	echo "      $l"
	[ -n "$l" ] || { fail "irq: no result"; return; }
	$PY - $l <<-'EOF' || fail "irq: interrupts off too long during a fill"
	import sys
	idle, fill = int(sys.argv[3], 16), int(sys.argv[5], 16)
	c = lambda n: n * 8e6 / 31469              # a line: 254 cycles at 8 MHz
	print('      the VSYNC interrupt delayed by at most %d lines idle (%.0f cycles, %.2f ms), %d lines during '
	      'the fills (%.0f cycles, %.2f ms)' % (idle, c(idle), c(idle) / 8e3, fill, c(fill), c(fill) / 8e3))
	# 16 bytes of a 16C550's FIFO at 115200 baud: 1.39 ms
	ok = c(fill) / 8e3 < 1.39
	print(('ok    ' if ok else 'FAIL  ') + 'irq: interrupts off for less than 1.39 ms (a 16-byte FIFO at 115200 baud) during full-screen fills')
	sys.exit(0 if ok else 1)
	EOF
}

FAILED=0
rm -rf "$OUT/misc"
for t in ${@:-flash flashsub alarm leak sprite font files rec wheel irq}; do
	t_$t
done
[ "$FAILED" = 0 ] || { echo "GATE review: FAIL"; exit 1; }
echo "GATE review: PASS"
