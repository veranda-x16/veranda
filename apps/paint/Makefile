# Paint, a Veranda application in C
#   make        Paint.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DPAINT_STOP=n ends it at frame n)
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/paint_play.c ../../tests/sdk_play.s
# the Open and Save dialog (vrchoose.h, DECISIONS V79, V82): the SDK's
# source compiled into overlay 1 (a banked overlay), its BSS in main RAM
# (paint.c's file_dlg maps it). The C stack 1.25 KB (Edit's is 1 KB;
# Paint has no recursion): the test build's script needs the room. cc65's
# zero page from $54: a0 and a1 ($50-$53) stay free for the test build's
# player (tests/sdk_play.s, in the interrupt)
# The Sunroom column (DECISIONS V147): chrome.c in overlay 2 (its BSS
# there too), its art (art.s, art.h: mkart.py writes them) in overlay 3,
# the newer tools (tools.c, the fill's core fill.s) in overlay 4.
VRF      := $(OUT)/vrchoose.o
OVS      := $(OUT)/chrome.o $(OUT)/art.o $(OUT)/tools.o $(OUT)/fill.o

all: $(OUT)/Paint.cvt

$(VRF): $(SDK)/src/vrchoose.c $(SDK)/include/vrchoose.h
	$(CC65) --code-name OVERLAY1 --rodata-name OVL1RO -c -o $@ $<

$(OUT)/chrome.o: chrome.c paint.h art.h
	$(CC65) --code-name OVERLAY2 --rodata-name OVL2RO --data-name OVL2DATA --bss-name OVL2BSS -c -o $@ chrome.c

$(OUT)/tools.o: tools.c paint.h
	$(CC65) -Cl --code-name OVERLAY4 --rodata-name OVL4RO --data-name OVL4DATA --bss-name OVL4BSS -c -o $@ tools.c

$(OUT)/art.o: art.s
	$(CC65) -c -o $@ art.s

$(OUT)/fill.o: fill.s
	$(CC65) -c -o $@ fill.s

$(OUT)/paint.bin: paint.c paint.h app.hdr $(VRF) $(OVS)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x500 -Wl -D,__ZPSTART__=0x54 -m $(OUT)/paint.map -o $@ paint.c $(EXTRA) $(VRF) $(OVS) $(SDK)/lib/veranda.lib

$(OUT)/Paint.cvt: $(OUT)/paint.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/paint.bin $(OUT)/paint.bin.1 \
		$(OUT)/paint.bin.2 $(OUT)/paint.bin.3 $(OUT)/paint.bin.4

test:
	rm -f $(OUT)/paint.bin $(OVS)
	$(MAKE) OUT=$(OUT) CFLAGS="-DPAINT_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/Paint.cvt
	$(SDK)/tools/vrun $(OUT)/Paint.cvt

clean:
	rm -f *.o paint.bin paint.bin.* paint.map Paint.cvt

.PHONY: all test run clean
