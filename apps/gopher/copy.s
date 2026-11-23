; Veranda Gopher: a line's bytes out of the document's RAM banks (main
; RAM; DECISIONS V109). doc.c's doc_line in C took a quarter of a page's
; drawing; this is the same loop in assembly.
;
; unsigned char __fastcall__ doc_copy(unsigned char count): count bytes
; from doc_src (RAMBANK mapped: its bank; past $BFFF the next bank, $A000)
; into ln, CR dropped, up to an LF; ln 0-terminated; the length.
; MIT licence (see LICENSE).

.importzp ptr1
.import _ln
.export _doc_copy, _doc_src

.segment "BSS"
_doc_src: .res 2
cnt:	.res 1

.segment "CODE"
_doc_copy:
	sta cnt
	lda _doc_src
	sta ptr1
	lda _doc_src+1
	sta ptr1+1
	ldx #0
@loop:	lda cnt
	beq @done
	dec cnt
	lda (ptr1)
	inc ptr1
	bne @got
	inc ptr1+1
	ldy ptr1+1
	cpy #$C0
	bne @got
	ldy #$A0
	sty ptr1+1
	inc $00                 ; (the next bank)
@got:	cmp #10
	beq @done
	cmp #13
	beq @loop
	sta _ln,x
	inx
	bra @loop
@done:	stz _ln,x
	txa
	ldx #0
	rts

