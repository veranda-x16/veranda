# Preferences, the control panel, a Veranda desk accessory in C (and the shared
# toolkit ../daui/daui.c)
#   make        Preferences.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DDA_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include -I ../daui --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/da_play.c ../../tests/sdk_play.s

all: $(OUT)/Preferences.cvt

$(OUT)/prefs.bin: prefs.c ../daui/daui.c ../daui/daui.h app.hdr
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/prefs.map -o $@ prefs.c ../daui/daui.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/Preferences.cvt: $(OUT)/prefs.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/prefs.bin

test:
	rm -f $(OUT)/prefs.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DPREFS_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o prefs.bin prefs.map Preferences.cvt

.PHONY: all test clean
