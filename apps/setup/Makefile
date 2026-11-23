# Veranda Setup, a Veranda application in C (DECISIONS V71): a card from
# before the folders moved into them, once (the shell starts it)
#   make        "Veranda Setup.cvt" (and Setup.cvt), against the installed SDK (SDK, default ../../build/sdk)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include

all: $(OUT)/Setup.cvt

$(OUT)/setup.bin: setup.c app.hdr
	$(CC65) $(CFLAGS) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/setup.map -o $@ setup.c $(SDK)/lib/veranda.lib

$(OUT)/Setup.cvt: $(OUT)/setup.bin icon.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/setup.bin
	cp $@ "$(OUT)/Veranda Setup.cvt"

clean:
	rm -f *.o setup.bin setup.map Setup.cvt "Veranda Setup.cvt"

.PHONY: all clean
