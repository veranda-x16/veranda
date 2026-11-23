# A Veranda application in C
#   make        the application: "$(NAME).cvt"
#   make run    in the emulator (tools/vrun)
#   make test   headless: it must log "TEMPLATE C RUNNING"
SDK   ?= ../..
NAME  := $(shell sed -n 's/^name *= *//p' app.hdr)
CC65  := cl65 -t none --cpu 65C02 -O -I $(SDK)/include
SRC   := main.c

all: app.cvt

app.bin: $(SRC) app.hdr
	$(CC65) -C $(SDK)/cfg/app-c.cfg -m app.map -o app.bin $(SRC) $(SDK)/lib/veranda.lib

app.cvt: app.bin icon.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o "$(NAME).cvt" app.hdr app.bin
	cp "$(NAME).cvt" app.cvt

run: app.cvt
	$(SDK)/tools/vrun "$(NAME).cvt"

test: app.cvt
	$(SDK)/tools/vrun --test "TEMPLATE C RUNNING" "$(NAME).cvt"

clean:
	rm -f *.o app.bin app.map app.cvt "$(NAME).cvt"

.PHONY: all run test clean
