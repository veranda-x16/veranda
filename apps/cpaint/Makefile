# Colour Paint, a Veranda application in C (DECISIONS V167)
#   make        ColourPaint.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DCP_STOP=n ends it at frame n)
# OUT: where the results go (default here)
# The Open and Save dialog (vrchoose) in overlay 1, as Paint has it; the
# column's art (art.s, apps/cpaint/mkart.py) in overlays 2 and 3; the
# tools of stage 4 (tools4.c) in overlay 4, draw.c's in overlay 5, the
# exports and the print (export.c) in overlay 7; cc65's
# zero page from $54: a0 and a1 ($50-$53) stay free for the test build's
# player (tests/cpaint_player.s; the test build's script in overlay 6).
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/cpaint_play.c ../../tests/cpaint_player.s
VRF      := $(OUT)/vrchoose.o

all: $(OUT)/ColourPaint.cvt

$(VRF): $(SDK)/src/vrchoose.c $(SDK)/include/vrchoose.h
	$(CC65) --code-name OVERLAY1 --rodata-name OVL1RO -c -o $@ $<

$(OUT)/tools4.o: tools4.c cpaint.h
	$(CC65) $(CFLAGS) -c -o $@ tools4.c

$(OUT)/draw.o: draw.c cpaint.h
	$(CC65) $(CFLAGS) -c -o $@ draw.c

$(OUT)/export.o: export.c cpaint.h
	$(CC65) $(CFLAGS) -c -o $@ export.c

$(OUT)/cpaint.bin: cpaint.c pic.s fill.s art.s cpaint.h defpal.h art.h app.hdr $(VRF) $(OUT)/tools4.o $(OUT)/draw.o $(OUT)/export.o
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x400 -Wl -D,__ZPSTART__=0x54 -m $(OUT)/cpaint.map -o $@ cpaint.c pic.s fill.s art.s $(EXTRA) $(VRF) $(OUT)/tools4.o $(OUT)/draw.o $(OUT)/export.o $(SDK)/lib/veranda.lib

$(OUT)/ColourPaint.cvt: $(OUT)/cpaint.bin icon.pbm icon.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/cpaint.bin $(OUT)/cpaint.bin.1 \
		$(OUT)/cpaint.bin.2 $(OUT)/cpaint.bin.3 $(OUT)/cpaint.bin.4 \
		$(OUT)/cpaint.bin.5 $(OUT)/cpaint.bin.6 $(OUT)/cpaint.bin.7

test:
	rm -f $(OUT)/cpaint.bin $(OUT)/tools4.o $(OUT)/draw.o $(OUT)/export.o
	$(MAKE) OUT=$(OUT) CFLAGS="-DCP_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o cpaint.bin cpaint.bin.* cpaint.map ColourPaint.cvt

.PHONY: all test clean
