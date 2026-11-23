; Veranda bank G2: the characters $A0-$FF of a font (DECISIONS V141)
;
; A Veranda font record may hold the characters $A0-$FF of the set
; (ISO-8859-16, V140) after GEOS's $20-$7F: its index table is then 193
; words (characters $20-$7F, $A0-$FF, the end; tools/fontcvt.py) and its
; bitmap begins right after it, so the bitmap's offset is the index's +
; 386, where a GEOS font has + 194; entry 96 is $7F's end and $A0's start,
; so a program that knows only GEOS's 96 characters reads the font as
; before. Bank G keeps only the first 97 entries (IDX_COPY) and has no
; room for this: GetCharWidth and Glyph ask here for a character of
; $80-$FF (without a resident stub: bank G's HiCall) and draw the '?' of
; the font when it has none.

.include "kernel.inc"

.import sysFont, fontBank, fontPage, FontRow, rowBuf
.export HiLook

EXT  = 2 * 193                  ; an extended record's index table

.segment "CODE"

; a = the character - 32 (96-223), the current font -> c clear: kTmp + 2
; its glyph's first bit in the rows (a word), a = kTmp + 3, y its width;
; c set: none ($80-$9F, a font without them, the system font, a width of
; 0: bank G draws '?'). kTmp kept; kTmp + 2, kTmp + 3, kPtr2, x changed.
HiLook:
	sec
	sbc #128
	bcc @no                 ; ($80-$9F)
	asl
	tay                     ; 2 * (c - $A0)
	bit sysFont
	bmi @no
	lda fontBank
	bne @bank
	; in the program's memory: the bitmap EXT bytes after the index
	lda cardDataPntr
	sec
	sbc curIndexTable
	tax
	lda cardDataPntr+1
	sbc curIndexTable+1
	cmp #>EXT
	bne @no
	cpx #<EXT
	bne @no
	lda cardDataPntr        ; kPtr2 = the last 194 bytes of the index (c set)
	sbc #194
	sta kPtr2
	lda cardDataPntr+1
	sbc #0
	sta kPtr2+1
	bra @entry
@bank:	phy                     ; in RAM banks: the header's offsets
	lda #4
	ldx fontPage
	ldy #4
	jsr FontRow
	lda rowBuf + 2
	sec
	sbc rowBuf
	tax
	lda rowBuf + 3
	sbc rowBuf + 1
	cmp #>EXT
	bne @no1
	cpx #<EXT
	bne @no1
	pla                     ; its entries: cardDataPntr - 194 + 2 * k
	clc
	adc cardDataPntr
	tay
	lda cardDataPntr+1
	adc #0
	tax
	tya
	sbc #194 - 1            ; (c clear)
	bcs @1
	dex
@1:	ldy #4
	jsr FontRow
	ldy #0
; (kPtr2),y: the glyph's entry and the next -> kTmp + 2 the start, y the
; width, a = kTmp + 3; c set for a width of 0
@entry:	lda (kPtr2),y
	sta kTmp+2
	iny
	lda (kPtr2),y
	sta kTmp+3
	iny
	lda (kPtr2),y
	sec
	sbc kTmp+2
	beq @no
	tay
	lda kTmp+3
	clc
	rts
@no1:	pla
@no:	sec
	rts
