# Calculator, a Veranda desk accessory in C
#   make        Calculator.cvt, against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: a scripted session linked in (TEST_SRC;
#               TESTFLAGS=-DCALC_STOP=n ends it at frame n with a dump)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include
TEST_SRC ?= ../../tests/calc_play.c ../../tests/sdk_play.s

all: $(OUT)/Calculator.cvt

$(OUT)/calc.bin: calc.c app.hdr
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/calc.map -o $@ calc.c $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/Calculator.cvt: $(OUT)/calc.bin icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/calc.bin

test:
	rm -f $(OUT)/calc.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DCALC_TEST $(TESTFLAGS)" EXTRA="$(TEST_SRC)" all

clean:
	rm -f *.o calc.bin calc.map Calculator.cvt

.PHONY: all test clean
