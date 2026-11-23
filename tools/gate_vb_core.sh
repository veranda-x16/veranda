#!/bin/bash
# Gate vb_core (VeraBASIC phase 1, docs/DECISIONS.md V86): VeraBASIC Run,
# the runtime, against tools/vbasic.py run, the reference interpreter.
#
#   tools/gate_vb_core.sh       (OUT=dir; VB_SD=0: skip the SD card image;
#                                R49=the ROM image, default the R49 release)
#
# 1. the kernel and the SDK; VeraBASIC Run built against it (an
#    application, VRND, API 6, overlay 1 banked) and its test build; main
#    RAM's end and the room left for the program's names; the test
#    desktop (tests/vbasic/vb_desk.s) for the switcher
# 2. the programs: tests/vbasic/core (hand-written and tests/vbasic/
#    mkcore.py's), every listing of the manual's chapters
#    (tests/vbasic/doclistings.py); the reference's log of each (floats:
#    the ROM's own maths, tools/vbrom.py); G4: each program's canonical
#    form (detok(tok(S))) logs the same in the reference and on the X16
# 3. VeraBASIC Run's test build runs them all (VBTEST.LST, the keys from
#    NAME.key) under ROM R49, on the host folder; every log equals the
#    reference's (tests/vbasic/check_core.py); the heap's collector ran
#    1000 times or more
# 4. Ctrl+C stops a loop and a FUNCTION deep in recursion; a program put
#    aside (TaskCtl TASK_ASIDE, Alt+Tab's) in the middle of a loop comes
#    back (the test desktop resumes it) and goes on counting
#    4b. V88: the free RAM banks filled at random (the test build's
#    "!fill n", several seeds), a program with strings and then another
#    from their .bas files: the second's heap starts empty, its logs as
#    the reference's
# 5. the same on an SD card image; a screenshot of the console
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_core}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
BATCH=${VB_BATCH:-70}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
rm -rf "$OUT"
mkdir -p "$OUT"
TOP=$(pwd)

# 1. the builds
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
mkdir -p "$OUT/app" "$OUT/test" "$OUT/desk"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "VeraBASIC Run does not build"; }
A="$OUT/app/VeraBASIC Run.cvt"
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" veranda)" = True ] && [ "$(field "$A" mode)" = 640x480 ] \
	|| fail "VeraBASIC Run.cvt: not an application (VRND, 640x480)"
