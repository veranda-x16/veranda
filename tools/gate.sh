#!/bin/bash
# Veranda gates (docs/PLAN.md section 9): each prints ok/FAIL lines and ends
# with "GATE <name>: PASS", or exits 1.
#
#   tools/gate.sh spec      phase 0: the API table generates files that
#                           assemble, link at their addresses and compile
#   tools/gate.sh boot      phase 1: VERANDA.PRG starts, a program draws,
#                           BASIC comes back and answers PRINT 6*7
#   tools/gate.sh gfx1      phase 1: drawing at 640x480 (tests/gfx1.s,
#                           tests/check_gfx1.py), timings; the clip
#                           rectangle (tests/clipr.s, V81)
#   tools/gate.sh gfx       phase 2: the classic calls in 320x240 equal GEOS
#                           64's byte for byte (tests/scene.s; needs
#                           GEOS64_REF, default ~/Projects/geos-old)
#   tools/gate.sh input     phase 3: the main loop: a scripted mouse, keys,
#                           processes, Sleep (tests/input.s)
set -e
cd "$(dirname "$0")/.."
OUT=${GATE_OUT:-build/gate}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
GEOS64_REF=${GEOS64_REF:-$HOME/Projects/geos-old}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

gate_spec() {
	S=$OUT/spec
	rm -rf "$S"
	mkdir -p "$S"
	echo "== api/veranda.api -> build/gen (tools/apigen.py)"
	$PY tools/apigen.py api/veranda.api build/gen --doc docs/API.md || fail "the table has errors"
	ok "the table parses; slots, variables and areas are consistent"
	git diff --quiet -- docs/API.md 2>/dev/null || echo "      (docs/API.md changed: commit it with the table)"

	ca65 -I build/gen tests/spec/inc_test.s -o "$S/inc_test.o" || fail "veranda.inc does not assemble"
	ok "veranda.inc assembles; its values are the API's"

	sed 's/^\(k_.*\)$/.export \1\n\1: rts/' build/gen/impl.txt > "$S/stubs.inc"
	ca65 -I "$S" tests/spec/stubs.s -o "$S/stubs.o"
	ca65 build/gen/jumptab.s -o "$S/jumptab.o" || fail "jumptab.s does not assemble"
	ld65 -C cfg/spec_jumptab.cfg "$S/jumptab.o" "$S/stubs.o" -o "$S/jumptab.bin" -m "$S/jumptab.map" \
		|| fail "the jump tables do not link at their addresses"
	ok "the jump tables link at \$8800 and \$8A00 (every entry where the API says)"

	ca65 -I build/gen build/gen/veranda_c.s -o "$S/veranda_c.o" || fail "the C bindings do not assemble"
	cl65 -t none -O -I build/gen -C cfg/spec_c.cfg tests/spec/c_test.c "$S/veranda_c.o" \
		-o "$S/c_test.bin" -m "$S/c_test.map" || fail "the C test does not compile or link"
	ok "veranda.h compiles, the C bindings link (cc65)"
	echo "GATE spec: PASS"
}

# the kernel (tools/kbuild.py) into build/; KDEFS: defines for it (gate
# fx: KDEFS="-D NOFX" builds a kernel that never uses VERA FX)
kernel() {
	$PY tools/kbuild.py $KDEFS >/dev/null || fail "the kernel does not build"
}

# test program tests/$1.s -> $2/TEST.PRG; run dir $2 gets the kernel too
testprg() {
	mkdir -p "$2"
	ca65 --cpu 65C02 -I build/gen -I inc "tests/$1.s" -o "$2/$1.o" || fail "tests/$1.s does not assemble"
	ca65 tests/prghdr.s -o "$2/prghdr.o"
	ld65 -C cfg/testprg.cfg "$2/prghdr.o" "$2/$1.o" -o "$2/TEST.PRG" || fail "tests/$1.s does not link"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
}

# run VERANDA.PRG in $1 (HostFS), $2 seconds at most; console in console.txt;
# the dump: $3 (default V: VRAM only; BV: the banked RAM, then VRAM)
run() {
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT "$2" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump "${3:-V}" > console.txt 2>&1) || true
}

