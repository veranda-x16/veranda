; VeraBASIC Run: the C overlays' bank B (record 11; vbc.cfg, DECISIONS
; V90): the entries overlay 8 (vbdlg.s) calls through bcall; each returns
; its result in x (bcall gives a back as the caller's bank).
;
;   $A000  LOW in: the libraries' part copied into main RAM (the console's
;          font; overlay 8 reads the font again after the call)
;   $A003  CLIPBOARD$: the Text Scrap's text into inbuf, x its length
;   $A006  CLIPBOARD: inbuf's text (+0 its length) to the Text Scrap
;   $A009  TILE: inbuf +0 card, +1 row, +2 colour ($FF its own), +3 the
;          program's name; x 0 or the kernel's error
;   $A00C  CLIPBOARD PICTURE: inbuf +0 card, +1 width, +2/+3 the top line,
;          +4/+5 the height; x 0 or the kernel's error
;
; MIT licence (LICENSE).

.setcpu "65C02"
.import __CODE_LOAD__, __CODE_RUN__, __LOW_START__, __LOW_LAST__
.import _vbc_clipget, _vbc_clipput, _vbc_tile, _vbc_photo
.importzp ptr1, ptr2

.segment "BCODE"

	jmp lowin               ; $A000
	jmp clipget             ; $A003
	jmp clipput             ; $A006
	jmp tile                ; $A009
	jmp photo               ; $A00C

LOWN = __LOW_LAST__ - __LOW_START__

lowin:	lda #<__CODE_LOAD__
	sta ptr1
	lda #>__CODE_LOAD__
	sta ptr1+1
	lda #<__CODE_RUN__
	sta ptr2
	lda #>__CODE_RUN__
	sta ptr2+1
	ldx #>LOWN
	ldy #0
@p:	cpx #0
	beq @t
@pg:	lda (ptr1),y
	sta (ptr2),y
	iny
	bne @pg
	inc ptr1+1
	inc ptr2+1
	dex
	bra @p
@t:	cpy #<LOWN
	beq @r
	lda (ptr1),y
	sta (ptr2),y
	iny
	bra @t
@r:	rts

clipget:
	jsr _vbc_clipget
	tax
	rts
clipput:
	jsr _vbc_clipput
	tax
	rts
tile:	jsr _vbc_tile
	tax
	rts
photo:	jsr _vbc_photo
	tax
	rts
