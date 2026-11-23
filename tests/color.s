; gate color (phase 9, the colour map): ColorRect, run as TEST.PRG
;
; A picture (patterns, frames, text), then paper colours by card: the
; whole screen in colour 9 (timed), back to 0, then the list in Areas
; (overlapping, one clipped at the right and bottom, one off the screen).
; -D OFF: then ColorRect $FF (the map hidden); -D MODE: then SetVideoMode
; (which hides it too). Menus and a dialog box (DECISIONS V33): a menu
; opened and closed (RecoverAllMenus) and a dialog box opened and closed
; (its DB_USR_ROUT calls RstrFrmDialogue), each timed after the areas
; (the colours put aside and back); -D MENU: the test ends with the menu open,
; -D DLG: with the dialog box open (from its DB_USR_ROUT).
; "TIME <name> <cycles>": menu, menuoff, dlg. Console: "TIME colouron|colour <cycles, hex>" (the first
; call, which shows the map, and the second), COLOR DONE;
; the VRAM dump. tests/check_color.py checks the map, the layers and the
; picture VERA composes.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:	stz dlgEnd
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	lda #2
	jsr SetPattern
	LoadW r3, 40
	LoadW r11, 30
	LoadW r4, 300
	LoadW r12, 200
	jsr WRectangle
	lda #$FF
	LoadW r3, 40
	LoadW r11, 30
	LoadW r4, 300
	LoadW r12, 200
	jsr WFrameRectangle
	lda #19
	jsr SetPattern
	LoadW r3, 350
	LoadW r11, 250
	LoadW r4, 600
	LoadW r12, 450
	jsr WRectangle
	LoadW r0, Text
	LoadW r11, 60
	LoadW r12, 300
	jsr WPutString

	sta EMU_CLOCK
	lda #9
	jsr Whole
	lda EMU_CLOCK           ; latch
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	sta EMU_CLOCK
	lda #0
	jsr Whole
	lda EMU_CLOCK
	sta clk2
	lda EMU_CLOCK+1
	sta clk2+1
	lda EMU_CLOCK+2
	sta clk2+2
	lda EMU_CLOCK+3
	sta clk2+3
	ldx #0
@a:	lda Areas,x
	sta r3L
	lda Areas+1,x
	sta r3H
	lda Areas+2,x
	sta r11L
	lda Areas+3,x
	sta r11H
	lda Areas+4,x
	phx
	jsr ColorRect
	plx
	txa
	clc
	adc #5
	tax
	cpx #AreasEnd - Areas
	bne @a
.ifdef MENU
	LoadW r0, CMenu
	lda #0
	jsr DoMenu
	jmp Done
.endif
.ifdef DLG
	LoadB dlgEnd, $80
	LoadW r0, CDlg
	jsr DoDlgBox
.endif
	jsr UiTimes
.ifndef OFF
.ifndef MODE
	LoadW r0, NBmp          ; COLOR.BMP: 4 bpp, the colours (tests/check_color.py)
	LoadW r3, 13
	LoadW r11, 7
	LoadW r4, 600
	LoadW r12, 470
	lda #$80
	jsr ExportRect
	stx err
	LoadW r3, 45            ; and a card's colour read back (7)
	LoadW r11, 31
	jsr GetCardColor
	sta got
.endif
.endif
.ifdef OFF
	lda #$FF
	jsr ColorRect
.endif
.ifdef MODE
	lda #MODE_640x480
	jsr SetVideoMode
.endif
Done:	ldx #0
@ut:	phx
	LoadW r0, MsgTime
	jsr Out
	plx
	ldy UiNames,x
@un:	lda UiNames,y
	beq @un1
	sta EMU_STDOUT
	iny
	bra @un
@un1:	lda #' '
	sta EMU_STDOUT
	phx
	txa
	asl
	asl
	tay
	ldx #4
@uh:	lda times+3,y
	jsr Hex
	dey
	dex
	bne @uh
	lda #10
	sta EMU_STDOUT
	plx
	inx
	cpx #3
	bne @ut
	LoadW r0, MsgTime
	jsr Out
	LoadW r0, MsgOn
	jsr Out
	ldx #3
