; Veranda shell: a window's colours moved with it (overlay 7 with wops.c;
; DECISIONS V81): CopyRect moves its pixels, this its cards' paper
; colours in the colour map (the entries: $1AC00 + y * 256 + x * 2, the
; map 128 cards wide; both bytes since V101: in tile mode a colour is the
; tile byte too, and a plain map's tile bytes are 0), so only the parts it
; uncovered are coloured again (win_colours) instead of the window's every
; card. Overlapping is fine: the rows from the bottom when it moves down, a
; row from its right end (VERA's decrement) when it moves right on the
; same rows. No menu or dialog box is open (no covered cards).
;
; void colour_move(unsigned char x, unsigned char y, unsigned char w,
;                  unsigned char h, unsigned char nx, unsigned char ny)
.include "veranda.inc"
.include "x16hw.inc"

.importzp c_sp
.import incsp5
.export _colour_move

MAPM    = $AC                   ; the map at $1AC00: its middle byte
INC1    = $11                   ; ADDR_H: increment 1, bit 16
DEC1    = $19                   ; decrement 1, bit 16

.segment "OVL7BSS"
cX:	.res 1
cY:	.res 1
cW:	.res 1
cH:	.res 1
cNX:	.res 1
cNY:	.res 1
cDir:	.res 1                  ; ADDR_H
cStep:	.res 1                  ; the rows: +1 or -1
cOdd:	.res 1                  ; 1: from an attribute byte

.segment "OVERLAY7"

_colour_move:
	sta cNY
	ldy #4
@a:	lda (c_sp),y            ; x, y, w, h, nx (pushed in that order)
	sta cX,y
	dey
	bpl @a
	; (the stack: nx at 0, h 1, w 2, y 3, x 4: reversed into cX ..)
	ldx cX                  ; cX <-> cNX, cY <-> cH
	lda cNX
	sta cX
	stx cNX
	ldx cY
	lda cH
	sta cY
	stx cH
	jsr incsp5
	lda cW
	beq @r0
	lda cH
	bne @go
@r0:	rts
@go:
	; rows: from the top, or from the bottom when moving down
	lda #1
	sta cStep
	lda cNY
	cmp cY
	bcc @t
	beq @t
	lda #$FF
	sta cStep
	lda cY                  ; the last rows first
	clc
	adc cH
	dea
	sta cY
	lda cNY
	clc
	adc cH
	dea
	sta cNY
@t:	; a row: left to right, or from its right end when moving right on the same rows
	lda #INC1
	sta cDir
	lda cNY
	cmp cY
	bne @row
	lda cNX
	cmp cX
	bcc @row
	beq @r0                 ; (not moved)
	lda #DEC1
	sta cDir
	lda cX
	clc
	adc cW
	dea
	sta cX
	lda cNX
	clc
	adc cW
	dea
	sta cNX
@row:	stz VERA_CTRL           ; port 0 reads the source
	lda cDir                ; (from the tile byte; going right, from the
	lsr a                   ; last entry's attribute byte)
	lsr a
	lsr a
	and #1
	sta cOdd
	lda cX
	asl a
	ora cOdd
	sta VERA_ADDR_L
	lda cY
	clc
	adc #MAPM
	sta VERA_ADDR_M
	lda cDir
	sta VERA_ADDR_H
	lda #1                  ; port 1 writes the destination
	sta VERA_CTRL
	lda cNX
	asl a
	ora cOdd
	sta VERA_ADDR_L
	lda cNY
	clc
	adc #MAPM
	sta VERA_ADDR_M
	lda cDir
	sta VERA_ADDR_H
	stz VERA_CTRL
	lda cW
	asl a
	tax
@c:	lda VERA_DATA0
	sta VERA_DATA1
	dex
	bne @c
	lda cY
	clc
	adc cStep
	sta cY
	lda cNY
	clc
	adc cStep
	sta cNY
	dec cH
	bne @row
@r:	rts
