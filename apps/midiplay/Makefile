# MIDI Player, a Veranda application in C and assembly (DECISIONS V205, V206)
#   make        "MIDI Player.cvt" (MIDIPlay.cvt), against the installed SDK (SDK, default ../../build/sdk)
#   make test   the test build: tests/midiplay_play.c and tests/term_play.s linked in
#   make run    in the emulator (tools/vrun)
# OUT: where the results go (default here)
#
# main RAM: main.c, engine.s, Melodius's MIDI engine (vendor/melodius:
# midi.s, math.s), sysui; overlay 1 (appBank): ui.c; overlays 2 and 3:
# ZSMKit v3 (vendor/zsmkit, built here from its source; zsmsplit.py makes
# its two banks two records); overlay 4: vis.c (the voices' meters, the
# keyboard), overlay 5: info.c (a song read through, the GM names),
# overlay 6: now.c (now playing) (V206; pics.h and digits.h from
# mkpics.py). app-c-ovl.cfg: cc65's zero page at $50 (the MIDI engine's
# two bytes there too), the C stack 2 KB below $8800.
SDK      ?= ../../build/sdk
OUT      ?= .
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include \
            --asm-include-dir . --asm-include-dir vendor/melodius
SRC      := main.c ui.c vis.c info.c now.c engine.s vendor/melodius/midi.s vendor/melodius/math.s ../sysui/sysui.c
HDRS     := mp.h pics.h digits.h notes.h ../sysui/sysui.h app.hdr audio_t.inc vendor/melodius/x16.inc vendor/melodius/audio.inc \
            vendor/melodius/macros.inc vendor/zsmkit/src/zsmkit.inc
TEST_SRC ?= ../../tests/midiplay_play.c ../../tests/sysui_test.c ../../tests/term_play.s
ZSMKIT   := vendor/zsmkit/src/zsmkit.s vendor/zsmkit/src/x16.inc vendor/zsmkit/src/audio.inc \
            vendor/zsmkit/src/macros.inc vendor/zsmkit/zsmkit.cfg

all: $(OUT)/MIDIPlay.cvt

# ZSMKit v3 from its source (as its own Makefile: ca65, ld65 with its zsmkit.cfg)
$(OUT)/zsmkit-a000.bin: $(ZSMKIT)
	ca65 --cpu 65C02 -o $(OUT)/zsmkit.o vendor/zsmkit/src/zsmkit.s
	ld65 -C vendor/zsmkit/zsmkit.cfg -m $(OUT)/zsmkit.map -o $@ $(OUT)/zsmkit.o

$(OUT)/zsmkit.a: $(OUT)/zsmkit-a000.bin zsmsplit.py
	python3 -I -B zsmsplit.py $< $(OUT)/zsmkit.map $(OUT)/zsmkit.a $(OUT)/zsmkit.b

$(OUT)/midiplay.bin: $(SRC) $(HDRS)
	$(CC65) $(CFLAGS) $(AFLAGS) -C $(SDK)/cfg/app-c-ovl.cfg -m $(OUT)/midiplay.map -o $@ $(SRC) $(EXTRA) $(SDK)/lib/veranda.lib

$(OUT)/MIDIPlay.cvt: $(OUT)/midiplay.bin $(OUT)/zsmkit.a icon.pbm tile.txt icon.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(OUT)/midiplay.bin $(OUT)/midiplay.bin.1 \
		$(OUT)/zsmkit.a $(OUT)/zsmkit.b $(OUT)/midiplay.bin.4 $(OUT)/midiplay.bin.5 $(OUT)/midiplay.bin.6

test:
	rm -f $(OUT)/midiplay.bin
	$(MAKE) OUT=$(OUT) CFLAGS="-DMP_TEST -DSYSUI_TEST $(TESTFLAGS)" AFLAGS="--asm-define MP_TEST" EXTRA="$(TEST_SRC)" all

run: $(OUT)/MIDIPlay.cvt
	$(SDK)/tools/vrun $(OUT)/MIDIPlay.cvt

clean:
	rm -f *.o ../sysui/*.o vendor/melodius/*.o midiplay.bin midiplay.bin.* midiplay.map MIDIPlay.cvt \
		zsmkit.o zsmkit.map zsmkit-a000.bin zsmkit.a zsmkit.b

.PHONY: all test run clean