end=$(sed -n 's/^BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' "$OUT/app/vbrun.map")
stk=$(sed -n 's/.*__STACKSIZE__=\(0x[0-9A-F]*\).*/\1/p' apps/vbasic/Makefile)
room=$(( 0x8800 - stk - 16#$end - 1 ))
code=$(sed -n 's/^CODE  *[0-9A-F]*  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' "$OUT/app/vbrun.map")
o1=$(stat -c %s "$OUT/app/vbrun.bin.1")
[ "$o1" -le 8191 ] || fail "overlay 1: $o1 bytes"
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for the program's names (2048 at least)"
ok "VeraBASIC Run builds: an application (VRND, API 6), main RAM to \$$end (code $((16#$code)) bytes), $room bytes for the program's procedures and names (8 a name), overlay 1 $o1 bytes"
make -s -C apps/vbasic test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
ca65 --cpu 65C02 -I "$SDK/include" -o "$OUT/desk/desk.o" tests/vbasic/vb_desk.s || fail "tests/vbasic/vb_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$OUT/desk/desk.bin" "$OUT/desk/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = VbDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$OUT/desk/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OUT/desk/SHELL.cvt" "$OUT/desk/desk.hdr" "$OUT/desk/desk.bin" >/dev/null \
	|| fail "vpack the test desktop"
ok "the test build (VB_TEST) and the test desktop"
$PY tests/vbasic/check_fpnative.py "$R49" || fail "the conversions done natively differ from the ROM's"

# 2. the programs and the reference's logs
P=$OUT/progs
mkdir -p "$P" "$OUT/exp"
cp tests/vbasic/core/*.bas "$P/"
cp tests/vbasic/core/*.key "$P/" 2>/dev/null || true
$PY tests/vbasic/doclistings.py "$P" docs/vbasic/manual/getting-started.md docs/vbasic/manual/language.md \
	docs/vbasic/manual/refcard.md > "$OUT/listings.txt" || fail "the manual's listings"
nman=$(wc -l < "$OUT/listings.txt")
names=()
for f in "$P"/*.bas; do
	n=$(basename "$f" .bas)
	k=()
	[ -f "$P/$n.key" ] && k=(--input "$P/$n.key")
	$PY tools/vbasic.py run --rom "$R49" --log "${k[@]}" "$f" | grep -v '^VB GC' > "$OUT/exp/$n.log" || true
	tail -1 "$OUT/exp/$n.log" | grep -q '^VB ' || fail "the reference on $n: no end"
	# G4: the canonical form runs the same
	$PY tools/vbasic.py canon "$f" -o "$P/${n}_c.bas" || fail "canon $n"
	[ -f "$P/$n.key" ] && cp "$P/$n.key" "$P/${n}_c.key"
	$PY tools/vbasic.py run --rom "$R49" --log "${k[@]}" "$P/${n}_c.bas" | grep -v '^VB GC' > "$OUT/exp/${n}_c.log" || true
	cmp -s "$OUT/exp/$n.log" "$OUT/exp/${n}_c.log" || fail "G4 (the reference): $n and its canonical form log differently"
	names+=("$n" "${n}_c")
done
ok "${#names[@]} programs: $(( ${#names[@]} / 2 )) ($nman of them the manual's listings) and their canonical forms; the reference's logs, each program's equal to its canonical form's (G4)"

# 3. the X16: batches of programs, each a session; $1: the folder, $2: the ROM,
# then the VBTEST.LST lines
session() {
	d=$1 rom=$2
	shift 2
	mkdir -p "$d"
	: > "$d/VBTEST.LST"
	for l in "$@"; do
		case "$l" in
		!*) echo "$l" >> "$d/VBTEST.LST" ;;
		*) printf '%s\n' "$l" >> "$d/VBTEST.LST" ;;
		esac
	done
}
build_docs() {         # into $1 the program documents named in VBTEST.LST
	while read -r line; do
		n=${line##* }
		[ "$n" = '!shot' ] && continue
		f="$P/$n.bas"
		[ -f "$f" ] || f="tests/vbasic/special/$n.bas"
		$PY tools/vbasic.py build "$f" -o "$1/$n.cvt" >/dev/null || fail "build $n"
		[ -f "${f%.bas}.key" ] && cp "${f%.bas}.key" "$1/$n.KEY"
	done < "$1/VBTEST.LST"
	cp "$OUT/test/VBRun.cvt" "$1/AUTOSTART.cvt"
	cp "$OUT/desk/SHELL.cvt" "$1/"
	cp build/VERANDA.SYS "$1/"
}
run_host() {           # $1 the folder, $2 the ROM
	build_docs "$1"
	cp build/VERANDA.PRG "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 900 "$EMU" -rom "$2" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	grep -a -q "VB DONE" "$1/console.txt" || { tail -5 "$1/console.txt"; fail "the session in $1 did not finish"; }
}
run_sd() {             # $1 the folder, $2 the ROM: on an SD card image
	mkdir -p "$1/card"
	mv "$1/VBTEST.LST" "$1/card/"
	build_docs "$1/card"
	$PY tools/vcard.py make --mb 64 "$1/sd.img" "$1/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$1/"
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 1800 "$EMU" -rom "$2" -sdcard sd.img -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	grep -a -q "VB DONE" "$1/console.txt" || { tail -5 "$1/console.txt"; fail "the SD card session in $1 did not finish"; }
}
SPECIAL=('!stop 40 ctrl_c' '!aside 12 aside' '!stop 60 ctrl_c_fn')
for s in ctrl_c aside ctrl_c_fn; do
	for e in exp need; do
		[ -f "tests/vbasic/special/$s.$e" ] && cp "tests/vbasic/special/$s.$e" "$OUT/exp/"
	done
done
for s in aside hello_console; do
	$PY tools/vbasic.py run --rom "$R49" --log tests/vbasic/special/$s.bas | grep -v '^VB GC' > "$OUT/exp/$s.log"
done

check_all() {          # $1: the consoles' folder pattern, $2: what
	cat $1/console.txt > "$OUT/all-$2.txt"
	$PY tests/vbasic/check_core.py "$OUT/all-$2.txt" "$OUT/exp" --only "${names[@]}" ctrl_c aside ctrl_c_fn hello_console \
		> "$OUT/check-$2.txt" || { grep -v '^ok' "$OUT/check-$2.txt"; fail "$2: logs differ"; }
	tail -1 "$OUT/check-$2.txt"
}

i=0
b=0
for ((i = 0; i < ${#names[@]}; i += BATCH)); do
	session "$OUT/host/b$b" "$R49" "${names[@]:i:BATCH}"
	b=$((b + 1))
done
session "$OUT/host/b$b" "$R49" "${SPECIAL[@]}" hello_console '!shot'
for d in "$OUT"/host/b*; do run_host "$d" "$R49"; done
check_all "$OUT/host/b*" host
gcs=$(sed -n 's/.*; \([0-9]*\) collections of the heap/\1/p' "$OUT/check-host.txt")
[ "${gcs:-0}" -ge 1000 ] || fail "the collector ran $gcs times (1000 at least)"
banks=$(grep -a -o "VB BANKS [0-9]* FREE OF [0-9]*" "$OUT/all-host.txt" | head -1 | sed 's/VB BANKS //')
ok "RAM banks at 512 KB with a small program loaded: $banks (the test build: one more for its keys)"
ok "the host folder, ROM R49: ${#names[@]} programs log as the reference; Ctrl+C stopped a loop and a FUNCTION 40 deep; put aside in the middle of a loop it came back and went on counting; the heap collected $gcs times"
$PY tools/vram2png.py --color "$OUT/host/b$b/dump.bin" "$OUT/console.png" >/dev/null 2>&1 \
	&& ok "a screenshot of the console: $OUT/console.png"

# 4b. the heap of a program run after another (V88): Run's test build
# fills every free RAM bank with bytes at random ("!fill n" in VBTEST.LST:
# the same bytes whatever the emulator's RAM held), then runs strings_gc2
# and strings_gc3 from their .bas files, the second with locals,
# parameters and temporaries alive across its collections: the heap
# starts empty and the collector reads no byte the heap has not written,
# so the bytes that were in the banks change nothing
HEAP_SEEDS=${VB_HEAP_SEEDS:-12 14 18 19 23}
mkdir -p "$OUT/heap/exp"
for n in strings_gc2 strings_gc3; do cp "$OUT/exp/$n.log" "$OUT/heap/exp/$n.bas.log"; done
for s in $HEAP_SEEDS; do
	d=$OUT/heap/s$s
	mkdir -p "$d"
	printf '!fill %s\nstrings_gc2.bas\nstrings_gc3.bas\n' "$s" > "$d/VBTEST.LST"
	cp tests/vbasic/core/strings_gc2.bas tests/vbasic/core/strings_gc3.bas "$d/"
	cp "$OUT/test/VBRun.cvt" "$d/AUTOSTART.cvt"
	cp build/VERANDA.SYS build/VERANDA.PRG "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo > console.txt 2>&1) || true
	grep -a -q "VB DONE" "$d/console.txt" || { tail -5 "$d/console.txt"; fail "the heap session (fill $s) did not finish"; }
	$PY tests/vbasic/check_core.py "$d/console.txt" "$OUT/heap/exp" --only strings_gc2.bas strings_gc3.bas \
		> "$d/check.txt" || { grep -v '^ok' "$d/check.txt"; fail "the heap after another program: the RAM banks filled at random (seed $s)"; }
done
ok "the heap after another program: the free RAM banks filled at random (seeds $HEAP_SEEDS), strings_gc2 then strings_gc3 from their .bas files log as the reference each time"

# 5. the SD card image
if [ "${VB_SD:-1}" != 0 ]; then
	b=0
	for ((i = 0; i < ${#names[@]}; i += BATCH)); do
		session "$OUT/sd/b$b" "$R49" "${names[@]:i:BATCH}"
		b=$((b + 1))
	done
	session "$OUT/sd/b$b" "$R49" "${SPECIAL[@]}" hello_console
	for d in "$OUT"/sd/b*; do run_sd "$d" "$R49"; done
	check_all "$OUT/sd/b*" sd
	ok "an SD card image, ROM R49: the same"
fi
echo "GATE vb_core: PASS"
