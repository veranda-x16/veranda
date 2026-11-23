# Veranda Update, a Veranda application in C (DECISIONS V130)
#   make        "Veranda Update.cvt" (Update.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/update_play.c, tests/sysui_test.c and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c http.c crc.s job.c man.c ui.c swap.c ../sysui/sysui.c
TEST_SRC ?= ../../tests/update_play.c ../../tests/sysui_test.c ../../tests/term_play.s
# main RAM: main.c (with the overlays' wrappers), http.c, crc.s, vrnet and
# sysui (veranda.lib, sysui.c); overlay 1 (appBank, mapped for good):
# job.c; overlay 2: man.c, ui.c; overlay 3: swap.c (a string the kernel
# reads stays in main RAM or goes through K()); a C stack of 1 KB

all: $(OUT)/Update.cvt

$(OUT)/update.bin: $(SRC) up.h ../sysui/sysui.h app.hdr
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/update.map -o $@ $(SRC) $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/Update.cvt: $(OUT)/update.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/update.bin $(OUT)/update.bin.1 $(OUT)/update.bin.2 $(OUT)/update.bin.3 $(OVLT)

test:
	rm -f $(OUT)/update.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DUP_TEST -DSYSUI_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/Update.cvt
	$(SDK)/tools/vrun $(OUT)/Update.cvt

clean:
	rm -f *.o ../sysui/*.o update.bin update.bin.* update.map Update.cvt

.PHONY: all test run clean