gate_boot() {
	B=$OUT/boot
	rm -rf "$B"
	kernel
	testprg boot "$B"
	run "$B" 20
	grep -q "BOOT DRAWN" "$B/console.txt" || { cat "$B/console.txt"; fail "the test program did not run"; }
	ok "VERANDA.PRG loads the kernel, starts TEST.PRG, which draws (BOOT DRAWN)"
	grep -q "^ 42" "$B/console.txt" || { tail -5 "$B/console.txt"; fail "BASIC did not answer PRINT 6*7"; }
	ok "ToBASIC: BASIC is back and answers PRINT 6*7 with 42"
	# BankCopy (DECISIONS V158; tests/bcopy.s): 600 random copies through
	# the kernel and through the old byte-by-byte copy (-D REF), the
	# registers and the bytes the same
	testprg bcopy "$B/bc"
	run "$B/bc" 60
	ca65 --cpu 65C02 -I build/gen -I inc -D REF tests/bcopy.s -o "$B/bc/ref.o" || fail "tests/bcopy.s -D REF does not assemble"
	mkdir -p "$B/bcref"
	ld65 -C cfg/testprg.cfg "$B/bc/prghdr.o" "$B/bc/ref.o" -o "$B/bcref/TEST.PRG" || fail "tests/bcopy.s -D REF does not link"
	cp build/VERANDA.PRG build/VERANDA.SYS "$B/bcref/"
	run "$B/bcref" 60
	for d in bc bcref; do tr -d '\r' < "$B/$d/console.txt" | grep -a '^BC ' > "$B/$d/bc.txt"; done
	n=$(grep -c -E '^BC [0-9A-F]{4} ' "$B/bc/bc.txt" || true)
	[ "$n" = 600 ] && grep -q '^BC DONE' "$B/bc/bc.txt" || { tail -5 "$B/bc/console.txt"; fail "BankCopy: the test did not finish ($n cases)"; }
	cmp -s "$B/bc/bc.txt" "$B/bcref/bc.txt" || { diff "$B/bc/bc.txt" "$B/bcref/bc.txt" | head -5; fail "BankCopy differs from the old copy"; }
	ok "BankCopy: 600 random copies (low RAM and banks, into the next bank, overlapping) as the old byte-by-byte copy, registers and bytes"
	echo "GATE boot: PASS"
}

gate_gfx1() {
	G=$OUT/gfx1
	rm -rf "$G"
	kernel
	testprg gfx1 "$G"
	run "$G" 60
	[ -f "$G/dump.bin" ] || { cat "$G/console.txt"; fail "no VRAM dump"; }
	$PY tests/check_gfx1.py "$G/dump.bin" "$G/console.txt" "$G" || fail "gfx1 checks"
	# the clip rectangle (DECISIONS V81; tests/clipr.s): 100 random cases
	# drawn with the clip into the foreground and without into the back
	# screen, compared pixel for pixel
	testprg clipr "$G/clip"
	run "$G/clip" 60
	c=$(tr -d '\r' < "$G/clip/console.txt" | grep -a -o 'CLIP [0-9]* [0-9A-F]* [0-9A-F]*' | tail -1)
	[ "$c" = "CLIP 100 0000 FF" ] || { tail -5 "$G/clip/console.txt"; fail "the clip rectangle: $c (cases, bad bytes, the first bad case)"; }
	ok "the clip rectangle: 100 random calls (rectangles, frames, lines, points, text, bitmaps) clipped, each as drawn whole and cut, pixel for pixel"
	# WDrawLine (DECISIONS V159; tests/lines.s): 2,100 random lines in the
	# three modes through the kernel and through the old point-by-point
	# line (-D REF): registers, both screens' sums and the final screens
	testprg lines "$G/lines"
	run "$G/lines" 120
	ca65 --cpu 65C02 -I build/gen -I inc -D REF tests/lines.s -o "$G/lines/ref.o" || fail "tests/lines.s -D REF does not assemble"
	mkdir -p "$G/linesref"
	ld65 -C cfg/testprg.cfg "$G/lines/prghdr.o" "$G/lines/ref.o" -o "$G/linesref/TEST.PRG" || fail "tests/lines.s -D REF does not link"
	cp build/VERANDA.PRG build/VERANDA.SYS "$G/linesref/"
	run "$G/linesref" 120
	for d in lines linesref; do tr -d '\r' < "$G/$d/console.txt" | grep -a -E '^(L|S) |^LINES DONE' > "$G/$d/l.txt"; done
	n=$(grep -c -E '^L [0-9A-F]{6} ' "$G/lines/l.txt" || true)
	[ "$n" = 2100 ] && grep -q '^LINES DONE' "$G/lines/l.txt" || { tail -5 "$G/lines/console.txt"; fail "lines: the test did not finish ($n lines)"; }
	cmp -s "$G/lines/l.txt" "$G/linesref/l.txt" || { diff "$G/lines/l.txt" "$G/linesref/l.txt" | head -5; fail "WDrawLine differs from the old line"; }
	cmp -s -n 76800 "$G/lines/dump.bin" "$G/linesref/dump.bin" || fail "WDrawLine: the screens at the end differ from the old line's"
	ok "WDrawLine: 2,100 random lines (640 x 480, 640 x 240, 320 x 240; ink, erase, recover; every screen choice; the clip) as the old line, registers and screens"
	echo "GATE gfx1: PASS"
}

