; Veranda bank G: screen rows to and from memory (WriteRow, ReadRow)

.include "kernel.inc"

.import fb_span, fb_calc_off, fb_seek, fbRow, fbCol, fbCnt, fbKeepL, fbKeepR, fbOp, fbSel, fbXor, kStride
.importzp FBOP_BUF

.export k_WriteRow, k_ReadRow

.segment "CODE"

; clip r3L (x card), r3H (count) to the row; fbCol, fbCnt; c set if nothing
Clip:	MoveW r11, fbRow
	CmpW r11, screenHeight
	bcs @no
	MoveB r3L, fbCol
	lda kStride
	sec
	sbc r3L
	bcc @no
	beq @no
	cmp r3H
	bcc @1
	lda r3H
@1:	sta fbCnt
	beq @no
	clc
	rts
@no:	sec
	rts

; r0 buffer, r3L x (cards), r3H count, r11 y: to the screens dispBufferOn selects
k_WriteRow:
	jsr Clip
	bcs @r
	stz fbKeepL
	stz fbKeepR
	stz fbXor
	LoadB fbOp, FBOP_BUF
	MoveB dispBufferOn, fbSel
	MoveW r0, fbBufPtr
	jmp fb_span
@r:	rts

; r0 buffer, r3L, r3H, r11: from the foreground (the back screen if
; dispBufferOn bit 6 alone)
k_ReadRow:
	jsr Clip
	bcs @r
	jsr fb_calc_off
	lda #0
	bit dispBufferOn
	bmi @1
	bvc @1
	lda #1
@1:	ldx #0
	ldy #0
	jsr fb_seek
	ldx fbCnt
@2:	lda VERA_DATA0
	sta (r0),y
	iny
	dex
	bne @2
@r:	rts
