#!/bin/bash
# A gate's session folder shot again, light or dark (DECISIONS V148: the
# before and after pictures of Look 3's stage D).
#
#   tools/sunshot.sh <session folder> <out.png> [dark] [timeout]
#
# The folder is one a gate made for a host-folder run (VERANDA.PRG,
# VERANDA.SYS, the program as AUTOSTART.cvt, its script; the session
# stops itself with a VRAM dump). It is copied (the gate's own is not
# touched); "dark": a settings file with Sunroom in dark mode
# (tests/check_theme.py prefs ... 3 14 5 5 129) put into its
# VERANDA/.SYSTEM; then the emulator, then tools/vram2png.py --color.
set -e
SRC=$(realpath -m "${1:-.}"); OUTP=$(realpath -m "${2:-x.png}")
cd "$(dirname "$0")/.."
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
[ -d "$SRC" ] && [ -n "$2" ] || { sed -n '2,13p' "$0"; exit 1; }
mkdir -p "$(dirname "$OUTP")"
T=$(mktemp -d "${TMPDIR:-/tmp}/sunshot.XXXXXX")
cp -r "$SRC"/. "$T/"
rm -f "$T/dump.bin"
mkdir -p "$T/VERANDA/.SYSTEM"
if [ "$3" = dark ]; then
	$PY tests/check_theme.py prefs "$T/VERANDA/.SYSTEM/Veranda Prefs.cvt" 3 14 5 5 129
fi
cp build/VERANDA.PRG build/VERANDA.SYS "$T/" 2>/dev/null || true
(cd "$T" && SDL_VIDEODRIVER=dummy timeout -s INT "${4:-300}" "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V > console.txt 2>&1) || true
[ -f "$T/dump.bin" ] || { tail -3 "$T/console.txt"; echo "sunshot: no dump"; rm -rf "$T"; exit 1; }
$PY tools/vram2png.py --color "$T/dump.bin" "$OUTP" >/dev/null
rm -rf "$T"
echo "$OUTP"
