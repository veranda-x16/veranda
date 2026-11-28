; gates edit and vb_ide (V215): the timed record's end (test_idle) and
; the redraw check's hashes.
;
; test_idle, from the program's idle pass (and the pass where only its
; status bar waits): a record timed by tests/edit_play.s's 'Z' is drawn
; when nothing waits (no key in the ROM's queue or Veranda's, no press, no
; wheel, no repeat to come): the clock then (play_mark).
;
; The hashes: each of
; textkit's text rows (54 card rows from pixel row 32) on the foreground:
; its 8 pixel rows (80 bytes each: the whole width, the scroll bar too)
; and its colour map row (80 cards, 2 bytes each), a Fletcher sum of 16
; bits. test_hash(0) keeps them; test_hash(1) hashes again and compares:
; test_hbad the rows unlike, test_hfirst the first of them (255: none).
; In the test build alone: Veranda Edit's overlay 4 (OVERLAY4),
; VeraBASIC's B_FILE (IDE: B2CODE); its tables in its own segment (RAM).
;
; MIT licence (see LICENSE).

	.setcpu "65C02"
	.include "x16hw.inc"
	.include "veranda.inc"
	.export _test_hash, _test_hbad, _test_hfirst, _test_idle
	.import _play_mark, _play_armed, _play_repn
	.importzp ptr1, tmp1, tmp2, tmp3

ROWS	= 54
TROW	= 4
CMAP	= VRAM_FREE + TROW * 256

.ifdef IDE
.segment "B2CODE"
.else
.segment "OVERLAY4"
.endif

ha:	.res ROWS * 2           ; as the steps drew them
hb:	.res ROWS * 2           ; as a full drawing does
_test_hbad: .res 1
_test_hfirst: .res 1

KBDBUF_PEEK = $FEBD

; void test_idle(void)
_test_idle:
	lda _play_armed
	beq @r
	lda _play_repn
	ora mouseWheel
	bne @r
	lda pressFlag
	and #SET_KEYPRESS | SET_MOUSE
	bne @r
	jsr KBDBUF_PEEK
	cpx #0
	bne @r
	jsr _play_mark
	stz _play_armed
@r:	rts

; void __fastcall__ test_hash(unsigned char which)
_test_hash:
	sta tmp3
	lda #<(TROW * 8 * 80)   ; the bitmap: the rows one after the other
	sta ptr1
	lda #>(TROW * 8 * 80)
	sta ptr1+1
	ldx #0                  ; the row
@r:	stz tmp1                ; the sums
	stz tmp2
	stz VERA_CTRL
	lda ptr1
	sta VERA_ADDR_L
	lda ptr1+1
	sta VERA_ADDR_M
	lda #VERA_INC1
	sta VERA_ADDR_H
	ldy #0                  ; 640 bytes: 256 + 256 + 128
	jsr Sum
	jsr Sum
	ldy #128
	jsr Sum
	lda #<CMAP              ; the colour map's row: 160 bytes
	sta VERA_ADDR_L
	txa
	clc
	adc #>CMAP
	sta VERA_ADDR_M
	lda #^CMAP | VERA_INC1
	sta VERA_ADDR_H
	ldy #160
	jsr Sum
	txa
	asl
	tay
	lda tmp3
	bne @b
	lda tmp1
	sta ha,y
	lda tmp2
	sta ha+1,y
	bra @n
@b:	lda tmp1
	sta hb,y
	lda tmp2
	sta hb+1,y
@n:	lda ptr1                ; the next row: 640 bytes on
	clc
	adc #<640
	sta ptr1
	lda ptr1+1
	adc #>640
	sta ptr1+1
	inx
	cpx #ROWS
	bne @r
	lda tmp3
	beq @x
	stz _test_hbad          ; the rows compared
	lda #$FF
	sta _test_hfirst
	ldx #0
@c:	txa
	asl
	tay
	lda ha,y
	cmp hb,y
	bne @d
	lda ha+1,y
	cmp hb+1,y
	beq @e
@d:	inc _test_hbad
	lda _test_hfirst
	cmp #$FF
	bne @e
	stx _test_hfirst
@e:	inx
	cpx #ROWS
	bne @c
@x:	rts

; y bytes from DATA0 (0: 256) into the sums
Sum:	lda VERA_DATA0
	clc
	adc tmp1
	sta tmp1
	clc
	adc tmp2
	sta tmp2
	dey
	bne Sum
	rts
