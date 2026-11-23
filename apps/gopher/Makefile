# Veranda Gopher, a Veranda application in C (DECISIONS V109)
#   make        "Veranda Gopher.cvt" (Gopher.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/gopher_play.c (overlay 3) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c net.c doc.c copy.s item.c ui.c marks.c
TEST_SRC ?= ../../tests/gopher_play.c ../../tests/term_play.s
# main RAM: main.c, net.c, doc.c and vrnet (veranda.lib); overlay 1
# (appBank) ui.c; overlay 2 marks.c, vrwin and vrscroll (V149); overlay 3 the test's

all: $(OUT)/Gopher.cvt

# the window's chrome and the scroll bar (vrwin.h): the SDK's sources
# compiled into overlay 2
VRW      := $(OUT)/vrwin.o $(OUT)/vrscroll.o
$(OUT)/vrwin.o: $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY2 -c -o $@ $<
$(OUT)/vrscroll.o: $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY2 -c -o $@ $<

$(OUT)/gopher.bin: $(SRC) gopher.h app.hdr $(VRW)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/gopher.map -o $@ $(SRC) $(EXTRA) $(VRW) $(SDK)/lib/veranda.lib

$(OUT)/Gopher.cvt: $(OUT)/gopher.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/gopher.bin $(OUT)/gopher.bin.1 $(OUT)/gopher.bin.2 $(OVL3)

test:
	rm -f $(OUT)/gopher.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DGOPHER_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVL3='$(OUT)/gopher.bin.3' all

run: $(OUT)/Gopher.cvt
	$(SDK)/tools/vrun $(OUT)/Gopher.cvt

clean:
	rm -f *.o gopher.bin gopher.bin.* gopher.map Gopher.cvt

.PHONY: all test run clean
