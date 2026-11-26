# Veranda shell (docs/PLAN.md phase 6), built with the installed SDK
#   make SDK=<the SDK's folder>     SHELL.cvt
# The resident part and twelve banked overlays (shell.h): app-c-ovl.cfg,
# overlays = banked in app.hdr.
SDK   ?= ../build/sdk
CC65  := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC   := main.c win.c mouse.c wops.c view.c dir.c files.c print.c pins.c chrome.c tiles.c bars.c look.c wall.c dock.c look3.c look3b.c info.c prg.c ghost.s ovl.s play.s wallmap.s clip.s cmove.s gui.s guiart.s
OVLS  := shell.bin.1 shell.bin.2 shell.bin.3 shell.bin.4 shell.bin.5 shell.bin.6 shell.bin.7 shell.bin.8 shell.bin.9 shell.bin.10 shell.bin.11 shell.bin.12

all: SHELL.cvt

# the SDK's tile drawing (vr_tile, DECISIONS V90) in the tiles' overlay
vrtile.o: $(SDK)/src/vrtile.c $(SDK)/include/vr.h
	$(CC65) --code-name OVERLAY10 --rodata-name OVL10RO --bss-name OVL10BSS -c -o $@ $<

shell.bin: $(SRC) shell.h winp.h icons.h tiles.h gui.inc vrtile.o
	$(CC65) -C $(SDK)/cfg/app-c-ovl.cfg -m shell.map -o shell.bin $(SRC) vrtile.o $(SDK)/lib/veranda.lib

# (V133) the colour icons' library: records 13 and 14
icons3a.bin icons3b.bin: icons3.txt $(SDK)/tools/mkicons3.py
	python3 -I -B $(SDK)/tools/mkicons3.py lib icons3.txt icons3a.bin icons3b.bin

# (V151) the small ones (16 x 16): record 15
icons3c.bin: icons3s.txt $(SDK)/tools/mkicons3.py
	python3 -I -B $(SDK)/tools/mkicons3.py lib icons3s.txt icons3c.bin

# (V207) the icons past those records (VIDKIT Player's, the players'
# documents, MIDI Player's small one) after overlay 17's code (prg.c):
# no RAM bank more
shell.ovf.17: shell.bin icons3.txt icons3s.txt $(SDK)/tools/mkicons3.py
	python3 -I -B $(SDK)/tools/mkicons3.py ovf shell.bin.17 shell.map icons3.txt icons3s.txt shell.ovf.17

SHELL.cvt: shell.bin app.hdr icon.pbm icons3a.bin icons3b.bin icons3c.bin shell.ovf.17
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o SHELL.cvt app.hdr shell.bin $(OVLS) icons3a.bin icons3b.bin icons3c.bin shell.bin.16 shell.ovf.17

clean:
	rm -f *.o shell.bin shell.bin.* shell.ovf.17 shell.map SHELL.cvt icons3a.bin icons3b.bin icons3c.bin

.PHONY: all clean