have_ref() {
	[ -f "$GEOS64_REF/build/bsw/kernal/kernal.bin" ] && [ -f "$GEOS64_REF/tools/x16/sim6502.py" ]
}

# GEOS 64's side of the scene in $1: the BSW 9 font (a test fixture,
# assembled from the reference) and the scene assembled for GEOS 64
scene_ref() {
	ca65 -D bsw=1 -D drv1541=1 -I "$GEOS64_REF" -I "$GEOS64_REF/inc" "$GEOS64_REF/kernal/bswfont/bswfont.s" -o "$1/bswfont.o"
	ld65 -C cfg/bswfont.cfg "$1/bswfont.o" -o "$1/bsw9.bin"
	ca65 --cpu 65C02 -D GEOS64 -I build/gen -I inc --bin-include-dir "$1" tests/scene.s -o "$1/scene64.o" \
		|| fail "the scene does not assemble for GEOS 64"
	ld65 -C cfg/scene64.cfg "$1/scene64.o" -o "$1/scene64.bin" -Ln "$1/scene64.lab"
}

# Veranda's side: $1/TEST.PRG (tests/gfx2.s with defines $3...) and the
# kernel from build dir $2; the font from $1
scene_prg() {
	d=$1 k=$2
	shift 2
	ca65 --cpu 65C02 -I build/gen -I inc --bin-include-dir "$d" tests/scene.s -o "$d/scene.o"
	ca65 --cpu 65C02 -I build/gen -I inc "$@" tests/gfx2.s -o "$d/gfx2.o"
	ca65 tests/prghdr.s -o "$d/prghdr.o"
	ld65 -C cfg/testprg.cfg "$d/prghdr.o" "$d/gfx2.o" "$d/scene.o" -o "$d/TEST.PRG" || fail "the scene does not link"
	cp "$k/VERANDA.PRG" "$k/VERANDA.SYS" "$d/"
}

# the scene in $1 compared with GEOS 64's (the reference in $2)
scene_check() {
	[ -f "$1/dump.bin" ] || { cat "$1/console.txt"; return 1; }
	$PY tests/check_gfx2.py "$GEOS64_REF" "$1/dump.bin" "$1/console.txt" "$2/scene64.bin" "$2/scene64.lab" "$1"
}

gate_gfx() {
	G=$OUT/gfx
	rm -rf "$G"
	mkdir -p "$G"
	if ! have_ref; then
		echo "SKIP  no GEOS 64 reference (GEOS64_REF=$GEOS64_REF): the oracle cannot run"
		echo "GATE gfx: SKIP"
		exit 0
	fi
	kernel
	scene_ref "$G"
	scene_prg "$G" build
	run "$G" 60
	scene_check "$G" "$G" || fail "gfx checks"
	echo "GATE gfx: PASS"
}

