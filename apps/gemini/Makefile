# Veranda Gemini, a Veranda application in C (DECISIONS V118)
#   make        "Veranda Gemini.cvt" (Gemini.cvt) and the Wikipedia launcher
#               (Wikipedia.cvt, V128), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/gemini_play.c (overlay 7), gemini_pics.c (8) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
STACK    ?= 0x0400
# (gate gemini measures its depth: "GE STACK")
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c net.c doc.c copy.s ui.c marks.c box.c url.c web.c wiki.c pic.c pngplan.c png.c pngcore.s tool.c
TEST_SRC ?= ../../tests/gemini_play.c ../../tests/gemini_pics.c ../../tests/term_play.s
# main RAM: main.c, net.c, doc.c, copy.s and vrnet (veranda.lib); overlay
# 1 (appBank) ui.c; overlay 2 marks.c, box.c; overlay 3 url.c;
# overlay 4 web.c (web pages, V124), wiki.c (Wikipedia, V128), pic.c and
# pngplan.c (pictures, V125);
# overlay 5 png.c and pngcore.s (the PNG decoder, V125);
# overlay 6 tool.c (the toolbar, from main RAM), the SDK's vrwin and
# vrscroll (the window's chrome, the scroll bar: V149; vrwin was in
# overlay 2);
# overlays 7 and 8 the test's

all: $(OUT)/Gemini.cvt $(OUT)/Wikipedia.cvt

# the Wikipedia launcher (V128): a document of Veranda Gemini's for APPS
$(OUT)/Wikipedia.cvt: wiki.hdr wiki.pbm wikitile.txt
	python3 -I -B $(SDK)/tools/vpack.py -o $@ --doc wiki.hdr

# the window's chrome and the scroll bar (vrwin.h): the SDK's sources
# compiled into overlay 6 (vrwin's variables in main RAM: the kernel
# reads its texts with the font's bank mapped; vrscroll's there)
VRW      := $(OUT)/vrwin.o $(OUT)/vrscroll.o
$(OUT)/vrwin.o: $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY6 -c -o $@ $<
$(OUT)/vrscroll.o: $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY6 --bss-name OVL6BSS -c -o $@ $<

$(OUT)/gemini.bin: $(SRC) gemini.h png.h app.hdr $(VRW)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=$(STACK) -m $(OUT)/gemini.map -o $@ $(SRC) $(EXTRA) $(VRW) $(SDK)/lib/veranda.lib

$(OUT)/Gemini.cvt: $(OUT)/gemini.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/gemini.bin $(OUT)/gemini.bin.1 $(OUT)/gemini.bin.2 $(OUT)/gemini.bin.3 $(OUT)/gemini.bin.4 $(OUT)/gemini.bin.5 $(OUT)/gemini.bin.6 $(OVLT)

test:
	rm -f $(OUT)/gemini.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DGEMINI_TEST --asm-define GEMINI_TEST=1 $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVLT='$(OUT)/gemini.bin.7 $(OUT)/gemini.bin.8' all

run: $(OUT)/Gemini.cvt
	$(SDK)/tools/vrun $(OUT)/Gemini.cvt

clean:
	rm -f *.o gemini.bin gemini.bin.* gemini.map Gemini.cvt Wikipedia.cvt

.PHONY: all test run clean
