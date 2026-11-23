#!/bin/bash
# Gate clip (docs/DECISIONS.md V54): the clipboard, GEOS's Text Scrap and
# Photo Scrap, through the SDK's scrap library (sdk/lib/scrap.h).
#
#   tools/gate_clip.sh          (CLIP_SD=0: skip the SD card run)
#
# 1. make api, the kernel, the SDK into build/gate/clip/sdk; Paint and the
#    two managers (apps/scrapman: Photo Manager, Text Manager, desk
#    accessories) built against it
# 2. a Text Scrap in geoWrite 2.1's format (tests/check_clip.py
#    --fixture: what its saveTextscrap writes through SaveFile) put in
#    the system folder /VERANDA of the run folder; the applications are
#    in the top folder (the library finds /VERANDA itself)
# 3. Paint's session (tests/clip_script.h, PAINT_CLIP): select, copy;
#    stopped there once: VERANDA/.SYSTEM/Photo Scrap.cvt checked on the host (the
#    CVT, the class, geoWrite's rules, the compacted bitmap equal to the
#    selection on the back screen, the colours the cards')
# 4. the whole session: paste (floating, put down elsewhere: both screens
#    and the cards' colours checked), the Photo Manager (add: Photo
#    Album.cvt; copy), cut (the scrap is the area as it was, the area
#    empty), the Text Manager (add the geoWrite scrap: Text Album.cvt;
#    copy: the Text Scrap byte for byte); scrap_stamp changes
# 5. Veranda Term's edit/copy screen (TERM_CLIP: tests/term_test.c's
#    script back-end, the ANSI page): the Text Scrap's text equals the
#    terminal's screen as the reference terminal makes it; in a folder
#    with no /VERANDA: the scrap in the root
# 6. screenshots: the selection, the picture floating, put down, the
#    Photo Manager and the Text Manager over Paint
# 7. the session on an SD card image (tools/vcard.py; /VERANDA on it)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/clip
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
[ -f "$SDK/include/scrap.h" ] && ar65 t "$SDK/lib/veranda.lib" | grep -q scrapio || fail "the SDK has no scrap library"
ok "the SDK has the clipboard: include/scrap.h, lib/veranda.lib (scrapio, scraptext, scrapphoto)"

$PY tests/clip_script.py "$OUT" || fail "tests/clip_script.py"
for s in clip photoman textman; do
	cmp -s "$OUT/${s}_script.h" tests/${s}_script.h || fail "tests/${s}_script.h is not what tests/clip_script.py writes"
done

field() { $PY "$SDK/tools/vpack.py" --list "$1" | sed -n "s/^$2 *//p"; }
mkdir -p "$OUT/app" "$OUT/test"
make -s -C apps/scrapman SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/build.log" 2>&1 \
	|| { cat "$OUT/app/build.log"; fail "the managers do not build"; }
