#!/bin/bash
# Gate export (docs/PLAN.md phase 9: printing as file export): ExportRect
# writes a screen area to a file as a 1 bpp BMP picture.
#
#   tools/gate_export.sh
#
# 1. tests/export.s as TEST.PRG: a scene on the foreground, another on the
#    back screen; five areas written (the whole foreground, one with its
#    left edge mid-card, one of the back screen, one pixel wide, one
#    clipped), an empty one refused; the VRAM dump at the end
# 2. tests/check_export.py: every file is a 1 bpp BMP equal to the dump's
#    pixels in its area, with VERA's paper and ink as its palette, and
#    Pillow reads it (on the host folder)
# 3. the same on an SD card image (tools/vcard.py), the files copied out
# Paint's file/export is in gate paint (tools/gate_paint.sh).
# Pictures: build/gate/export/full.png, part.png, back.png (the BMP files
# as Pillow reads them), screen.png (the dump).
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/export
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/host"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
H=$OUT/host
ca65 --cpu 65C02 -I build/gen -I inc tests/export.s -o "$H/export.o" || fail "tests/export.s does not assemble"
ca65 tests/prghdr.s -o "$H/prghdr.o"
ld65 -C cfg/testprg.cfg "$H/prghdr.o" "$H/export.o" -o "$H/TEST.PRG" || fail "tests/export.s does not link"
cp build/VERANDA.PRG build/VERANDA.SYS "$H/"
(cd "$H" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$H/dump.bin" ] || { tail -20 "$H/console.txt"; fail "the test did not finish"; }
$PY tools/vram2png.py "$H/dump.bin" "$OUT/screen.png" 2>/dev/null || true
$PY tools/check_vera.py "$H/dump.bin" || fail "the display does not show the bitmap"
echo "== on the host folder"
$PY tests/check_export.py "$H" "$OUT" || fail "the pictures (host folder)"

S=$OUT/sd
mkdir -p "$S/card" "$S/out"
cp "$H/TEST.PRG" build/VERANDA.SYS "$S/card/"
$PY tools/vcard.py make --mb 64 "$S/sd.img" "$S/card" >/dev/null || fail "vcard make"
cp build/VERANDA.PRG "$S/"
(cd "$S" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
	-run -warp -sound none -echo -dump V > out/console.txt 2>&1) || true
[ -f "$S/dump.bin" ] || { tail -20 "$S/out/console.txt"; fail "SD card: the test did not finish"; }
mv "$S/dump.bin" "$S/out/"
for f in FULL PART BACK THIN CLIP; do
	$PY tools/vcard.py get "$S/sd.img" "$f.BMP" "$S/out/$f.BMP" >/dev/null || fail "SD card: no $f.BMP"
done
echo "== on an SD card image"
$PY tests/check_export.py "$S/out" || fail "the pictures (SD card)"
echo "pictures: $OUT/full.png, part.png, back.png (the files), screen.png (the dump)"
echo "GATE export: PASS"
