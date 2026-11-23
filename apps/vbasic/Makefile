# VeraBASIC Run (DECISIONS V86), a Veranda application: the interpreter in
# assembly (vb.s and its parts), the window, the loader and the test
# harness in C (main.c), against the installed SDK
#   make        "VeraBASIC Run.cvt" (SDK, default ../../build/sdk)
#   make test   the test build (VB_TEST: VBTEST.LST's programs, logged)
#   make ide    "VeraBASIC.cvt", the editor and the runtime (DECISIONS V93):
#               these sources with VB_IDE (in $(OUT)/ide), the C overlays
#               linked again for that main link, then the editor's own link
#               (ide/ide.cfg): its main RAM part as records 12-14, its
#               banks as records 15-22, the debugger (DECISIONS V97): the
#               runtime's overlay 12 as record 23, its bank B9 as 24;
#               Save program and Make application (DECISIONS V99): B10 as record 5 (V149: vbfloat.s in overlay 8)
#   make idetest  the editor's test build (IDE_TEST: tests/edit_play.s plays
#               IDE.PLY; in $(OUT)/idetest)
# OUT: where the results go (default here)
SDK      ?= ../../build/sdk
OUT      ?= .
GEN      ?= ../../vbasic/gen
CC65     := cl65 -t none --cpu 65C02 -O -I $(SDK)/include --asm-include-dir $(SDK)/include --asm-include-dir $(GEN)
.DEFAULT_GOAL := all
SRC      := main.c vb.s
DEPS     := vb.inc vbdbg.s vbdbg.inc vbexpr.s vbstr.s vbio.s vbload.s vbtok.s vbprep.s vbphelp.s vbfloat.s vbx.s vbev.s vbui.s vbgfx.s vbdlg.s vbfile.s $(GEN)/tokens.inc
# the window chrome: the SDK's source compiled into overlay 7 (main RAM is
# the interpreter's)
VRWIN    := $(OUT)/vrwin.o

$(VRWIN): $(SDK)/src/vrwin.c $(SDK)/include/vrwin.h
	$(CC65) --code-name OVERLAY7 -c -o $@ $<

all: $(OUT)/VBRun.cvt


# (objects of their own: tools/vbceq.py reads their exports)
$(OUT)/vbrun.bin: $(SRC) $(DEPS) $(VRWIN) app.hdr
	$(CC65) $(CFLAGS) -c -o $(OUT)/main.o main.c
	$(CC65) $(CFLAGS) -c -o $(OUT)/vb.o vb.s
	$(CC65) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=0x200 -Wl -Ln,$(OUT)/vbrun.lbl -m $(OUT)/vbrun.map -o $@ $(OUT)/main.o $(OUT)/vb.o $(VRWIN) $(SDK)/lib/veranda.lib

# the C overlays (records 10 and 11, vbc.cfg; DECISIONS V90): a link of
# their own after the main one, its symbols below $A000 as equates
VBCA     := $(OUT)/vbca.o $(OUT)/vrchoose.o
VBCB     := $(OUT)/vbcbs.o $(OUT)/vbcb.o $(OUT)/vrtile.o $(OUT)/scrapio.o $(OUT)/scraptget.o $(OUT)/scraptput.o $(OUT)/scraptbeg.o $(OUT)/scrapphoto.o
SEGA     := --code-name ACODE --rodata-name ARO --data-name ADATA
SEGB     := --code-name BCODE --rodata-name BRO --data-name BDATA
$(OUT)/vbca.o: vbca.s
	$(CC65) -c -o $@ $<
$(OUT)/vbcbs.o: vbcb.s
	$(CC65) -c -o $@ $<
$(OUT)/vrchoose.o: $(SDK)/src/vrchoose.c
	$(CC65) $(SEGA) -c -o $@ $<
$(OUT)/vbcb.o: vbcb.c
	$(CC65) $(SEGB) --bss-name BBSS -c -o $@ $<
$(OUT)/%.o: $(SDK)/src/%.c
	$(CC65) $(SEGB) --bss-name BSS2 -c -o $@ $<
BIN      ?= vbrun
$(OUT)/vbc.a: $(OUT)/$(BIN).bin $(VBCA) $(VBCB) vbc.cfg ../../tools/vbceq.py
	python3 -I -B ../../tools/vbceq.py $(OUT)/$(BIN).lbl $(OUT)/$(BIN).map $(OUT)/vbceq.s
	$(CC65) -c -o $(OUT)/vbceq.o $(OUT)/vbceq.s
	$(CC65) -C vbc.cfg $$(python3 -I -B ../../tools/vbceq.py --defs $(OUT)/$(BIN).lbl) -m $(OUT)/vbc.map -o $(OUT)/vbc $(VBCA) $(VBCB) $(OUT)/vbceq.o $(SDK)/lib/veranda.lib

