; Veranda bank T: a line's points (DECISIONS V159)
;
; FbLine, from bank G's WDrawLine (kernel/g/draw.s) for a line wholly on
; the screen (and in the clip): the midpoint rule's terms in the zero page
; (kernel/line.inc), VERA's ports at the first point's byte (port 0: the
; byte read and written, increment 0; port 1: the back screen for a
; recover, read, or the foreground for both screens, written; a steep
; line's increment the stride, one access a point, a flat one's 0), lnM
; its pixel's mask. A point: new = D XOR ((D XOR S) AND lnM), D port 0's
; byte, S the fill's byte (lnP) or, for a recover, port 1's: Plot's span
; rule (both screens: the back screen's other pixels to both; a recover:
; the foreground from the back screen). From point to point the ports
; and the mask step (a steep line's port 1 steps itself).
;
; y = $FF for a steep line (major y), else 0 (major x); a = 1 if port 1
; is used (lnF not 0); lnC = the points + $101. In LATE, after the
; variables (the room: font.s's buf and rtab one buffer, V159).

.include "kernel.inc"
.include "line.inc"

.import kStride
.export FbLine

.segment "BSS"

ftSt:	.res 1                  ; $FF steep
ftNP:	.res 1                  ; 1: port 1 used (with port 0: x = 1 .. 0)
ftT:	.res 1

.segment "LATE"

FbLine:
	sty ftSt
	sta ftNP
Point:	lda lnP
	bit lnF
	bpl @a
	lda VERA_DATA1
@a:	eor VERA_DATA0
	and lnM
	eor VERA_DATA0
	sta VERA_DATA0
	bvc @b
	sta VERA_DATA1
@b:	dec lnC
	bne @c
	dec lnC+1
	bne @c
	rts
@c:	bit ftSt
	bmi @sy
	lsr lnM                 ; flat: x + 1
	bcc @t
	ror lnM
	lda #1
	jsr FtStep
	bra @t
@sy:	clc                     ; steep: y + 1 (port 0; port 1 steps itself)
	lda VERA_ADDR_L
	adc kStride
	sta VERA_ADDR_L
	bcc @t
	inc VERA_ADDR_M
	bne @t
	inc VERA_ADDR_H
@t:	lda lnE+1
	bmi NoStep
	lda lnE                 ; the minor coordinate steps
	clc
	adc lnI2
	sta lnE
	lda lnE+1
	adc lnI2+1
	sta lnE+1
	bit ftSt
	bpl Flat2
	bit lnSy                ; steep: x +- 1
	bmi @l
	lsr lnM
	bcc Point
	ror lnM
	lda #1
	bra @s
@l:	asl lnM
	bcc Point
	rol lnM
	lda #$FF
@s:	jsr FtStep
	bra Point

Flat2:	ldx ftNP                ; flat: y +- 1, the ports x .. 0
	bit lnSy
	bmi @up
@dn:	stx VERA_CTRL
	clc
	lda VERA_ADDR_L
	adc kStride
	sta VERA_ADDR_L
	bcc @d
	inc VERA_ADDR_M
	bne @d
	inc VERA_ADDR_H
@d:	dex
	bpl @dn
	jmp Point
@up:	stx VERA_CTRL
	sec
	lda VERA_ADDR_L
	sbc kStride
	sta VERA_ADDR_L
	bcs @u
	lda VERA_ADDR_M
	bne @m
	dec VERA_ADDR_H
@m:	dec VERA_ADDR_M
@u:	dex
	bpl @up
	jmp Point
NoStep:	lda lnE
	clc
	adc lnI1
	sta lnE
	lda lnE+1
	adc lnI1+1
	sta lnE+1
	jmp Point

; the ports' addresses + a (-128 .. 127): port 0, and port 1 if ftNP
FtStep:	sta ftT
	ldy #0
	cmp #$80
	bcc @1
	dey
@1:	ldx ftNP
@p:	stx VERA_CTRL
	clc
	lda VERA_ADDR_L
	adc ftT
	sta VERA_ADDR_L
	tya
	adc VERA_ADDR_M
	sta VERA_ADDR_M
	tya
	adc VERA_ADDR_H         ; (bit 16; the increment above it as it is)
	sta VERA_ADDR_H
	dex
	bpl @p
	rts
