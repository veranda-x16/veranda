# Veranda Claude, a Veranda application in C (DECISIONS V114, V123)
#   make        "Veranda Claude.cvt" (Claude.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/claude_play.c (overlay 9) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c copy.s store.c net.c ui.c prefs.c parse.c turn.c page.c code.c file.c conv.c hist.c
TEST_SRC ?= ../../tests/claude_play.c ../../tests/term_play.s
# main RAM: main.c, copy.s, store.c, net.c and vrnet (veranda.lib);
# overlay 1 (appBank) ui.c; overlay 2 prefs.c, turn.c and vrwin; overlay 3
# parse.c, sbar.c and vrscroll (V149); overlay 4 page.c; overlay 5 code.c and the scrap library;
# overlay 6 file.c; overlay 7 conv.c; overlay 8 hist.c; overlay 9 the test's

all: $(OUT)/Claude.cvt

# the window's chrome (vrwin.h): the SDK's source compiled into overlay 2
VRW      := $(OUT)/vrwin.o
$(VRW): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY2 -c -o $@ $<

# (V149) the scroll bar (vrwin.h's vr_scroll): the SDK's source and sbar.c
# compiled into overlay 3, beside the parser (its room)
SBAR     := $(OUT)/vrscroll.o $(OUT)/sbar.o
$(OUT)/vrscroll.o: $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY3 --rodata-name OVL3RO --bss-name OVL3BSS -c -o $@ $<
$(OUT)/sbar.o: sbar.c claude.h $(SDK)/include/vrwin.h
	$(CC65) $(CFLAGS) --code-name OVERLAY3 --rodata-name OVL3RO --bss-name OVL3BSS -c -o $@ sbar.c

# the clipboard (scrap.h): the SDK's source compiled into overlay 5 with
# code.c, its only caller (V123: not linked into main RAM from veranda.lib)
SCRAP    := $(OUT)/scrapio.o $(OUT)/scraptbeg.o $(OUT)/scraptget.o
$(SCRAP): $(OUT)/%.o: $(SDK)/src/%.c $(SDK)/include/scrap.h
	$(CC65) --code-name OVERLAY5 --rodata-name OVL5RO --bss-name OVL5BSS --data-name OVL5DATA \
	    -DSCRAP_PATH=scrap_path -c -o $@ $<

$(OUT)/claude.bin: $(SRC) claude.h basictok.h app.hdr $(VRW) $(SCRAP) $(SBAR)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/claude.map -o $@ $(SRC) $(EXTRA) $(VRW) $(SCRAP) $(SBAR) $(SDK)/lib/veranda.lib

$(OUT)/Claude.cvt: $(OUT)/claude.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/claude.bin $(OUT)/claude.bin.1 $(OUT)/claude.bin.2 $(OUT)/claude.bin.3 $(OUT)/claude.bin.4 $(OUT)/claude.bin.5 $(OUT)/claude.bin.6 $(OUT)/claude.bin.7 $(OUT)/claude.bin.8 $(OVL9)

test:
	rm -f $(OUT)/claude.bin $(OUT)/sbar.o
	$(MAKE) OUT=$(OUT) CFLAGS="-DCLAUDE_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVL9='$(OUT)/claude.bin.9' all

run: $(OUT)/Claude.cvt
	$(SDK)/tools/vrun $(OUT)/Claude.cvt

clean:
	rm -f *.o claude.bin claude.bin.* claude.map Claude.cvt

.PHONY: all test run clean
