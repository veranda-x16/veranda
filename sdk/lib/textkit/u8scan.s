; textkit (Veranda Edit): u8.c's fast part (DECISIONS V143): the length of
; iobuf's run of ASCII, so plain text is not looked at byte by byte in C.
; MIT licence (see LICENSE).

	.setcpu "65C02"
	.export _u8_scan
	.import _iobuf
	.importzp ptr1, tmp1, tmp2

; unsigned int __fastcall__ u8_scan(unsigned int n): the index of iobuf's
; first byte past $7F, n if none
_u8_scan:
	sta tmp1
	stx tmp2
	lda #<_iobuf
	sta ptr1
	lda #>_iobuf
	sta ptr1+1
	ldx #0
	ldy #0
@l:	cpy tmp1
	bne @t
	cpx tmp2
	beq @e
@t:	lda (ptr1),y
	bmi @e
	iny
	bne @l
	inc ptr1+1
	inx
	bra @l
@e:	tya
	rts
