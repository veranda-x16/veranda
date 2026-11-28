; textkit (Veranda Edit, VeraBASIC): a row of the window's text drawn
; (DECISIONS V215), as the kernel's PutCards draws it (8 x 8 cards from a
; 1 bpp font, each opaque: bit 7 the left pixel; reversed: inverted; bold:
; v OR v >> 1) but with each card's style its own and none of PutCards'
; clipping (the text's rows are on the screen): one call for a row whose
; styles change from card to card. On the foreground (VRAM 0, 80 bytes a
; pixel row); one seek a card, the address stepping by 80 down the card.
;
; Its variables in "BSS" (main RAM: a program's other banks may set
; them); its code in "CODE", or with TK_BANK (an assembler define) in
; segment "B<n>CODE" (the program's bank of view.c).
;
; MIT licence (see LICENSE).

	.setcpu "65C02"
	.include "x16hw.inc"
	.export _tk_putrow, _tk_pc, _tk_pf, _tk_px, _tk_pn, _tk_pa, _tk_pb, _tk_pfont
	.export _tk_jiffy, _tk_keys
	.importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3, tmp4

TY	= 32                    ; (textkit.h: TROW * 8)

.segment "BSS"

_tk_pc:	.res 2                  ; the characters
_tk_pf:	.res 2                  ; each card's style (0: all plain): 1 reversed, 2 bold
_tk_px:	.res 1                  ; the first card's column
_tk_pn:	.res 1                  ; the cards
_tk_pa:	.res 1                  ; the cards [pa, pb) reversed too (the selection)
_tk_pb:	.res 1
_tk_pfont: .res 2               ; the font (8 bytes a glyph)

.ifdef TK_BANK
.segment .sprintf("B%dCODE", TK_BANK)
.else
.segment "CODE"
.endif

; void __fastcall__ tk_putrow(unsigned char r): the cards on text row r
; (none if tk_pn is 0). A blank (a space) is 8 bytes of its paper, no
; glyph looked at
_tk_putrow:
	ldx _tk_pn
	bne @0
	rts
@0:	jsr RowAddr
	txa
	clc
	adc _tk_px
	sta tmp1
	tya
	adc #0
	sta tmp2
	lda _tk_pc
	sta ptr1
	lda _tk_pc+1
	sta ptr1+1
	lda _tk_pf
	sta ptr3
	lda _tk_pf+1
	sta ptr3+1
	lda _tk_pfont           ; (a glyph: ptr2 = the font + 256 * (c >> 5),
	sta ptr2                ; y = 8 * (c AND 31))
	stz VERA_CTRL
	lda #$C0                ; by 80: down the card
	sta VERA_ADDR_H
	ldy #0
@c:	lda tmp1
	sta VERA_ADDR_L
	lda tmp2
	sta VERA_ADDR_M
	inc tmp1
	bne @1
	inc tmp2
@1:	lda ptr3+1              ; the style
	beq @3
	lda (ptr3),y
@3:	cpy _tk_pa              ; the range: reversed
	bcc @4
	cpy _tk_pb
	bcs @4
	eor #1
@4:	and #3
	tax
	lda (ptr1),y
	cmp #' '
	bne @g
	txa                     ; a blank: its paper
	lsr
	lda #0
	bcc @5
	lda #$FF
@5:
.repeat 8
	sta VERA_DATA0
.endrepeat
	jmp @m
@g:	phy
	pha
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc _tk_pfont+1
	sta ptr2+1
	pla
	and #$1F
	asl
	asl
	asl
	tay
	txa
	bne @st
.repeat 8                       ; plain
	lda (ptr2),y
	sta VERA_DATA0
	iny
.endrepeat
	bra @n
@st:	lsr                     ; reversed (bit 0), bold (bit 1: v OR v >> 1)
	tax
	lda #0
	bcc @6
	lda #$FF
@6:	sta tmp3
@b:	lda (ptr2),y
	cpx #0
	beq @7
	sta tmp4
	lsr
	ora tmp4
@7:	eor tmp3
	sta VERA_DATA0
	iny
	tya
	and #7
	bne @b
@n:	ply
@m:	iny
	cpy _tk_pn
	beq @r
	jmp @c
@r:	rts

; unsigned char tk_jiffy(void): the jiffies' low byte (the ROM's RDTIM)
_tk_jiffy:
	jsr $FFDE
	ldx #0
	rts

; unsigned char tk_keys(void): the keys in the ROM's queue, not yet taken
; by the main loop (KBDBUF_PEEK)
_tk_keys:
	jsr $FEBD
	txa
	ldx #0
	rts

; a = a text row: y.x = its first pixel row's address on the foreground
; ((TY + 8a) * 80 = TY * 80 + a * 5 * 128)
RowAddr:
	sta tmp1
	stz tmp2
	asl
	rol tmp2
	asl
	rol tmp2                ; a * 4
	clc
	adc tmp1
	bcc @1
	inc tmp2                ; tmp2.a = a * 5
@1:	lsr tmp2                ; * 128: (a * 5) << 8 >> 1
	ror
	tay
	lda #0
	ror
	tax
	tya
	clc
	adc #>(TY * 80)
	tay
	rts
