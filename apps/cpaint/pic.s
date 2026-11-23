; Colour Paint: the picture's bytes, fast (cpaint.h; DECISIONS V167)
;
; pic_out   row pa_y, bytes pa_x .. pa_x + pa_n - 1, to VRAM at pa_v
; pic_span  the same bytes = pa_c
; vzero     pa_n bytes of 0 to VRAM at pa_v; vfill: of pa_c
; pget(x, y), pset(x, y) (= pa_c)
;
; MIT licence (see LICENSE).

.importzp ptr1, ptr2, tmp1, tmp2
.import popa
.import _pbank, _ubank, _rowbank, _rowlo, _rowhi
.export _pa_y, _pa_c, _pa_x, _pa_n, _pa_v
.export _pic_out, _pic_span, _vzero, _vfill, _pget, _pset, _uget

VADDRL = $9F20
VADDRM = $9F21
VADDRH = $9F22
VDATA0 = $9F23
VCTRL  = $9F25

.segment "BSS"

_pa_y:	.res 1
_pa_c:	.res 1
_pa_x:	.res 2
_pa_n:	.res 2
_pa_v:	.res 4
keep:	.res 1
cnt:	.res 2

.segment "CODE"

; ptr1 = row pa_y's byte pa_x, its bank mapped (the old one in keep)
Row:	lda _pbank
RowB:	sta tmp1
	lda $00
	sta keep
	ldx _pa_y
	lda _rowbank,x
	clc
	adc tmp1
	sta $00
	lda _rowlo,x
	clc
	adc _pa_x
	sta ptr1
	lda _rowhi,x
	adc _pa_x+1
	sta ptr1+1
	rts

; VERA port 0 at pa_v, counting up by 1
VAt:	stz VCTRL
	lda _pa_v
	sta VADDRL
	lda _pa_v+1
	sta VADDRM
	lda _pa_v+2
	and #1
	ora #$10
	sta VADDRH
	rts

_pic_out:
	jsr Row
	jsr VAt
	lda _pa_n
	sta cnt
	ldx _pa_n+1
	ldy #0
	txa
	beq @rest
@page:	lda (ptr1),y            ; whole pages
	sta VDATA0
	iny
	bne @page
	inc ptr1+1
	dex
	bne @page
@rest:	ldx cnt
	beq @done
@b:	lda (ptr1),y
	sta VDATA0
	iny
	dex
	bne @b
@done:	lda keep
	sta $00
	rts

_pic_span:
	jsr Row
	lda _pa_n
	sta cnt
	ldx _pa_n+1
	ldy #0
	lda _pa_c
	cpx #0
	beq @rest
@page:	sta (ptr1),y
	iny
	bne @page
	inc ptr1+1
	dex
	bne @page
@rest:	ldx cnt
	beq @done
@b:	sta (ptr1),y
	iny
	dex
	bne @b
@done:	lda keep
	sta $00
	rts

_vzero:	lda #0
	bra Fill
_vfill:	lda _pa_c
Fill:	sta tmp1
	jsr VAt
	lda tmp1
	ldx _pa_n+1
	beq @rest
	ldy #0
@page:	sta VDATA0
	iny
	bne @page
	dex
	bne @page
@rest:	ldx _pa_n
	beq @done
@b:	sta VDATA0
	dex
	bne @b
@done:	rts

; vout(p): pa_n bytes (at most 255) from p to VRAM at pa_v
.export _vout
_vout:	sta ptr1
	stx ptr1+1
	jsr VAt
	ldx _pa_n
	beq @r
	ldy #0
@b:	lda (ptr1),y
	sta VDATA0
	iny
	dex
	bne @b
@r:	rts

; pget(x, y): a = the byte
_pget:	sta _pa_y
	jsr popax2
	jsr Row
	lda (ptr1)
	ldx keep
	stx $00
	ldx #0
	rts

; uget(x, y): undo's whole copy (the same layout, from ubank)
_uget:	sta _pa_y
	jsr popax2
	lda _ubank
	jsr RowB
	lda (ptr1)
	ldx keep
	stx $00
	ldx #0
	rts

; pset(x, y): = pa_c
_pset:	sta _pa_y
	jsr popax2
	jsr Row
	lda _pa_c
	sta (ptr1)
	lda keep
	sta $00
	rts

