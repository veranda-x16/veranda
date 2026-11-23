# Note Pad, a Veranda desk accessory in C
#   make        "Note Pad.cvt" (as NotePad.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (tests/note_play.c,
#               tests/sdk_play.s; TESTFLAGS=-DNOTE_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/note_play.c ../../tests/sdk_play.s

all: $(OUT)/NotePad.cvt

$(OUT)/notepad.bin: notepad.c app.hdr
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/notepad.map -o $@ notepad.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/NotePad.cvt: $(OUT)/notepad.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/notepad.bin
	cp $@ "$(OUT)/Note Pad.cvt"

test:
	rm -f $(OUT)/notepad.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DNOTE_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o notepad.bin notepad.map NotePad.cvt "Note Pad.cvt"

.PHONY: all test clean
