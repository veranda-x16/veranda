# Veranda Chat, a Veranda application in C (DECISIONS V111)
#   make        "Veranda Chat.cvt" (Chat.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/irc_play.c (overlay 6) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c conn.c store.c ui.c proto.c servers.c input.c bar.c
TEST_SRC ?= ../../tests/irc_play.c ../../tests/term_play.s
# main RAM: main.c, conn.c, store.c and vrnet (veranda.lib); overlay 1
# (appBank) ui.c; overlay 2 proto.c; overlay 3 servers.c;
# overlay 4 input.c and vrwin; overlay 5 bar.c (the scroll bars, the
# menus) and vrscroll (V149); overlay 6 the test's

all: $(OUT)/Chat.cvt

# the window's chrome (vrwin.h): the SDK's source compiled into overlay 4
VRW      := $(OUT)/vrwin.o
$(VRW): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY4 -c -o $@ $<

# (V149) the Sunroom scroll bar (vrwin.h's vr_scroll): the SDK's source
# compiled into overlay 5 with bar.c
VRS      := $(OUT)/vrscroll.o
$(VRS): $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY5 --bss-name OVL5BSS -c -o $@ $<

# (V143) the character set (the SDK's src/vrcs.s) in overlay 4, input.c's;
# proto.c's decoding reaches it through main.c's l10_byte
VRCS     := $(OUT)/vrcs.o
$(VRCS): $(SDK)/src/vrcs.s
	$(CC65) --asm-define VRCS_OVL=4 -c -o $@ $<

$(OUT)/chat.bin: $(SRC) chat.h app.hdr $(VRW) $(VRS) $(VRCS)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/chat.map -o $@ $(SRC) $(EXTRA) $(VRW) $(VRS) $(VRCS) $(SDK)/lib/veranda.lib

$(OUT)/Chat.cvt: $(OUT)/chat.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/chat.bin $(OUT)/chat.bin.1 $(OUT)/chat.bin.2 $(OUT)/chat.bin.3 $(OUT)/chat.bin.4 $(OUT)/chat.bin.5 $(OVL6)

test:
	rm -f $(OUT)/chat.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DCHAT_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVL6='$(OUT)/chat.bin.6' all

run: $(OUT)/Chat.cvt
	$(SDK)/tools/vrun $(OUT)/Chat.cvt

clean:
	rm -f *.o chat.bin chat.bin.* chat.map Chat.cvt

.PHONY: all test run clean
