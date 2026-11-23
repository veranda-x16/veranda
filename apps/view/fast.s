; View's inner loops (apps/view/view.c): a 4 bpp row's pixels and the
; fitted row's pixels, a pixel at a time, in assembly (in C, cc65 spends
; about 300 cycles a pixel). MIT licence (see LICENSE).

	.export _cv4, _cv_src, _cv_n, _cv_out, _cv_om, _cv_hist, _cv_cmap
	.export _sc_row, _sc_src, _sc_dst, _sc_dw, _sc_bank
	.importzp ptr1, ptr2, ptr3, ptr4, tmp1, tmp2

	.bss
_cv_src:  .res 2                ; the source bytes
_cv_n:    .res 1                ; how many (1-255), two pixels each
_cv_out:  .res 2                ; the row's byte being made
_cv_om:   .res 1                ; its bit
_cv_hist: .res 2                ; the card's 16 counts
_cv_cmap: .res 16               ; a pixel's entry -> a card colour
_sc_src:  .res 2                ; the source row's bits
_sc_dst:  .res 2                ; the row made (cleared by the caller)
_sc_dw:   .res 2                ; its pixels
_sc_bank: .res 1                ; the tables' bank

	.code

; cv4: cv_n bytes of a 4 bpp row: a pixel 1 is ink (cv_om's bit set at
; cv_out), any other counts once in the card's counts at cv_hist (16 a
; card, by cv_cmap's colour); the state is left for the next call
_cv4:	lda _cv_src
	sta ptr1
	lda _cv_src+1
	sta ptr1+1
	lda _cv_out
	sta ptr2
	lda _cv_out+1
	sta ptr2+1
	lda _cv_hist
	sta ptr3
	lda _cv_hist+1
	sta ptr3+1
@byte:	lda (ptr1)
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr pix
	pla
	and #15
	jsr pix
	inc ptr1
	bne :+
	inc ptr1+1
:	dec _cv_n
	bne @byte
	lda ptr2
	sta _cv_out
	lda ptr2+1
	sta _cv_out+1
	lda ptr3
	sta _cv_hist
	lda ptr3+1
	sta _cv_hist+1
	rts

pix:	cmp #1
	bne @paper
	lda (ptr2)
	ora _cv_om
	sta (ptr2)
	bra @next
@paper:	tax
	ldy _cv_cmap,x
	lda (ptr3),y
	inc a
	sta (ptr3),y
@next:	lsr _cv_om
	bne @r
	lda #$80
	sta _cv_om
	inc ptr2
	bne :+
	inc ptr2+1
:	clc
	lda ptr3
	adc #16
	sta ptr3
	bcc @r
	inc ptr3+1
@r:	rts

; sc_row: sc_dw pixels into sc_dst, pixel x the source's (sc_src) bit
; that the tables in RAM bank sc_bank give: at $A000 + x its byte, at
; $A280 + x its mask (view.c makes them for the picture's size)
_sc_row:
	lda 0
	pha
	lda _sc_bank
	sta 0
	lda _sc_src
	sta @ld+1
	lda _sc_src+1
	sta @ld+2
	lda #<$A000
	sta ptr1
	lda #>$A000
	sta ptr1+1
	lda #<$A280
	sta ptr3
	lda #>$A280
	sta ptr3+1
	lda _sc_dst
	sta ptr2
	lda _sc_dst+1
	sta ptr2+1
	lda _sc_dw
	sta ptr4
	lda _sc_dw+1
	sta ptr4+1
	lda #$80
	sta tmp2
@pix:	lda (ptr1)
	tay
@ld:	lda $FFFF,y
	and (ptr3)
	beq @skip
	lda (ptr2)
	ora tmp2
	sta (ptr2)
@skip:	lsr tmp2
	bne @next
	lda #$80
	sta tmp2
	inc ptr2
	bne @next
	inc ptr2+1
@next:	inc ptr1
	bne :+
	inc ptr1+1
:	inc ptr3
	bne :+
	inc ptr3+1
:	lda ptr4
	bne :+
	dec ptr4+1
:	dec ptr4
	lda ptr4
	ora ptr4+1
	bne @pix
	pla
	sta 0
	rts
