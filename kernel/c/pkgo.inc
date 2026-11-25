; the pack images' common part (kernel/w/pack.s, unpack.s): the regions in
; order, each page through PageOp; c set from Put when the banks ran out
PkGo:	tsx
	stx pkSP
	lda ram_bank
	sta pkHome
	stz VERA_CTRL
	stz pkCur
	lda PK_LIST
	sta ram_bank
	sta r7L                 ; (V189: pages below $A000 read with it mapped)
	; the application's RAM
	stz pkKind
	lda #$08
	ldx #128
	jsr Pages
	; VRAM: up to the colour map
	inc pkKind              ; 1
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	lda #VERA_INC1
	sta VERA_ADDR_H
	ldx #214
	jsr Pages
	ldx #214
	jsr Pages
	; the colour map ($1AC00-$1EFFF): its tile bytes, then its colours
	; (every other byte: each half packs into runs)
	ldx #0
@m:	stx kTmp
	lda #<VRAM_FREE
	ora kTmp
	sta VERA_ADDR_L
	lda #>VRAM_FREE
	sta VERA_ADDR_M
	lda #^VRAM_FREE | VERA_INC2
	sta VERA_ADDR_H
	ldx #34
	jsr Pages
	ldx kTmp
	inx
	cpx #2
	bne @m
	; bank 1
	inc pkKind              ; 2
	lda #1
	sta r7L
	lda #$A0
	ldx #32
	jsr Pages
	; bank U, XOR its copy
	inc pkKind              ; 3
	lda kBankBase
	clc
	adc #BANK_U
	sta r7L
	sec
	sbc #KCOPY_BANKS
	sta r7H
	lda #$A0
	ldx #32
	jsr Pages
	lda pkHome
	sta ram_bank
	clc
	rts

; x pages from page a (r6)
Pages:	sta r6H
	stz r6L
	stx pkCnt
@p:	jsr PageOp
	inc r6H
	dec pkCnt
	bne @p
	rts
