; Veranda shell: the clip's helpers (DECISIONS V81), in the resident part
; (every overlay calls them).
;
; The scene (win.c) is drawn with the kernel's clip rectangle on
; (clipOn: leftMargin .. rightMargin by windowTopW .. windowBottomW), a
; dirty rectangle at a time; what does not meet it is not drawn at all.
;
; shell_seen(l, t, r, b): 1 if l .. r by t .. b meets the clip, or the
;                         clip is off
; num(n, out):            n in decimal (below)
.include "veranda.inc"

.importzp c_sp, ptr1, ptr2, sreg, tmp1, tmp2, tmp3, tmp4
.import incsp4, incsp6
.export _shell_seen, _num, _look_rect, _colClip, _colX0, _colX1, _colY0, _colY1
.import _theme_rect, _lookNone
.import _ovl_go, _ovl_bk, _ovl_fn, _bWall, _gui_box, _gui_unbox, _DoDlgBox
.export _boxBand, _boxPlain, _dlg

.segment "BSS"
_colClip: .res 1                ; the colour clip: look_rect writes only cards
_colX0:	.res 1                  ; colX0 .. colX1 by colY0 .. colY1
_colX1:	.res 1
_colY0:	.res 1
_colY1:	.res 1
lrC:	.res 1

.segment "CODE"

; void look_rect(x, w, y, h, c): cards x, y (w by h) in colour c
; (theme_rect), none with the Classic theme (lookNone); with the colour
; clip on only its cards (the scene's, V81)
_look_rect:
	ldx _lookNone
	beq @1
	jmp incsp4
@1:	ldx _colClip
	beq @go
	sta lrC
	ldy #3                  ; the stack: h 0, y 1, w 2, x 3
	ldx #0                  ; x, w against colX0 .. colX1; then y, h
@ax:	dey                     ; the size (0: none)
	lda (c_sp),y
	beq @no
	iny
	clc
	adc (c_sp),y            ; + the start
	dea                     ; the end
	cmp _colX0,x
	bcc @no
	sta tmp2
	lda (c_sp),y            ; the start
	cmp _colX1,x
	beq @s1
	bcs @no
@s1:	cmp _colX0,x            ; start = max(start, lo)
	bcs @s2
	lda _colX0,x
	sta (c_sp),y
@s2:	lda tmp2                ; end = min(end, hi)
	cmp _colX1,x
	bcc @s3
	lda _colX1,x
@s3:	sec                     ; size = end - start + 1
	sbc (c_sp),y
	ina
	dey
	sta (c_sp),y
	dey                     ; (the next one's start)
	inx
	inx
	cpx #4
	bne @ax
	lda lrC
@go:	jmp _theme_rect
@no:	jmp incsp4

; void num(unsigned long n, char *out): n in decimal, no leading zeros
; (main.c's division by ten in C took some 2,000 cycles a digit, the
; list's sizes and dates 7 ms a row: V81); each power of ten subtracted
; while it fits
_num:	sta ptr1
	stx ptr1+1
	ldy #3
@a:	lda (c_sp),y
	sta tmp1,y              ; (tmp1-tmp4: n, low byte first)
	dey
	bpl @a
	jsr incsp4
	ldx #36                 ; 10^9 first: its bytes at Pow + x
	ldy #0                  ; the characters written
@p:	stz sreg+1              ; the digit
@s:	sec                     ; n - 10^k (ptr2, sreg): kept if it fits
	lda tmp1
	sbc Pow,x
	sta ptr2
	lda tmp2
	sbc Pow+1,x
	sta ptr2+1
	lda tmp3
	sbc Pow+2,x
	sta sreg
	lda tmp4
	sbc Pow+3,x
	bcc @n
	sta tmp4
	lda sreg
	sta tmp3
	lda ptr2+1
	sta tmp2
	lda ptr2
	sta tmp1
	inc sreg+1
	bra @s
@n:	lda sreg+1
	bne @d
	cpy #0                  ; a leading 0 is not written (the units are)
	bne @d
	cpx #0
	bne @x
@d:	ora #'0'
	sta (ptr1),y
	iny
@x:	dex
	dex
	dex
	dex
	bpl @p
	lda #0
	sta (ptr1),y
	rts

_shell_seen:
	sta ptr1                ; b
	stx ptr1+1
	lda clipOn
	beq @yes
	lda ptr1                ; b >= windowTopW
	cmp windowTopW
	lda ptr1+1
	sbc windowTopW+1
	bcc @no
	ldy #2                  ; t <= windowBottomW
	lda windowBottomW
	cmp (c_sp),y
	iny
	lda windowBottomW+1
	sbc (c_sp),y
	bcc @no
	ldy #0                  ; r >= leftMargin
	lda (c_sp),y
	cmp leftMargin
	iny
	lda (c_sp),y
	sbc leftMargin+1
	bcc @no
	ldy #4                  ; l <= rightMargin
	lda rightMargin
	cmp (c_sp),y
	iny
	lda rightMargin+1
	sbc (c_sp),y
	bcc @no
@yes:	lda #1
	.byte $2C               ; (bit: over the next 2 bytes)
@no:	lda #0
	ldx #0
	jmp incsp6

; the shell's message boxes' colour chrome (gui.s, overlay 11; V102):
; boxBand, boxPlain: their user routine (DB_USR_ROUT: gui_box(1), its first
; line a title band; gui_box(0)); dlg(box): DoDlgBox, then gui_unbox
_boxBand:
	lda #1
	.byte $2C
_boxPlain:
	lda #0
	ldx #<_gui_box
	ldy #>_gui_box
Ovl:	stx _ovl_fn
	sty _ovl_fn+1
	ldx _bWall
	stx _ovl_bk
	jmp _ovl_go
_dlg:	jsr _DoDlgBox
	pha
	ldx #<_gui_unbox
	ldy #>_gui_unbox
	jsr Ovl
	pla
	ldx #0
	rts

.segment "RODATA"
Pow:	.dword 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000, 1000000000
