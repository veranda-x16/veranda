#!/bin/bash
# Gate sound (DECISIONS V69): the system sounds (PlaySound, Beep, the
# kernel's events, the settings).
#
#   tools/gate_sound.sh           (SOUND_WAV=0: skip the WAV recording)
#
# 1. table: tests/sound.s (TEST.PRG) plays every sound, Beep, the menu tick
#    on, the volume at 31 and 0, the sounds off with a sentinel in voices
#    14 and 15, a sound replacing another, the alarm not replaced; a watch
#    in intFirstVector logs voices 15 and 14 whenever they change;
#    tests/check_sound.py replays the run in tools/mksounds.py's model of
#    the player: the registers at every frame must be the table's; every
#    sounding write as real VERA needs it (L and R, a volume, a wide pulse;
#    V72), each sound loud, blocks saved before V72 at full volume
# 2. keep: the shell (as at power-on: the menu ticks off), AppOne started
#    and back, disk > empty trash (YES), options > BASIC (keep Veranda); from
#    the dump, the kernel's log of sounds played (bank G2's sndLog): the
#    start-up chime once, SND_APP, SND_WARNING, SND_TRASH, SND_EXIT; no
#    menu tick; voices 14 and 15 silent in BASIC (the exit sound played to
#    its end before the ROM's interrupt came back)
# 3. resume: "Veranda Prefs" with the menu ticks on; a desk accessory
#    opened and closed, BASIC (keep), SYS 35328, Quit Veranda: the chime,
#    ticks, SND_OPEN, SND_CLOSE, SND_EXIT; back from BASIC the chime again,
#    SND_EXIT at the quit
# 3c. prefs (V72): the user's card's "Veranda Prefs.cvt" (V65's Preferences:
#    byte 15 0) read at boot: kSndAtt 0, the sounds on, the chime and the
#    exit sound recorded at full volume
# 4. pcm: gate audio's synthetic mixer (tests/audio, BURN 82: 87 % of the
#    CPU on PCM from AFLOW) with a sound started every 40 frames while it
#    mixes: 0 underruns, the sounds heard on voice 15
# 5. wav: every sound recorded by the emulator (-wav, real time, SDL's
#    dummy audio driver), cut at the silences into build/gate/sound/wav,
#    each at least half a full PSG voice's peak
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/sound
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
cp -r shell "$OUT/src"
rm -f "$OUT/src"/*.cvt "$OUT/src"/*.bin "$OUT/src"/*.map
make -s -C "$OUT/src" SDK="$SDK" >"$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; fail "the shell does not build"; }
A=$OUT/apps
mkdir -p "$A"
ca65 --cpu 65C02 -I "$SDK/include" -D APPN=1 -o "$A/app1.o" tests/shell_app.s || fail "tests/shell_app.s"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/app1.bin" "$A/app1.o" || fail "tests/shell_app.s does not link"
printf 'name = AppOne\nclass = Test1\nmode = 640x480\napi = 1\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/app1.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/AppOne.cvt" "$A/app1.hdr" "$A/app1.bin" >/dev/null || fail "vpack AppOne"
CC="cl65 -t none --cpu 65C02 -O -I $SDK/include"
capp() {        # capp <name> <hdr> <sources...>
	local n=$1 h=$2
	shift 2
	$CC -C "$SDK/cfg/app-c.cfg" -o "$A/$n.bin" "$@" "$SDK/lib/veranda.lib" >"$A/$n.log" 2>&1 \
		|| { cat "$A/$n.log"; fail "$n does not build"; }
	(cd tests/audio && $PY "$SDK/tools/vpack.py" --load 0x0801 -o "$OLDPWD/$A/$n.cvt" "$(basename "$h")" \
		"$OLDPWD/$A/$n.bin") >/dev/null || fail "$n does not pack"
}
capp AudDA tests/audio/da.hdr tests/audio/da.c
capp SndDA tests/audio/sndda.hdr tests/audio/sndda.c
capp AudChk tests/audio/chk.hdr tests/audio/chk.c
capp AudSnd tests/audio/app.hdr -DBURN=82 -DSOUND tests/audio/main.c tests/audio/aud.s
testprg() {     # testprg <script> <dir>: TEST.PRG of tests/sound.s with that script
	mkdir -p "$2"
	$PY tests/sound_script.py "$1" "$2/steps.inc" || fail "tests/sound_script.py $1"
	ca65 --cpu 65C02 -I build/gen -I inc -I "$2" tests/sound.s -o "$2/sound.o" || fail "tests/sound.s"
	ca65 tests/prghdr.s -o "$2/prghdr.o"
	ld65 -C cfg/testprg.cfg "$2/prghdr.o" "$2/sound.o" -o "$2/TEST.PRG" || fail "tests/sound.s does not link"
	rm -f "$2/steps.inc" "$2"/*.o
	cp build/VERANDA.PRG build/VERANDA.SYS "$2/"
}
ok "built: the kernel, the SDK, the shell, AppOne, AudDA, SndDA, gate audio's mixer with sounds, TEST.PRG"

# 1. the table
R=$OUT/table
testprg gate "$R"
(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
	-warp -sound none -echo > console.txt 2>&1) || true
grep -q '^E ' "$R/console.txt" || { tail -20 "$R/console.txt"; fail "table: the session did not end"; }
$PY tests/check_sound.py "$R/console.txt" | grep -v "^$" || true
$PY tests/check_sound.py "$R/console.txt" >/dev/null || fail "table: the registers are not the table's"

# the kernel's log of sounds played (bank G2's sndLog) in a dump of the banked RAM
sndlog() {      # sndlog <dump.bin>: the ids, oldest first
	$PY - "$1" build <<'EOF'
import sys
d = open(sys.argv[1], 'rb').read()
ram = d[:len(d) - 132878]
n = len(ram) // 8192
base = n - 10                           # the kernel banks: the top 10 (G G2 U F S X P T W C, V165)
lab = {ln.split()[2].lstrip('.'): int(ln.split()[1], 16) for ln in open(sys.argv[2] + '/k/bank_G2.lab')}
g2 = ram[(base + 1) * 8192:(base + 2) * 8192]
log = g2[lab['sndLog'] - 0xA000:lab['sndLog'] - 0xA000 + 16]
k = g2[lab['sndLogN'] - 0xA000]
ids = [log[(k - m + i) % 16] for i in range(m)] if (m := min(k, 16)) else []
print(' '.join(str(x) for x in ids))
EOF
}
# voices 14 and 15 from a VRAM dump: "f15 v15 f14 v14"
voices() {
	$PY - "$1" <<'EOF'
import sys
d = open(sys.argv[1], 'rb').read()
v = d[len(d) - 132878:][0x1F9C0 + 56:0x1F9C0 + 64]
print('%d %d %d %d' % (v[4] | v[5] << 8, v[6] & 63, v[0] | v[1] << 8, v[2] & 63))
EOF
}
names() {
	$PY -c "
import sys; sys.path.insert(0, 'tools'); import mksounds as m
n = {v: k for k, v in m.api_ids().items()}
print(' '.join(n.get(int(x), x) for x in sys.argv[1:]))" $1
}
emu() {         # emu <dir>: the shell's run, until its BASIC program ends it
	(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump BV > console.txt 2>&1) || true
	[ -f "$1/dump.bin" ] || { tail -20 "$1/console.txt"; fail "$2: the session did not end (no dump)"; }
}
shellrun() {    # shellrun <run> <dir>
	mkdir -p "$2"
	cp "$OUT/src/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG build/RBOOT "$A/AppOne.cvt" "$2/"
	shift 0
}

# 2. keep: the chime once, an application, the trash, BASIC
R=$OUT/keep
shellrun keep "$R"
mkdir -p "$R/TRASH"
echo "junk" > "$R/TRASH/Junk.txt"
$PY tests/sound_shell.py keep "$R" console.txt || fail "tests/sound_shell.py keep"
emu "$R" keep
grep -a -q 'SHELL EMPTIED' "$R/console.txt" || { tail -20 "$R/console.txt"; fail "keep: the trash was not emptied"; }
grep -a -q 'VERANDA STAYS IN MEMORY' "$R/console.txt" || fail "keep: not in BASIC"
L=$(names "$(sndlog "$R/dump.bin")")
[ "$L" = "STARTUP APP WARNING TRASH EXIT" ] || fail "keep: the sounds played: $L"
ok "keep: the sounds played, in order: $L (the chime once: not when the shell came back from AppOne; no menu tick by default)"
V=$(voices "$R/dump.bin")
[ "$V" = "0 0 0 0" ] || fail "keep: voices 15 and 14 in BASIC: $V"
ok "keep: in BASIC voices 15 and 14 silent (frequency 0, volume 0): the exit sound played to its end first"

# 3. resume: the menu ticks, an accessory, BASIC and back, Quit Veranda
R=$OUT/resume
shellrun resume "$R"
cp "$A/SndDA.cvt" "$R/"
$PY tests/sound_shell.py resume "$R" console.txt || fail "tests/sound_shell.py resume"
emu "$R" resume
grep -a -q 'SNDDA RAN' "$R/console.txt" || { tail -20 "$R/console.txt"; fail "resume: the accessory did not run"; }
grep -a -q 'VERANDA BACK FROM BASIC' "$R/console.txt" || fail "resume: not back from BASIC"
grep -a -q 'G END' "$R/console.txt" || fail "resume: Quit Veranda did not reach BASIC"
L=$(names "$(sndlog "$R/dump.bin")")
echo "      resume: the sounds played (the log since the return from BASIC: its kernel banks are their copy again): $L"
S=$(echo "$L" | tr ' ' '\n' | grep -v MENU | tr '\n' ' ' | sed 's/ $//')
[ "$S" = "STARTUP EXIT" ] || fail "resume: after the return: $S (the chime, then the quit's sound)"
echo "$L" | grep -q MENU || fail "resume: no menu tick with the menu ticks on"
ok "resume: back from BASIC the chime again; menu ticks (the settings' bit 6); Quit Veranda: SND_EXIT"
V=$(voices "$R/dump.bin")
[ "$V" = "0 0 0 0" ] || fail "resume: voices 15 and 14 after Quit Veranda: $V"
ok "resume: after Quit Veranda voices 15 and 14 silent"
# 3b. before BASIC (the log above is the resumed kernel's): the same run
# with the emulator stopped in BASIC (G0 ends it): the accessory's sounds
R=$OUT/desk
shellrun resume "$R"
cp "$A/SndDA.cvt" "$R/"
$PY tests/sound_shell.py resume "$R" console.txt || fail "tests/sound_shell.py resume"
$PY - "$R" <<'EOF'
import os, sys
sys.path.insert(0, 'tests')
import basic_gate as bg
open(os.path.join(sys.argv[1], 'G0'), 'wb').write(bg.prg(['10 PRINT "G END"', '20 POKE 40884,1:SYS 65535']))
EOF
emu "$R" desk
L=$(names "$(sndlog "$R/dump.bin")")
S=$(echo "$L" | tr ' ' '\n' | grep -v MENU | tr '\n' ' ' | sed 's/ $//')
[ "$S" = "STARTUP OPEN CLOSE EXIT" ] || fail "desk: the sounds played: $L"
[ "$(echo "$L" | tr ' ' '\n' | grep -c MENU)" -ge 4 ] || fail "desk: menu ticks: $L"
ok "desk: $L (an accessory opens and closes; a tick at each menu press)"

# 3c. an old settings file (V72): the user's card's "Veranda Prefs.cvt",
# saved by V65's Preferences (byte 15 0, no PREFS_VOLSET), read at boot;
# recorded in real time: the chime and the exit sound at full volume
R=$OUT/prefs
shellrun prefs "$R"
lab() { $PY -c "import sys; print([l.split()[1] for l in open(sys.argv[1]) if l.split()[2] == '.' + sys.argv[2]][0])" "$@"; }
AT=$((16#$(lab build/k/bank_S.lab kSndAtt)))
[ $((16#$(lab build/k/bank_S.lab kPrefs))) = $((AT + 1)) ] || fail "prefs: kPrefs is not after kSndAtt"
PB=$((16#$(lab build/k/bank_S.lab prBlock)))
$PY tests/sound_shell.py prefs "$R" tests/sound_prefs_v65.cvt $AT || fail "tests/sound_shell.py prefs"
(cd "$R" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" -prg VERANDA.PRG \
	-run -echo -dump BV -wav prefs.wav > console.txt 2>&1) || true
[ -f "$R/dump.bin" ] || { tail -20 "$R/console.txt"; fail "prefs: the session did not end (no dump)"; }
G=$(tr -d '\r' < "$R/console.txt" | sed 's/\\X1D//g' | grep -a -o 'G PREFS *[0-9]* *[0-9]*' | tail -1 | tr -s ' ')
[ "$G" = "G PREFS 0 0" ] || fail "prefs: kSndAtt and kPrefs after the old file: '$G' (want 0 0)"
$PY - "$R/dump.bin" tests/sound_prefs_v65.cvt $PB <<'EOF' || fail "prefs: the settings block is not the file's"
import sys
d = open(sys.argv[1], 'rb').read()
ram = d[:len(d) - 132878]
s = ram[(len(ram) // 8192 - 10 + 4) * 8192:][:8192]    # bank S (G G2 U F S X P T W C)
blk = s[int(sys.argv[3]) - 0xA000:][:16]
want = open(sys.argv[2], 'rb').read()[508:524]
sys.exit(0 if blk == want else 'block %s, the file %s' % (blk.hex(' '), want.hex(' ')))
EOF
L=$(names "$(sndlog "$R/dump.bin")")
[ "$L" = "STARTUP EXIT" ] || fail "prefs: the sounds played: $L"
P=$($PY - "$R/prefs.wav" <<'EOF'
import array, sys, wave
w = wave.open(sys.argv[1], 'rb')
a = array.array('h', w.readframes(w.getnframes()))
print(max(abs(x) for x in a) if a else 0)
EOF
)
[ "$P" -ge 4088 ] || fail "prefs: the recording's peak $P (a full voice: 4088)"
ok "prefs: the user's V65 Veranda Prefs.cvt (flags 0, byte 15 0, theme 14 0 14 \$80): the block as the file, kSndAtt 0 (full volume), kPrefs 0 (sounds on); $L recorded, peak $P (a full voice 4088)"

# 4. PCM from AFLOW with sounds
R=$OUT/pcm
mkdir -p "$R"
cp "$A/AudSnd.cvt" "$R/AUTOSTART.cvt"
cp "$A/AudDA.cvt" "$R/"
cp "$A/AudChk.cvt" "$R/DESKTOP.cvt"
head -c 65536 /dev/urandom > "$R/data.bin"
cp build/VERANDA.PRG build/VERANDA.SYS "$R/"
(cd "$R" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy exec timeout -s INT 200 "$EMU" -rom "$ROM" \
	-prg VERANDA.PRG -run -warp -echo > console.txt 2>&1) &
pid=$!
for i in $(seq 1 600); do
	grep -q "AUDCHK MAINLOOP" "$R/console.txt" 2>/dev/null && break
	kill -0 $pid 2>/dev/null || break
	sleep 0.25
done
sleep 0.5
kill $pid 2>/dev/null || true
wait $pid 2>/dev/null || true
val() { tr -d '\r' < "$R/console.txt" | sed -n "s/^.*AUD $1 \([0-9]*\).*/\1/p" | tail -1; }
grep -q "AUD QUIT" "$R/console.txt" || { tail -10 "$R/console.txt"; fail "pcm: the session did not reach its quit"; }
[ "$(val underruns)" = 0 ] || fail "pcm: $(val underruns) underruns"
[ "$(val da_underruns)" = 0 ] || fail "pcm: $(val da_underruns) underruns around the accessory"
[ "$(val sounds)" -ge 5 ] || fail "pcm: $(val sounds) sounds started"
[ "$(val psg_frames)" -ge 100 ] || fail "pcm: voice 15 sounded in $(val psg_frames) frames"
ok "pcm: $(val batches) PCM batches at 87 % of the CPU with $(val sounds) sounds played meanwhile (voice 15 sounding in $(val psg_frames) frames): 0 underruns"

# 5. the WAVs
if [ "${SOUND_WAV:-1}" != 0 ]; then
	R=$OUT/wavrun
	testprg wav "$R"
	(cd "$R" && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout -s INT 120 "$EMU" -rom "$ROM" \
		-prg VERANDA.PRG -run -echo -wav all.wav > console.txt 2>&1) || true
	[ -s "$R/all.wav" ] || { tail -5 "$R/console.txt"; fail "wav: no recording"; }
	$PY tools/sndwav.py "$R/all.wav" "$OUT/wav" || fail "wav: the recording is not as the table"
fi
echo "GATE sound: PASS"
