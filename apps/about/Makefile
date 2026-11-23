# About this X16, a Veranda application in C (DECISIONS V119)
#   make        "About this X16.cvt" (About.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/about_play.c and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
BUILD    ?= $(shell git -C $(CURDIR) rev-parse --short HEAD 2>/dev/null || echo unknown)
# Veranda's version (docs/RELEASING.md): VERANDA_VERSION, else the file VERSION at the top
RELEASE  ?= $(or $(VERANDA_VERSION),$(shell cat $(CURDIR)/../../VERSION 2>/dev/null),unknown)
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := about.c hw.s ../sysui/sysui.c ../sysui/card.c ../sysui/sd.s ../sysui/dos.s
TEST_SRC ?= ../../tests/about_play.c ../../tests/sysui_test.c ../../tests/term_play.s

all: $(OUT)/About.cvt

$(OUT)/about.bin: $(SRC) ../sysui/sysui.h app.hdr
	$(CC65) $(CFLAGS) -DVR_BUILD='"$(BUILD)"' -DVR_RELEASE='"$(RELEASE)"' -C $(SDK)/cfg/app-c.cfg -m $(OUT)/about.map -o $@ $(SRC) $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/About.cvt: $(OUT)/about.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/about.bin

test:
	rm -f $(OUT)/about.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DAB_TEST -DSYSUI_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/About.cvt
	$(SDK)/tools/vrun $(OUT)/About.cvt

clean:
	rm -f *.o ../sysui/*.o about.bin about.map About.cvt

.PHONY: all test run clean
