# A Veranda application in assembly (ca65)
#   make        the application: "$(NAME).cvt"
#   make run    in the emulator (tools/vrun)
#   make test   headless: it must log "TEMPLATE ASM RUNNING"
SDK   ?= ../..
NAME  := $(shell sed -n 's/^name *= *//p' app.hdr)
SRC   := main.s

all: app.cvt

main.o: $(SRC)
	ca65 --cpu 65C02 -I $(SDK)/include -o main.o $(SRC)

app.bin: main.o
	ld65 -C $(SDK)/cfg/app.cfg -m app.map -o app.bin main.o

app.cvt: app.bin app.hdr icon.pbm
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o "$(NAME).cvt" app.hdr app.bin
	cp "$(NAME).cvt" app.cvt

run: app.cvt
	$(SDK)/tools/vrun "$(NAME).cvt"

test: app.cvt
	$(SDK)/tools/vrun --test "TEMPLATE ASM RUNNING" "$(NAME).cvt"

clean:
	rm -f *.o app.bin app.map app.cvt "$(NAME).cvt"

.PHONY: all run test clean
