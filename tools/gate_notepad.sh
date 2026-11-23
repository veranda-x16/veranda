#!/bin/bash
# Gate notepad: Note Pad, a desk accessory (apps/notepad) over Paint.
#
#   tools/gate_notepad.sh          (NOTE_SD=0: skip the SD card run)
#
# 1. the SDK installed; Note Pad built against it (a sequential DESK_ACC
#    that keeps the mode) and as test builds (tests/note_script.h), Paint
#    as gate desk's test build (tests/desk_script.h: it opens the first
#    accessory of its list, then draws again when it is back)
# 2. the first session, with a VERANDA folder (the system folder) and no
#    Note File: Note Pad makes one; "Shopping list" etc. typed on page 1,
#    PgDn (a new page), New, PgUp, Delete, "!", the close box
# 3. tests/check_notepad.py: the console in order; both screens and the
#    colour map as they were; VERANDA/Note File.cvt a record file whose
#    records are the two pages left
# 4. the second session, over that Note File: page 1 of 2, Next, Escape
# 5. a screenshot with Note Pad open over Paint (note.png; check_vera.py)
# 6. the first session on an SD card image
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/notepad
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
for s in desk note; do
	$PY tests/${s}_script.py "$OUT/$s.h" && cmp -s "$OUT/$s.h" tests/${s}_script.h \
		|| fail "tests/${s}_script.h is not what tests/${s}_script.py writes"
done

build() {        # $1 folder, $2 the target (all or test), $3 the test's flags
	mkdir -p "$OUT/$1"
	make -s -C apps/notepad $2 SDK="$SDK" OUT="$TOP/$OUT/$1" TESTFLAGS="$3" >"$OUT/$1/build.log" 2>&1 \
		|| { cat "$OUT/$1/build.log"; fail "Note Pad does not build ($1)"; }
}
build app all
field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
N="$OUT/app/Note Pad.cvt"
[ "$(field "$N" 'geos type')" = 5 ] && [ "$(field "$N" structure)" = sequential ] && [ "$(field "$N" mode)" = keep ] \
	|| fail "Note Pad.cvt: not a sequential DESK_ACC that keeps the mode"
ok "Note Pad builds against the installed SDK: a desk accessory (DESK_ACC), $(field "$N" load)-$(field "$N" end)"
build first test -DNOTE_FIRST
build second test ""
mkdir -p "$OUT/paint"
make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$OUT/paint" TESTFLAGS=-DPAINT_DESK >"$OUT/paint/build.log" 2>&1 \
	|| { cat "$OUT/paint/build.log"; fail "Paint's test build"; }

# run Paint with the accessory $1 in folder $2, $3 seconds at most
# (the layout of DECISIONS V71: the accessory in VERANDA/APPS, the Note
# File in VERANDA/.SYSTEM, which Note Pad makes)
run() {
	mkdir -p "$2/VERANDA/APPS"
	cp "$OUT/paint/Paint.cvt" "$2/AUTOSTART.cvt"
	cp "$1" "$2/VERANDA/APPS/Note Pad.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
	(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT "$3" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$2/dump.bin" ] || { tail -5 "$2/console.txt"; fail "the session in $2 did not finish"; }
}
R=$OUT/run1
run "$OUT/first/Note Pad.cvt" "$R" 120
$PY tools/check_vera.py "$R/dump.bin" || fail "the display"
echo "== the first session (no Note File yet), on the host folder"
$PY tests/check_notepad.py "$R" first || fail "the first session"

R2=$OUT/run2
mkdir -p "$R2/VERANDA/.SYSTEM"
cp "$R/VERANDA/.SYSTEM/Note File.cvt" "$R2/VERANDA/.SYSTEM/"
run "$OUT/second/Note Pad.cvt" "$R2" 120
echo "== the second session (the Note File there)"
$PY tests/check_notepad.py "$R2" second || fail "the second session"

shot=$(sed -n 's|^/\* shot note \([0-9]*\) \*/|\1|p' tests/note_script.h)
build shot test "-DNOTE_FIRST -DNOTE_STOP=$shot"
run "$OUT/shot/Note Pad.cvt" "$OUT/shot/run" 60
$PY tools/check_vera.py "$OUT/shot/run/dump.bin" || fail "the display with Note Pad open"
$PY tools/vram2png.py --color "$OUT/shot/run/dump.bin" "$OUT/note.png" 2>/dev/null || true
$PY tests/check_l10_text.py "$OUT/shot/run/dump.bin" "$ROM" "third żółw" || fail "the set's letters on the screen (V143)"
grep -q "NOTE PAGE 3 3" "$OUT/shot/run/console.txt" || fail "the session (stopped) did not get to page 3"
ok "a screenshot with Note Pad open over Paint (page 3): $OUT/note.png"

if [ "${NOTE_SD:-1}" != 0 ]; then
	S=$OUT/sd
	mkdir -p "$S/card/VERANDA/APPS" "$S/out/VERANDA/.SYSTEM"
	cp "$OUT/paint/Paint.cvt" "$S/card/AUTOSTART.cvt"
	cp "$OUT/first/Note Pad.cvt" "$S/card/VERANDA/APPS/"
	cp build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: the session did not finish"; }
	for f in PRE.RAW POST.RAW PRE.MAP POST.MAP; do
		$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null || fail "SD card: no $f"
	done
	$PY tools/vcard.py get "$S/sd.img" "VERANDA/.SYSTEM/Note File.cvt" "$S/out/VERANDA/.SYSTEM/Note File.cvt" >/dev/null \
		|| fail "SD card: no VERANDA/.SYSTEM/Note File.cvt"
	echo "== the first session on an SD card image"
	$PY tests/check_notepad.py "$S/out" first || fail "the session (SD card)"
fi
echo "screenshot: $OUT/note.png (Note Pad over Paint)"
echo "GATE notepad: PASS"
