; Veranda bank C: the switcher's unpacker (DECISIONS V83, V189): pack.s's
; pages back from the chain (its format and order there), run at PK_RUN;
; the image at PKIMG_B in bank C (V189)

.include "kernel.inc"

.global S_k_TaskCtl
.import kBankBase

pkSP    = r8L
pkHome  = r8H
pkKind  = r9L
pkCnt   = r9H
pkI     = r10L
pkJ     = r10H
pkV     = r11L
pkT     = r11H
pkCur   = r12L

.segment "PKIMG"

PkImgB:
.assert PkImgB = PKIMG_B, lderror, "the unpack image is not at PKIMG_B"
.org PK_RUN
.include "pkgo.inc"

PageOp:	ldx pkKind              ; (V189) VRAM: straight to VERA
	dex
	beq UnpV
	lda (r4)                ; a page of one byte ($FF first): straight to
	cmp #$FF                ; the page but for bank U's XOR
	bne @gen
	jsr Get
	jsr Get
	ldx pkKind
	cpx #3
	beq @buf
	ldx ram_bank            ; bank r7L at r6 (kind 0: RAM, r7L the
	ldy r7L                 ; chain's bank)
	sty ram_bank
	ldy #0
@f:	sta (r6),y
	iny
	bne @f
	stx ram_bank
	rts
@buf:	ldy #0                  ; (kind 3) PK_BUF, then as any page
@b:	sta PK_BUF,y
	iny
	bne @b
	bra Store
@gen:	jsr Unpack
; PK_BUF to the page (as Fetch; kind 0 with r7L, the chain's bank,
; mapped)
Store:	ldy #0
	ldx ram_bank
	lda pkKind
	cmp #3
	bne @3
	lda r7H
	sta ram_bank
@x:	lda (r6),y
	eor PK_BUF,y
	sta PK_BUF,y
	iny
	bne @x
@3:	lda r7L
	sta ram_bank
@b:	lda PK_BUF,y
	sta (r6),y
	iny
	bne @b
	stx ram_bank
	rts

; (V189) a VRAM page from the chain straight to VERA's port 0, as Unpack
UnpV:	ldy #0
@n:	jsr Get
	cmp #$FF
	beq @rest
	cmp #$80
	bcs @run
	tax
	inx
@l:	jsr Get
	sta VERA_DATA0
	iny
	dex
	bne @l
	tya
	bne @n
	rts
@run:	sbc #$80 - 3            ; (c set)
	tax
	jsr Get
@r1:	sta VERA_DATA0
	iny
	dex
	bne @r1
	tya
	bne @n
	rts
@rest:	jsr Get
	cpy #0
	bne @r2
	ldx #256 / 8            ; the whole page: 8 at a time
@v:
.repeat 8
	sta VERA_DATA0
.endrepeat
	dex
	bne @v
	rts
@r2:	sta VERA_DATA0
	iny
	bne @r2
	rts

; a page from the chain to PK_BUF
Unpack:	ldy #0
@n:	jsr Get
	cmp #$FF
	beq @rest
	cmp #$80
	bcs @run
	tax
	inx
@l:	jsr Get
	sta PK_BUF,y
	iny
	dex
	bne @l
	cpy #0
	bne @n
	rts
@run:	sbc #$80 - 3            ; (c set)
	tax
	jsr Get
@r1:	sta PK_BUF,y
	iny
	dex
	bne @r1
	cpy #0
	bne @n
	rts
@rest:	jsr Get
@r2:	sta PK_BUF,y
	iny
	bne @r2
	rts

; a byte from the chain (x, y kept)
Get:	lda (r4)
	inc r4L
	beq @p
	rts
@p:	pha
	inc r4H
	lda r4H
	cmp #$C0
	bne @r
	phx
	phy
	lda #TC_NEXT            ; (V145: bank W's, the next from the list or,
	FARCALL k_TaskCtl       ; in Roomy mode, from the card)
	sta ram_bank
	lda #$A0
	sta r4H
	ply
	plx
@r:	pla
	rts

PkEnd:
.reloc
PkLenB = PkEnd - PkGo
.assert PkLenB <= PK_MAX, error, "the unpack image does not fit $0600-PK_N"
