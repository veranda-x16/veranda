#!/bin/bash
# Install the Veranda SDK (docs/PLAN.md section 7) into a folder.
#
#   tools/mksdk.sh [dest]        default build/sdk; needs `make api` first
#
# dest/include  veranda.h veranda.inc macros.inc x16hw.inc vr.h scrap.h vrchoose.h fontpick.h theme.h vrpath.h vrwin.h wallcfg.h vrcs.h vralert.h
#               vrser.h vrnet.h vrpic.h
#      cfg      app.cfg (assembly) app-c.cfg (C) app-c-ovl.cfg (C, banked overlays)
#      lib      veranda.lib (C bindings, crt0, the interrupt trampoline, the clipboard,
#               the Open and Save dialog, vr_dlgbox, vr_tramp, the font picker, the theme, the folders,
#               the window chrome, the application tile vr_tile; vrser, the serial
#               driver, and vrnet, TCP sockets through a Zimodem modem: V98, docs/NET.md;
#               vrpic, a program's full-colour picture in the kernel's tile mode: V105)
#               vrcanvas, a picture of one byte a pixel in the kernel's canvas mode: V166)
#      src      the clipboard's C sources (scrap*.c) and the Open and Save dialog's
#               (vrchoose.c), the window chrome (vrwin.c) and the tile (vrtile.c), for a program that puts
#               them into an overlay (they
#               are in lib/veranda.lib too); textkit/: the text editing parts of
#               Veranda Edit (textkit.h: the gap buffer, the view, editing, undo,
#               find, the clipboard, the files), compiled into a program;
#               vrsync.c, vrserc.c, vrnet.c (the serial driver's C half, the modem's
#               rate, the sockets: Term compiles vrsync.c into an overlay of its own);
#               vrcs.s, the character set and UTF-8 (V140; -D VRCS_OVL=n: overlay n)
#      tools    vpack.py mkicons3.py vicon.py vcard.py vram2png.py mkwall.py (and wallcv.c, its C helper) vrun
#      bin      VERANDA.PRG VERANDA.SYS (when built)
#      template c/ asm/
#      docs     README.md, GUIDE.md (the programming guide), API.md (every call),
#               NET.md (vrnet, the network: V98)
set -e
cd "$(dirname "$0")/.."
DEST=${1:-build/sdk}
export CC65_HOME=${CC65_HOME:-$HOME/.local/share/cc65}
[ -f build/gen/veranda.h ] || { echo "mksdk: run make api first" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"/{include,cfg,lib,src,tools,template,docs}
cp build/gen/veranda.h build/gen/veranda.inc inc/macros.inc inc/x16hw.inc sdk/lib/vr.h sdk/lib/scrap.h sdk/lib/vrchoose.h sdk/lib/fontpick.h sdk/lib/theme.h sdk/lib/vrpath.h sdk/lib/vrwin.h sdk/lib/wallcfg.h sdk/lib/vrser.h sdk/lib/vrnet.h sdk/lib/vrpic.h sdk/lib/vrcanvas.h sdk/lib/vrcs.h sdk/lib/vralert.h "$DEST/include/"
cp sdk/cfg/app.cfg sdk/cfg/app-c.cfg sdk/cfg/app-c-ovl.cfg "$DEST/cfg/"
O=$(mktemp -d)
python3 -I -B tools/splitc.py build/gen/veranda_c.s "$O/src"     # one object a call
for s in "$O"/src/*.s sdk/lib/crt0.s sdk/lib/irq.s sdk/lib/vrfile.s sdk/lib/vrdlg.s sdk/lib/vrtramp.s sdk/lib/fontpick.s sdk/lib/vrser.s sdk/lib/vrnetcrc.s sdk/lib/vrpic.s sdk/lib/vrcanvas.s sdk/lib/vrcs.s sdk/lib/vrkbd.s sdk/lib/vrkmap.s sdk/lib/vrroom.s; do
	ca65 --cpu 65C02 -I "$DEST/include" -I "$CC65_HOME/asminc" "$s" -o "$O/$(basename "$s" .s).o"
done
for c in sdk/lib/scrapio.c sdk/lib/scraptbeg.c sdk/lib/scraptput.c sdk/lib/scraptget.c sdk/lib/scrapphoto.c sdk/lib/vrchoose.c sdk/lib/theme.c sdk/lib/themedraw.c sdk/lib/themecov.c sdk/lib/vrpath.c sdk/lib/vrwin.c sdk/lib/vrscroll.c sdk/lib/vralert.c sdk/lib/vrbar.c sdk/lib/vrtile.c sdk/lib/vrserc.c sdk/lib/vrsync.c sdk/lib/vrnet.c sdk/lib/vrahead.c; do     # the clipboard (scrap.h)
	cl65 -t none --cpu 65C02 -O -I "$DEST/include" --asm-include-dir "$DEST/include" -c -o "$O/$(basename "$c" .c).o" "$c"
done
ar65 a "$DEST/lib/veranda.lib" "$O"/*.o
rm -rf "$O"
cp sdk/lib/scrap*.c sdk/lib/vrchoose.c sdk/lib/vrwin.c sdk/lib/vrscroll.c sdk/lib/vralert.c sdk/lib/vrtile.c sdk/lib/vrserc.c sdk/lib/vrsync.c sdk/lib/vrnet.c sdk/lib/vrahead.c sdk/lib/vrnetp.h sdk/lib/vrcs.s "$DEST/src/"   # (to compile into an overlay of one's own)
mkdir -p "$DEST/src/textkit"
cp sdk/lib/textkit/*.c sdk/lib/textkit/*.s sdk/lib/textkit/textkit.h "$DEST/src/textkit/"   # (Veranda Edit's text parts: V93)
cp tools/vrcs.py tools/vpack.py tools/mkicons3.py tools/vicon.py tools/vcard.py tools/vram2png.py tools/mkwall.py tools/wallkit.py tools/wall_dusk.py tools/wallcv.c tools/vrun "$DEST/tools/"
if [ -f build/VERANDA.PRG ] && [ -f build/VERANDA.SYS ]; then
	mkdir -p "$DEST/bin"
	cp build/VERANDA.PRG build/VERANDA.SYS "$DEST/bin/"
fi
cp -r sdk/template/c sdk/template/asm "$DEST/template/"
cp sdk/docs/README.md sdk/docs/GUIDE.md docs/API.md docs/NET.md "$DEST/docs/"
echo "mksdk: the SDK in $DEST"
