; Veranda bank S: GEOS's maths calls on zero page words, the divisions and the rest (written
; from the GEOS programmer's reference: registers and results as
; documented there; from bank G2, DECISIONS V81: no bank has room for all; bank X to S in V101,
; Ddiv and Ddec in bank W: kernel/w/math.s)
;
; x (and y) are zero page addresses of the operands; words are low byte
; first. Results go to the operand at x.

.include "kernel.inc"

.export k_DSdiv, k_Dabs, k_Dnegate
.global S_k_Ddiv                ; (bank W's, kernel/w/math.s)

; signed: the quotient's sign from both, the remainder's from the dividend
k_DSdiv:
	lda 1,x
	sta kPtr                ; the dividend's sign
	eor a:1,y
	sta kPtr+1              ; the quotient's
	jsr k_Dabs
	phx
	tya
	tax
	jsr k_Dabs
	plx
	FARCALL k_Ddiv
	bit kPtr+1
	bpl @1
	jsr k_Dnegate
@1:	bit kPtr
	bpl @r
	phx
	ldx #r8
	jsr k_Dnegate
	plx
@r:	rts

; the word at x made positive
k_Dabs:
	lda 1,x
	bpl Done
	; (on into Dnegate)

; the word at x negated
k_Dnegate:
	sec
	lda #0
	sbc 0,x
	sta 0,x
	lda #0
	sbc 1,x
	sta 1,x
Done:	rts
