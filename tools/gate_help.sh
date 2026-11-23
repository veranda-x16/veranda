#!/bin/bash
# Gate help (DECISIONS V134): Veranda's manual on the X16.
#
# 1. tools/mkhelp.py: docs/manual converts (every page in _Sidebar.md,
#    every link to a page, lines of 80 columns at most, each part 48 KB at
#    most) into the files the package puts in /VERANDA/HELP.
# 2. The shell's Veranda > Help in the emulator (the card's layout:
#    the shell in /VERANDA, View in /VERANDA/APPS, the manual in
#    /VERANDA/HELP, the window on /DOCUMENTS): View starts with
#    "Veranda manual.txt" as its document, in /VERANDA/HELP (its test
#    build's console: VIEW DOC ... IN /VERANDA/HELP, and the screen it
#    shows, tests/check_view.py doc); a screenshot, help.png.
# 3. Without View in the applications: Help says so (a box, OK), and the
#    shell goes on to its script's end.
# Out: build/gate/help/.
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/help
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
export PATH=$CC65_HOME/bin:$PATH
ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; echo "GATE help: FAIL"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
SDK=$OUT/sdk

# 1. the text
$PY tools/mkhelp.py --check > "$OUT/check.txt" || fail "mkhelp.py --check"
$PY tools/mkhelp.py "$OUT/HELP" || fail "mkhelp.py"
n=$(ls "$OUT/HELP" | wc -l)
[ "$n" -ge 2 ] && [ -f "$OUT/HELP/Veranda manual.txt" ] || fail "the manual's files ($n)"
ok "mkhelp.py: $n files ($(cat "$OUT/HELP"/* | wc -c) bytes), the links and the widths checked"

# 2. the shell and View
make -s api >/dev/null
make -s all >/dev/null
tools/mksdk.sh "$SDK" >/dev/null || fail "the SDK"
mkdir -p "$OUT/shell" "$OUT/view"
cp shell/*.c shell/*.h shell/*.s shell/*.inc shell/Makefile shell/app.hdr shell/icon.pbm shell/icons3.txt shell/icons3s.txt "$OUT/shell/"
make -s -C "$OUT/shell" SDK="$(realpath "$SDK")" >"$OUT/shell/build.log" 2>&1 || fail "the shell does not build"
make -s -C apps/view test SDK="$(realpath "$SDK")" OUT="$(realpath "$OUT/view")" >"$OUT/view/build.log" 2>&1 \
	|| fail "View's test build"
ok "the shell and View's test build"

run() {         # <name> <with View: 1/0>
	local R=$OUT/run-$1
	mkdir -p "$R/VERANDA/APPS" "$R/VERANDA/.SYSTEM" "$R/DOCUMENTS"
	cp "$OUT/shell/SHELL.cvt" build/VERANDA.PRG "$R/VERANDA/"
	cp build/VERANDA.SYS "$R/"
	cp -r "$OUT/HELP" "$R/VERANDA/HELP"
	[ "$2" = 1 ] && cp "$OUT/view/View.cvt" "$R/VERANDA/APPS/"
	echo "a note" > "$R/DOCUMENTS/Note.txt"
	$PY - "$R/SHELL.TST" <<'EOF'
import sys
sys.path.insert(0, 'tests')
import shell_script as ss
p = ss.Part()
p.wait(30)
p.menu('geos', 'help')
p.wait(90)
p.click(ss.YES_X, ss.YES_Y)       # (no View: the message's OK)
p.wait(60)
p.end(ss.END_DONE)
ss.write(sys.argv[1], [p])
EOF
	cp build/VERANDA.PRG "$R/"
	(cd "$R" && SDL_VIDEODRIVER=dummy timeout -s INT 60 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo -dump V > console.txt 2>&1) || true
	tr -d '\r' < "$R/console.txt" > "$R/console.log"
}

run view 1
R=$OUT/run-view
grep -q 'VIEW DOC Veranda manual.txt IN /VERANDA/HELP' "$R/console.log" \
	|| { tail -15 "$R/console.log"; fail "Help did not start View with the manual"; }
ok "Veranda > Help: View started with Veranda manual.txt in /VERANDA/HELP"
[ -f "$R/VERANDA/HELP/DOC.RAW" ] || fail "View's screen (DOC.RAW)"
$PY tests/check_view.py doc "$R/VERANDA/HELP" "$ROM" "Veranda manual.txt" || fail "the screen is not the manual's first page"
ok "View shows the manual's first page (tests/check_view.py doc)"
if [ -f "$R/dump.bin" ]; then
	$PY tools/vram2png.py --color "$R/dump.bin" "$OUT/help.png" >/dev/null 2>&1 && ok "the screenshot: $OUT/help.png"
fi

# 3. no View
run noview 0
R=$OUT/run-noview
grep -q 'VIEW DOC' "$R/console.log" && fail "View ran without being there"
grep -q 'SHELL DONE' "$R/console.log" || { tail -15 "$R/console.log"; fail "without View: the shell did not go on"; }
ok "without View in the applications: the shell's message, OK, the shell goes on (SHELL DONE)"
echo "GATE help: PASS"