for m in PhotoMgr TextMgr; do
	C=$OUT/app/$m.cvt
	[ "$(field "$C" 'geos type')" = 5 ] && [ "$(field "$C" structure)" = sequential ] && [ "$(field "$C" mode)" = keep ] \
		|| fail "$m.cvt: not a sequential DESK_ACC that keeps the mode"
	end=$(field "$C" end)
	[ $((16#${end#\$})) -le $((16#8000)) ] || fail "$m.cvt ends at $end"
	ok "$(field "$C" name): a desk accessory (DESK_ACC), $(field "$C" load)-$end"
done
make -s -C apps/paint SDK="$SDK" OUT="$TOP/$OUT/app" >"$OUT/app/paint.log" 2>&1 \
	|| { cat "$OUT/app/paint.log"; fail "Paint does not build"; }
end=$(field "$OUT/app/Paint.cvt" end)
[ $((16#${end#\$})) -le $((16#8000)) ] || fail "Paint.cvt ends at $end"
ok "Paint with the clipboard builds: \$0801-$end"

# the test builds: Paint's session, the managers' (TESTFLAGS: a stop)
build_paint() {      # out dir, flags
	mkdir -p "$1"
	make -s -C apps/paint test SDK="$SDK" OUT="$TOP/$1" TESTFLAGS="-DPAINT_CLIP $2" >"$1/build.log" 2>&1 \
		|| { cat "$1/build.log"; fail "Paint's test build ($2)"; }
}
build_man() {
	mkdir -p "$1"
	make -s -C apps/scrapman test SDK="$SDK" OUT="$TOP/$1" TESTFLAGS="$2" >"$1/build.log" 2>&1 \
		|| { cat "$1/build.log"; fail "the managers' test builds ($2)"; }
}
build_paint "$OUT/test"
build_man "$OUT/test"
$PY tests/check_clip.py --fixture "$OUT/fixture.cvt" || fail "the geoWrite-format fixture"

# a run folder: Paint as AUTOSTART, the managers in /VERANDA/APPS, the
# geoWrite Text Scrap in /VERANDA/.SYSTEM (the layout of DECISIONS V71);
# $1 Paint, $2 the managers' dir, $3 the folder, $4 s
run() {
	mkdir -p "$3/VERANDA/.SYSTEM" "$3/VERANDA/APPS"
	cp "$1" "$3/AUTOSTART.cvt"
	cp "$2/PhotoMgr.cvt" "$3/VERANDA/APPS/Photo Manager.cvt"
	cp "$2/TextMgr.cvt" "$3/VERANDA/APPS/Text Manager.cvt"
	cp "$OUT/fixture.cvt" "$3/VERANDA/.SYSTEM/Text  Scrap.cvt"
	cp build/VERANDA.PRG build/VERANDA.SYS "$3/"
	(cd "$3" && SDL_VIDEODRIVER=dummy timeout -s INT "$4" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
}
shot() { sed -n "s|^/\* shot $1 \([0-9]*\) \*/|\1|p" tests/$2; }

echo "== edit/copy (the session stopped after it)"
CP=$OUT/copy
build_paint "$CP" "-DPAINT_STOP=$(shot copied clip_script.h)"
run "$CP/Paint.cvt" "$OUT/test" "$CP/run" 60
[ -f "$CP/run/dump.bin" ] || { tail -5 "$CP/run/console.txt"; fail "no dump after the copy"; }
$PY tests/check_clip.py --copy "$CP/run" || fail "the Photo Scrap after edit/copy"

echo "== the whole session on the host folder"
R=$OUT/run
run "$OUT/test/Paint.cvt" "$OUT/test" "$R" 240
[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "the session did not finish"; }
$PY tools/check_vera.py "$R/dump.bin" || fail "the display"
$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/end.png" 2>/dev/null || true
$PY tests/check_clip.py "$R" "$CP/run" "$OUT/fixture.cvt" || fail "the session (host folder)"

echo "== Veranda Term: options/copy screen (no /VERANDA here: the scrap in the root)"
TM=$OUT/term
mkdir -p "$TM/run"
make -s -C apps/term test SDK="$SDK" OUT="$TOP/$TM" TESTFLAGS=-DTERM_CLIP >"$TM/build.log" 2>&1 \
	|| { cat "$TM/build.log"; fail "Veranda Term's test build (TERM_CLIP)"; }
$PY tests/term_bbs.py --page "$TM/run/TERM.IN"
cp "$TM/Term.cvt" "$TM/run/AUTOSTART.cvt"
cp build/VERANDA.PRG build/VERANDA.SYS "$TM/run/"
echo "page end 4 0" > "$TM/run/TERM.TST"
(cd "$TM/run" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
grep -q "TERM COPIED" "$TM/run/console.txt" || { tail -5 "$TM/run/console.txt"; fail "Term: no TERM COPIED"; }
[ ! -e "$TM/run/VERANDA" ] || fail "Term: a VERANDA folder appeared"
$PY tests/check_clip.py --term "$TM/run/Text  Scrap.cvt" "$TM/run/TERM.IN" || fail "Term's copy"

echo "== screenshots"
for name in select floating pasted; do
	T=$OUT/shot-$name
	build_paint "$T" "-DPAINT_STOP=$(shot $name clip_script.h)"
	run "$T/Paint.cvt" "$OUT/test" "$T/run" 60
	[ -f "$T/run/dump.bin" ] || fail "no dump at the shot $name"
	$PY tools/check_vera.py "$T/run/dump.bin" || fail "$name: the display"
	$PY tools/vram2png.py --color "$T/run/dump.bin" "$OUT/$name.png" 2>/dev/null || true
done
for name in photoman textman; do
	T=$OUT/shot-$name
	build_man "$T" "-DMAN_STOP=$(shot $name ${name}_script.h)"
	[ $name = textman ] && cp "$OUT/test/PhotoMgr.cvt" "$T/"      # (only the Text Manager stops)
	run "$OUT/test/Paint.cvt" "$T" "$T/run" 200
	[ -f "$T/run/dump.bin" ] || fail "no dump at the shot $name"
	$PY tools/check_vera.py "$T/run/dump.bin" || fail "$name: the display"
	$PY tools/vram2png.py --color "$T/run/dump.bin" "$OUT/$name.png" 2>/dev/null || true
	grep -q "MAN ADDED" "$T/run/console.txt" || fail "$name: the page was not added"
done
$PY tests/check_clip.py --floating "$OUT/shot-floating/run/dump.bin" "$CP/run" || fail "the floating picture"

if [ "${CLIP_SD:-1}" != 0 ]; then
	echo "== the same on an SD card image"
	S=$OUT/sd
	mkdir -p "$S/card/VERANDA/.SYSTEM" "$S/card/VERANDA/APPS" "$S/out/VERANDA/.SYSTEM"
	cp "$OUT/test/Paint.cvt" "$S/card/AUTOSTART.cvt"
	cp "$OUT/test/PhotoMgr.cvt" "$S/card/VERANDA/APPS/Photo Manager.cvt"
	cp "$OUT/test/TextMgr.cvt" "$S/card/VERANDA/APPS/Text Manager.cvt"
	cp "$OUT/fixture.cvt" "$S/card/VERANDA/.SYSTEM/Text  Scrap.cvt"
	cp build/VERANDA.SYS "$S/card/"
	$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
	cp build/VERANDA.PRG "$S/"
	(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
		-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
	[ -f "$S/dump.bin" ] || { tail -5 "$S/out/console.txt"; fail "SD card: the session did not finish"; }
	mv "$S/dump.bin" "$S/out/"
	for f in "VERANDA/.SYSTEM/Photo Album.cvt" "VERANDA/.SYSTEM/Text Album.cvt" PRECUT.RAW COPY.MAP PASTE.MAP CUT.MAP \
		"VERANDA/.SYSTEM/Photo Scrap.cvt" "VERANDA/.SYSTEM/Text  Scrap.cvt"; do
		$PY tools/vcard.py get "$S/sd.img" "$f" "$S/out/$f" >/dev/null || fail "SD card: no $f"
	done
	$PY tests/check_clip.py "$S/out" "$CP/run" "$OUT/fixture.cvt" || fail "the session (SD card)"
fi
echo "screenshots: $OUT/select.png (the selection), floating.png (the paste under the pointer),"
echo "             pasted.png (put down), photoman.png (the Photo Manager), textman.png (the Text Manager), end.png"
echo "GATE clip: PASS"
