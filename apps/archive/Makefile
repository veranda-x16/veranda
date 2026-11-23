# Archive, a Veranda application in C: GEOS disk images (D64, D71, D81)
#   make        Archive.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/archive_play.c linked in (keys for
#               the Open dialog, then a scripted sequence;
#               TESTFLAGS=-DARCHIVE_STOP=1 ends it after the first listing,
#               -DARCHIVE_SHOT in the dialog)
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/archive_play.c

all: $(OUT)/Archive.cvt

# the Open dialog (vrchoose.h, DECISIONS V79, V82): the SDK's source
# compiled into overlay 1 (banked overlays), its BSS and (V148) its read-only
# data in main RAM; overlay 2 is the window (archive.c, mapped as appBank)
# (archive.c's file_dlg maps it)
VRF      := $(OUT)/vrchoose.o

$(VRF): $(SDK)/src/vrchoose.c $(SDK)/include/vrchoose.h
	$(CC65) --code-name OVERLAY1 -c -o $@ $<

$(OUT)/archive.bin: archive.c app.hdr $(VRF)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -m $(OUT)/archive.map -o $@ archive.c $(EXTRA) $(VRF) $(SDK)/lib/veranda.lib

$(OUT)/Archive.cvt: $(OUT)/archive.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/archive.bin $(OUT)/archive.bin.1 $(OUT)/archive.bin.2

test:
	rm -f $(OUT)/archive.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DARCHIVE_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/Archive.cvt
	$(SDK)/tools/vrun $(OUT)/Archive.cvt

clean:
	rm -f *.o archive.bin archive.bin.* archive.map Archive.cvt

.PHONY: all test run clean
