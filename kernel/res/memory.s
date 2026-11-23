; Veranda resident core: memory and string calls (they may work on memory
; in the caller's RAM bank, so they run with it mapped)

.include "kernel.inc"

.export k_ClearRam, k_FillRam, k_MoveData, k_InitRam
.export k_CopyString, k_CopyFString, k_CmpString, k_CmpFString

.segment "CODE"

; r0 count, r1 address
k_ClearRam:
	lda #0
	sta r2L
; r0 count, r1 address, r2L value
k_FillRam:
	MoveW r1, kPtr
	lda r2L
	ldx r0H
	beq @part
	ldy #0
@page:	sta (kPtr),y
	iny
	bne @page
	inc kPtr+1
	dex
	bne @page
@part:	ldy r0L
	beq @r
@b:	dey
	sta (kPtr),y
	cpy #0
	bne @b
@r:	rts

; r0 source, r1 destination, r2 count (overlapping areas are fine)
k_MoveData:
	lda r2L
	ora r2H
	beq @r
	CmpW r1, r0
	beq @r
	bcs @down               ; destination above the source: from the end
	MoveW r0, kPtr
	MoveW r1, kPtr2
	ldx r2H
	beq @fpart
	ldy #0
@fpage:	lda (kPtr),y
	sta (kPtr2),y
	iny
	bne @fpage
	inc kPtr+1
	inc kPtr2+1
	dex
	bne @fpage
@fpart:	ldx r2L
	beq @r
	ldy #0
@fb:	lda (kPtr),y
	sta (kPtr2),y
	iny
	dex
	bne @fb
@r:	rts
@down:	; from the last byte: kPtr = source + count - 256 * pages ...
	lda r0L
	sta kPtr
	lda r0H
	clc
	adc r2H
	sta kPtr+1
	lda r1L
	sta kPtr2
	lda r1H
	clc
	adc r2H
	sta kPtr2+1
	ldy r2L                 ; the partial page first, at the top
	beq @dpages
@db:	dey
	lda (kPtr),y
	sta (kPtr2),y
	cpy #0
	bne @db
@dpages:
	ldx r2H
	beq @r
@dp:	dec kPtr+1
	dec kPtr2+1
	ldy #$FF
@dq:	lda (kPtr),y
	sta (kPtr2),y
	dey
	bne @dq
	lda (kPtr),y
	sta (kPtr2),y
	dex
	bne @dp
	rts

; r0 table: .word address (0 ends), .byte count, count bytes; again
k_InitRam:
	MoveW r0, kPtr
@ent:	ldy #0
	lda (kPtr),y
	sta kPtr2
	iny
	lda (kPtr),y
	sta kPtr2+1
	ora kPtr2
	beq @r
	iny
	lda (kPtr),y
	tax
	AddVW 3, kPtr
	ldy #0
	txa
	beq @ent
@b:	lda (kPtr),y
	sta (kPtr2),y
	iny
	dex
	bne @b
	tya
	clc
	adc kPtr
	sta kPtr
	bcc @ent
	inc kPtr+1
	bra @ent
@r:	rts

; x, y = zero page addresses of pointers: copy a 0-terminated string
k_CopyString:
	lda #0
; a = count (0: up to the 0, which is copied)
k_CopyFString:
	sta kTmp
	lda 0,x
	sta kPtr
	lda 1,x
	sta kPtr+1
	lda 0,y
	sta kPtr2
	lda 1,y
	sta kPtr2+1
	ldy #0
@1:	lda (kPtr),y
	sta (kPtr2),y
	ldx kTmp
	bne @n
	cmp #0
	beq @r
	bra @nx
@n:	dec kTmp
	beq @r
@nx:	iny
	bne @1
@r:	rts

; x, y = zero page pointers: compare 0-terminated strings; z set if equal
k_CmpString:
	lda #0
k_CmpFString:
	sta kTmp
	lda 0,x
	sta kPtr
	lda 1,x
	sta kPtr+1
	lda 0,y
	sta kPtr2
	lda 1,y
	sta kPtr2+1
	ldy #0
@1:	lda (kPtr),y
	cmp (kPtr2),y
	bne @r
	ldx kTmp
	bne @n
	cmp #0
	beq @r                  ; both ended: equal (z set)
	bra @nx
@n:	dec kTmp
	beq @r
@nx:	iny
	bne @1
	lda #0                  ; 256 equal bytes
@r:	rts
