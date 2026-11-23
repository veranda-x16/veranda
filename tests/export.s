; gate export (phase 9, printing as a file): ExportRect, run as TEST.PRG
;
; A scene on the foreground (patterns, frames, lines, text) and another
; on the back screen only; then five pictures written:
;   FULL.BMP  the whole foreground (timed)
;   PART.BMP  13,7 - 300,250 of the foreground (the left edge mid-card)
;   BACK.BMP  101,301 - 517,470 of the back screen
;   THIN.BMP  7,5 - 7,60 (one pixel wide, the card's last pixel)
;   CLIP.BMP  600,400 - 900,900 (clipped to 639,479)
; and one empty area (left > right: INCOMPATIBLE). Console: "EXPORT <n>
; <error>" lines, TIME full <cycles, hex>, EXPORT DONE; then the VRAM dump.
; tests/check_export.py compares each file with the dump.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:
	; the foreground
	LoadB dispBufferOn, ST_WR_FORE
	ldx #0
@r:	phx
	lda Rects,x             ; pattern, left, top, right, bottom (words)
	jsr SetPattern
	plx
	phx
	lda Rects+1,x
	sta r3L
	lda Rects+2,x
	sta r3H
	lda Rects+3,x
	sta r11L
	lda Rects+4,x
	sta r11H
	lda Rects+5,x
	sta r4L
	lda Rects+6,x
	sta r4H
	lda Rects+7,x
	sta r12L
	lda Rects+8,x
	sta r12H
	jsr WRectangle
	lda #$FF
	jsr WFrameRectangle
	plx
	txa
	clc
	adc #9
	tax
	cpx #RectsEnd - Rects
	bne @r
	LoadW r3, 3
	LoadW r11, 2
	LoadW r4, 636
	LoadW r12, 477
	lda #DRAW_INK
	jsr WDrawLine
	LoadW r3, 7
	LoadW r11, 5
	LoadW r4, 7
	LoadW r12, 60
	lda #DRAW_INK
	jsr WDrawLine
	LoadW r0, Text
	LoadW r11, 40
	LoadW r12, 420
	jsr WPutString
	; the back screen only: something else
	LoadB dispBufferOn, ST_WR_BACK
	lda #19
	jsr SetPattern
	LoadW r3, 90
	LoadW r11, 290
	LoadW r4, 400
	LoadW r12, 479
	jsr WRectangle
	LoadW r3, 101
	LoadW r11, 470
	LoadW r4, 517
	LoadW r12, 301
	lda #DRAW_INK
	jsr WDrawLine
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK

	; the pictures
	sta EMU_CLOCK
	LoadW r0, NFull
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	lda #0
	jsr ExportRect
	jsr Clock
	lda #'1'
	jsr Log
	LoadW r0, NPart
	LoadW r3, 13
	LoadW r11, 7
	LoadW r4, 300
	LoadW r12, 250
	lda #0
	jsr ExportRect
	lda #'2'
	jsr Log
	LoadW r0, NBack
	LoadW r3, 101
	LoadW r11, 301
	LoadW r4, 517
	LoadW r12, 470
	lda #1
	jsr ExportRect
	lda #'3'
	jsr Log
	LoadW r0, NThin
	LoadW r3, 7
	LoadW r11, 5
	LoadW r4, 7
	LoadW r12, 60
	lda #0
	jsr ExportRect
	lda #'4'
	jsr Log
	LoadW r0, NClip
	LoadW r3, 600
	LoadW r11, 400
	LoadW r4, 900
	LoadW r12, 900
	lda #0
	jsr ExportRect
	lda #'5'
	jsr Log
	LoadW r0, NNone
	LoadW r3, 300
	LoadW r11, 10
	LoadW r4, 299
	LoadW r12, 20
	lda #0
	jsr ExportRect
	lda #'6'
	jsr Log
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; "EXPORT <a> <x as two digits>"
Log:	pha
	stx err
	LoadW r0, MsgExp
	jsr Out
	pla
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	lda err
	jsr Hex
	lda #10
	sta EMU_STDOUT
	rts

; "TIME full <32-bit hex>"
Clock:	stx err
	lda EMU_CLOCK           ; latch
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	LoadW r0, MsgTime
	jsr Out
	ldx #3
@1:	lda clk,x
	jsr Hex
	dex
	bpl @1
	lda #10
	sta EMU_STDOUT
	ldx err
	rts

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

Rects:	; pattern, left, top, right, bottom
	.byte 2
	.word 20, 20, 200, 120
	.byte 19
	.word 150, 90, 420, 260
	.byte 12
	.word 333, 31, 637, 199
	.byte 7
	.word 10, 300, 250, 470
	.byte 26
	.word 450, 250, 630, 470
RectsEnd:
Text:	.byte "Veranda prints to a file: ", 24, "bold", 27, " and plain.", 0
NFull:	.byte "FULL.BMP", 0
NPart:	.byte "PART.BMP", 0
NBack:	.byte "BACK.BMP", 0
NThin:	.byte "THIN.BMP", 0
NClip:	.byte "CLIP.BMP", 0
NNone:	.byte "NONE.BMP", 0
MsgExp:	.byte "EXPORT ", 0
MsgTime: .byte "TIME full ", 0
MsgDone: .byte "EXPORT DONE", 10, 0

.segment "BSS"

err:	.res 1
clk:	.res 4
