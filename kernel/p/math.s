; Veranda bank P: GEOS's maths calls on zero page words, the shifts and products (written
; from the GEOS programmer's reference: registers and results as
; documented there; from bank G2, DECISIONS V81: no bank has room for all)
;
; x (and y) are zero page addresses of the operands; words are low byte
; first. Results go to the operand at x.

.include "kernel.inc"

.export k_DShiftLeft, k_DShiftRight, k_BBMult, k_BMult, k_DMult

; the product of two words in kTmp and kTmp+2 (16 bits of it) -> kPtr2
Mul16:	stz kPtr2
	stz kPtr2+1
@l:	lda kTmp+2
	ora kTmp+3
	beq @r
	lsr kTmp+3
	ror kTmp+2
	bcc @s
	clc
	lda kPtr2
	adc kTmp
	sta kPtr2
	lda kPtr2+1
	adc kTmp+1
	sta kPtr2+1
@s:	asl kTmp
	rol kTmp+1
	bra @l
@r:	lda kPtr2
	sta 0,x
	lda kPtr2+1
	sta 1,x
	rts

; the word at x shifted left y times
k_DShiftLeft:
@l:	dey
	bmi @r
	asl 0,x
	rol 1,x
	bra @l
@r:	rts

; the word at x shifted right y times (zeros in from the left)
k_DShiftRight:
@l:	dey
	bmi @r
	lsr 1,x
	ror 0,x
	bra @l
@r:	rts

; the byte at x times the byte at y -> the word at x; a is the product's
; low byte on return, as GEOS 64's BBMult leaves it (geoWrite adds to it
; without reading the word: its geos menu's height, DECISIONS V66)
k_BBMult:
	lda 0,x
	sta kTmp
	stz kTmp+1
	lda a:0,y
	sta kTmp+2
	stz kTmp+3
	jsr Mul16
	lda 0,x
	rts

; the word at x times the byte at y -> the word at x (as GEOS, the byte
; after the one at y becomes 0)
k_BMult:
	lda #0
	sta a:1,y
	; (on into DMult)

; the word at x times the word at y -> the word at x (the low 16 bits)
k_DMult:
	lda 0,x
	sta kTmp
	lda 1,x
	sta kTmp+1
	lda a:0,y
	sta kTmp+2
	lda a:1,y
	sta kTmp+3
	bra Mul16