; pa_x from the C stack (the first argument, an unsigned int)
.import popax
popax2:	jsr popax
	sta _pa_x
	stx _pa_x+1
	rts

; undo keeps its copy in the picture's layout (from ubank): row pa_y's
; bytes pa_x .. + pa_n - 1 copied there (urow_save) or exchanged with it
; (urow_swap), through buf
.export _urow_save, _urow_swap
.segment "BSS"
buf:	.res 320
pk:	.res 1                  ; the picture's bank for the row
uk:	.res 1                  ; the copy's
.segment "CODE"

Banks:	jsr Row                 ; ptr1, the picture's bank mapped
	lda $00
	sta pk
	sec
	sbc _pbank
	clc
	adc _ubank
	sta uk
	rts

; (ptr1) to buf, pa_n bytes (a row: at most 320)
ToBuf:	ldy #0
	lda _pa_n+1
	beq @lo
@a:	lda (ptr1),y
	sta buf,y
	iny
	bne @a
	inc ptr1+1
	ldx _pa_n
	beq @r
@b:	lda (ptr1),y
	sta buf+256,y
	iny
	dex
	bne @b
@r:	dec ptr1+1
	rts
@lo:	ldx _pa_n
	beq @z
@c:	lda (ptr1),y
	sta buf,y
	iny
	dex
	bne @c
@z:	rts

; buf to (ptr1)
FromBuf: ldy #0
	lda _pa_n+1
	beq @lo
@a:	lda buf,y
	sta (ptr1),y
	iny
	bne @a
	inc ptr1+1
	ldx _pa_n
	beq @r
@b:	lda buf+256,y
	sta (ptr1),y
	iny
	dex
	bne @b
@r:	dec ptr1+1
	rts
@lo:	ldx _pa_n
	beq @z
@c:	lda buf,y
	sta (ptr1),y
	iny
	dex
	bne @c
@z:	rts

; buf and (ptr1) exchanged
Swap:	ldy #0
	lda _pa_n+1
	beq @lo
@a:	lda (ptr1),y
	tax
	lda buf,y
	sta (ptr1),y
	txa
	sta buf,y
	iny
	bne @a
	inc ptr1+1
	lda _pa_n
	beq @r
	sta tmp1
@b:	lda (ptr1),y
	tax
	lda buf+256,y
	sta (ptr1),y
	txa
	sta buf+256,y
	iny
	dec tmp1
	bne @b
@r:	dec ptr1+1
	rts
@lo:	lda _pa_n
	beq @z
	sta tmp1
@c:	lda (ptr1),y
	tax
	lda buf,y
	sta (ptr1),y
	txa
	sta buf,y
	iny
	dec tmp1
	bne @c
@z:	rts

_urow_save:
	jsr Banks
	jsr ToBuf
	lda uk
	sta $00
	jsr FromBuf
	lda keep
	sta $00
	rts

_urow_swap:
	jsr Banks
	jsr ToBuf
	lda uk
	sta $00
	jsr Swap
	lda pk
	sta $00
	jsr FromBuf
	lda keep
	sta $00
	rts

; the whole row pa_y to buf / from buf (pa_x, pa_n set by the caller)
.export _row_get, _row_put, _rowbuf
_rowbuf = buf
_row_get:
	jsr Row
	jsr ToBuf
	lda keep
	sta $00
	rts
_row_put:
	jsr Row
	jsr FromBuf
	lda keep
	sta $00
	rts

;---------------------------------------------------------------
; pack_row: rowbuf's 320 bytes, PackBits, to *pk (in the bank mapped);
; pk moves past them. A run of 3 or more the same: 257 - n, the byte;
; else literals up to the next such run (at most 128): n - 1, the bytes.
;---------------------------------------------------------------
.export _pack_row
.import _pk

.segment "BSS"
rem:	.res 2                  ; the bytes left
lim:	.res 1                  ; min(rem, 128)
rem8:	.res 1                  ; min(rem, 255)
.segment "CODE"

_pack_row:
	lda #<buf
	sta ptr1
	lda #>buf
	sta ptr1+1
	lda _pk
	sta ptr2
	lda _pk+1
	sta ptr2+1
