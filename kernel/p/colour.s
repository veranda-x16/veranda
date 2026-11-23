; Veranda bank P: the page PrintRect makes (kernel/x/printrect.s), and its
; colours (docs/DECISIONS.md V38)
;
; PrPage starts a page of its own with the placement PrintRect worked out;
; PrRows sends a row (widened by PrintRect, in its bank) for as many page
; rows as it covers, or white rows: the row is copied once, then coded
; again against itself (all V0). With colour, the content stream clips to
; the area and draws the paper colours' image (a byte a card, indexed in
; the palette's 16 entries) under the ink's image mask.

.include "kernel.inc"

.export PrPage, PrRows, PrInfo, ContentColour, ColourImage
.import PageBegin, PageEnd, PutByte, PutStr, PutNum, PutSNum, PutSp
.import prOpen, prErr, pw, ph, rowBytes, prMargin, prDpi, inPage, pgCol, rowsSent, num
.import CopyRow, src, cBank, EncRow, EncWhite, EncSame

MAP     = $1AC00                ; the colour map (kernel/s/color.s)

.segment "BSS"

; PrPage's r0-r9: the area's left and bottom, width, height (dots, PDF
; coordinates), the colours' image (width, height, x, y), its first card,
; cards, first card row, card rows (the content's order)
x0:	.res 2
yb:	.res 2
wd:	.res 2
hd:	.res 2
cw:	.res 2
ch:	.res 2
cx:	.res 2
cy:	.res 2
card:	.res 1
cards:	.res 1
crow:	.res 1
crows:	.res 1
n:	.res 2

.segment "CODE"

;---------------------------------------------------------------
; PrInfo: the open document's page -> x error (INCOMPATIBLE: none); r1
; bytes a row, r2 rows, r3 dots across, r4 the margin (dots), a 0 at 150
; dpi, 1 at 300
;---------------------------------------------------------------
PrInfo:	bit prOpen
	bmi @1
	ldx #INCOMPATIBLE
	rts
@1:	MoveW rowBytes, r1
	MoveW ph, r2
	MoveW pw, r3
	MoveW prMargin, r4
	lda prDpi
	ldx #0
	rts

;---------------------------------------------------------------
; PrPage: a page of its own (the one being sent ends first); a = pgCol
; ($40 the ink's colour, $80 the paper colours); r0-r9 as above -> x
; error, c set if no page
;---------------------------------------------------------------
PrPage:	pha
	ldx #19
@1:	lda r0,x
	sta x0,x
	dex
	bpl @1
	bit prOpen
	bmi @2
	pla
	ldx #INCOMPATIBLE
	sec
	rts
@2:	bit inPage
	bpl @3
	jsr PageEnd
@3:	pla
	sta pgCol
	jsr PageBegin
	bcs @r
	ldx prErr
@r:	rts

;---------------------------------------------------------------
; PrRows: the row at r0 (0: a white row; at $A000-$BFFF in the caller's
; RAM bank) for r1 rows of the page (no more than its rows left)
;---------------------------------------------------------------
PrRows:	tsx
	lda $0103,x             ; the caller's RAM bank
	sta cBank
	bit inPage
	bmi @0
	ldx #INCOMPATIBLE
	rts
@0:	MoveW r1, n
	lda n
	ora n+1
	beq @done
	CmpW rowsSent, ph
	bcs @done
	MoveW r0, src
	lda src
	ora src+1
	bne @cp
	jsr EncWhite
	bra @nx
@cp:	jsr CopyRow             ; (to rowA: the same row again after it)
	jsr EncRow
@nx:	IncW rowsSent
@row:	lda n                   ; the rest: the same row
	bne @1
	dec n+1
@1:	dec n
	lda n
	ora n+1
	beq @done
	CmpW rowsSent, ph
	bcs @done
	jsr EncSame
	IncW rowsSent
	bra @row
@done:	ldx prErr
	rts

; the content's colour part: "x0 yb Wd Hd re W n q cw 0 0 ch cx cy cm /K
; Do Q "
ContentColour:
	ldx #0
@1:	lda x0,x
	sta num
	lda x0+1,x
	sta num+1
	phx
	jsr PutSNum
	plx
	lda Sep,x
	sta r9L
	lda Sep+1,x
	sta r9H
	phx
	jsr PutStr
	plx
	inx
	inx
	cpx #16
	bne @1
	rts

; the colours' image object (after "n 0 obj"): a byte a card, the
; palette's 16 entries
ColourImage:
	LoadW r9, SKImg
	jsr PutStr
	lda cards
	jsr Num8
	LoadW r9, SKHgt
	jsr PutStr
	lda crows
	jsr Num8
	LoadW r9, SKCs
	jsr PutStr
	ldx #0                  ; the palette: RRGGBB, each nibble twice
@p:	phx
	txa
	asl
	stz VERA_CTRL
	sta VERA_ADDR_L         ; (VRAM_PALETTE's low byte is 0)
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	lda VERA_DATA0
	pha
	lda VERA_DATA0
	jsr Hex2                ; R
	pla
	pha
	lsr
	lsr
	lsr
	lsr
	jsr Hex2                ; G
	pla
	jsr Hex2                ; B
	plx
	inx
	cpx #16
	bne @p
	LoadW r9, SKLen
	jsr PutStr
	stz num                 ; cards * rows
	stz num+1
	stz num+2
	ldx crows
@m:	lda num
	clc
	adc cards
	sta num
	bcc @m1
	inc num+1
@m1:	dex
	bne @m
	jsr PutNum
	LoadW r9, SKStr
	jsr PutStr
	; the cards: the map's attribute bytes, the paper colour in the high
	; nibble
	ldy #0
@r:	stz VERA_CTRL
	lda card
	asl
	ina
	sta VERA_ADDR_L         ; MAP + 1 + row * 256 + card * 2
	tya
	clc
	adc crow
	clc
	adc #>MAP
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^MAP | $20   ; increment 2
	ldx cards
@c:	lda VERA_DATA0
	lsr
	lsr
	lsr
	lsr
	jsr PutByte
	dex
	bne @c
	iny
	cpy crows
	bne @r
	LoadW r9, SKEnd
	jmp PutStr
Num8:	sta num
	stz num+1
	stz num+2
	jmp PutNum
; the low nibble of a as two hex digits
Hex2:	and #$0F
	tax
	lda HexD,x
	jsr PutByte
	jmp PutByte

.segment "RODATA"

Sep:	.word SSp, SSp, SSp, SClip, S00, SSp, SSp, SDoK
HexD:	.byte "0123456789ABCDEF"
SSp:	.byte " ", 0
SClip:	.byte " re W n q ", 0
S00:	.byte " 0 0 ", 0
SDoK:	.byte " cm /K Do Q ", 0
SKImg:	.byte "<</Type/XObject/Subtype/Image/Width ", 0
SKHgt:	.byte "/Height ", 0
SKCs:	.byte "/ColorSpace[/Indexed/DeviceRGB 15<", 0
SKLen:	.byte ">]/BitsPerComponent 8/Length ", 0
SKStr:	.byte ">>", 10, "stream", 10, 0
SKEnd:	.byte 10, "endstream", 10, "endobj", 10, 0