RECS     := $(OUT)/vbrun.bin $(foreach n,1 2 3 4 5 6 7 8 9,$(OUT)/vbrun.bin.$(n)) $(OUT)/vbc.a $(OUT)/vbc.b
$(OUT)/VBRun.cvt: $(OUT)/vbrun.bin $(OUT)/vbc.a icon.pbm tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ app.hdr $(RECS)
	cp $@ "$(OUT)/VeraBASIC Run.cvt"

test:
	rm -f $(OUT)/vbrun.bin $(OUT)/vbc.a
	$(MAKE) OUT=$(OUT) CFLAGS="-DVB_TEST --asm-define VB_TEST=1 $(TESTFLAGS)" all

run: $(OUT)/VBRun.cvt
	$(SDK)/tools/vrun $(OUT)/VBRun.cvt

clean:
	rm -f *.o vbrun.bin vbrun.bin.* vbrun.map vbrun.lbl vbc vbc.a vbc.b vbc.map vbceq.s VBRun.cvt "VeraBASIC Run.cvt"
	rm -rf build-ide

# ---- VeraBASIC, the editor (DECISIONS V93) ----
TK       := $(SDK)/src/textkit
# (the editor's build: $(OUT)/ide, or build-ide here, not the sources' ide/)
IDED     := $(if $(filter .,$(OUT)),build-ide,$(OUT)/ide)
IDESTK   := 0x200
IDEF     := -DVB_IDE --asm-define VB_IDE=1
IDECC    := $(CC65) -I ide -I $(TK) -I $(GEN)
# the editor's parts: what each bank holds (ide/ide.h); a bank's tables in
# it (BnRO) where the kernel reads none of them (textkit's stay in LOW)
IDE_LOW  := low ops undo text
IDE_B1   := view keys
IDE_B2   := file scrap cmd scrapio scraptbeg trace
IDE_B4   := help names
IDE_B5   := fmt sbar
IDE_B6   := syn
IDE_B7   := cmd2 find
IDE_B8   := colour tok
IDE_B9   := dbg
IDE_B10  := mk
IDEO     = $(foreach f,$(IDE_LOW) $(IDE_B1) $(IDE_B2) $(IDE_B4) $(IDE_B5) $(IDE_B6) $(IDE_B7) $(IDE_B8) $(IDE_B9) $(IDE_B10),$(IDED)/i_$(f).o) \
           $(IDED)/i_vrchoose.o $(IDED)/i_lows.o $(IDED)/i_buf.o
IDEH     := ide/ide.h ide/ideshare.h ide/dbgshare.h ide/tkapp.h $(TK)/textkit.h $(GEN)/idekw.h
$(foreach f,$(IDE_B1),$(IDED)/i_$(f).o): ISEG := --code-name B1CODE
$(foreach f,$(IDE_B2),$(IDED)/i_$(f).o): ISEG := --code-name B2CODE -DSCRAP_PATH=scrap_path
$(IDED)/i_cmd.o $(IDED)/i_trace.o: ISEG := --code-name B2CODE --rodata-name B2RO
$(foreach f,$(IDE_B4),$(IDED)/i_$(f).o): ISEG := --code-name B4CODE --rodata-name B4RO
$(foreach f,$(IDE_B5),$(IDED)/i_$(f).o): ISEG := --code-name B5CODE --rodata-name B5RO
$(foreach f,$(IDE_B6),$(IDED)/i_$(f).o): ISEG := --code-name B6CODE --rodata-name B6RO
$(IDED)/i_cmd2.o: ISEG := --code-name B7CODE --rodata-name B7RO
$(IDED)/i_find.o: ISEG := --code-name B7CODE
$(foreach f,$(IDE_B8),$(IDED)/i_$(f).o): ISEG := --code-name B8CODE --rodata-name B8RO
$(foreach f,$(IDE_B9),$(IDED)/i_$(f).o): ISEG := --code-name B9CODE --rodata-name B9RO --bss-name B9BSS
$(foreach f,$(IDE_B10),$(IDED)/i_$(f).o): ISEG := --code-name B10CODE --rodata-name B10RO
$(IDED)/i_%.o: ide/%.c $(IDEH)
	$(IDECC) $(IDEF) $(ICFLAGS) $(ISEG) -c -o $@ $<
