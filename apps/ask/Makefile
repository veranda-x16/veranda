# Veranda Ask, a Veranda application in C (DECISIONS V116): built from
# Veranda Claude's files (../claude, with -DASK) and its own
#   make        "Veranda Ask.cvt" (Ask.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/ask_play.c (overlay 11) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include -I . -I ../claude --asm-include-dir $(SDK)/include
CL       := ../claude
SHARED   := $(CL)/main.c $(CL)/copy.s $(CL)/store.c $(CL)/net.c $(CL)/ui.c $(CL)/prefs.c $(CL)/parse.c \
            $(CL)/code.c $(CL)/file.c $(CL)/conv.c $(CL)/hist.c
SRC      := $(SHARED) tok.c turn.c page.c auth.c log.c logx.c logclk.c logq.c
TEST_SRC ?= ../../tests/ask_play.c ../../tests/term_play.s
# main RAM: main.c, copy.s, store.c, net.c, tok.c and vrnet (veranda.lib);
# overlay 1 (appBank) ui.c; overlay 2 prefs.c, turn.c; overlay 3 parse.c
# (with pick.c) and vrwin; overlay 4 page.c; overlay 5 auth.c; overlay 6
# code.c and the scrap library, 7 file.c, 8 conv.c, 9 hist.c (V123);
# overlay 10 log.c (V129; logclk.c in 4, logx.c in 8 and 9), sbar.c and
# vrscroll (V149); overlay 11 the test's

all: $(OUT)/Ask.cvt

# the window's chrome (vrwin.h): the SDK's source compiled into overlay 3
# (Claude has it in 2; Ask's turn.c needs that room)
VRW      := $(OUT)/vrwin.o
$(VRW): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY3 -c -o $@ $<

# (V149) the scroll bar (vrwin.h's vr_scroll): the SDK's source and
# ../claude/sbar.c compiled into overlay 10, beside log.c (its room)
SBAR     := $(OUT)/vrscroll.o $(OUT)/sbar.o
$(OUT)/vrscroll.o: $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY10 --rodata-name OVL10RO --bss-name OVL10BSS -c -o $@ $<
$(OUT)/sbar.o: $(CL)/sbar.c $(CL)/claude.h ask.h $(SDK)/include/vrwin.h
	$(CC65) -DASK $(CFLAGS) --code-name OVERLAY10 --rodata-name OVL10RO --bss-name OVL10BSS -c -o $@ $(CL)/sbar.c

# the clipboard (scrap.h): the SDK's source in overlay 6 with code.c (V123)
SCRAP    := $(OUT)/scrapio.o $(OUT)/scraptbeg.o $(OUT)/scraptget.o
$(SCRAP): $(OUT)/%.o: $(SDK)/src/%.c $(SDK)/include/scrap.h
	$(CC65) --code-name OVERLAY6 --rodata-name OVL6RO --bss-name OVL6BSS --data-name OVL6DATA \
	    -DSCRAP_PATH=scrap_path -c -o $@ $<

$(OUT)/ask.bin: $(SRC) pick.c ask.h $(CL)/claude.h $(CL)/basictok.h app.hdr $(VRW) $(SCRAP) $(SBAR)
	$(CC65) -DASK $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/ask.map -o $@ $(SRC) $(EXTRA) $(VRW) $(SCRAP) $(SBAR) $(SDK)/lib/veranda.lib

$(OUT)/Ask.cvt: $(OUT)/ask.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/ask.bin $(OUT)/ask.bin.1 $(OUT)/ask.bin.2 $(OUT)/ask.bin.3 $(OUT)/ask.bin.4 $(OUT)/ask.bin.5 $(OUT)/ask.bin.6 $(OUT)/ask.bin.7 $(OUT)/ask.bin.8 $(OUT)/ask.bin.9 $(OUT)/ask.bin.10 $(OVL11)

test:
	rm -f $(OUT)/ask.bin $(OUT)/sbar.o
	$(MAKE) OUT=$(OUT) CFLAGS="-DCLAUDE_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVL11='$(OUT)/ask.bin.11' all

run: $(OUT)/Ask.cvt
	$(SDK)/tools/vrun $(OUT)/Ask.cvt

clean:
	rm -f *.o $(CL)/*.o ask.bin ask.bin.* ask.map Ask.cvt

.PHONY: all test run clean
