; gate print (printing to PDF, DECISIONS V38): run as TEST.PRG
;
; 1. errors: PrintBand and PrintClose with no document (INCOMPATIBLE)
; 2. BANDS.PDF, A4 at 300 dpi, two pages of bands: page 1 all 3,508
;    rows of a test pattern (tests/check_print.py's band_page1: squares,
;    random bytes, sparse dots, sparse "text") in bands
;    of 16 rows from main RAM; a second PrintOpen refused; page 2, 1,000
;    rows (band_page2) in bands of 26 from a RAM bank at $A000 (the last
;    band 12 rows), then PrintPage (the rest white), PrintClose
; 3. the screens: a page of text on the foreground; a scene on the back
;    screen only; colours (ColorRect) and a red ink
; 4. TEXT150.PDF (A4, 150 dpi): the whole foreground fit to the page,
;    then 13,7 - 300,250 at 80 pixels an inch; TEXT300.PDF (A4, 300
;    dpi): the foreground fit; COLOR.PDF (Letter, 150 dpi): the back
;    screen's 40,20 - 600,460 fit, in colour; the foreground's 13,7 -
;    300,250, natural size, in colour
; Console: "PRINT <tag> <x>" lines, "DIMS <r1> <r2> <r3>", "TIME <what>
; <cycles>" (hex), PRINT DONE; then the VRAM dump.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

BUF     = $3000                 ; a band in main RAM (16 rows of 310)
ROWB    = 310                   ; A4 at 300 dpi

.segment "CODE"

Start:	jsr MkTab
	; 1. no document
	LoadW r0, BUF
	lda #1
	jsr PrintBand
	lda #'a'
	jsr Log
	jsr PrintClose
	lda #'b'
	jsr Log

	; 2. BANDS.PDF
	LoadW r0, NBands
	lda #PRINT_300DPI
	jsr PrintOpen
	lda #'c'
	jsr Log
	jsr Dims
	LoadW r0, NBands
	lda #0
	jsr PrintOpen           ; (one at a time)
	lda #'d'
	jsr Log
	jsr ClkZero
	stz gy
	stz gy+1
@p1:	LoadW a0, BUF           ; 16 rows of page 1
	ldx #16
@g1:	phx
	jsr Row1
	IncW gy
	plx
	dex
	bne @g1
	LoadW r0, BUF
	lda #16
	jsr Timed
	jsr PrintBand
	jsr Untime
	cpx #0
	bne @e1
	CmpWI gy, 3504
	bcc @p1
	LoadW a0, BUF           ; the last 4 rows
	ldx #4
@g2:	phx
	jsr Row1
	IncW gy
	plx
	dex
	bne @g2
	LoadW r0, BUF
	lda #4
	jsr Timed
	jsr PrintBand
	jsr Untime
@e1:	lda #'e'
	jsr Log
	lda #'1'
	jsr ClkLog
	; page 2 from a RAM bank
	lda #1
	jsr BankAlloc
	sta bank
	lda #'f'
	jsr Log
	jsr ClkZero
	stz gy
	stz gy+1
@p2:	lda #26                 ; rows in this band
	sta n
	sec
	lda #<1000
	sbc gy
	tax
	lda #>1000
	sbc gy+1
	bne @f
	cpx #26
	bcs @f
	stx n
@f:	lda ram_bank
	pha
	lda bank
	sta ram_bank
	LoadW a0, $A000
	ldx n
@g3:	phx
	jsr Row2
	IncW gy
	plx
	dex
	bne @g3
	LoadW r0, $A000
	lda n
	jsr Timed
	jsr PrintBand           ; (from the bank mapped now)
	jsr Untime
	pla
	sta ram_bank
	cpx #0
	bne @e2
	CmpWI gy, 1000
	bcc @p2
@e2:	lda #'g'
	jsr Log
	jsr Timed
	jsr PrintPage
	jsr Untime
	lda #'h'
	jsr Log
	jsr Timed
	jsr PrintClose
	jsr Untime
	lda #'i'
	jsr Log
	lda #'2'
	jsr ClkLog

	; 3. the screens
	jsr Screens

	; 4. TEXT150.PDF: the foreground fit, then a part at 80 pixels an inch
	LoadW r0, NT150
	lda #0
	jsr PrintOpen
	lda #'j'
	jsr Log
	jsr Dims
	jsr ClkZero
	jsr Whole
	lda #PRINT_FIT
	jsr Timed
	jsr PrintRect
	jsr Untime
	lda #'k'
	jsr Log
	lda #'3'
	jsr ClkLog
	jsr Part
	lda #0
	jsr PrintRect
	lda #'l'
	jsr Log
	jsr PrintClose
	lda #'m'
	jsr Log
	; TEXT300.PDF
	LoadW r0, NT300
	lda #PRINT_300DPI
	jsr PrintOpen
	lda #'n'
	jsr Log
	jsr Dims
	jsr ClkZero
	jsr Whole
	lda #PRINT_FIT
	jsr Timed
	jsr PrintRect
	jsr Untime
	lda #'o'
	jsr Log
	lda #'4'
	jsr ClkLog
	jsr PrintClose
	lda #'p'
	jsr Log
	; COLOR.PDF
	LoadW r0, NColor
	lda #PRINT_LETTER
	jsr PrintOpen
	lda #'q'
	jsr Log
	jsr Dims
	jsr ClkZero
	LoadW r3, 40
	LoadW r11, 20
	LoadW r4, 600
	LoadW r12, 460
	lda #PRINT_BACK | PRINT_FIT | PRINT_COLOR
	jsr Timed
	jsr PrintRect
	jsr Untime
	lda #'r'
	jsr Log
	lda #'5'
	jsr ClkLog
	jsr Part
	lda #PRINT_COLOR
	jsr PrintRect
	lda #'s'
	jsr Log
	jsr PrintClose
	lda #'t'
	jsr Log
	; nothing left: an empty area
	LoadW r0, NNone
	lda #0
	jsr PrintOpen
	LoadW r3, 300
	LoadW r11, 10
	LoadW r4, 299
	LoadW r12, 20
	lda #0
	jsr PrintRect
	lda #'u'
	jsr Log
	jsr PrintClose          ; (a document of no pages)
	lda #'v'
	jsr Log

	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Whole:	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	rts
