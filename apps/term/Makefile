# Veranda Term, a Veranda application in C (and ser.s, the interrupt half)
#   make        "Veranda Term.cvt", against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/term_test.c and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -Ors -Cl -I $(SDK)/include --asm-include-dir $(SDK)/include
SRC      := term.c vt.c vtrun.s net.c xmodem.c ui.c sync.c tcp.c hosts.c
TEST_SRC ?= ../../tests/term_play.s
# the clipboard: the SDK's scrap library compiled into overlay 1 (with
# options/copy screen, ui.c), not linked from veranda.lib into the
# resident program, which has no room for it (DECISIONS V71)
SCRAP    := $(OUT)/scrapio.o $(OUT)/scraptbeg.o
# the modem's rate: the SDK's vrsync.c compiled into overlay 2 with
# sync.c (V94, V98); the serial driver (vrser.s, vrserc.c) from
# veranda.lib, resident
SYNC     := $(OUT)/vrsync.o
# the status bar (V149) is hosts.c's o_status in overlay 3, drawn as the
# SDK's vr_win_status draws one (V194: its own code, only what changed)

all: $(OUT)/Term.cvt

$(SCRAP): $(OUT)/%.o: $(SDK)/src/%.c $(SDK)/include/scrap.h
	$(CC65) --code-name OVERLAY1 --rodata-name OVL1RO --bss-name OVL1BSS --data-name OVL1DATA \
	    -DSCRAP_PATH=scrap_path -c -o $@ $<

$(SYNC): $(SDK)/src/vrsync.c $(SDK)/include/vrser.h
	$(CC65) --code-name OVERLAY2 --rodata-name OVL2RO --bss-name OVL2BSS --data-name OVL2DATA -c -o $@ $<

$(OUT)/term.bin: $(SRC) term.h net.h app.hdr $(SCRAP) $(SYNC)
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x400 -m $(OUT)/term.map -o $@ $(SRC) $(EXTRA) $(SCRAP) $(SYNC) $(SDK)/lib/veranda.lib

$(OUT)/Term.cvt: $(OUT)/term.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/term.bin $(OUT)/term.bin.1 $(OUT)/term.bin.2 $(OUT)/term.bin.3

test:
	rm -f $(OUT)/term.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DTERM_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

run: $(OUT)/Term.cvt
	$(SDK)/tools/vrun $(OUT)/Term.cvt

clean:
	rm -f *.o term.bin term.bin.1 term.bin.2 term.bin.3 term.map Term.cvt scrapio.o scraptbeg.o vrsync.o

.PHONY: all test run clean
