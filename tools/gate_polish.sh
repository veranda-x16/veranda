#!/bin/bash
# Gate polish (docs/DECISIONS.md V140-V143): Polish letters in Veranda:
# the character set (ISO-8859-16) and UTF-8, fonts with the glyphs of
# $A0-$FF, the Polish (programmers) keyboard.
#
#   tools/gate_polish.sh [part ...]     parts: cs font keys (default all)
#
# cs    the SDK's sdk/lib/vrcs.s on the host (cc65's sim65:
#       tests/vrcs_test.c): every byte to Unicode, UTF-8 and back against
#       Python's iso8859_16 codec, "Zażółć gęślą jaźń" in both cases from
#       UTF-8 (tests/check_vrcs.py)
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/polish
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
MEMU=${MEMU:-$HOME/Projects/x16-emulator-mouse/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
PARTS=${*:-cs font keys}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }
has() { case " $PARTS " in *" $1 "*) return 0 ;; esac; return 1; }

mkdir -p "$OUT"

if has cs; then
	C=$OUT/cs
	rm -rf "$C"
	mkdir -p "$C"
	cl65 -t sim65c02 -O -I sdk/lib tests/vrcs_test.c sdk/lib/vrcs.s -o "$C/vrcs.prg" -m "$C/vrcs.map" \
		|| fail "tests/vrcs_test.c does not build (sim65)"
	sim65 "$C/vrcs.prg" > "$C/out.txt" || fail "vrcs_test.c did not run"
	$PY tests/check_vrcs.py "$C/out.txt" || fail "the character set library"
fi

