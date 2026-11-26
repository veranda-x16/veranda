#!/bin/bash
# Gate midiplay (DECISIONS V205): MIDI Player (apps/midiplay) under ROM R49
# at 512 KB. The test build (tests/midiplay_play.c, make test) works the
# program from its main loop and logs the engines' events; the songs are
# made by tests/midiplay_files.py; tests/check_midiplay.py reads the
# console against them.
#
#   tools/gate_midiplay.sh        (OUT=... where the results go, default build/gate/midiplay)
#
# 1. the kernel and the SDK; MIDI Player built against it (MIDIPlay.cvt: an
#    application, banked overlays: the window, ZSMKit's two banks, which
#    must be adjacent) and its test build; the sizes
# 2. host (warp): the folder MUSIC listed; BAD.MID refused; FMT0.MID (format
#    0, running status, drums on channel 10) then by Play next FMT1.MID
#    (format 1, a tempo change, a long note, pitch bend): every note and
#    drum at its frame (60 a second of the song's time) within one frame;
#    paused a second: nothing sounds, the time held; SONG.ZSM (ZSMKit):
#    its key-ons and PSG volume at their ticks; the end of the last song
#    stops; the volume; Alt+Tab (the test desktop tests/term_desk.s brings
#    it back after 3 s): paused aside, going on after; the playlist drawn
#    40 times while it plays: no tick late; quit; the tick's cycles
# 3. doc: a test desktop (tests/midiplay_desk.c) opens /MUSIC/FMT0.MID as the
#    shell opens a document (GetFile, ST_LD_DATA, the program's folder
#    current, the document's in curDirName): it plays, /MUSIC the playlist
# 4. wav (real time, the emulator's -wav ...,wait: the recording starts with
#    the song): sound while FMT1.MID plays, silence while it is paused and
#    after Stop, sound while SONG.ZSM plays, silence after the quit
# Screenshots: $OUT/list.png (the playlist), midi.png (a MIDI song
# playing), zsm.png (the ZSM playing).
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/midiplay}
PY="python3 -I -B"
R49=${R49:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
ROM=${ROM:-$R49}
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

[ -f "$ROM" ] || fail "no ROM at $ROM"
[ -x "$EMU" ] || fail "no emulator at $EMU"
rm -rf "$OUT"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)

# 1. the application and its test build
A=$OUT/app
mkdir -p "$A/rel" "$A/test"
make -s -C apps/midiplay all SDK="$SDK" OUT="$A/rel" > "$A/rel.log" 2>&1 || { cat "$A/rel.log"; fail "apps/midiplay does not build"; }
make -s -C apps/midiplay test SDK="$SDK" OUT="$A/test" > "$A/test.log" 2>&1 || { cat "$A/test.log"; fail "apps/midiplay's test build"; }
$PY - "$A/rel" "$A/test" <<'EOF' || fail "the sizes"
import re, sys
def sizes(d):
    m = open(d + '/midiplay.map').read()
    seg = {g[0]: (int(g[1], 16), int(g[2], 16)) for g in re.findall(r'^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+[0-9A-F]{6}', m, re.M)}
    end = max(seg[s][1] for s in ('CODE', 'RODATA', 'DATA', 'BSS'))
    import os
    za = os.path.getsize(d + '/zsmkit.a')
    zb = os.path.getsize(d + '/zsmkit.b')
    return end, seg['OVERLAY1'][1] - 0x9FFF, za, zb
r, t = sizes(sys.argv[1]), sizes(sys.argv[2])
cvt = len(open(sys.argv[1] + '/MIDIPlay.cvt', 'rb').read())
print('ok    the sizes: MIDIPlay.cvt %d bytes; main RAM $0801-$%04X (%d bytes; the C stack 2 KB below $8800: '
      '%d free; the test build to $%04X); overlay 1 (the window) %d bytes; ZSMKit %d + %d bytes (overlays 2, 3); '
      'RAM banks: 5 for the records (the window, ZSMKit\'s two, the loader\'s padding), 2 the playlist, a song its size in 8 KB banks'
      % (cvt, r[0], r[0] - 0x801, 0x8000 - r[0] - 1, t[0], r[1], r[2], r[3]))
if t[0] >= 0x8000 or max(r[1], t[1], r[2], r[3]) > 8191:
    sys.exit('FAIL  out of room')
