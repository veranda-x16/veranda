# Photo Manager and Text Manager, Veranda desk accessories in C (one
# source, scrapman.c, built twice: -DPHOTO and -DTEXT)
#   make        PhotoMgr.cvt and TextMgr.cvt (their GEOS names: Photo
#               Manager, Text Manager), against the installed SDK (SDK,
#               default ../../build/sdk)
#   make test   the test builds: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DMAN_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/man_play.c ../../tests/sdk_play.s

all: $(OUT)/PhotoMgr.cvt $(OUT)/TextMgr.cvt

# (V148) the C stack 1 KB (its deepest use is a few dozen bytes): the room for
# Sunroom's chrome (vrwin.h) beside the Photo Manager's 20 KB picture buffer
$(OUT)/photoman.bin: scrapman.c photo.hdr
	$(CC65) -DPHOTO $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -Wl -D,__STACKSIZE__=0x400 -m $(OUT)/photoman.map -o $@ scrapman.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/textman.bin: scrapman.c text.hdr
	$(CC65) -DTEXT $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -Wl -D,__STACKSIZE__=0x400 -m $(OUT)/textman.map -o $@ scrapman.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/PhotoMgr.cvt: $(OUT)/photoman.bin photo.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ photo.hdr $(OUT)/photoman.bin

$(OUT)/TextMgr.cvt: $(OUT)/textman.bin text.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ text.hdr $(OUT)/textman.bin

test:
	rm -f $(OUT)/photoman.bin $(OUT)/textman.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DMAN_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o *.bin *.map *.cvt

.PHONY: all test clean