Part:	LoadW r3, 13
	LoadW r11, 7
	LoadW r4, 300
	LoadW r12, 250
	rts

;---------------------------------------------------------------
; the test patterns (tests/check_print.py has the same)
;---------------------------------------------------------------
; the table: an 8-bit Galois LFSR (taps $B8) from 1
MkTab:	lda #1
	ldx #0
@1:	lsr
	bcc @2
	eor #$B8
@2:	sta Tab,x
	inx
	bne @1
	rts

; page 1's row gy to (a0), a0 past it: rows 0-999 16 x 16 squares, 1000-
; 1099 the table, 1100-1399 the table & $11, 1400- sparse "text"; a
; border: the first two and the last two dots of every row
Row1:	MoveW a0, a1            ; (the row's start)
	stz bl
	LoadW cnt, ROWB
	CmpWI gy, 1000
	bcs @b
	lda gy                  ; A: ((gy >> 4) ^ (b >> 1)) & 1
	lsr
	lsr
	lsr
	lsr
	sta k1
@a:	lda bl
	lsr
	eor k1
	and #1
	beq @a0
	lda #$FF
@a0:	jsr Put
	bne @a
	jmp @bd
@b:	CmpWI gy, 1400
	bcs @c
	LoadB k3, $FF           ; B: Tab[(gy * 3 + b) & 255], from 1100 & $11
	CmpWI gy, 1100
	bcc @b0
	LoadB k3, $11
@b0:	lda gy
	asl
	clc
	adc gy
	sta k1
@b1:	lda k1
	clc
	adc bl
	tax
	lda Tab,x
	and k3
	jsr Put
	bne @b1
	bra @bd
@c:	lda gy                  ; C: (gy & 63) < 24 and (b & 7) < 5: Tab[(gy + 5 b) & 255] & $7E
	and #63
	cmp #24
	bcs @c0
	MoveB gy, k1
	stz k2                  ; 5 b
@c1:	lda bl
	and #7
	cmp #5
	lda #0
	bcs @c2
	lda k1
	clc
	adc k2
	tax
	lda Tab,x
	and #$7E
@c2:	pha
	lda k2
	clc
	adc #5
	sta k2
	pla
	jsr Put
	bne @c1
	bra @bd
@c0:	lda #0
	jsr Put
	bne @c0
@bd:	lda (a1)                ; the border
	ora #$C0
	sta (a1)

	lda a1+1
	pha
	inc a1+1
	ldy #ROWB - 1 - 256
	lda (a1),y
	ora #$03
	sta (a1),y
	pla
	sta a1+1
	rts

; page 2's row gy: Tab[(gy + b) & 255] & Tab[(7 gy + 3 b) & 255] & $18
Row2:	stz bl
	LoadW cnt, ROWB
	lda gy
	sta k1
	asl
	asl
	asl
	sec
	sbc gy
	sta k2                  ; 7 gy + 3 b
@1:	lda k1
	clc
	adc bl
	tax
	lda Tab,x
	sta k3
	ldx k2
	lda Tab,x
	and k3
	and #$18
	pha
	lda k2
	clc
	adc #3
	sta k2
	pla
	jsr Put
	bne @1
	rts

; a to (a0), a0 + 1, bl + 1; z set after the row's last byte
Put:	sta (a0)
	IncW a0
	inc bl
	lda cnt
	bne @1
	dec cnt+1
@1:	dec cnt
	lda cnt
	ora cnt+1
	rts

;---------------------------------------------------------------
; the screens: text on the foreground, a scene on the back screen,
; colours, a red ink
;---------------------------------------------------------------
Screens:
	LoadB dispBufferOn, ST_WR_FORE
	LoadW r12, 8            ; the baselines, 9 rows apart
	stz line
@t:	lda line
	and #3
	asl
	tax
	lda Lines,x
	sta r0L
	lda Lines+1,x
	sta r0H
	LoadW r11, 6
	lda line
	and #1
	beq @t1
	LoadW r11, 30
@t1:	jsr WPutString
	AddVW 9, r12
	inc line
	lda line
	cmp #53
	bne @t
	; the back screen
	LoadB dispBufferOn, ST_WR_BACK
	ldx #0
@r:	phx
	lda Rects,x
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
	LoadW r3, 45
	LoadW r11, 25
	LoadW r4, 595
	LoadW r12, 455
	lda #DRAW_INK
	jsr WDrawLine
	LoadW r0, TBack
	LoadW r11, 200
	LoadW r12, 440
	jsr WPutString
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	; colours: card areas (x, width, y, height, colour)
	ldx #0
@k:	lda Cols,x
	sta r3L
	lda Cols+1,x
	sta r3H
	lda Cols+2,x
	sta r11L
	lda Cols+3,x
	sta r11H
	lda Cols+4,x
	phx
	jsr ColorRect
	plx
	txa
	clc
	adc #5
	tax
	cpx #ColsEnd - Cols
	bne @k
	LoadW r0, $FFFF         ; the ink red
	LoadW r1, $0E22
	jsr SetColors
	rts

;---------------------------------------------------------------
; the console
;---------------------------------------------------------------
; "PRINT <a> <x>"
Log:	pha
	stx err
	LoadW r0, MsgPr
	jsr Out
	pla
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	lda err
	jsr Hex
	lda #10
	sta EMU_STDOUT
	ldx err
	rts

; "DIMS <r1> <r2> <r3>"
Dims:	LoadW r0, MsgDims
	MoveW r1, k4
	MoveW r2, k5
	MoveW r3, k6
	jsr Out
	ldx #0
@1:	lda k4+1,x
	jsr Hex
	lda k4,x
	jsr Hex
	lda #' '
	sta EMU_STDOUT
	inx
	inx
	cpx #6
	bne @1
	lda #10
	sta EMU_STDOUT
	rts

; the time of the calls between Timed and Untime, added up (a, the
; registers and the flags as they were)
ClkZero: stz clk
	stz clk+1
	stz clk+2
	stz clk+3
	rts
Timed:	sta EMU_CLOCK           ; (reset)
	rts
Untime:	php
	pha
	phx
	lda EMU_CLOCK           ; latch
	clc
	adc clk
	sta clk
	lda EMU_CLOCK+1
	adc clk+1
	sta clk+1
	lda EMU_CLOCK+2
	adc clk+2
	sta clk+2
	lda EMU_CLOCK+3
	adc clk+3
	sta clk+3
	plx
	pla
	plp
	rts

; "TIME <a> <clk, hex>"
ClkLog:	pha
	LoadW r0, MsgTime
	jsr Out
	pla
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	ldx #3
@1:	lda clk,x
	jsr Hex
	dex
	bpl @1
	lda #10
	sta EMU_STDOUT
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

NBands:	.byte "BANDS.PDF", 0
NT150:	.byte "TEXT150.PDF", 0
NT300:	.byte "TEXT300.PDF", 0
NColor:	.byte "COLOR.PDF", 0
NNone:	.byte "NONE.PDF", 0
MsgPr:	.byte "PRINT ", 0
MsgDims: .byte "DIMS ", 0
MsgTime: .byte "TIME ", 0
MsgDone: .byte "PRINT DONE", 10, 0
L0:	.byte "Veranda prints to a PDF file: a page at printer resolution, 150 or 300 dots an inch, A4 or Letter.", 0
L1:	.byte "The rows go out in bands, coded as CCITT Group 4 on the way; ", 24, "bold", 27, " and ", 25, "italic", 27, " text too.", 0
L2:	.byte "GEOS printed through drivers; a PC prints the file. The quick brown fox jumps over the lazy dog 0123456789.", 0
L3:	.byte "Each page is one image, an image mask in the ink's colour; the paper colours, if any, are a second image.", 0
Lines:	.word L0, L1, L2, L3
TBack:	.byte "the back screen", 0
Rects:	; pattern, left, top, right, bottom (the back screen)
	.byte 2
	.word 40, 20, 220, 140
	.byte 19
	.word 150, 90, 420, 260
	.byte 12
	.word 333, 31, 600, 199
	.byte 7
	.word 50, 300, 250, 460
	.byte 26
	.word 450, 250, 600, 460
RectsEnd:
Cols:	; x, width, y, height (cards), colour
	.byte 5, 20, 2, 10, 2
	.byte 30, 30, 8, 20, 5
	.byte 0, 80, 40, 6, 7
	.byte 60, 15, 30, 25, 14
	.byte 1, 10, 0, 4, 3
ColsEnd:

.segment "BSS"

err:	.res 1
clk:	.res 4
gy:	.res 2
bl:	.res 1
k1:	.res 1
k2:	.res 1
k3:	.res 1
k4:	.res 2
k5:	.res 2
k6:	.res 2
cnt:	.res 2
n:	.res 1
bank:	.res 1
line:	.res 1
Tab:	.res 256