EOF
ca65 --cpu 65C02 -I "$SDK/include" -o "$A/desk.o" tests/term_desk.s || fail "tests/term_desk.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/desk.bin" "$A/desk.o" || fail "the test desktop does not link"
printf 'name = SHELL\nclass = TermDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/desk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/SHELL.cvt" "$A/desk.hdr" "$A/desk.bin" >/dev/null || fail "vpack the test desktop"
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$A/docdesk.bin" tests/midiplay_desk.c "$SDK/lib/veranda.lib" \
	> "$A/docdesk.log" 2>&1 || { cat "$A/docdesk.log"; fail "tests/midiplay_desk.c"; }
printf 'name = SHELL\nclass = MpDesk\nmode = 640x480\napi = 6\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/docdesk.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/DOCDESK.cvt" "$A/docdesk.hdr" "$A/docdesk.bin" >/dev/null || fail "vpack the document's test desktop"
ok "MIDI Player builds against the installed SDK (and its test build)"

# a session's folder: $1 the folder, $2 the session
tree() {
	local R=$1
	mkdir -p "$R/VERANDA/.SYSTEM/TASKS" "$R/MUSIC/More"
	$PY tests/midiplay_files.py "$R/MUSIC" || fail "tests/midiplay_files.py"
	mv "$R/MUSIC/expect.json" "$R/"
	echo "$2" > "$R/MP.TST"
	cp "$A/test/MIDIPlay.cvt" "$R/AUTOSTART.cvt"
	cp "$A/SHELL.cvt" build/VERANDA.PRG build/VERANDA.SYS "$R/"
	cp "$A/SHELL.cvt" "$R/VERANDA/"
}

echo "== host, 512 KB: MIDI, ZSM, pause, Play next, Alt+Tab, quit"
R=$OUT/host
tree "$R" host
t0=$(date +%s.%N)
(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 180 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -rtc -ram 512 > console.txt 2>&1) || true
echo "      (host: $(python3 -c "import time; print('%.1f' % (time.time() - $t0))") s)"
[ -f "$R/dump.bin" ] || { tr '\r' '\n' < "$R/console.txt" | grep -a -o 'MP .*\|TERMDESK.*' | tail -20; fail "host: the session did not end"; }
$PY tests/check_midiplay.py host "$R/console.txt" "$R/expect.json" || fail "host"
$PY tests/ftp_shot.py "$R/LIST.RAW" "$OUT/list.png" || fail "list.png"
$PY tests/ftp_shot.py "$R/MIDI.RAW" "$OUT/midi.png" || fail "midi.png"
$PY tests/ftp_shot.py "$R/ZSM.RAW" "$OUT/zsm.png" || fail "zsm.png"

echo "== a document: /MUSIC/FMT0.MID opened as the shell opens it"
R=$OUT/doc
tree "$R" doc
rm "$R/AUTOSTART.cvt"
mkdir -p "$R/VERANDA/APPS"
cp "$A/test/MIDIPlay.cvt" "$R/VERANDA/APPS/MIDI Player.cvt"
cp "$A/DOCDESK.cvt" "$R/SHELL.cvt"
cp "$A/DOCDESK.cvt" "$R/VERANDA/SHELL.cvt"
(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo -dump V -rtc -ram 512 > console.txt 2>&1) || true
[ -f "$R/dump.bin" ] || { tr '\r' '\n' < "$R/console.txt" | grep -a -o 'MP.*' | tail -20; fail "doc: the session did not end"; }
$PY tests/check_midiplay.py doc "$R/console.txt" || fail "doc"

if [ "${MIDIPLAY_WAV:-1}" != 0 ]; then
	echo "== wav (real time): sound and silence"
	R=$OUT/wav
	tree "$R" wav
	(cd "$R" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG \
		-run -echo -dump V -rtc -ram 512 -wav song.wav,wait > console.txt 2>&1) || true
	[ -s "$R/song.wav" ] || { tail -5 "$R/console.txt"; fail "wav: no recording"; }
	$PY tests/check_midiplay.py wav "$R/console.txt" "$R/song.wav" || fail "wav"
fi
echo "screenshots: $OUT/list.png midi.png zsm.png"
echo "GATE midiplay: PASS"
