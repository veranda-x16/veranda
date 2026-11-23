; Veranda bank W: the switcher's unpacker (DECISIONS V83): pack.s's
; pages back from the chain (its format and order there), run at PK_RUN

.include "kernel.inc"

.export PkImgB, PkLenB
.import kBankBase
.global S_k_TaskCtl

pkSP    = r8L
pkHome  = r8H
pkKind  = r9L
pkCnt   = r9H
pkI     = r10L
pkJ     = r10H
pkV     = r11L
pkT     = r11H
pkCur   = r12L

.segment "RODATA"

PkImgB:
.org PK_RUN
.include "pkgo.inc"

PageOp:	jsr Unpack
	jmp Store

; PK_BUF to the page (as Fetch)
Store:	ldy #0
	ldx pkKind
	bne @1
@r:	lda PK_BUF,y
	sta (r6),y
	iny
	bne @r
	rts
@1:	dex
	bne @2
@v:	lda PK_BUF,y
	sta VERA_DATA0
	iny
	bne @v
	rts
@2:	ldx ram_bank
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
.assert PkLenB <= PK_N - PK_RUN, error, "the unpack image does not fit $0600-PK_N"
