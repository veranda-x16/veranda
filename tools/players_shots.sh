#!/bin/bash
# Pictures of MIDI Player's and VIDKIT Player's Look 3 icons (DECISIONS
# V207), light and dark, on the plain desktop and on Still Water: the Apps
# window (a package's whole APPS folder) in large icons (page 1: MIDI
# Player; page 2: VIDKIT Player) with both pinned to the dock, the Apps
# window in the list, and a Music folder in Documents (MIDI, ZSM, ZCM,
# WAV and SPV files) in large icons and in the list.
#
#   tools/players_shots.sh          (after tools/gate_tile.sh: its shell,
#                                    its wallpapers)
#
# APPS=<folder> (default the newest ~/Projects/veranda-dist/pkg-*/VERANDA/APPS).
# Out: build/players/<desktop>-<light|dark>-<shot>.png
#
# MIT licence (see LICENSE).
set -e
cd "$(dirname "$0")/.."
G=build/gate/tile
OUT=build/players
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
APPS=${APPS:-$(ls -td "$HOME"/Projects/veranda-dist/pkg-*/VERANDA/APPS 2>/dev/null | head -1)}
DARK="3 14 5 5 129"
fail() { echo "FAIL  $*"; exit 1; }
[ -f "$G/src/SHELL.cvt" ] && [ -f "$G/wall/Still Water.cvt" ] || fail "run tools/gate_tile.sh first"
[ -d "$APPS" ] || fail "no APPS folder (APPS=<folder>)"
rm -rf "$OUT"
mkdir -p "$OUT"

shot() {        # $1 the desktop (plain, water), $2 light or dark, $3 the shot
	local R=$OUT/run/$1-$2-$3
	mkdir -p "$R/VERANDA/WALLPAPERS" "$R/VERANDA/.SYSTEM" "$R/VERANDA/APPS" "$R/DOCUMENTS/Music"
	cp "$G/src/SHELL.cvt" "$R/VERANDA/"
	cp build/VERANDA.SYS build/VERANDA.PRG "$R/"
	cp "$G/wall/Still Water.cvt" "$R/VERANDA/WALLPAPERS/"
	if [ "$1" = water ]; then
		$PY - "$R/VERANDA/.SYSTEM/WALLPAPER.CFG" <<'EOF'
import sys
c = bytearray(64)
c[0:3] = b'WP\x01'
c[8:8 + 11] = b'Still Water'
d = b'/VERANDA/WALLPAPERS'
c[32:32 + len(d)] = d
open(sys.argv[1], 'wb').write(bytes(c))
EOF
	fi
	[ "$2" = light ] || $PY tests/check_theme.py prefs "$R/VERANDA/.SYSTEM/Veranda Prefs.cvt" $DARK
	cp "$APPS"/*.cvt "$R/VERANDA/APPS/"
	echo "a note" > "$R/DOCUMENTS/Note.txt"
	for f in "Canyon.mid" "Nightbirds.mid" "Winter.mid" "Overture.midi" "Xenon.zsm" "Chime.zcm" "Hello.wav" "Harbour.spv"; do
		echo x > "$R/DOCUMENTS/Music/$f"
	done
	$PY - "$R" "$3" <<'EOF'
import os, sys
sys.path.insert(0, 'tests')
import shell_script as ss
d, what = sys.argv[1], sys.argv[2]
apps = ['..'] + ss.listing([], sorted(n for n in os.listdir(os.path.join(d, 'VERANDA', 'APPS')) if n.endswith('.cvt')))
p = ss.Part()
p.wait(30)
if what.startswith('apps'):
    p.click(*ss.place(1))
    p.wait(60)
    p.click(*ss.cell(apps.index('MIDI Player.cvt')))
    p.wait(10)
    p.menu('options', 'pin')
    p.wait(30)
    p.menu('page', 'next')
    p.wait(60)
    p.click(*ss.cell(apps.index('VIDKIT Player.cvt') - 20))
    p.wait(10)
    p.menu('options', 'pin')
    p.wait(30)
    p.menu('select', 'none')
    p.wait(30)
    if what == 'apps1':
        p.menu('page', 'previous')
        p.wait(60)
    if what == 'appslist':
        p.menu('page', 'previous')
        p.wait(60)
        p.menu('view', 'name')
        p.wait(60)
else:
    p.click(*ss.place(2))
    p.wait(60)
    docs = ['..'] + ss.listing(['Music'], ['Note.txt'])
    p.dbl(*ss.cell(docs.index('Music')))
    p.wait(90)
    if what == 'musiclist':
        p.menu('view', 'name')
        p.wait(60)
p.wait(60)
p.end(ss.END_DONE)
ss.write(os.path.join(d, 'SHELL.TST'), [p])
EOF
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	[ -f "$R/dump.bin" ] || { tail -5 "$R/console.txt"; fail "$1 $2 $3: the session did not end"; }
	$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/$1-$2-$3.png" 2>/dev/null || fail "vram2png"
	echo "$OUT/$1-$2-$3.png"
}

for desk in plain water; do
	for th in light dark; do
		for s in apps1 apps2 appslist music musiclist; do
			shot $desk $th $s
		done
	done
done