gate_input() {
	G=$OUT/input
	rm -rf "$G"
	kernel
	# tests/input.s holds Ctrl through the ROM's shflag: this ROM's address
	sym=$(dirname "$ROM")/kernal.sym
	if [ -f "$sym" ] && ! grep -q "^al 00A80C .shflag" "$sym"; then
		fail "the ROM's shflag is not at \$A80C ($sym): change SHFLAG in tests/input.s"
	fi
	# the session, twice
	for n in 1 2; do
		testprg input "$G/$n"
		run "$G/$n" 60
		[ -f "$G/$n/dump.bin" ] || { cat "$G/$n/console.txt"; fail "no VRAM dump (run $n)"; }
		echo "== run $n"
		$PY tests/check_input.py "$G/$n/dump.bin" "$G/$n/console.txt" || fail "input checks (run $n)"
	done
	cmp -s "$G/1/console.txt" "$G/2/console.txt" || fail "the two runs' logs differ"
	ok "the two runs' logs are the same"
	# the ROM's mouse: its range and the re-centring (tests/mouse.s)
	testprg mouse "$G/mouse"
	run "$G/mouse" 20
	for l in "A027F 01DF" "B01FB 00FB" "C0000 0000" "D00FF 00C8" "E0018 0118"; do
		grep -a -q "^$l\$" "$G/mouse/console.txt" || { grep -a -E '^[ABCD][0-9A-F]' "$G/mouse/console.txt"; fail "the ROM's mouse: no \"$l\""; }
	done
	ok "the ROM's mouse: the pointer reaches both corners (the device re-centred); mouseYPos current when the kernel places the pointer"
	ok "BBMult leaves the product's low byte in a, as GEOS 64 (geoWrite's geos menu, DECISIONS V66)"
	if ! have_ref; then
		echo "SKIP  no GEOS 64 reference: the scenes with a moving pointer cannot be compared"
		echo "GATE input: PASS (without the scenes)"
		exit 0
	fi
	# the scene 20 times with a moving pointer: still GEOS 64's
	mkdir -p "$G/scene" "$G/control"
	scene_ref "$G/scene"
	scene_prg "$G/scene" build -D MOVING
	run "$G/scene" 120
	echo "== 20 scenes, a moving pointer"
	scene_check "$G/scene" "$G/scene" || fail "the scenes drawn with a moving pointer differ from GEOS 64's"
	# the control: without the interrupt's VERA restore the same must fail
	$PY tools/kbuild.py --out build/control -D NO_VERA_RESTORE >/dev/null || fail "the control kernel does not build"
	cp "$G/scene/bsw9.bin" "$G/control/"
	scene_prg "$G/control" build/control -D MOVING
	run "$G/control" 120
	if scene_check "$G/control" "$G/scene" >"$G/control/check.txt" 2>&1; then
		fail "the control (no VERA restore in the interrupt) passes too: the scenes do not test the interrupt"
	fi
	ok "the control (no VERA restore in the interrupt) differs, as it must"
	echo "GATE input: PASS"
}

# gate ui: each session tests/ui_<name>.s on GEOS 64 (the simulator) and
# on a Veranda kernel whose system font is GEOS 64's (a test fixture)
UI_ALL="menu:28 menu:60 menu:100 menu icons:16 icons:100 icons dlg:35 dlg:55 dlg:75 dlg"