@t:	lda clk,x
	jsr Hex
	dex
	bpl @t
	lda #10
	sta EMU_STDOUT
	LoadW r0, MsgTime2
	jsr Out
	ldx #3
@t2:	lda clk2,x
	jsr Hex
	dex
	bpl @t2
	lda #10
	sta EMU_STDOUT
	LoadW r0, MsgErr
	jsr Out
	lda err
	jsr Hex
	lda got
	jsr Hex
	lda #10
	sta EMU_STDOUT
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; times 0-2: a menu open, closed, a dialog box opened and closed
UiTimes:
	stz slot
	LoadW r0, CMenu         ; (once untimed: a DoMenu after a while can take
	lda #0                  ; a second, with this kernel and the one before)
	jsr DoMenu
	jsr RecoverAllMenus
	sta EMU_CLOCK
	LoadW r0, CMenu
	lda #0
	jsr DoMenu
	ldx slot
	jsr Latch
	sta EMU_CLOCK
	jsr RecoverAllMenus
	ldx slot
	inx
	jsr Latch
	sta EMU_CLOCK
	LoadW r0, CDlg
	jsr DoDlgBox
	ldx slot
	inx
	inx
; the clock into times + 4x
Latch:	txa
	asl
	asl
	tax
	lda EMU_CLOCK
	sta times,x
	lda EMU_CLOCK+1
	sta times+1,x
	lda EMU_CLOCK+2
	sta times+2,x
	lda EMU_CLOCK+3
	sta times+3,x
	rts

; the dialog box's DB_USR_ROUT: closes it at once (-D DLG: the test ends)
DRout:	bit dlgEnd
	bpl @1
	jmp Done
@1:	jmp RstrFrmDialogue

NoOp:	rts

; the whole screen (80 x 60 cards) in colour a
Whole:	stz r3L
	stz r11L
	ldx #80
	stx r3H
	ldx #60
	stx r11H
	jmp ColorRect

Out:	ldy #0
@1:	lda (r0),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts

Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	sta EMU_STDOUT
	rts

.segment "RODATA"

; x, width, y, height (cards), colour: tests/check_color.py has the same
Areas:	.byte 2, 20, 3, 10, 2
	.byte 10, 30, 8, 20, 5
	.byte 70, 20, 50, 20, 6
	.byte 40, 1, 0, 60, 14
	.byte 90, 5, 5, 5, 7
	.byte 0, 80, 59, 1, 0
	.byte 44, 30, 30, 15, 7
	.byte 50, 6, 34, 4, 0
AreasEnd:
Text:	.byte "Colour by card, the ink stays black.", 0
MsgTime: .byte "TIME ", 0
MsgOn:	.byte "colouron ", 0
UiNames: .byte UN0 - UiNames, UN1 - UiNames, UN2 - UiNames
UN0:	.byte "menu", 0
UN1:	.byte "menuoff", 0
UN2:	.byte "dlg", 0
; a menu over the colours (cards 12-25, rows 6-11) and the default dialog
; box (cards 28-52, rows 24-36 with its shadow)
CMenu:	.byte 48, 48 + 3 * 14
	.word 100, 200
	.byte VERTICAL | UN_CONSTRAINED | 3
	.word MT1
	.byte MENU_ACTION
	.word NoOp
	.word MT2
	.byte MENU_ACTION
	.word NoOp
	.word MT3
	.byte MENU_ACTION
	.word NoOp
MT1:	.byte "Normal colours", 0
MT2:	.byte "under a menu", 0
MT3:	.byte "and a dialog box", 0
CDlg:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word DT
	.byte OK, DBI_X_0, DBI_Y_2
	.byte DB_USR_ROUT
	.word DRout
	.byte 0
DT:	.byte "A dialog box: black on white.", 0
MsgTime2: .byte "TIME colour ", 0
MsgDone: .byte "COLOR DONE", 0
MsgErr:	.byte "EXPORT ", 0
NBmp:	.byte "COLOR.BMP", 0

.segment "BSS"
clk:	.res 4
clk2:	.res 4
err:	.res 1
got:	.res 1
times:	.res 4 * 3
slot:	.res 1
dlgEnd:	.res 1