$(IDED)/i_%.o: $(TK)/%.c $(IDEH)
	$(IDECC) $(IDEF) $(ICFLAGS) $(ISEG) -c -o $@ $<
$(IDED)/i_%.o: $(SDK)/src/%.c
	$(IDECC) $(IDEF) $(ICFLAGS) $(ISEG) -c -o $@ $<
$(IDED)/i_vrchoose.o: $(SDK)/src/vrchoose.c
	$(IDECC) --code-name B3CODE --rodata-name B3RO --bss-name B3BSS -c -o $@ $<
$(IDED)/i_lows.o: ide/low.s
	$(IDECC) -c -o $@ $<
$(IDED)/i_buf.o: $(TK)/buf.s
	$(IDECC) -c -o $@ $<

# the main link with VB_IDE (and, for idetest, the player), its C overlays
$(IDED)/vbide.bin: $(SRC) $(DEPS) app.hdr ide/ideshare.h $(PLAYER)
	mkdir -p $(IDED)
	$(CC65) --code-name OVERLAY7 -c -o $(IDED)/vrwin.o $(SDK)/src/vrwin.c
	$(CC65) $(IDEF) $(ICFLAGS) -c -o $(IDED)/main.o main.c
	$(CC65) $(IDEF) $(ICFLAGS) -c -o $(IDED)/vb.o vb.s
	$(if $(PLAYER),$(CC65) -c -o $(IDED)/play.o $(PLAYER))
	$(CC65) -C $(SDK)/cfg/app-c-ovl.cfg -Wl -D,__STACKSIZE__=$(IDESTK) -Wl -Ln,$(IDED)/vbide.lbl -m $(IDED)/vbide.map -o $@ $(IDED)/main.o $(IDED)/vb.o $(if $(PLAYER),$(IDED)/play.o) $(IDED)/vrwin.o $(SDK)/lib/veranda.lib
	$(MAKE) OUT=$(IDED) BIN=vbide $(IDED)/vbc.a
	python3 -I -B ../../tools/vbceq.py $(IDED)/vbide.lbl $(IDED)/vbide.map $(IDED)/ideeq.s --lc
	$(CC65) -c -o $(IDED)/ideeq.o $(IDED)/ideeq.s

$(IDED)/ide.low: $(IDED)/vbide.bin $(IDEO) ide/ide.cfg
	$(CC65) -C ide/ide.cfg $$(python3 -I -B ../../tools/vbceq.py --ide $(IDED)/vbide.lbl) -m $(IDED)/ide.map -o $(IDED)/ide $(IDEO) $(IDED)/ideeq.o $(SDK)/lib/veranda.lib
	python3 -I -B -c "import sys; d=open(sys.argv[1],'rb').read(); [open(sys.argv[1]+'.%d' % i,'wb').write(d[i*8191:(i+1)*8191] or b'\0') for i in range(3)]" $(IDED)/ide.low
	for n in 1 2 3 4 5 6 7 8 9 10; do [ -s $(IDED)/ide.$$n ] || printf '\140' > $(IDED)/ide.$$n; done

# (record 5: B10, ide.10; overlay 8 has vbfloat.s in this build: ideshare.h IDE_REC_MK, V149)
IDERECS  = $(IDED)/vbide.bin $(foreach n,1 2 3 4,$(IDED)/vbide.bin.$(n)) $(IDED)/ide.10 \
           $(foreach n,6 7 8 9,$(IDED)/vbide.bin.$(n)) $(IDED)/vbc.a $(IDED)/vbc.b \
           $(IDED)/ide.low.0 $(IDED)/ide.low.1 $(IDED)/ide.low.2 $(foreach n,1 2 3 4 5 6 7 8,$(IDED)/ide.$(n)) \
           $(IDED)/vbide.bin.12 $(IDED)/ide.9
$(IDED)/VeraBASIC.cvt: $(IDED)/ide.low ide/app.hdr ide/icon.pbm ide/tile.txt
	python3 -I -B $(SDK)/tools/vpack.py --load 0x0801 -o $@ ide/app.hdr $(IDERECS)

ide:
	$(MAKE) OUT=$(OUT) $(IDED)/VeraBASIC.cvt

idetest:
	$(MAKE) OUT=$(OUT) IDED=$(OUT)/idetest ICFLAGS="-DIDE_TEST --asm-define IDE_TEST=1" PLAYER=../../tests/edit_play.s $(OUT)/idetest/VeraBASIC.cvt

.PHONY: all test run clean ide idetest
