#!/bin/bash
# Gate guide (docs/PLAN.md phase 9, the reference guide): the guide's
# examples build and run, and the reference is current.
#
#   tools/gate_guide.sh
#
# 1. docs/API.md is what tools/apigen.py makes from api/veranda.api now
# 2. the SDK installs README.md, GUIDE.md and API.md
# 3. every example in sdk/docs/GUIDE.md (a ```c block whose first line is
#    "/* example: NAME */") builds against the INSTALLED SDK, runs as
#    TEST.PRG and logs "GUIDE NAME OK"
# 4. every call the guide names in `code` exists in the API table
set -e
cd "$(dirname "$0")/.."
OUT=build/gate/guide
PY="python3 -I -B"
EMU=${EMU:-$HOME/Projects/x16-emulator/build/x16emu}
ROM=${ROM:-$HOME/Projects/x16-rom/build/x16/rom.bin}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen --doc "$OUT/API.md" >/dev/null || fail "the API table"
cmp -s "$OUT/API.md" docs/API.md || fail "docs/API.md is out of date (make api)"
ok "docs/API.md is current"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
for f in README.md GUIDE.md API.md; do
	[ -s "$SDK/docs/$f" ] || fail "the SDK has no docs/$f"
done
ok "the SDK installs README.md, GUIDE.md and API.md"

# the names in `backticks` that look like calls or variables must exist
$PY - "$SDK/docs/GUIDE.md" "$SDK/include/veranda.h" "$SDK/include/vr.h" "$SDK/include/scrap.h" "$SDK/include/vrchoose.h" "$SDK/include/fontpick.h" "$SDK/include/vrpic.h" "$SDK/include/vralert.h" "$SDK/include/vrwin.h" <<'EOF' || fail "the guide names something the API does not have"
import re, sys
guide = open(sys.argv[1]).read()
known = ''.join(open(f).read() for f in sys.argv[2:])
names = set(re.findall(r'`([A-Za-z_][A-Za-z0-9_]*)(?:\([^`]*\))?`', guide))
skip = {'main', 'exit', 'static', 'make', 'mode', 'api', 'r0', 'r0L', 'r5', 'r6',
        'app.hdr', 'vpack', 'vrun', 'void', 'icon', 'W', 'mx', 'my'}
bad = sorted(n for n in names if n not in skip and not re.search(r'\b%s\b' % re.escape(n), known)
             and (n[0].isupper() or n[0] in 'kmsdiac' or n.isupper()))
for n in bad:
    print('guide: unknown name', n)
sys.exit(1 if bad else 0)
EOF
ok "every call and variable the guide names is in the API"

$PY - sdk/docs/GUIDE.md "$OUT/ex" <<'EOF' || fail "no examples"
import os, re, sys
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
n = 0
for m in re.finditer(r'```c\n(/\* example: (\w+) \*/\n.*?)```', open(src).read(), re.S):
    open(os.path.join(out, m.group(2) + '.c'), 'w').write(m.group(1))
    n += 1
print(n, 'examples')
sys.exit(0 if n else 1)
EOF
count=0
for c in "$OUT"/ex/*.c; do
	name=$(basename "$c" .c)
	d=$OUT/run/$name
	mkdir -p "$d"
	cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -o "$d/app.bin" "$c" \
		"$SDK/lib/veranda.lib" >"$d/build.log" 2>&1 || { cat "$d/build.log"; fail "example $name does not build"; }
	grep -q -i "warning" "$d/build.log" && { cat "$d/build.log"; fail "example $name: warnings"; }
	$PY -c "import sys; d=open(sys.argv[1],'rb').read(); open(sys.argv[2],'wb').write(bytes([1,8])+d)" \
		"$d/app.bin" "$d/TEST.PRG"
	cp "$SDK/bin/VERANDA.PRG" "$SDK/bin/VERANDA.SYS" "$d/"
	(cd "$d" && SDL_VIDEODRIVER=dummy timeout -s INT 15 "$EMU" -rom "$ROM" -prg VERANDA.PRG -run \
		-warp -sound none -echo > console.txt 2>&1) || true
	grep -a -q "GUIDE $name OK" "$d/console.txt" || { tail -5 "$d/console.txt"; fail "example $name did not log \"GUIDE $name OK\""; }
	ok "example $name builds against the installed SDK and runs"
	count=$((count + 1))
done
echo "GATE guide: PASS ($count examples)"
