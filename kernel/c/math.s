; Veranda bank C (V183: from bank W): GEOS's maths calls Ddiv and Ddec (DECISIONS V81, V101:
; bank S, which has the others, has no room for them; written from the
; GEOS programmer's reference: registers and results as documented there)
;
; x (and y) are zero page addresses of the operands; words are low byte
; first. Results go to the operand at x.

.include "kernel.inc"

.export k_Ddiv, k_Ddec

; the word at x divided by the word at y: the quotient at x, the remainder
; in r8
k_Ddiv:
	lda a:0,y
	sta kTmp
	lda a:1,y
	sta kTmp+1
	stz r8L
	stz r8H
	lda #16
	sta kTmp+2
@l:	asl 0,x
	rol 1,x
	rol r8L
	rol r8H
	lda r8L
	sec
	sbc kTmp
	tay
	lda r8H
	sbc kTmp+1
	bcc @n
	sta r8H
	sty r8L
	inc 0,x
@n:	dec kTmp+2
	bne @l
	rts

; the word at x minus 1; Z set if it is 0 then
k_Ddec:
	lda 0,x
	bne @1
	dec 1,x
@1:	dec 0,x
	lda 0,x
	ora 1,x
	rts

