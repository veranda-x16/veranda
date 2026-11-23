#!/bin/bash
# Gate vb_files (VeraBASIC phase 4, docs/DECISIONS.md V90): the Veranda
# extensions, part 2 (dialogs, files and folders, the clipboard, icons,
# tiles, pictures, sprites) in VeraBASIC Run, against tools/vbasic.py run
# --replay --dir, the reference, which does the files on the host too.
#
#   tools/gate_vb_files.sh   (OUT=dir; R49=the ROM image; EMU_MOUSE=an
#                             x16emu with -mousescript; VB_JOBS=n; VB_SD=0:
#                             no SD card image)
#
# 1. the kernel and the SDK; VeraBASIC Run (release: main RAM's room for a
#    program's names, every overlay in its bank, the C overlays' two banks
#    and their part in main RAM) and its test build; the test desktop
# 2. the sessions, each in a folder of its own under ROM R49, with real
#    mouse input where a program has a script (tests/vbasic/files/NAME.ms:
#    tests/vbasic/ui_mouse.py, "dialog N" waits for a box): files (long
#    names of 63 characters, PRINT #, INPUT #, LINE INPUT #, GET #, PUT #,
#    SEEK, LOF, LOC, EOF, "m", the folders), errs (every file error caught
#    by TRY, ERRFILE the kernel's), dir (DIR$), dlg (MSGBOX, ASK,
#    INPUTBOX$, a DIALOG block), fsel (the Open and Save dialog: a folder
#    entered, a long name typed, a file opened, Cancel), pict (PICTURE$,
#    BITMAP, ICON, SPRITE, TILE, the clipboard), the four examples
#    (docs/vbasic/examples: notes, dice, addressbook, tiles) and the
#    extensions chapter's part 2 (docs/vbasic/manual/extensions2.md)
# 3. each: Run's log equals the reference's on Run's values and events
#    (tests/vbasic/vb_compare.sh), and the folder Run left equals the
#    reference's, file for file, byte for byte (the scraps apart); the Text
#    Scrap as Veranda Edit writes it (tests/vbasic/check_files.py), the
#    Photo Scrap whole, DIR$'s names the folder's
# 4. the same on an SD card image (tools/vcard.py; the card's files copied
#    back out and compared the same way), and there alone abspath (names
#    from the top, "/dir/name", from a folder below it: x16emu's host
#    folder fails a new file so named, V106)
# 5. screenshots: Notes with its Save dialog, Dice, the Address book's
#    DIALOG being filled in
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_files}
PY="python3 -I -B"
EMU=${EMU_MOUSE:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
JOBS=${VB_JOBS:-6}
F=tests/vbasic/files

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$R49" ] || fail "no ROM R49 at $R49"
{ "$EMU" -help 2>&1 || true; } | grep -q -- -mousescript || fail "$EMU has no -mousescript (the emulator's branch mousescript)"
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
seg() { sed -n "s/^$2  *\([0-9A-F]*\)  *\([0-9A-F]*\).*/\1 \2/p" "$1"; }
end=$(seg "$OUT/app/vbrun.map" BSS | cut -d' ' -f2)
stk=$(sed -n 's/.*__STACKSIZE__=\(0x[0-9A-F]*\).*/\1/p' apps/vbasic/Makefile)
room=$(( 0x8800 - stk - 16#$end - 1 ))
[ "$room" -ge 2048 ] || fail "main RAM: $room bytes left for the program's names (2048 at least)"
sizes=""
for n in 1 2 3 4 5 6 7 8 9; do
	e=$(seg "$OUT/app/vbrun.map" "OVL${n}BSS" | cut -d' ' -f2)
	[ -n "$e" ] || e=$(seg "$OUT/app/vbrun.map" "OVERLAY$n" | cut -d' ' -f2)
	s=$(( 16#$e - 0xA000 + 1 ))
	[ "$s" -le 8192 ] || fail "overlay $n: $s bytes with its BSS"
	sizes="$sizes $n:$s"
done
a=$(stat -c %s "$OUT/app/vbc.a")
b=$(seg "$OUT/app/vbc.map" BBSS | cut -d' ' -f2)
b=$(( 16#$b - 0xA000 + 1 ))
low=$(( 16#$(seg "$OUT/app/vbc.map" RODATA | cut -d' ' -f2) - 16#$(seg "$OUT/app/vbc.map" CODE | cut -d' ' -f1) + 1 ))
[ "$a" -le 8192 ] && [ "$b" -le 8192 ] || fail "the C overlays: A $a, B $b bytes"
[ "$low" -le 2048 ] || fail "the C overlays' part in main RAM: $low bytes (the console's font: 2048)"
ok "VeraBASIC Run builds: main RAM to \$$end, $room bytes for a program's procedures and names; the overlays with their BSS:$sizes; the C overlays A $a, B $b (records 10, 11), their libraries' part $low bytes run in the console font's place"
make -s -C apps/vbasic test SDK="$SDK" OUT="$TOP/$OUT/test" >"$OUT/test/build.log" 2>&1 \
	|| { cat "$OUT/test/build.log"; fail "the test build does not build"; }
ca65 --cpu 65C02 -I "$SDK/include" -o "$OUT/desk/desk.o" tests/vbasic/vb_desk.s || fail "tests/vbasic/vb_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$OUT/desk/desk.bin" "$OUT/desk/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = VbDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$OUT/desk/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OUT/desk/SHELL.cvt" "$OUT/desk/desk.hdr" "$OUT/desk/desk.bin" >/dev/null \
	|| fail "vpack the test desktop"
ok "the test build (VB_TEST) and the test desktop"

# the programs: the tests, the examples, the chapter's listings
P=$OUT/progs
mkdir -p "$P"
cp -r "$F"/*.bas "$F"/*.ms "$F"/*.dir "$P/"
for e in notes dice addressbook tiles; do cp "docs/vbasic/examples/$e.bas" "$P/"; done
$PY tests/vbasic/doclistings.py "$P" docs/vbasic/manual/extensions2.md > "$OUT/listings.txt" 2>/dev/null \
	|| fail "the chapter's listings"
nl=$(wc -l < "$OUT/listings.txt")
ok "the programs: $(ls "$P"/*.bas | wc -l) (the 4 examples of docs/vbasic/examples, the chapter's $nl listings)"

# 2. the sessions: $1 the session, $2 SD (0 or 1), then its programs
session() {
	local s=$1 sd=$2
	shift 2
	local d=$OUT/$( [ "$sd" = 1 ] && echo sd || echo host )/$s args=()
	for p in "$@"; do args+=("$P/$p.bas"); done
	SD=$sd TMO=500 MAP="$OUT/test/vbrun.map" EMU="$EMU" R49="$R49" \
		tests/vbasic/vb_session.sh "$d" "$OUT/test/VBRun.cvt" "$OUT/desk/SHELL.cvt" "${args[@]}" >/dev/null 2>&1 \
		|| echo "session" > "$d/fail"
	tests/vbasic/vb_compare.sh "$d" "${args[@]}" > "$d/compare.txt" 2>&1 || echo "compare" >> "$d/fail"
	diff -r -x 'Text  Scrap.cvt' -x 'Photo Scrap.cvt' "$d/card" "$d/ref" > "$d/tree.txt" 2>&1 || echo "tree" >> "$d/fail"
	echo done > "$d/done"
}
export -f session
export OUT P EMU R49 PY
SESSIONS=("files 0 files errs dir" "dlg 0 dlg" "fsel 0 fsel" "pict 0 pict" "notes 0 notes" "dice 0 dice"
	"addressbook 0 addressbook" "tiles 0 tiles")
for n in $(cat "$OUT/listings.txt"); do SESSIONS+=("$n 0 $n"); done
if [ "${VB_SD:-1}" != 0 ]; then
	for s in "${SESSIONS[@]}"; do SESSIONS+=("${s/ 0 / 1 }"); done
	# names from the top while the current folder is not the top (V106):
	# on the SD card image only, x16emu's host folder fails a new file so
	# named (its fault: the folder looked for under the current one)
	SESSIONS+=("abspath 1 abspath")
fi
printf '%s\n' "${SESSIONS[@]}" | xargs -P "$JOBS" -L 1 bash -c 'session "$@"' _
ok "${#SESSIONS[@]} sessions run (R49; the host folder$( [ "${VB_SD:-1}" != 0 ] && echo ' and an SD card image'), $JOBS at a time)"

# 3, 4. the logs, the folders, the scraps, DIR$
for where in host sd; do
	[ -d "$OUT/$where" ] || continue
	nst=0
	for d in "$OUT/$where"/*/; do
		s=$(basename "$d")
		if [ -f "$d/fail" ]; then
			cat "$d/compare.txt" "$d/tree.txt" 2>/dev/null | head -30
			fail "$where/$s: $(tr '\n' ' ' < "$d/fail")"
		fi
		grep -q '^VB DONE' "$d/x16.log" || { tail -5 "$d/x16.log"; fail "$where/$s: the session did not finish"; }
		for r in "$d"/*.ref; do
			tail -1 "$r" | grep -q '^VB END' || fail "$where/$s: $(basename "$r" .ref) did not end by END ($(tail -1 "$r"))"
		done
		nst=$((nst + $(grep -c '^VB> \|^VB= ' "$d/x16.log" || true)))
	done
	$PY tests/vbasic/check_files.py dir "$OUT/$where/files/dir.log" "$OUT/$where/files/card/Listing of a folder" \
		|| fail "$where: DIR$"
	$PY tests/vbasic/check_files.py scrap "$OUT/$where/notes/card" 'The robin came back to the feeder.\nTwo wrens, one blue tit, no crows.\n' \
		|| fail "$where: notes: the Text Scrap"
	$PY tests/vbasic/check_files.py scrap "$OUT/$where/pict/card" 'Copied by VeraBASIC\na second line' \
		|| fail "$where: pict: the Text Scrap"
	$PY tests/vbasic/check_files.py photo "$OUT/$where/pict/card" 2 12 || fail "$where: pict: the Photo Scrap"
	n63=$(find "$OUT/$where/files/card" -type f -name '*' | awk -F/ 'length($NF) == 63' | wc -l)
	[ "$n63" -ge 2 ] || fail "$where: files of 63-character names on the card: $n63"
	ok "$where: every session logs as the reference ($nst statements' and functions' lines), the folders equal the reference's; $n63 files of 63-character names"
done

# 5. screenshots: the sessions stopped where they are worth a look
shot() {
	local n=$1 ms=$2 d=$OUT/shot/$1
	MS="$ms" TMO=300 MAP="$OUT/test/vbrun.map" EMU="$EMU" R49="$R49" \
		tests/vbasic/vb_session.sh "$d" "$OUT/test/VBRun.cvt" "$OUT/desk/SHELL.cvt" "$P/$n.bas" >/dev/null 2>&1 || true
	[ -f "$d/dump.bin" ] && $PY "$SDK/tools/vram2png.py" --color "$d/dump.bin" "$OUT/$n.png" >/dev/null
	[ -f "$OUT/$n.png" ] || fail "screenshot $n"
}
mkdir -p "$OUT/shot"
sed '/^dialog 3/q' "$F/notes.ms" > "$OUT/shot/notes.ms"
printf 'pause 60\nexit\n' >> "$OUT/shot/notes.ms"
sed '/^events 3/q' "$F/dice.ms" > "$OUT/shot/dice.ms"
printf 'pause 60\nexit\n' >> "$OUT/shot/dice.ms"
sed '/^type 555 1906/q' "$F/addressbook.ms" > "$OUT/shot/addressbook.ms"
printf 'pause 60\nexit\n' >> "$OUT/shot/addressbook.ms"
shot notes "$OUT/shot/notes.ms"
shot dice "$OUT/shot/dice.ms"
shot addressbook "$OUT/shot/addressbook.ms"
ok "screenshots: $OUT/notes.png (the Save dialog), $OUT/dice.png, $OUT/addressbook.png (its DIALOG)"
echo "GATE vb_files: PASS"
