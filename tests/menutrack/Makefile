# gate mouse's menu tracking program (tools/gate_mouse.sh; DECISIONS V137)
#   make SDK=<an installed SDK> OUT=<dir>   -> $(OUT)/MenuTrack.cvt
SDK ?= ../../build/sdk
OUT ?= .

all: $(OUT)/MenuTrack.cvt

$(OUT)/main.o: main.s
	ca65 --cpu 65C02 -I $(SDK)/include -o $@ main.s

$(OUT)/app.bin: $(OUT)/main.o
	ld65 -C $(SDK)/cfg/app.cfg -o $@ $<

$(OUT)/MenuTrack.cvt: $(OUT)/app.bin app.hdr icon.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $<

.PHONY: all