gate_ui() {
	G=$OUT/ui
	rm -rf "$G"
	mkdir -p "$G"
	if ! have_ref; then
		echo "SKIP  no GEOS 64 reference (GEOS64_REF=$GEOS64_REF): the oracle cannot run"
		echo "GATE ui: SKIP"
		exit 0
	fi
	kernel
	ca65 -D bsw=1 -D drv1541=1 -I "$GEOS64_REF" -I "$GEOS64_REF/inc" "$GEOS64_REF/kernal/bswfont/bswfont.s" -o "$G/bswfont.o"
	ld65 -C cfg/bswfont.cfg "$G/bswfont.o" -o "$G/bsw9.bin"
	$PY tools/kbuild.py --out build/uikernel --sysfont "$G/bsw9.bin" >/dev/null || fail "the test kernel does not build"
	# "name:frame": session name compared at that frame instead of its last
	for e in ${UI_SESSIONS:-$UI_ALL}; do
		[ "$e" = 640 ] && continue
		n=${e%%:*}
		S=$G/${e/:/@}
		mkdir -p "$S"
		if [ "$e" != "$n" ]; then
			sed "s/\.word \$FFFF, [0-9]*/.word \$FFFF, ${e#*:}/" tests/ui_$n.s > "$S/src.s"
		else
			cp tests/ui_$n.s "$S/src.s"
		fi
		ca65 --cpu 6502 -D GEOS64 -I build/gen -I inc -I tests "$S/src.s" -o "$S/s64.o" || fail "ui_$n.s does not assemble for GEOS 64"
		ld65 -C cfg/ui64.cfg "$S/s64.o" -o "$S/s64.bin" -Ln "$S/s64.lab" || fail "ui_$n.s does not link for GEOS 64"
		ca65 --cpu 65C02 -I build/gen -I inc "$S/src.s" -o "$S/s.o" || fail "ui_$n.s does not assemble"
		ca65 --cpu 65C02 -I build/gen -I inc tests/ui.s -o "$S/ui.o"
		ca65 tests/prghdr.s -o "$S/prghdr.o"
		ld65 -C cfg/testprg.cfg "$S/prghdr.o" "$S/ui.o" "$S/s.o" -o "$S/TEST.PRG" || fail "ui_$n.s does not link"
		cp build/uikernel/VERANDA.PRG build/uikernel/VERANDA.SYS "$S/"
		run "$S" 60 BV
		[ -f "$S/dump.bin" ] || { tail -5 "$S/console.txt"; fail "$n: no VRAM dump"; }
		echo "== session $e"
		$PY tests/check_ui.py "$GEOS64_REF" "$S/dump.bin" "$S/console.txt" "$S/s64.bin" "$S/s64.lab" "$S" "$e" \
			|| fail "session $e"
		$PY tests/check_banks.py "$S/dump.bin" build/uikernel || fail "session $e: the kernel changed"
	done
	# 640x480, the foreground only: the save-under stack (Veranda's kernel)
	if [ -z "$UI_SESSIONS" ] || [ "$UI_SESSIONS" = 640 ]; then
		for f in 9 20 64 90; do
			S=$G/640@$f
			mkdir -p "$S"
			sed "s/\.word \$FFFF, [0-9]*/.word \$FFFF, $f/" tests/ui_640.s > "$S/src.s"
			ca65 --cpu 65C02 -I build/gen -I inc "$S/src.s" -o "$S/s.o" || fail "ui_640.s does not assemble"
			ca65 --cpu 65C02 -D MODE640 -I build/gen -I inc tests/ui.s -o "$S/ui.o"
			ca65 tests/prghdr.s -o "$S/prghdr.o"
			ld65 -C cfg/testprg.cfg "$S/prghdr.o" "$S/ui.o" "$S/s.o" -o "$S/TEST.PRG" || fail "ui_640.s does not link"
			cp build/VERANDA.PRG build/VERANDA.SYS "$S/"
			run "$S" 60 BV
			[ -f "$S/dump.bin" ] || { tail -5 "$S/console.txt"; fail "640: no VRAM dump at frame $f"; }
			$PY tests/check_banks.py "$S/dump.bin" build || fail "640: the kernel changed"
			$PY tools/vram2png.py "$S/dump.bin" "$S/screen.png" 2>/dev/null || true
		done
		echo "== session 640"
		$PY tests/check_same.py "$G/640@9/dump.bin" "$G/640@90/dump.bin" \
			"640: after a sub menu and a dialog box (foreground only) the screen is as before" \
			|| fail "session 640"
		# (V84) two boxes over a foreground-only screen whose back screen
		# holds noise: one that fits on the save-under stack, one that
		# does not (the kernel keeps what it covers on the back screen)
		for f in 9 66 98 126 160; do
			S=$G/640box@$f
			mkdir -p "$S"
			sed "s/\.word \$FFFF, [0-9]*/.word \$FFFF, $f/" tests/ui_640box.s > "$S/src.s"
			ca65 --cpu 65C02 -I build/gen -I inc "$S/src.s" -o "$S/s.o" || fail "ui_640box.s does not assemble"
			ca65 --cpu 65C02 -D MODE640 -I build/gen -I inc tests/ui.s -o "$S/ui.o"
			ca65 tests/prghdr.s -o "$S/prghdr.o"
			ld65 -C cfg/testprg.cfg "$S/prghdr.o" "$S/ui.o" "$S/s.o" -o "$S/TEST.PRG" || fail "ui_640box.s does not link"
			cp build/VERANDA.PRG build/VERANDA.SYS "$S/"
			run "$S" 60 BV
			[ -f "$S/dump.bin" ] || { tail -5 "$S/console.txt"; fail "640box: no VRAM dump at frame $f"; }
			$PY tools/vram2png.py "$S/dump.bin" "$S/screen.png" 2>/dev/null || true
		done
		echo "== session 640box"
		B=$G/640box
		$PY tests/check_same.py --differ "$B@9/dump.bin" "$B@66/dump.bin" "640box: box A (Lighthouse Pinball's) is open" \
			&& $PY tests/check_same.py "$B@9/dump.bin" "$B@98/dump.bin" \
				"640box: after box A (on the save-under stack) the foreground is as before" \
			&& $PY tests/check_same.py --differ "$B@9/dump.bin" "$B@126/dump.bin" "640box: box B (26 KB, too big for the stack) is open" \
			&& $PY tests/check_same.py "$B@9/dump.bin" "$B@160/dump.bin" \
				"640box: after box B (kept on the back screen) the foreground is as before, its shadow's corner too" \
			|| fail "session 640box"
	fi
	echo "GATE ui: PASS"
}

