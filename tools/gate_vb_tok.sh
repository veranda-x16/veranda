#!/bin/bash
# Gate vb_tok (VeraBASIC phase 2, docs/DECISIONS.md V87): the tokenizer and
# prepare on the X16, program documents, the shell opening them.
#
#   tools/gate_vb_tok.sh        (OUT=dir; VB_SD=0: skip the SD card image;
#                                R49=the ROM image, default the R49 release)
#
# 1. the kernel and the SDK; VeraBASIC Run built against it (an
#    application, VRND, API 6, no documents = BAS (V93: VeraBASIC, the
#    editor, opens .bas files); overlays 1-5 within their
#    banks; main RAM's room for a program's names) and its test build;
#    the shell
# 2. G3: every program of tests/vbasic/mktokset.py (the corpus, the planted
#    errors, the core programs, the manual's listings, every keyword's
#    example, generated programs, float spellings, a 55 KB program)
#    tokenized and prepared by VeraBASIC Run's test build under ROM R49
#    ("!tok NAME" in VBTEST.LST): its four records equal
#    tools/vbtokens.py's byte for byte, or, for a program with an error,
#    its message is the PC's first one (tests/vbasic/check_tok.py); the
#    speed over them all: 10,000 bytes of source a second at least
# 3. the core programs (tests/vbasic/core) run from their .bas files: Run
#    tokenizes and prepares each, then runs it; every log equals the
#    reference's (tools/vbasic.py run, tests/vbasic/check_core.py)
# 4. the shell (its test hook, tests/vbasic/vb_shell_script.py) double-
#    clicks a program document (vbasic.py build) in the top folder, then
#    one in a folder (Run found in the top folder), with long names: Run
#    starts with each (its parent class), the program's output equals the
#    reference's, and the shell comes back (a .bas file: VeraBASIC's, gate
#    vb_ide)
# 5. 2 and 4 again on an SD card image; screenshots: Run's console after a
#    .BAS run, the shell after the session
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_tok}
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
BATCH=${VB_BATCH:-150}
SPEED=${VB_SPEED:-10000}

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
mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/vbasic SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "VeraBASIC Run does not build"; }
A="$OUT/app/VeraBASIC Run.cvt"
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
[ "$(field "$A" 'geos type')" = 6 ] && [ "$(field "$A" veranda)" = True ] || fail "VeraBASIC Run.cvt: not an application"
! field "$A" documents | grep -q BAS || fail "VeraBASIC Run.cvt declares documents = BAS (V93: VeraBASIC's)"
end=$(sed -n 's/^BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' "$OUT/app/vbrun.map")
stk=$(sed -n 's/.*__STACKSIZE__=\(0x[0-9A-F]*\).*/\1/p' apps/vbasic/Makefile)
room=$(( 0x8800 - stk - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for the program's names (2048 at least)"
ovl=""
for n in 1 2 3 4 5; do
	seg=$(grep -E "^(OVERLAY$n|OVL${n}BSS|OVL${n}RO|OVL${n}DATA) " "$OUT/app/vbrun.map" | awk '{print $3}' | sort | tail -1)
	used=$(( 16#$seg - 0xA000 + 1 ))
	[ "$used" -le 8192 ] || fail "overlay $n: $used bytes with its BSS"
	ovl="$ovl $n:$used"
done
ok "VeraBASIC Run builds: VRND, API 6, no documents (.bas: VeraBASIC's); main RAM to \$$end, $room bytes for the program's procedures and names; overlays (bytes with their BSS):$ovl"
make -s -C apps/vbasic test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
cp -r shell "$OUT/shsrc"
rm -f "$OUT/shsrc"/*.cvt "$OUT/shsrc"/*.bin "$OUT/shsrc"/*.map "$OUT/shsrc"/*.o
make -s -C "$OUT/shsrc" SDK="$SDK" >"$OUT/shsrc/build.log" 2>&1 || { cat "$OUT/shsrc/build.log"; fail "the shell does not build"; }
ok "the test build (VB_TEST) and the shell"

emu() {         # $1 the folder, $2 the console file, then the emulator's options
	local ed=$1 ec=$2
	shift 2
	(cd "$ed" && SDL_VIDEODRIVER=dummy timeout -s INT 1800 "$EMU" -rom "$R49" -prg VERANDA.PRG -run \
		-warp -sound none -echo "$@" > "$ec" 2>&1) || true
}
# a VBTEST.LST session: $1 the folder (the files in it), $2 host|sd
session() {
	local d=$1
	cp "$OUT/test/VBRun.cvt" "$d/AUTOSTART.cvt"
	cp build/VERANDA.SYS "$d/"
	if [ "$2" = sd ]; then
		mkdir -p "$d/../sdrun"
		$PY tools/vcard.py make --mb 64 "$d/../sdrun/sd.img" "$d" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$d/../sdrun/"
		emu "$d/../sdrun" console.txt -sdcard sd.img
		mv "$d/../sdrun/console.txt" "$d/console.txt"
		rm -rf "$d/../sdrun"
	else
		cp build/VERANDA.PRG "$d/"
		emu "$d" console.txt
	fi
	grep -a -q "VB DONE" "$d/console.txt" || { tail -5 "$d/console.txt"; fail "the session in $d did not finish"; }
}

# 2. G3
G=$OUT/g3
$PY tests/vbasic/mktokset.py "$G/files" --fuzz 100 --big > "$G.names" || fail "mktokset.py"
nprog=$(wc -l < "$G.names")
g3() {          # $1 host|sd
	rm -f "$G/all-$1.txt"
	split -l "$BATCH" "$G.names" "$G/batch-"
	for b in "$G"/batch-*; do
		d=$G/run
		rm -rf "$d"
		mkdir -p "$d"
		while read -r n; do cp "$G/files/$n" "$d/"; done < "$b"
		sed 's/^/!tok /' "$b" > "$d/VBTEST.LST"
		session "$d" "$1"
		cat "$d/console.txt" >> "$G/all-$1.txt"
		rm -rf "$d" "$b"
	done
	$PY tests/vbasic/check_tok.py "$G/all-$1.txt" "$G/files" --speed "$SPEED" > "$G/check-$1.txt" \
		|| { grep FAIL "$G/check-$1.txt" | head -20; fail "$1: G3"; }
	tail -1 "$G/check-$1.txt"
}
g3 host
ok "G3, the host folder, ROM R49: $nprog programs, records 0-3 byte for byte as vbtokens.py (the PC's first error for those with one)"
speed=$(tail -1 "$G/check-host.txt" | sed -n 's/.*: \([0-9]*\) bytes a second$/\1/p')
ok "the speed: $speed bytes of source a second (tokenize and prepare, 8 MHz; $SPEED at least)"

# 3. the core programs from their .bas files
R=$OUT/run
mkdir -p "$R/exp"
names=()
for f in tests/vbasic/core/*.bas; do
	n=$(basename "$f")
	cp "$f" "$R/"
	k=()
	if [ -f "${f%.bas}.key" ]; then
		cp "${f%.bas}.key" "$R/$n.KEY"
		k=(--input "$R/$n.KEY")
	fi
	$PY tools/vbasic.py run --rom "$R49" --log "${k[@]}" "$f" | grep -v '^VB GC' > "$R/exp/$n.log" || true
	names+=("$n")
done
rm -f "$R/all.txt"
for ((i = 0; i < ${#names[@]}; i += 70)); do
	printf '%s\n' "${names[@]:i:70}" > "$R/VBTEST.LST"
	session "$R" host
	cat "$R/console.txt" >> "$R/all.txt"
done
$PY tests/vbasic/check_core.py "$R/all.txt" "$R/exp" --only "${names[@]}" > "$R/check.txt" \
	|| { grep -v '^ok' "$R/check.txt" | head; fail "the core programs from their .bas files"; }
ok "${#names[@]} core programs run from their .bas files (tokenized and prepared by Run, then run): $(tail -1 "$R/check.txt")"
# the screenshot: a .bas run, the console
S=$OUT/shot
mkdir -p "$S"
cp tests/vbasic/shell/hello.bas "$S/Hello from VeraBASIC on the card.bas"
printf 'Hello from VeraBASIC on the card.bas\n!shot\n' > "$S/VBTEST.LST"
cp "$OUT/test/VBRun.cvt" "$S/AUTOSTART.cvt"
cp build/VERANDA.SYS build/VERANDA.PRG "$S/"
emu "$S" console.txt -dump V
$PY tools/vram2png.py --color "$S/dump.bin" "$OUT/console.png" >/dev/null 2>&1 && rm -f "$S/dump.bin" \
	&& ok "a screenshot of Run's console after a .bas run: $OUT/console.png"

# 4. the shell: double clicks
shell_files() {         # $1 the folder
	mkdir -p "$1/Docs"
	cp "$OUT/shsrc/SHELL.cvt" build/VERANDA.SYS "$1/"
	cp "$OUT/test/VBRun.cvt" "$1/VeraBASIC Run.cvt"
	$PY tools/vbasic.py build tests/vbasic/shell/birdwatch.bas -o "$1/Bird Watch from the lake.cvt" >/dev/null
	$PY tools/vbasic.py build tests/vbasic/shell/squares.bas -o "$1/Docs/Squares and a table of them.cvt" >/dev/null
}
E=$OUT/shell-exp
mkdir -p "$E"
i=0
for src in birdwatch squares; do
	i=$((i + 1))
	n=$($PY tests/vbasic/vb_shell_script.py --names | sed -n "${i}p")
	$PY tools/vbasic.py run --rom "$R49" --log tests/vbasic/shell/$src.bas | grep -v '^VB GC' > "$E/$n.log"
done
mapfile -t snames < <($PY tests/vbasic/vb_shell_script.py --names)
shell_check() {         # $1 the console, $2 what
	got=$(tr -d '\r' < "$1" | grep -a -o -E 'SHELL STARTED|SHELL DONE|VB RUN .*|VB END|VB DONE' | sed 's/ *$//')
	want=$($PY tests/vbasic/vb_shell_script.py --want)
	[ "$got" = "$want" ] || { echo "$got" | diff <(echo "$want") - | head -20; fail "$2: the console's lines"; }
	$PY tests/vbasic/check_core.py "$1" "$E" --only "${snames[@]}" > "$OUT/shell-check.txt" \
		|| { grep -v '^ok' "$OUT/shell-check.txt"; fail "$2: the programs' output"; }
	ok "$2: double clicks in the shell started VeraBASIC Run with a program document (its parent class)"
	ok "$2:   and in Docs with another (Run found in the top folder),"
	ok "$2:   long names (${#snames[@]}: $(printf '%s, ' "${snames[@]}" | sed 's/, $//')); each output as the reference's"
}
H=$OUT/shell-host
mkdir -p "$H"
shell_files "$H"
cp build/VERANDA.PRG "$H/"
$PY tests/vbasic/vb_shell_script.py "$H" console.txt || fail "the shell's script"
emu "$H" console.txt -dump V
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "the shell session did not end"; }
shell_check "$H/console.txt" "host folder"
$PY tools/vram2png.py --color "$H/dump.bin" "$OUT/shell.png" >/dev/null 2>&1 && rm -f "$H/dump.bin"

# 5. the SD card image
if [ "${VB_SD:-1}" != 0 ]; then
	g3 sd
	ok "G3 on an SD card image, ROM R49: the same"
	SD=$OUT/shell-sd
	mkdir -p "$SD/card"
	shell_files "$SD/card"
	$PY tests/vbasic/vb_shell_script.py "$SD/card" || fail "the shell's script"
	$PY tools/vcard.py make --mb 64 "$SD/sd.img" "$SD/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$SD/"
	emu "$SD" console.txt -sdcard sd.img -dump V
	[ -f "$SD/dump.bin" ] || { tail -20 "$SD/console.txt"; fail "the SD card's shell session did not end"; }
	shell_check "$SD/console.txt" "SD card image"
	$PY tools/vram2png.py --color "$SD/dump.bin" "$OUT/shell-sd.png" >/dev/null 2>&1 && rm -f "$SD/dump.bin" "$SD/sd.img"
fi
echo "GATE vb_tok: PASS"
