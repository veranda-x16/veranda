#!/bin/bash
# Gate vb_sdk (VeraBASIC phase 4, docs/DECISIONS.md V90): the shell's tile
# drawing moved into the SDK (vr_tile, sdk/lib/vrtile.c, vr.h) for
# VeraBASIC's TILE, and the shell built on it, with nothing else changed.
#
#   tools/gate_vb_sdk.sh       (VB_SDK_GATES=0: the three gates not run)
#
# 1. the SDK installs: vr_tile in lib/veranda.lib, declared in
#    include/vr.h, its source in src/vrtile.c (a program short of main RAM
#    compiles it into an overlay)
# 2. a C program in main RAM links vr_tile from veranda.lib; the shell
#    compiles src/vrtile.c into its tiles' overlay (10): vr_tile in
#    OVERLAY10, nothing of it in the shell's main RAM, the shell's frame
#    table gone from tiles.c
# 3. gates sdk, shell and edit pass (tools/gate_sdk.sh, gate_shell.sh,
#    gate_edit.sh: the shell's windows, its tiles' screens among them)
set -e
cd "$(dirname "$0")/.."
OUT=${OUT:-build/gate/vb_sdk}
PY="python3 -I -B"
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}

ok() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
$PY tools/apigen.py api/veranda.api build/gen >/dev/null || fail "the API table"
$PY tools/kbuild.py >/dev/null || fail "the kernel does not build"
tools/mksdk.sh "$OUT/sdk" >/dev/null || fail "the SDK does not install"
SDK=$(cd "$OUT/sdk" && pwd)
ar65 t "$SDK/lib/veranda.lib" | grep -qx vrtile.o || fail "veranda.lib has no vrtile.o"
grep -q 'vr_tile(unsigned char x, unsigned int y, const unsigned char \*glyph, unsigned char \*buf)' "$SDK/include/vr.h" \
	|| fail "vr.h does not declare vr_tile"
[ -f "$SDK/src/vrtile.c" ] || fail "the SDK's src/ has no vrtile.c"
ok "the SDK: vr_tile in lib/veranda.lib, include/vr.h, src/vrtile.c"

# 2. a program in main RAM; the shell's overlay
cat > "$OUT/t.c" <<'EOF'
#include <veranda.h>
#include <vr.h>
static unsigned char glyph[128], buf[128];
int main(void)
{
    vr_tile(2, 16, glyph, buf);
    return 0;
}
EOF
cl65 -t none --cpu 65C02 -O -I "$SDK/include" -C "$SDK/cfg/app-c.cfg" -m "$OUT/t.map" -o "$OUT/t.bin" "$OUT/t.c" "$SDK/lib/veranda.lib" \
	|| fail "a C program does not link vr_tile"
grep -q 'veranda.lib(vrtile.o)' "$OUT/t.map" || fail "the C program's vr_tile is not the library's"
ok "a C program links vr_tile from veranda.lib ($(wc -c < "$OUT/t.bin") bytes)"
make -s -C shell clean >/dev/null
make -s -C shell SDK="$SDK" >"$OUT/shell.log" 2>&1 || { cat "$OUT/shell.log"; fail "the shell does not build"; }
awk '/^vrtile.o:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on' shell/shell.map > "$OUT/vrtile.segs"
grep -q 'OVERLAY10' "$OUT/vrtile.segs" || fail "the shell's vr_tile is not in its tiles' overlay"
! grep -q '^    CODE' "$OUT/vrtile.segs" || fail "the shell has vr_tile in main RAM"
! grep -q 'veranda.lib(vrtile.o)' shell/shell.map || fail "the shell links the library's vr_tile (main RAM)"
! grep -q 'frameRow' shell/tiles.c || fail "shell/tiles.c still draws the frame itself"
grep -q 'vr_tile(' shell/tiles.c || fail "shell/tiles.c does not call vr_tile"
end=$(sed -n 's/^BSS  *[0-9A-F]*  *\([0-9A-F]*\).*/\1/p' shell/shell.map)
ok "the shell: src/vrtile.c compiled into its tiles' overlay (10), tiles.c calls vr_tile; its main RAM to \$$end"
make -s -C shell clean >/dev/null

# 3. the gates the move touches
if [ "${VB_SDK_GATES:-1}" != 0 ]; then
	for g in sdk shell edit; do
		tools/gate_$g.sh > "$OUT/gate_$g.txt" 2>&1 || { tail -20 "$OUT/gate_$g.txt"; fail "gate $g"; }
		ok "gate $g passes ($(grep -c '^ok' "$OUT/gate_$g.txt") checks; $OUT/gate_$g.txt)"
	done
fi
echo "GATE vb_sdk: PASS"