; (V110) text in cells of 8 x h pixels, straight into VERA: cs_n
; characters at cs_txt (main RAM; 1-255) at card cs_x, pixel row cs_y of
; the foreground screen (VRAM_FG, 80 bytes a row: the kernel's PutCards
; and WBitmapUp write it so too; its interrupt keeps VERA's addresses).
; WBitmapUp from a composed buffer took 9 frames a page, this 5. The font
; is 10 tables of 256 bytes in RAM bank cs_fbank at $B000 (main.c's
; load_font): rows 0-7 of every character, then a box character's
; ($B0-$DF) top row and bottom row (0 for the others), which fill the
; rows above and below the glyph, so that CP437's lines and blocks meet
; from one text line to the next. The glyph's 8 rows start at row
; (h - 8) / 2. cs_fl bit 0 reverses. RAMBANK is kept.
;
; void cs_draw(void)
.export _cs_draw, _cs_txt, _cs_x, _cs_y, _cs_n, _cs_h, _cs_fl, _cs_fbank

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
VERA_CTRL   = $9F25

.segment "BSS"
_cs_txt: .res 80
_cs_x:	.res 1
_cs_y:	.res 2
_cs_n:	.res 1
_cs_h:	.res 1
_cs_fl:	.res 1
_cs_fbank: .res 1
keep:	.res 1
k:	.res 1
top:	.res 1
adr:	.res 2
t16:	.res 2

.segment "CODE"
_cs_draw:
	lda $00
	sta keep
	lda _cs_fbank
	sta $00
	lda _cs_y               ; adr = y * 80 + x
	sta adr
	lda _cs_y+1
	asl adr
	rol a
	asl adr
	rol a
	asl adr
	rol a
	asl adr
	rol a
	sta adr+1               ; (y * 16)
	sta t16+1
	lda adr
	sta t16
	asl adr
	rol adr+1
	asl adr
	rol adr+1               ; (y * 64)
	lda adr
	clc
	adc t16
	sta adr
	lda adr+1
	adc t16+1
	sta adr+1
	lda adr
	clc
	adc _cs_x
	sta adr
	bcc :+
	inc adr+1
:	lda _cs_n
	sta cpn+1
	lda _cs_h
	sec
	sbc #8
	lsr
	sta top
	lda _cs_fl
	and #1
	beq :+
	lda #$FF
:	sta rev+1
	stz k
cs_row:	stz VERA_CTRL
	lda adr
	sta VERA_ADDR_L
	lda adr+1
	sta VERA_ADDR_M
	lda #$10                ; (step 1)
	sta VERA_ADDR_H
	lda k                   ; the table: above the glyph, its rows, below
	sec
	sbc top
	bcc cs_above
	cmp #8
	bcs cs_below
	ora #$B0
	bra cs_set
cs_above: lda #$B8
	bra cs_set
cs_below: lda #$B9
cs_set:	sta src+2
	ldx #0
cs_loop: ldy _cs_txt,x
src:	lda $B000,y
rev:	eor #0
	sta VERA_DATA0
	inx
cpn:	cpx #0
	bne cs_loop
	lda adr
	clc
	adc #80
	sta adr
	bcc :+
	inc adr+1
:	inc k
	lda k
	cmp _cs_h
	bne cs_row
	lda keep
	sta $00
	rts

; (V143) void __fastcall__ cs_font(unsigned char ctl): the font for
; cs_draw into RAM bank cs_fbank at $B000 (10 tables of 256 bytes: rows
; 0-7 of every character, then a box character's top and bottom row, 0
; for the others). From ROM bank 6: $00-$7F CP437's (ctl bit 7: control
; characters as '?'); $80-$9F private glyphs, CP437's pi, square and
; root, then its shades, blocks and box lines (Priv: the box ones, $83-$9F,
; fill the taller cells' rows above and below); $A0-$FF Veranda's set,
; ISO-8859-16: the ROM's own glyphs of it (its CHARLAE set, found by its
; A ogonek; a ROM without it: CP437's). RAMBANK and ROM bank kept.
.export _cs_font
.importzp ptr1, ptr2, tmp1, tmp2, tmp3

.segment "BSS"
csA:	.res 2                  ; CP437's set
csL:	.res 2                  ; ISO-8859-16's upper half (high byte 0: none)
csCtl:	.res 1

.segment "RODATA"
Sigs:	.byte $7E, $81, $A5, $81, $BD, $99, $81, $7E   ; CP437's 1 (a smiley)
	.byte $18, $3C, $24, $66, $7E, $66, $0C, $06   ; ISO-8859-16's $A1 (A ogonek)
Priv:	.byte $E3, $FE, $FB, $B0, $B1, $B2, $B3, $B4, $BF, $C0, $C1, $C2, $C3, $C4, $C5, $D9
	.byte $DA, $DB, $DC, $DD, $DE, $DF, $BA, $CD, $C9, $BB, $C8, $BC, $CC, $B9, $CB, $CA

.segment "CODE"
; x = the signature's last byte in Sigs, a = the step in pages -> ptr1 =
; the set (its glyph 1 is the signature), c clear; c set: none
Find:	sta tmp1
	stx tmp2
	lda #$C0
	sta ptr1+1
	stz ptr1
@n:	ldx tmp2
	ldy #15
@c:	lda (ptr1),y
	cmp Sigs,x
	bne @nx
	dex
	dey
	cpy #8
	bcs @c
	clc
	rts
@nx:	lda ptr1+1
	clc
	adc tmp1
	sta ptr1+1
	bcc @n
	rts                     ; (c set)

_cs_font:
	sta csCtl
	lda $00
	pha
	lda _cs_fbank
	sta $00
	php
	sei                     ; (ROM bank 6 has no vectors)
	lda $01
	pha
	lda #6
	sta $01
	lda #8
	ldx #7
	jsr Find
	ldx #$C8
	bcs @a0
	ldx ptr1+1
@a0:	stx csA+1
	stz csA
	lda #1
	ldx #15
	jsr Find
	lda ptr1+1
	bcc @l0
	lda #0
@l0:	sta csL+1
	ldx #0                  ; x = the character
@g:	txa
	ldy #0                  ; (tmp3 = the set: 0 CP437, $80 ISO-8859-16)
	cmp #32
	bcs @c1
	bit csCtl
	bpl @asc
	lda #'?'
	bra @asc
@c1:	cmp #$80
	bcc @asc
	cmp #$A0
	bcs @hi
	lda Priv-$80,x
	bra @asc
@hi:	ldy csL+1
	beq @asc0
	sbc #$A0                ; (c set)
	ldy #$80
	bra @asc
@asc0:	txa
	ldy #0
@asc:	sty tmp3
	sta ptr1                ; ptr1 = the set + a * 8
	stz ptr1+1
	asl ptr1
	rol ptr1+1
	asl ptr1
	rol ptr1+1
	asl ptr1
	rol ptr1+1
	lda tmp3
	bne @lh
	lda ptr1+1
	clc
	adc csA+1
	sta ptr1+1
	bra @cp
@lh:	lda ptr1+1
	clc
	adc csL+1
	sta ptr1+1              ; (both sets begin on a page)
@cp:	ldy #0
	lda (ptr1),y
	sta $B000,x
	iny
	lda (ptr1),y
	sta $B100,x
	iny
	lda (ptr1),y
	sta $B200,x
	iny
	lda (ptr1),y
	sta $B300,x
	iny
	lda (ptr1),y
	sta $B400,x
	iny
	lda (ptr1),y
	sta $B500,x
	iny
	lda (ptr1),y
	sta $B600,x
	iny
	lda (ptr1),y
	sta $B700,x
	cpx #$83                ; the box lines: top and bottom rows
	bcc @nb
	cpx #$A0
	bcs @nb
	sta $B900,x             ; (row 7, in a)
	lda (ptr1)
	sta $B800,x
	bra @nx
@nb:	stz $B800,x
	stz $B900,x
@nx:	inx
	beq @e
	jmp @g
@e:	pla
	sta $01
	plp
	pla
	sta $00
	rts