if has keys; then
	K=$OUT/keys
	rm -rf "$K"
	mkdir -p "$K"
	$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
	$PY tools/kbuild.py > "$K/kbuild.txt" || fail "the kernel does not build"
	tools/mksdk.sh "$K/sdk" >/dev/null || fail "the SDK"
	SDK=$(cd "$K/sdk" && pwd)
	[ -x "$MEMU" ] && grep -q keydown "$(dirname "$MEMU")/../src/mousescript.c" || fail "no -mousescript emulator with keydown ($MEMU)"
	ca65 --cpu 65C02 -I "$SDK/include" tests/kbd.s -o "$K/kbd.o" || fail "tests/kbd.s"
	ca65 --cpu 65C02 -I "$SDK/include" sdk/lib/vrkbd.s -o "$K/vrkbd.o" || fail "sdk/lib/vrkbd.s"
	ca65 --cpu 65C02 -I "$SDK/include" sdk/lib/vrkmap.s -o "$K/vrkmap.o" || fail "sdk/lib/vrkmap.s"
	ld65 -C "$SDK/cfg/app.cfg" "$K/kbd.o" "$K/vrkbd.o" "$K/vrkmap.o" -o "$K/kbd.bin" || fail "tests/kbd.s does not link"
	printf 'name        = KbdTest\nclass       = KbdTest\nversion     = 1.0\nauthor      = Veranda\ndescription = gate polish: the keyboard.\nmode        = 640x480\napi         = 1\nicon        = %s\n' \
		"$(pwd)/sdk/template/asm/icon.pbm" > "$K/kbd.hdr"
	$PY tools/vpack.py --load 0x0801 -o "$K/AUTOSTART.cvt" "$K/kbd.hdr" "$K/kbd.bin" >/dev/null || fail "tests/kbd.s: vpack"
	mkdir -p "$K/edit"
	make -s -C apps/edit SDK="$SDK" OUT="$(pwd)/$K/edit" >"$K/edit.log" 2>&1 || { cat "$K/edit.log"; fail "Veranda Edit does not build"; }
	# the keys: IBM key numbers (62 right Alt, 60 left Alt, 44 left Shift)
	keys() {        # $1: the first frame
		f=$1
		tap() { echo "$f keydown $1"; f=$((f + 4)); echo "$f keyup $1"; f=$((f + 4)); }
		tap 31; tap 48; tap 19                          # a c e
		echo "$f keydown 60"; f=$((f + 4)); tap 31; echo "$f keyup 60"; f=$((f + 8))   # left Alt + A
		tap 21                                          # t
		echo "$f keydown 62"; f=$((f + 4))
		for k in 31 48 19 39 51 25 32 47 46; do tap $k; done
		echo "$f keydown 44"; f=$((f + 4))
		for k in 31 48 19 39 51 25 32 47 46; do tap $k; done
		echo "$f keyup 44"; f=$((f + 4)); echo "$f keyup 62"; f=$((f + 120))
		echo "$f exit"
	}
	prefs() {       # the settings with the Polish keyboard (byte 6, PREFS_POLISH)
		$PY -c 'import sys; d=bytearray(open("tests/sound_prefs_v65.cvt","rb").read()); d[508+6] |= 4; open(sys.argv[1],"wb").write(d)' "$1/Veranda Prefs.cvt"
	}
	run_keys() {    # $1 the folder, $2 the application's .cvt, $3 the first key's frame
		mkdir -p "$1"
		cp build/VERANDA.PRG build/VERANDA.SYS "$K/AUTOSTART.cvt" "$1/"
		cp "$2" "$1/APP.cvt"
		prefs "$1"
		[ -z "$4" ] || cp -r "$4"/. "$1/"
		keys "$3" > "$1/keys.txt"
		(cd "$1" && SDL_VIDEODRIVER=dummy timeout -s INT 300 "$MEMU" -rom "$ROM" -ram 512 -prg VERANDA.PRG -run \
			-warp -sound none -echo -mousescript keys.txt -dump V > console.txt 2>&1) || true
		[ -f "$1/dump.bin" ] || { tr -d '\r' < "$1/console.txt" | tail -5; fail "$1: no dump"; }
		grep -aq "KEYMAP PL-PL" "$1/console.txt" || { grep -a KEYMAP "$1/console.txt"; fail "vr_kbd did not select the ROM's PL-PL key map"; }
	}
	E=$K/edit-run
	run_keys "$E" "$(ls "$K"/edit/*.cvt | head -1)" 900
	ok "vr_kbd with PREFS_POLISH: the ROM's key map is PL-PL (KEYMAP PL-PL)"
	$PY tools/vram2png.py --color "$E/dump.bin" "$OUT/keys-edit.png" 2>/dev/null || true
	$PY tests/check_l10_text.py "$E/dump.bin" "$ROM" "tąćęłńóśźżĄĆĘŁŃÓŚŹŻ" \
		|| fail "Edit: right Alt + a c e l n o s x z (and Shift), after left Alt + A"
	ok "Edit: \"ace\", left Alt + A (select all, a shortcut), \"t\", right Alt + a c e l n o s x z and with Shift: tąćęłńóśźżĄĆĘŁŃÓŚŹŻ ($OUT/keys-edit.png)"
	CW=${CW:-$HOME/Projects/commander-write}   # (its build: tools/gate.sh there)
	CWCVT="$CW/build/veranda/Veranda Write.cvt"
	if [ -f "$CWCVT" ]; then
		F=$K/fonts
		$PY tools/fontcvt.py testfonts "$F" || fail "the fonts"
		X=$K/cw-extra
		mkdir -p "$X/VERANDA/FONTS" "$X/VERANDA/.SYSTEM"
		cp "$F/Gate Sans.cvt" "$F/Gate Mono.cvt" "$X/VERANDA/FONTS/"
		prefs "$X/VERANDA"
		prefs "$X/VERANDA/.SYSTEM"
		C=$K/cw-run
		run_keys "$C" "$CWCVT" 1500 "$X"
		$PY tools/vram2png.py --color "$C/dump.bin" "$OUT/keys-cw.png" 2>/dev/null || fail "Veranda Write: no picture"
		$PY "$CW/tools/check_polish.py" "$OUT/keys-cw.png" "$F/Gate Sans.cvt" 12 "tąćęłńóśźżĄĆĘŁŃÓŚŹŻ" \
			|| fail "Veranda Write: right Alt + a c e l n o s x z (and Shift), after left Alt + A"
		ok "Veranda Write: the same keys: tąćęłńóśźżĄĆĘŁŃÓŚŹŻ in Gate Sans 12 as tools/fontcvt.py's record draws it ($OUT/keys-cw.png)"
	else
		echo "skip  Veranda Write: no $CWCVT"
	fi
fi

echo "GATE polish: PASS"
