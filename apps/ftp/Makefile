# Veranda FTP, a Veranda application in C (DECISIONS V100)
#   make        "Veranda FTP.cvt" (FTP.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/ftp_play.c (overlay 4) and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := main.c proto.c list.c ui.c local.c sites.c u8.c pane.c
TEST_SRC ?= ../../tests/ftp_play.c ../../tests/term_play.s
# main RAM: main.c, proto.c, list.c and vrnet (veranda.lib); overlay 1
# (appBank) ui.c, local.c, u8.c and vrcs's table (V143: the SDK's
# src/vrcs.s, VRCS_BYTE: names in UTF-8 shown in the set); overlay 2
# sites.c and vrwin; overlay 3 (V149) pane.c and vrscroll; overlay 4 the
# test's

all: $(OUT)/FTP.cvt

# the window's chrome (vrwin.h): the SDK's source compiled into overlay 2
VRW      := $(OUT)/vrwin.o
$(VRW): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY2 -c -o $@ $<

# the scroll bars (vrwin.h, V146): the SDK's source compiled into overlay 3
VRS      := $(OUT)/vrscroll.o
$(VRS): $(SDK)/src/vrscroll.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY3 --rodata-name OVL3RO --bss-name OVL3BSS -c -o $@ $<

VRCS     := $(OUT)/vrcs.o
$(VRCS): $(SDK)/src/vrcs.s
	$(CC65) --asm-define VRCS_OVL=1 --asm-define VRCS_BYTE -c -o $@ $<

$(OUT)/ftp.bin: $(SRC) ftp.h app.hdr $(VRW) $(VRS) $(VRCS)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x0400 -m $(OUT)/ftp.map -o $@ $(SRC) $(EXTRA) $(VRW) $(VRS) $(VRCS) $(SDK)/lib/veranda.lib

$(OUT)/FTP.cvt: $(OUT)/ftp.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/ftp.bin $(OUT)/ftp.bin.1 $(OUT)/ftp.bin.2 $(OUT)/ftp.bin.3 $(OVL4)

test:
	rm -f $(OUT)/ftp.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DFTP_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" OVL4='$(OUT)/ftp.bin.4' all

run: $(OUT)/FTP.cvt
	$(SDK)/tools/vrun $(OUT)/FTP.cvt

clean:
	rm -f *.o ftp.bin ftp.bin.* ftp.map FTP.cvt

.PHONY: all test run clean