@tok:	lda #<(buf + 320)       ; rem = the end - ptr1
	sec
	sbc ptr1
	sta rem
	lda #>(buf + 320)
	sbc ptr1+1
	sta rem+1
	bne @big
	lda rem
	bne @small
	jmp @done
@big:	lda #128
	sta lim
	lda #255
	sta rem8
	bra @run
@small:	sta rem8
	cmp #128
	bcc @s1
	lda #128
@s1:	sta lim
@run:	ldy #0                  ; the run's length
	lda (ptr1),y
	sta tmp1
@r:	iny
	cpy lim
	beq @rn
	lda (ptr1),y
	cmp tmp1
	beq @r
@rn:	cpy #3
	bcc @lit
	sty tmp2                ; a run: 257 - n, the byte
	lda #1
	sec
	sbc tmp2
	sta (ptr2)
	ldy #1
	lda tmp1
	sta (ptr2),y
	lda #2
	jsr Dst
	lda tmp2
	jsr Src
	bra @tok
@lit:	ldy #0                  ; literals up to the next run of 3
@l:	cpy lim
	beq @ln
	tya                     ; y + 2 < rem?
	clc
	adc #2
	bcs @l1
	cmp rem8
	bcs @l1
	sty tmp2
	lda (ptr1),y
	iny
	cmp (ptr1),y
	bne @l0
	iny
	cmp (ptr1),y
	beq @lb                 ; a run starts at tmp2
@l0:	ldy tmp2
@l1:	iny
	bra @l
@lb:	ldy tmp2
@ln:	sty tmp2                ; n = y
	tya
	dea
	sta (ptr2)
	lda #1
	jsr Dst
	ldy #0
@c:	lda (ptr1),y
	sta (ptr2),y
	iny
	cpy tmp2
	bne @c
	lda tmp2
	jsr Dst
	lda tmp2
	jsr Src
	jmp @tok
@done:	lda ptr2
	sta _pk
	lda ptr2+1
	sta _pk+1
	rts

; ptr2 += a; ptr1 += a
Dst:	clc
	adc ptr2
	sta ptr2
	bcc @r
	inc ptr2+1
@r:	rts
Src:	clc
	adc ptr1
	sta ptr1
	bcc @r
	inc ptr1+1
@r:	rts

;---------------------------------------------------------------
; (V172) old_row: two rows of Paint's picture (obuf: 74 bytes each) at
; half size into rowbuf: a pixel 1 (black) if any of its four dots is
; ink, 0 else; rowbuf 296-319 0
;---------------------------------------------------------------
.export _old_row
.import _obuf
_old_row:
	ldx #0                  ; the byte
	ldy #0                  ; the pixel (rowbuf, 0-295: 4 a byte)
@b:	lda _obuf,x
	ora _obuf+74,x
	sta tmp1
	lda #0
	bit tmp1                ; (bit 7, 6 of the pair: N, V)
	bmi @1
	bvc @1z
@1:	lda #1
@1z:	sta buf,y
	iny
	lda tmp1
	and #$30
	beq @2
	lda #1
@2:	sta buf,y
	iny
	lda tmp1
	and #$0C
	beq @3
	lda #1
@3:	sta buf,y
	iny
	lda tmp1
	and #$03
	beq @4
	lda #1
@4:
	sta buf,y
	iny
	bne @n
	jmp Hi                  ; the rest from pixel 256 in the page after
@n:	inx
	cpx #74
	bne @b
	rts
; pixels 256-295 (bytes 64-73), then 296-319 0
Hi:	inx
@b:	lda _obuf,x
	ora _obuf+74,x
	sta tmp1
	lda #0
	bit tmp1
	bmi @1
	bvc @1z
@1:	lda #1
@1z:	sta buf+256,y
	iny
	lda tmp1
	and #$30
	beq @2
	lda #1
@2:	sta buf+256,y
	iny
	lda tmp1
	and #$0C
	beq @3
	lda #1
@3:	sta buf+256,y
	iny
	lda tmp1
	and #$03
	beq @4
	lda #1
@4:	sta buf+256,y
	iny
	inx
	cpx #74
	bne @b
	lda #0                  ; 296-319
@z:	sta buf+256,y
	iny
	cpy #64
	bne @z
	rts
