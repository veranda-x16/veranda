; Veranda resident core: a glyph row of a font in RAM banks (DECISIONS V62)
;
; Text is drawn by bank G, which sits at $A000 itself: a font kept in
; other RAM banks (the font service, bank T) cannot be read from there.
; For such a font (fontBank <> 0) the glyph renderer asks for each row of
; a glyph here: the row's bytes are copied into rowBuf, below $A000, and
; read from there exactly as a font in the application's RAM is read.
;
; A font's offsets count from $A000 of its first bank (fontBank) and go on
; into the next banks: bank fontBank + offset / 8192, address $A000 +
; offset MOD 8192. A row crossing into the next bank is copied byte by byte.

.include "kernel.inc"

.export FontRow, rowBuf
.import fontBank

.segment "BSS"

rowBuf:	.res ROWBUF

.segment "CODE"

; a = low, x = high byte of the row's offset; y = bytes (1 .. ROWBUF)
; -> kPtr2 = rowBuf with those bytes; the caller's RAM bank mapped again.
; Changes a, x, y, kTmp+3.
FontRow:
	sta kPtr2
	txa
	and #$1F
	ora #$A0
	sta kPtr2+1
	txa
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc fontBank
	ldx ram_bank
	sta ram_bank
	lda kPtr2+1
	cmp #$BF
	beq @edge
@fast:	dey
@l:	lda (kPtr2),y
	sta rowBuf,y
	dey
	bpl @l
@done:	stx ram_bank
	lda #<rowBuf
	sta kPtr2
	lda #>rowBuf
	sta kPtr2+1
	rts
@edge:	tya                     ; past $BFFF?
	clc
	adc kPtr2
	bcc @fast
	beq @fast
	sty kTmp+3              ; byte by byte, into the next bank at $C000
	ldy #0
@b:	lda (kPtr2)
	sta rowBuf,y
	inc kPtr2
	bne @n
	lda #$A0
	sta kPtr2+1
	inc ram_bank
@n:	iny
	cpy kTmp+3
	bne @b
	bra @done
