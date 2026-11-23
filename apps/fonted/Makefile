# Font Editor, a Veranda application in C (DECISIONS V62)
#   make        "Font Editor.cvt", against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DFONTED_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/fonted_play.c ../../tests/sdk_play.s

all: $(OUT)/FontEd.cvt

# (V148) the alert icon (the SDK's vralert.h) from the colour icon; the C stack 1 KB
# (its deepest use is a few dozen bytes: the room for Sunroom's chrome)
$(OUT)/alerticon.c: icon.txt
	python3 -I -B $(SDK)/tools/vicon.py --alert icon.txt $@

$(OUT)/fonted.bin: fonted.c app.hdr $(OUT)/alerticon.c
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -Wl -D,__STACKSIZE__=0x400 -m $(OUT)/fonted.map -o $@ fonted.c $(OUT)/alerticon.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/FontEd.cvt: $(OUT)/fonted.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/fonted.bin

test:
	rm -f $(OUT)/fonted.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DFONTED_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/FontEd.cvt
	$(SDK)/tools/vrun $(OUT)/FontEd.cvt

clean:
	rm -f *.o alerticon.c fonted.bin fonted.map FontEd.cvt

.PHONY: all test run clean
