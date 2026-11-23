# View, a Veranda application in C: text, BMP, Paint, Photo Scraps, info
#   make        View.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/view_play.c linked in (VIEW_TEST: it
#               makes BMPs with ExportRect, opens each kind of file and
#               writes its screen to a file; tools/gate_view.sh)
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/view_play.c

all: $(OUT)/View.cvt

# the Open dialog (vrchoose.h, DECISIONS V79, V82): the SDK's source
# compiled into overlay 2, its BSS in main RAM (view.c's file_dlg maps it)
VRF      := $(OUT)/vrchoose.o

$(VRF): $(SDK)/src/vrchoose.c $(SDK)/include/vrchoose.h
	$(CC65) --code-name OVERLAY2 -c -o $@ $<

# (banked overlays, app-c-ovl.cfg: overlay 1 the info page; DECISIONS V79)
$(OUT)/view.bin: view.c fast.s app.hdr $(VRF)
	$(CC65) $(CFLAGS) -Wl -D,__STACKSIZE__=0x0180 -C $(SDK)/cfg/app-c-ovl.cfg -m $(OUT)/view.map -o $@ view.c fast.s $(EXTRA) $(VRF) $(SDK)/lib/veranda.lib

$(OUT)/View.cvt: $(OUT)/view.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/view.bin $(OUT)/view.bin.1 $(OUT)/view.bin.2

test:
	rm -f $(OUT)/view.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DVIEW_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/View.cvt
	$(SDK)/tools/vrun $(OUT)/View.cvt

clean:
	rm -f *.o view.bin view.bin.* view.map View.cvt

.PHONY: all test run clean
