#!/bin/bash
# Gate basic (DECISIONS V64, the RBOOT model): BASIC with Veranda kept in
# memory, and the way back.
#
#   tools/gate_basic.sh          (BASIC_SD=0: skip the SD card runs)
#
# 1. the kernel (VERANDA.PRG, VERANDA.SYS, RBOOT), the SDK, the shell,
#    AppOne (tests/shell_app.s); tests/basic_gate.py writes each run's
#    SHELL.TST and its BASIC programs (the shell, while its script plays,
#    types "?6*7" and "^Gn" into BASIC: n is the part)
# 2. run mem: the folder Docs opened; geos > BASIC (keep Veranda): the
#    hint, 42, MEMTOP (RB banks, $8800), an array filling BASIC's memory
#    up to MEMTOP and every RAM bank below RB written and read back; the
#    ROM's NMI routine (RUN STOP/RESTORE) with SYS 35328 queued; back: the
#    shell in Docs starts AppOne (only there); the kernel banks' code
#    equal to VERANDA.SYS and their copy equal to it whole (-dump BV)
# 3. run core: the resident core overwritten but ReEntry ($8A00), SYS 35328:
#    back from the copy; then VERANDA.SYS and VERANDA.PRG renamed away,
#    all of $8800-$9EFF overwritten, LOAD"RBOOT": back from the copy in
#    RAM (nothing on the card it could have loaded); the banks again
# 4. run card: the copy in bank RB damaged: SYS 35328 says so, RBOOT
#    finds no intact copy and starts VERANDA.PRG from the card (MEMTOP's
#    banks given back first); then geos > Quit Veranda: MEMTOP as at
#    power-on, SYS 35328 refuses (the descriptor made invalid)
# 5. runs tkeep, tquit (DECISIONS V67; found on a real X16: a black
#    screen after either exit): "Veranda Prefs.cvt" with dark paper,
#    light ink and a 2 s blank; the screen blanked once (run blank: the
#    dump while blanked shows it), woken, then BASIC (keep) or Quit
#    Veranda: the dump in BASIC shows the ROM's text screen
#    (tools/text2png.py: layer 1 on, a text map, the hint and G0's line
#    readable), drawn to *-text-keep.png and *-text-quit.png
# 6. the runs again on an SD card image (VERANDA.PRG on the card too)
# 7. all of it again under the R49 release ROM (R49_ROM; skipped when the
#    file is not there): the user's X16 runs R49
# 8. under R49, as the user does it (V73, user() below): a card in V71's
#    layout with the user's settings in .SYSTEM, the shell's menu by mouse, a
#    program that zeroed $A9-$FF first; keep + SYS 35328, keep + ^RBOOT,
#    quit + SYS 35328 (the message, no BRK); 512 KB and 2 MB
#    (BASIC_USER_ONLY=1: only these)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/basic
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
R49_ROM=${R49_ROM:-$HOME/Downloads/Release.R49.ROM.Image/rom.bin}
EMUM=${EMUM:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
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
ca65 --cpu 65C02 -I "$SDK/include" -D APPN=1 -D ZAP -o "$A/zap.o" tests/shell_app.s || fail "tests/shell_app.s -D ZAP"
ld65 -C "$SDK/cfg/app.cfg" -o "$A/zap.bin" "$A/zap.o" || fail "Zap does not link"
printf 'name = Zap\nclass = Zap\nmode = 640x480\napi = 1\nicon = %s\n' "$SDK/template/c/icon.pbm" > "$A/zap.hdr"
$PY "$SDK/tools/vpack.py" --load 0x0801 -o "$A/Zap.cvt" "$A/zap.hdr" "$A/zap.bin" >/dev/null || fail "vpack Zap"
ok "built: VERANDA.PRG, VERANDA.SYS, RBOOT ($(stat -c %s build/RBOOT) bytes), the shell, AppOne, Zap"

# the files of run $1 in $2 (the system folder: the root)
files() {
	mkdir -p "$2/Docs"
	cp "$OUT/src/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG build/RBOOT "$2/"
	cp "$A/AppOne.cvt" "$2/Docs/"
	shift 2
	$PY tests/basic_gate.py "$RUN" "$DIR" "$@" || fail "tests/basic_gate.py $RUN"
}

# the console's lines, in this order: $1 console, $2 where, $3... regexes
inorder() {
	local c=$1 where=$2
	shift 2
	tr -d '\r' < "$c" | $PY -c '
import re, sys
text = sys.stdin.read()
pos = 0
for pat in sys.argv[1:]:
    m = re.compile(pat, re.M).search(text, pos)
    if not m:
        print("      missing, after offset %d: %s" % (pos, pat))
        sys.exit(1)
    pos = m.end()
' "$@" || { tail -30 "$c"; fail "$where: the console is not as expected"; }
}

# run $1 in folder $2 (host: HostFS; sd: the card image made of $2/card)
emu() {
	if [ "$1" = host ]; then
		(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
			-warp -sound none -echo -dump BV > console.txt 2>&1) || true
	else
		$PY tools/vcard.py make --mb 64 "$2/sd.img" "$2/card" >/dev/null || fail "vcard make"
		cp build/VERANDA.PRG "$2/"
		(cd "$2" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMU" -rom "$ROM" -sdcard sd.img -prg VERANDA.PRG \
			-run -warp -sound none -echo -dump BV > console.txt 2>&1) || true
	fi
}

banks() {
	[ -f "$1/dump.bin" ] || { tail -20 "$1/console.txt"; fail "$2: the session did not end (no dump)"; }
	$PY tests/check_banks.py "$1/dump.bin" build >/dev/null || fail "$2: the kernel banks' code changed"
	$PY - "$1/dump.bin" build <<'EOF' || fail "$2: the kernel banks' copy"
import sys
d = open(sys.argv[1], 'rb').read()
ram = d[:len(d) - 132878]
img = open(sys.argv[2] + '/VERANDA.SYS', 'rb').read()[2:]
n = len(ram) // 8192
k = len(img) // 8192                 # the kernel banks (10: G G2 U F S X P T W C)
base = n - k
k -= 1                               # (V165: bank C, the last, has no copy)
img = img[:k * 8192]
copy = bytearray(ram[(base - k) * 8192:base * 8192])
# (bank S's copy holds the shell's folder: DESK_SET writes it, V63)
desk = next(int(ln.split()[1], 16) for ln in open(sys.argv[2] + '/k/bank_S.lab') if ln.split()[2] == '.deskPath')
d = 4 * 8192 + desk - 0xA000
assert copy[d:d + 64].split(b'\0')[0] in (b'/', b'/Docs'), 'bank S\'s copy: the shell\'s folder %r' % copy[d:d + 64]
copy[d:d + 64] = img[d:d + 64]
# (bank T's copy holds BASIC's zero page $A9-$FF as the loader found it,
# V73: CHRGET at $E7 begins with inc txtptr)
z = 7 * 8192 + 0x1F00
assert copy[z + 0xE7 - 0xA9] == 0xE6, 'bank T\'s copy: BASIC\'s zero page %r' % bytes(copy[z:z + 87])
copy[z:z + 87] = img[z:z + 87]
assert copy == img, 'the copy in RAM banks %d-%d differs from VERANDA.SYS' % (base - k, base - 1)
rb = ram[(base - k - 1) * 8192:(base - k) * 8192]
assert rb[:8] == b'VERANDA\x01', 'bank RB (%d) has no signature' % (base - k - 1)
EOF
}

session() {
	where=$1 kind=$2
	EXTRA=console.txt
	[ "$kind" = sd ] && EXTRA=
	# run mem
	RUN=mem
	D=$RUNS/$kind-mem
	DIR=$D
	[ "$kind" = sd ] && DIR=$D/card
	mkdir -p "$DIR"
	files mem "$DIR" $EXTRA
	emu "$kind" "$D"
	C=$D/console.txt
	inorder "$C" "$where, run mem" 'SHELL STARTED' 'VERANDA STAYS IN MEMORY\. BACK TO IT: SYS 35328' \
		'^ 42' 'G0 START' 'MEMTOP 44.{1,6}34816' 'FREE [0-9]+' 'ARRAY [0-9]+.{1,6}ERRORS 0.{1,6}FREE [0-9]+' \
		'BANKS 43.{1,6}ERRORS 0' 'G0 RESTORE' 'VERANDA BACK FROM BASIC' 'SHELL STARTED' 'APP 1 RAN' \
		'SHELL STARTED' 'SHELL DONE'
	free=$(tr -d '\r' < "$C" | sed -n 's/^FREE \([0-9]*\).*/\1/p' | head -1)
	left=$(tr -d '\r' < "$C" | sed -n 's/^ARRAY .*FREE \([0-9]*\).*/\1/p' | head -1)
	[ "$left" -lt 400 ] || fail "$where: $left bytes still free after the array (it should fill up to MEMTOP)"
	ok "$where, run mem: the hint, 42; MEMTOP 44 banks and \$8800; $free bytes free for BASIC, an array filled them up to $left bytes under MEMTOP, read back; RAM banks 1-43 written and read back"
	ok "$where, run mem: RUN STOP/RESTORE's warm start, then SYS 35328: Veranda back, the shell in Docs (AppOne, only there, started)"
	banks "$D" "$where, run mem"
	ok "$where, run mem: the kernel banks' code as loaded, their copy equal to VERANDA.SYS, bank RB signed"
	$PY tools/check_vera.py "$D/dump.bin" >/dev/null || fail "$where, run mem: the shell's display after the return"
	$PY tools/vram2png.py "$D/dump.bin" "$RUNS/$kind-back.png" >/dev/null || fail "vram2png"
	ok "$where, run mem: the shell's screen after the return: $RUNS/$kind-back.png"

	# run core
	RUN=core
	D=$RUNS/$kind-core
	DIR=$D
	[ "$kind" = sd ] && DIR=$D/card
	mkdir -p "$DIR"
	files core "$DIR" $EXTRA
	emu "$kind" "$D"
	C=$D/console.txt
	inorder "$C" "$where, run core" 'SHELL STARTED' 'VERANDA STAYS IN MEMORY' 'G0 START' 'G0 SYS' \
		'VERANDA BACK FROM BASIC' 'SHELL STARTED' 'VERANDA STAYS IN MEMORY' 'G1 START' 'G1 RBOOT' \
		'VERANDA IS IN MEMORY: STARTING IT' 'VERANDA BACK FROM BASIC' 'SHELL STARTED' 'SHELL DONE'
	! grep -a -q 'G0 STILL IN BASIC\|NO INTACT COPY' "$C" || fail "$where, run core: a refusal"
	if [ "$kind" = host ]; then
		ls "$D" > "$D/after.txt"
	else
		$PY tools/vcard.py ls "$D/sd.img" > "$D/after.txt"
	fi
	grep -q '^VSYS.OFF' "$D/after.txt" && grep -q '^VPRG.OFF' "$D/after.txt" && ! grep -q '^VERANDA\.\(SYS\|PRG\)' "$D/after.txt" \
		|| { cat "$D/after.txt"; fail "$where, run core: VERANDA.SYS and VERANDA.PRG were not renamed away"; }
	ok "$where, run core: the resident core overwritten but ReEntry (\$8A00-\$8A5F): SYS 35328 brought Veranda back from its copy"
	ok "$where, run core: VERANDA.SYS and VERANDA.PRG renamed away, all of \$8800-\$9EFF overwritten: RBOOT brought it back from the copy in RAM"
	banks "$D" "$where, run core"
	ok "$where, run core: the kernel banks' code as loaded, their copy equal to VERANDA.SYS"

	# run card
	RUN=card
	D=$RUNS/$kind-card
	DIR=$D
	[ "$kind" = sd ] && DIR=$D/card
	mkdir -p "$DIR"
	files card "$DIR" $EXTRA
	emu "$kind" "$D"
	C=$D/console.txt
	inorder "$C" "$where, run card" 'SHELL STARTED' 'VERANDA STAYS IN MEMORY' 'G0 START' 'G0 SYS' \
		'NO VERANDA IN RAM: .RBOOT' 'G0 REFUSED' 'NO INTACT COPY OF VERANDA IN MEMORY' 'LOADING VERANDA.PRG' \
		'SHELL STARTED' '^ 42' 'G1 START' 'MEMTOP 64.{1,6}40704' 'NO VERANDA IN RAM' 'G1 REFUSED'
	! tr -d '\r' < "$C" | sed -n '/LOADING VERANDA.PRG/,$p' | grep -a -q 'VERANDA STAYS IN MEMORY' \
		|| fail "$where, run card: Quit Veranda printed the hint"
	ok "$where, run card: the copy damaged: SYS 35328 refused with a message, RBOOT started VERANDA.PRG from the card"
	ok "$where, run card: Quit Veranda: MEMTOP 64 banks and \$9F00 again, SYS 35328 refuses (the descriptor made invalid)"
}

# the text screen after an exit (DECISIONS V67); $3: the PNGs' suffix
text() {
	where=$1 kind=$2 tag=$3
	EXTRA=console.txt
	[ "$kind" = sd ] && EXTRA=
	for RUN in blank tkeep tquit; do
		[ "$RUN" = blank ] && [ "$kind" = sd ] && continue
		D=$RUNS/$kind-$RUN
		DIR=$D
		[ "$kind" = sd ] && DIR=$D/card
		rm -rf "$D"
		mkdir -p "$DIR"
		files $RUN "$DIR" $EXTRA
		emu "$kind" "$D"
		[ -f "$D/dump.bin" ] || { tail -20 "$D/console.txt"; fail "$where, run $RUN: no dump"; }
	done
	if [ "$kind" = host ]; then
		$PY -c '
import sys
d = open(sys.argv[1], "rb").read()
v = d[len(d) - 132878:]
# (V96: blanking leaves DC_VIDEO alone and closes the display window,
# DCSEL 1, which the dump does not hold: palette entry 0 black is the sign)
assert v[131072 + 256:131072 + 258] == bytes(2), "palette entry 0"
' "$RUNS/host-blank/dump.bin" || fail "$where, run blank: the screen did not blank (the hard case would not be tested)"
		ok "$where: idle 5 s with the settings' 2 s blank: the screen blanked (entry 0 black: V96)"
	fi
	inorder "$RUNS/$kind-tkeep/console.txt" "$where, run tkeep" 'SHELL STARTED' 'VERANDA STAYS IN MEMORY' '^ 42' 'G0 TEXT'
	inorder "$RUNS/$kind-tquit/console.txt" "$where, run tquit" 'SHELL STARTED' '^ 42' 'G0 TEXT'
	! grep -a -q 'VERANDA STAYS IN MEMORY' "$RUNS/$kind-tquit/console.txt" || fail "$where, run tquit: the hint"
	$PY tools/text2png.py "$RUNS/$kind-tkeep/dump.bin" "$RUNS/$kind-text-keep$tag.png" \
		--want 'VERANDA STAYS IN MEMORY. BACK TO IT: SYS 35328' --want 'G0 TEXT' \
		|| fail "$where, run tkeep: BASIC's text screen is not shown"
	$PY tools/text2png.py "$RUNS/$kind-tquit/dump.bin" "$RUNS/$kind-text-quit$tag.png" --want 'G0 TEXT' \
		|| fail "$where, run tquit: BASIC's text screen is not shown"
	ok "$where: dark paper, light ink, a blank, then BASIC (keep Veranda) and Quit Veranda: the ROM's text screen, the hint and G0's line readable ($RUNS/$kind-text-keep$tag.png, $RUNS/$kind-text-quit$tag.png)"
}

all() {
	session "host folder$2" host
	text "host folder$2" host "$1"
	if [ "${BASIC_SD:-1}" != 0 ]; then
		session "SD card$2" sd
		text "SD card$2" sd "$1"
	fi
}

# (V73; found on a real X16, R49: SYS 35328 typed after BASIC (keep
# Veranda) went into the ROM's monitor, a BRK at BASIC's CHRGET ($E7),
# which a program had overwritten: Veranda gave BASIC its zero page back
# as the program left it.) As the user does it: an SD card with the
# system in /VERANDA and the user's settings (tests/basic_user_prefs.cvt),
# DOS"CD:VERANDA", LOAD, RUN typed; the real shell's menu with the mouse
# (-mousescript, ~/Projects/x16-emulator-mouse); before each exit Zap (an
# application that zeroes $A9-$FF, tests/shell_app.s -D ZAP) runs from
# /DOCUMENTS, the folder the shell opens (V71).
# keep: Zap, options > BASIC (keep Veranda), SYS35328 typed: back; Zap,
# BASIC (keep), ^RBOOT typed: back from RAM; the shell's screen.
# quit: Zap, options > Quit Veranda, SYS35328 typed: the message, no BRK.
# $1: keep or quit, $2: the RAM in KB
user() {
	local kind=$1 ram=$2 D=$RUNS/user-$1-$2 t=2500 s
	# the V71 layout, as set up: the system in /VERANDA, its data in
	# .SYSTEM (with Setup's log), the shell opening /DOCUMENTS, where Zap is
	# (a program may be anywhere; the window shows ".." and Zap)
	mkdir -p "$D/card/VERANDA/APPS" "$D/card/VERANDA/.SYSTEM" "$D/card/DOCUMENTS"
	cp "$OUT/src/SHELL.cvt" build/VERANDA.SYS build/VERANDA.PRG build/RBOOT "$D/card/VERANDA/"
	cp "$A/Zap.cvt" "$D/card/DOCUMENTS/"
	cp tests/basic_user_prefs.cvt "$D/card/VERANDA/.SYSTEM/Veranda Prefs.cvt"
	echo "V71" > "$D/card/VERANDA/.SYSTEM/LAYOUT.LOG"
	$PY tools/vcard.py make --mb 64 "$D/sd.img" "$D/card" >/dev/null || fail "vcard make"
	s=$D/mouse.txt
	printf '180 type DOS"CD:VERANDA"\\n\n300 type LOAD"VERANDA.PRG"\\n\n500 type RUN\\n\n' > "$s"
	# $1 the menu item (96 keep, 112 quit, 16 lines an item: V74; from the menu's first item; the
	# pointer stays on the title, 17 lines above it: V137), $2 what is typed in BASIC
	cycle() {
		local f
		for f in 0 5 10 15; do echo "$((t + f)) move -200 -200"; done   # the pointer to 0,0
		echo "$((t + 60)) move 150 112"         # Zap: after ".." in /DOCUMENTS (its row: folder windows open as a list, V176)
		echo "$((t + 80)) down"; echo "$((t + 84)) up"; echo "$((t + 90)) down"; echo "$((t + 94)) up"
		t=$((t + 1500))
		for f in 0 5 10 15; do echo "$((t + f)) move -200 -200"; done
		echo "$((t + 60)) move 300 7"           # Options (the bar in the Veranda look, V74; the UI font, V79)
		echo "$((t + 80)) down"; echo "$((t + 86)) up"
		echo "$((t + 110)) move 0 $(($1 + 17))"
		echo "$((t + 130)) down"; echo "$((t + 136)) up"
		echo "$((t + 800)) type $2\\n"
		t=$((t + 2500))
	} >> "$s"
	if [ "$kind" = keep ]; then
		cycle 96 SYS35328
		cycle 96 ^RBOOT
	else
		cycle 112 SYS35328
		t=$((t - 1500))
	fi
	echo "$t exit" >> "$s"
	(cd "$D" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$EMUM" -rom "$ROM" -sdcard sd.img -ram "$ram" \
		-warp -sound none -echo -mousescript mouse.txt -dump BV > console.txt 2>&1) || true
	[ -f "$D/dump.bin" ] || { tail -20 "$D/console.txt"; fail "user $kind, $ram KB: no dump"; }
	C=$D/console.txt
	! grep -a -q 'BDIZC' "$C" || { tail -20 "$C"; fail "user $kind, $ram KB: the ROM's monitor (a BRK)"; }
	if [ "$kind" = keep ]; then
		inorder "$C" "user keep, $ram KB" 'SHELL THEME' 'APP 1 RAN' 'VERANDA STAYS IN MEMORY' 'VERANDA BACK FROM BASIC' \
			'APP 1 RAN' 'VERANDA STAYS IN MEMORY' 'VERANDA IS IN MEMORY: STARTING IT' 'VERANDA BACK FROM BASIC'
		! grep -a -q 'NO VERANDA IN RAM\|NO INTACT' "$C" || fail "user keep, $ram KB: a refusal"
		$PY tools/check_vera.py "$D/dump.bin" >/dev/null || fail "user keep, $ram KB: the shell's display after the return"
		$PY tools/vram2png.py --color "$D/dump.bin" "$RUNS/user-keep-$ram.png" >/dev/null || fail "vram2png"
		ok "as on the X16 (R49, $ram KB, the user's settings, the menu by mouse, Zap zeroed \$A9-\$FF first): BASIC (keep), SYS 35328: back; again, ^RBOOT: back from RAM ($RUNS/user-keep-$ram.png)"
	else
		inorder "$C" "user quit, $ram KB" 'SHELL THEME' 'APP 1 RAN' 'NO VERANDA IN RAM'
		! grep -a -q 'VERANDA STAYS IN MEMORY' "$C" || fail "user quit, $ram KB: the hint"
		$PY tools/text2png.py "$D/dump.bin" "$RUNS/user-quit-$ram.png" --want 'NO VERANDA IN RAM' --want 'READY.' >/dev/null \
			|| fail "user quit, $ram KB: BASIC's screen"
		ok "as on the X16 (R49, $ram KB): Zap, Quit Veranda, SYS 35328: the message and READY., no BRK ($RUNS/user-quit-$ram.png)"
	fi
}

RUNS=$OUT
[ "${BASIC_USER_ONLY:-0}" = 1 ] || all "" ""
if [ -f "$R49_ROM" ] && [ "$R49_ROM" != "$ROM" ]; then
	ROM=$R49_ROM
	RUNS=$OUT/r49
	mkdir -p "$RUNS"
	[ "${BASIC_USER_ONLY:-0}" = 1 ] || all "" " (R49)"
	if [ -x "$EMUM" ]; then
		for ram in 512 2048; do
			user keep $ram
			user quit $ram
		done
	else
		echo "skip  the mouse emulator ($EMUM) is not there: the user runs"
	fi
else
	echo "skip  the R49 ROM ($R49_ROM) is not there"
fi
echo "GATE basic: PASS"
