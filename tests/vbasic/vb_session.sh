#!/bin/bash
# One VeraBASIC Run test session (gates vb_files, vb_ui style): the test
# build runs the programs of a list in a fresh folder under ROM R49.
#
#   tests/vbasic/vb_session.sh DIR TESTCVT DESKCVT PROG.bas ... [-- options]
#     DIR       the session's folder (made anew; the programs' documents,
#               AUTOSTART.cvt, SHELL.cvt, the kernel; PROG.lst lines first
#               when there is one, PROG.ms its mouse script, PROG.dir a
#               folder whose files are copied in first)
#   environment: R49 (the ROM), EMU (x16emu with -mousescript), MAP (the
#   test build's map for the mouse script), MS (another mouse script),
#   TMO (the emulator's time, seconds), SD=1: on an SD card image
#   (tools/vcard.py; the card's files then copied back out into DIR/card)
# The console in DIR/console.txt, Run's lines in DIR/x16.log.
set -e
cd "$(dirname "$0")/../.."
TOP=$(pwd)
D=$1; TEST=$2; DESK=$3; shift 3
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
rm -rf "$D"
mkdir -p "$D/card"
C=$D/card
: > "$C/VBTEST.LST"
echo '!shot' >> "$C/VBTEST.LST"
ms=()
for p in "$@"; do
	n=$(basename "$p" .bas)
	b=$(dirname "$p")/$n
	[ -d "$b.dir" ] && cp -r "$b.dir"/. "$C/"
	if [ -f "$b.lst" ]; then cat "$b.lst" >> "$C/VBTEST.LST"; fi
	grep -q "^!aside\|^!stop" "$b.lst" 2>/dev/null || echo "$n" >> "$C/VBTEST.LST"
	$PY tools/vbasic.py build "$p" -o "$C/$n.cvt" >/dev/null
	[ -f "$b.key" ] && cp "$b.key" "$C/$n.KEY"
	ms1=${MS:-$b.ms}
	if [ -f "$ms1" ]; then
		$PY tests/vbasic/ui_mouse.py "$ms1" "$MAP" "$D/mouse.txt"
		ms=(-mousescript ../mouse.txt)
	fi
done
cp "$TEST" "$C/AUTOSTART.cvt"
cp "$DESK" "$C/SHELL.cvt"
cp build/VERANDA.SYS "$C/"
cp build/VERANDA.PRG "$D/"
cp -r "$C" "$D/init"                # (the folder as the session starts: the reference's)
if [ "${SD:-0}" = 1 ]; then
	$PY tools/vcard.py make --mb 64 "$D/sd.img" "$C" >/dev/null
	[ ${#ms[@]} -gt 0 ] && ms=(-mousescript mouse.txt)
	(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT ${TMO:-600} "$EMU" -rom "$R49" -sdcard sd.img -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump RV "${ms[@]}" > console.txt 2>&1) || true
	# the card's files back out into DIR/card (as the host folder's would be)
	$PY tools/vcard.py ls "$D/sd.img" > "$D/sd.list" 2>/dev/null || true
	rm -rf "$C"
	mkdir -p "$C"
	while IFS= read -r ln; do
		p=$(echo "$ln" | sed 's/  *[0-9]*$//')
		case "$p" in
		*/) mkdir -p "$C/$p" ;;
		*) mkdir -p "$(dirname "$C/$p")"; $PY tools/vcard.py get "$D/sd.img" "$p" "$C/$p" >/dev/null ;;
		esac
	done < "$D/sd.list"
	[ -f "$D/dump.bin" ] || true
else
	(cd "$C" && SDL_VIDEODRIVER=dummy timeout -s INT ${TMO:-600} "$EMU" -rom "$R49" -prg ../VERANDA.PRG -run \
		-warp -sound none -echo -dump RV "${ms[@]}" > ../console.txt 2>&1) || true
	[ -f "$C/dump.bin" ] && mv "$C/dump.bin" "$D/"
fi
python3 -I -B tests/vbasic/vb_log.py "$D/console.txt" > "$D/x16.log"
