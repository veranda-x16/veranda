# Calendar, a month and its appointments with alarms, a Veranda desk accessory
# in C (and the shared toolkit ../daui/daui.c)
#   make        Calendar.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DDA_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include -I ../daui --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/da_play.c ../../tests/sdk_play.s

all: $(OUT)/Calendar.cvt

# (V148) the alert icon (the SDK's vralert.h) from the colour icon
$(OUT)/alerticon.c: icon.txt
	python3 -I -B $(SDK)/tools/vicon.py --alert icon.txt $@

$(OUT)/cal.bin: calendar.c ../daui/daui.c ../daui/daui.h app.hdr $(OUT)/alerticon.c
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/cal.map -o $@ calendar.c ../daui/daui.c $(OUT)/alerticon.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/Calendar.cvt: $(OUT)/cal.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/cal.bin

test:
	rm -f $(OUT)/cal.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DCAL_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o alerticon.c cal.bin cal.map Calendar.cvt

.PHONY: all test clean
