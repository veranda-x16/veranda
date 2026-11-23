# Disk Tools, a Veranda application in C (DECISIONS V119)
#   make        "Disk Tools.cvt" (DiskTools.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/disktools_play.c and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c walk.c space.c check.c checkui.c cardtab.c clean.c ../sysui/sysui.c ../sysui/sd.s ../sysui/dos.s
TEST_SRC ?= ../../tests/disktools_play.c ../../tests/sysui_test.c ../../tests/term_play.s
# main RAM: main.c, walk.c, check.c, sysui; overlay 1 (appBank): clean.c
# and the SDK's vrwin.c; overlay 2: space.c, cardtab.c, checkui.c and
# sysui's card.c (its card_read and card_dos renamed: main.c's wrappers
# map overlay 2 around them); a C stack of 1 KB
# (app-c-ovl.cfg: its zero page at $50 leaves $A9-$D3 free, which the
# test build's player, tests/term_play.s, uses)

all: $(OUT)/DiskTools.cvt

# the window's chrome (vrwin.h): the SDK's source compiled into overlay 1
VRW      := $(OUT)/vrwin.o
$(VRW): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY1 -c -o $@ $<

CARD     := $(OUT)/card.o
$(CARD): ../sysui/card.c ../sysui/sysui.h
	$(CC65) --code-name OVERLAY2 -Dcard_read=card_read_o -Dcard_dos=card_dos_o -c -o $@ $<

$(OUT)/disktools.bin: $(SRC) dt.h check.h ../sysui/sysui.h app.hdr $(VRW) $(CARD)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/disktools.map -o $@ $(SRC) $(EXTRA) $(VRW) $(CARD) $(SDK)/lib/veranda.lib

$(OUT)/DiskTools.cvt: $(OUT)/disktools.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/disktools.bin $(OUT)/disktools.bin.1 $(OUT)/disktools.bin.2

test:
	rm -f $(OUT)/disktools.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DDT_TEST -DSYSUI_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/DiskTools.cvt
	$(SDK)/tools/vrun $(OUT)/DiskTools.cvt

clean:
	rm -f *.o ../sysui/*.o vrwin.o card.o disktools.bin disktools.bin.* disktools.map DiskTools.cvt

.PHONY: all test run clean
