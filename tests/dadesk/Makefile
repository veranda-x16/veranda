# gate da: the test program (dadesk.c), against the installed SDK
#   make        DADesk.cvt (SDK, default ../../build/sdk; OUT: where)
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include

all: $(OUT)/DADesk.cvt

$(OUT)/dadesk.bin: dadesk.c watch.s app.hdr
	$(CC65) -C $(SDK)/cfg/app-c.cfg -m $(OUT)/dadesk.map -o $@ dadesk.c watch.s ../sdk_play.s $(SDK)/lib/veranda.lib

$(OUT)/DADesk.cvt: $(OUT)/dadesk.bin icon.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/dadesk.bin

.PHONY: all
