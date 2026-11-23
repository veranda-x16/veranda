; Veranda bank C (V183: from bank W, which the switcher fills): a tile desktop's card as VERA shows it, for ExportRect
; (bank X; DECISIONS V101: banks S, which has tile mode, X and G have no room left)

.include "kernel.inc"

.export TileCard

MAP     = VRAM_FREE             ; $1AC00

.segment "BSS"

tT:	.res 1
tE:	.res 1
tK:	.res 1
tS:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; TileCard (ExportRect, bank X): x = card, a = card row, y = the pixel
; row in it (0-7) -> kTmp .. kTmp+3 its 8 pixels as VERA shows them (4
; bpp, the left one high; the flips applied), a = the palette row << 4
; shown (a covered card's: 15 or 14)
;---------------------------------------------------------------
TileCard:
	sty tK
	clc
	adc #>MAP
	stz VERA_CTRL
	sta VERA_ADDR_M
	txa
	asl
	sta VERA_ADDR_L
	LoadB VERA_ADDR_H, ^MAP | VERA_INC1
	lda VERA_DATA0          ; the tile's low byte
	sta tT
	lda VERA_DATA0
	sta tE
	bit #8                  ; vflip: row 7 - y
	beq @1
	lda #7
	sec
	sbc tK
	sta tK
@1:	lda tT                  ; VRAM_TILES + tile * 32 + row * 4
	asl
	asl
	asl
	asl
	asl
	sta tS
	lda tK
	asl
	asl
	ora tS
	sta VERA_ADDR_L
	lda tE
	and #3
	asl
	asl
	asl
	asl
	asl
	sta tS
	lda tT
	lsr
	lsr
	lsr
	ora tS
	clc
	adc #>(VRAM_TILES & $FFFF)
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_TILES | VERA_INC1
	ldx #0
@b:	lda VERA_DATA0
	sta kTmp,x
	inx
	cpx #4
	bne @b
	lda tE                  ; hflip: the bytes reversed, their nibbles swapped
	bit #4
	beq @r
	ldx #3
@h:	lda kTmp,x
	asl
	adc #$80
	rol
	asl
	adc #$80
	rol
	pha
	dex
	bpl @h
	ldx #3
@h2:	pla
	sta kTmp,x
	dex
	bpl @h2
	; (pushed kTmp+3 first ... kTmp last: pulled into kTmp+3 first: reversed)
@r:	lda tE
	and #$F0
	rts
