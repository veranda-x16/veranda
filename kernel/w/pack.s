; Veranda bank W: the switcher's packer (DECISIONS V83); unpack.s the other way
;
; An image that bank W copies to PK_RUN ($0600: dbFileNames and
; dataLongName; the system variables were put aside first) and calls
; there, so that it can map any RAM bank at $A000: bank W cannot map
; another bank under itself. Its page buffer is PK_BUF ($0400:
; fileHeader).
;
; PkGo, a = 0 (pack): the application's state, page by page, into a chain
; of RAM banks from PK_LIST[0] at r4 (the first bank's first free page);
; each page packed alone: a byte c < $80: c + 1 bytes as they are; $80 +
; k (k <= 126): the next byte k + 3 times; $FF: the next byte to the end
; of the page. A new bank when one is full (TaskCtl TC_TAKE, bank W);
; none left (or CHAIN_MAX): c set (the banks taken are in PK_LIST, PK_N).
; unpack.s's image: the same pages back from the chain. In order:
;   $0800-$87FF        the application's RAM (128 pages)
;   VRAM $00000-$1EFFF both screens, the save-under stack, the sprites'
;                      pictures, the colour map (496 pages)
;   bank 1             the application's own bank (32)
;   bank U             menus, icons, dialog boxes, GetString: each byte
;                      XOR its pristine copy's (V50), so its code packs
;                      to nothing (32)
; The application's own banks (overlays, a record file, what it asked
; for) are not copied: they stay its own while it is aside.

.include "kernel.inc"

.export PkImgA, PkLenA
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

PkImgA:
.org PK_RUN
.include "pkgo.inc"

PageOp:	jsr Fetch
	jmp Pack

; the page to PK_BUF (kind 0 RAM at r6, 1 VRAM, 2 bank r7L at r6, 3 the
; same XOR bank r7H)
Fetch:	ldy #0
	ldx pkKind
	bne @1
@r:	lda (r6),y
	sta PK_BUF,y
	iny
	bne @r
	rts
@1:	dex
	bne @2
@v:	lda VERA_DATA0
	sta PK_BUF,y
	iny
	bne @v
	rts
@2:	ldx ram_bank
	lda r7L
	sta ram_bank
@b:	lda (r6),y
	sta PK_BUF,y
	iny
	bne @b
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
@3:	stx ram_bank
	rts

; PK_BUF packed to the chain
Pack:	ldy #0
@next:	sty pkI
	lda PK_BUF,y
	sta pkV
@r:	iny
	beq @tail               ; the same to the page's end
	cmp PK_BUF,y
	beq @r
	tya                     ; a run of y - pkI
	sec
	sbc pkI
	cmp #3
	bcc @lit
	sty pkJ
	tax
@ch:	cpx #130                ; (at most 129 a run; 3 at least left)
	bcc @fin
	txa
	sbc #3
	cmp #130
	bcc @c1
	lda #129
@c1:	sta pkT
	jsr Run
	txa
	sec
	sbc pkT
	tax
	bra @ch
@fin:	txa
	jsr Run
	ldy pkJ
	bra @next
@tail:	lda #$FF
	jsr Put
	lda pkV
	jmp Put
@lit:	ldy pkI                 ; bytes as they are, up to a run of 3
	ldx #0
@l1:	cpx #128
	beq @emit
	cpy #254
	bcs @take
	lda PK_BUF,y
	cmp PK_BUF+1,y
	bne @take
	cmp PK_BUF+2,y
	beq @emit
@take:	inx
	iny
	bne @l1
@emit:	sty pkJ
	dex
	txa
	jsr Put
	ldy pkI
@e1:	lda PK_BUF,y
	jsr Put
	iny
	cpy pkJ
	bne @e1
	cpy #0
	beq @end
	jmp @next
@end:	rts

; a run of a (3-129) of pkV
Run:	clc
	adc #$80 - 3
	jsr Put
	lda pkV
; a byte to the chain (x, y kept)
Put:	sta (r4)
	inc r4L
	beq @p
	rts
@p:	inc r4H
	lda r4H
	cmp #$C0
	beq @nb
	rts
@nb:	phx
	phy
	ldx PK_N
	cpx #CHAIN_MAX
	bcs @full
	lda #TC_TAKE
	FARCALL k_TaskCtl       ; a = the bank (FarRet mapped the old one)
	cpx #0
	bne @full
	ldx PK_N
	sta PK_LIST,x
	inc PK_N
	sta ram_bank
	lda #$A0
	sta r4H
	ply
	plx
	rts
@full:	ldx pkSP                ; out of PkGo: c set
	txs
	lda pkHome
	sta ram_bank
	sec
	rts

PkEnd:
.reloc
PkLenA = PkEnd - PkGo
.assert PkLenA <= PK_N - PK_RUN, error, "the pack image does not fit $0600-PK_N"