# gate disk: tests/disk.s on the host folder (HostFS)
# run TEST.PRG ($2) on an SD card image in $1 (FAT32, tools/vcard.py):
# VERANDA.SYS and the test read from it, the files written to it, then
# copied out to $1/out with the console
sdrun() {
	mkdir -p "$1/card"
	cp "$2" build/VERANDA.SYS "$1/card/"
	$PY tools/vcard.py make --mb 64 "$1/sd.img" "$1/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -20 "$1/console.txt"; fail "SD card: $2 did not finish"; }
	mkdir -p "$1/out"
	cp "$1/console.txt" "$1/out/"
	$PY tools/vcard.py ls "$1/sd.img" | while read -r line; do
		f=$(echo "$line" | sed 's/ *[0-9]*$//')         # (names may have spaces)
		case "$f" in */) continue ;; esac
		mkdir -p "$1/out/$(dirname "$f")"
		$PY tools/vcard.py get "$1/sd.img" "$f" "$1/out/$f" >/dev/null
	done
}

gate_disk() {
	G=$OUT/disk
	rm -rf "$G"
	kernel
	testprg disk "$G"
	run "$G" 60
	[ -f "$G/dump.bin" ] || { tail -20 "$G/console.txt"; fail "the test did not finish"; }
	testprg disk2 "$G/2"
	run "$G/2" 60
	[ -f "$G/2/dump.bin" ] || { tail -20 "$G/2/console.txt"; fail "part 2 did not finish"; }
	testprg rmw "$G/3"
	run "$G/3" 60
	[ -f "$G/3/dump.bin" ] || { tail -20 "$G/3/console.txt"; fail "part 3 did not finish"; }
	testprg lfn "$G/4"
	run "$G/4" 60
	[ -f "$G/4/dump.bin" ] || { tail -20 "$G/4/console.txt"; fail "part 4 (long names) did not finish"; }
	$PY tests/check_disk.py "$G" "$G/2" || fail "disk checks"
	$PY tests/check_rmw.py "$G/3" || fail "writes into a file"
	echo "== long names (tests/lfn.s, DECISIONS V82)"
	$PY tests/check_lfn.py "$G/4" || fail "long names"
	# the same on an SD card image
	sdrun "$G/sd-disk" "$G/TEST.PRG"
	sdrun "$G/sd-disk2" "$G/2/TEST.PRG"
	sdrun "$G/sd-rmw" "$G/3/TEST.PRG"
	echo "== the same on an SD card image"
	$PY tests/check_disk.py "$G/sd-disk/out" "$G/sd-disk2/out" || fail "disk checks (SD card)"
	$PY tests/check_rmw.py "$G/sd-rmw/out" || fail "writes into a file (SD card)"
	sdrun "$G/sd-lfn" "$G/4/TEST.PRG"
	echo "== long names on an SD card image"
	$PY tests/check_lfn.py "$G/sd-lfn/out" || fail "long names (SD card)"
	R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
	if [ -f "$R49" ]; then
		ROM=$R49 sdrun "$G/sd-lfn49" "$G/4/TEST.PRG"
		echo "== long names on an SD card image under R49"
		$PY tests/check_lfn.py "$G/sd-lfn49/out" || fail "long names (SD card, R49)"
	fi
	# without the guard (-D NORMW: an overwrite goes by MCIOUT): the ROM's
	# fault (R49) shows on the card, so the test above would catch it
	echo "== without the guard (a kernel built with -D NORMW)"
	KDEFS="-D NORMW" kernel
	sdrun "$G/sd-normw" "$G/3/TEST.PRG"
	kernel
	n=$($PY tests/check_rmw.py "$G/sd-normw/out" | grep -c '^FAIL' || true)
	if [ "$n" -gt 0 ]; then
		ok "without it, $n files come out wrong on the card (the ROM's MCIOUT, DECISIONS V55)"
	else
		echo "      note: without it the files are right too: this ROM's MCIOUT overwrites correctly"
	fi
	echo "GATE disk: PASS"
}

case "$1" in
	disk) gate_disk ;;
	ui) gate_ui ;;
	input) gate_input ;;
	gfx) gate_gfx ;;
	spec) gate_spec ;;
	boot) gate_boot ;;
	gfx1) gate_gfx1 ;;
	*) echo "usage: $0 spec|boot|gfx1|gfx|input|ui|disk" >&2; exit 2 ;;
esac
