#!/bin/bash
# Veranda Look 3's pictures (DECISIONS V132, V133): the shell in the
# emulator with the mockups' folder (the proposal's 14 programs, a folder,
# a note), in icon view, list view, small icons (V151), with the File menu open and with
# Veranda > About, light and dark; each beside its mockup.
#
#   tools/look3_shots.sh [<APPS folder of a package>] [<mockups folder>]
#
# The programs come from a package's VERANDA/APPS (read only; default
# ~/Projects/veranda-dist/pkg-9277017/VERANDA/APPS); this repository's
# get their colour icon added (vpack.py --icon3 apps/*/icon.txt), the
# others take the shell's library's (shell/icons3.txt). Out: build/look3/
#   <what>-light.png, <what>-dark.png   the emulator's screen
#   side-<what>.png                     mockup | emulator (light)
set -e
cd "$(dirname "$0")/.."
OUT=build/look3
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
APPS=${1:-$HOME/Projects/veranda-dist/pkg-9277017/VERANDA/APPS}
MOCK=${2:-$HOME/Projects/veranda-dist/plans/look3}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
SDK=$OUT/sdk

mkdir -p "$OUT"
make -s api >/dev/null
make -s all >/dev/null
tools/mksdk.sh "$SDK" >/dev/null
rm -rf "$OUT/src"
mkdir -p "$OUT/src"
cp shell/*.c shell/*.h shell/*.s shell/*.inc shell/Makefile shell/app.hdr shell/icon.pbm shell/icons3.txt shell/icons3s.txt "$OUT/src/"
make -s -C "$OUT/src" SDK="$(realpath "$SDK")" >/dev/null 2>&1 || { echo "the shell does not build"; exit 1; }
mkdir -p "$OUT/fonts"
$PY tools/fontcvt.py testfonts "$OUT/fonts" >/dev/null

PROGS=("Paint" "Veranda Write" "Veranda Calc" "Calendar" "Veranda Edit" "Veranda Gemini" "Veranda Claude"
       "Veranda Ask" "Preferences" "Solitaire" "MOD Player" "Disk Tools" "Veranda Update" "About this X16")
folder() {      # <dir> <what> <dark>
	rm -rf "$1"
	mkdir -p "$1/VERANDA/.SYSTEM" "$1/VERANDA/FONTS" "$1/DOCUMENTS/Letters"
	cp "$OUT/src/SHELL.cvt" "$1/VERANDA/"
	cp build/VERANDA.SYS "$1/"
	cp "$OUT/fonts/Gate Sans.cvt" "$1/VERANDA/FONTS/"
	for p in "${PROGS[@]}"; do
		f="$APPS/$p.cvt"
		[ -f "$f" ] || continue
		hdr=$(grep -l "^name *= *$p\$" apps/*/app.hdr 2>/dev/null | head -1)
		if [ -n "$hdr" ] && [ -f "$(dirname "$hdr")/icon.txt" ]; then
			$PY tools/vpack.py -o "$1/DOCUMENTS/$p.cvt" --icon3 "$(dirname "$hdr")/icon.txt" "$f"
		else
			cp "$f" "$1/DOCUMENTS/"
		fi
	done
	echo "Dear Ada, the garden is in bloom." > "$1/DOCUMENTS/Note.txt"
	[ "$3" = dark ] && $PY tests/check_theme.py prefs "$1/VERANDA/.SYSTEM/Veranda Prefs.cvt" 3 14 5 5 129
	$PY tests/look3_script.py "$1" "$2" "Veranda Gemini.cvt"
}
for what in icons list small menu about; do
	for mode in light dark; do
		R=$OUT/run/$what-$mode
		folder "$R" $what $mode
		cp build/VERANDA.PRG "$R/"
		(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump V > console.txt 2>&1) || true
		[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; echo "$what $mode: no dump"; exit 1; }
		$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/$what-$mode.png" >/dev/null
		echo "$OUT/$what-$mode.png"
	done
done
$PY - "$OUT" "$MOCK" <<'EOF'
import sys
from PIL import Image, ImageDraw
out, mock = sys.argv[1:]
for what, m in (('icons', 'A-desktop.png'), ('list', 'A-list.png'), ('small', 'A-list.png'), ('menu', 'A-list.png'),
                ('about', 'A-app.png')):
    a = Image.open('%s/%s' % (mock, m)).convert('RGB')
    b = Image.open('%s/%s-light.png' % (out, what)).convert('RGB').resize(a.size)
    im = Image.new('RGB', (a.width * 2 + 8, a.height + 20), (255, 255, 255))
    im.paste(a, (0, 20))
    im.paste(b, (a.width + 8, 20))
    d = ImageDraw.Draw(im)
    d.text((4, 4), 'mockup (plans/look3/%s)' % m, fill=(0, 0, 0))
    d.text((a.width + 12, 4), 'x16emu: the shell (%s)' % what, fill=(0, 0, 0))
    im.save('%s/side-%s.png' % (out, what))
    print('%s/side-%s.png' % (out, what))
EOF
