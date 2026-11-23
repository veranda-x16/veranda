; Veranda bank G: the span engine
;
; One span: bytes fbCol .. fbCol + fbCnt - 1 of screen row fbRow (16 bits),
; on the screens dispBufferOn selects (bit 7 foreground, bit 6 back
; screen), bit 7 = leftmost pixel. Per byte i:
;     keep = (i == 0 ? fbKeepL : 0) | (i == cnt-1 ? fbKeepR : 0)
;     new  = (A AND keep) OR (data AND NOT keep)
; where A is the source byte (fill, invert, buf) or the old destination
; byte (recover, imprint), and data depends on fbOp:
;     FBOP_FILL     fbPat
;     FBOP_INV      NOT source
;     FBOP_BUF      (fbBufPtr),i XOR fbXor
;     FBOP_RECOVER  back screen   -> foreground only
;     FBOP_IMPRINT  foreground    -> back screen only
; The source is the back screen if it is being written, else the
; foreground (GEOS's rule); InvertLine reads the foreground first.
; Port 1 reads the source, port 0 writes the destination.

.include "kernel.inc"

.import kStride, kFx

.export fb_span, fb_span_off, fb_calc_off, fb_seek, fbBlkN, fbB, fbTmp, fbE0, fbE1
.import fb_fxfill, fb_clip
.exportzp FBOP_FILL, FBOP_INV, FBOP_BUF, FBOP_RECOVER, FBOP_IMPRINT
.export fbRow, fbCol, fbCnt, fbKeepL, fbKeepR, fbOp, fbPat, fbSel, fbXor, fbOff

FBOP_FILL       = 0
FBOP_INV        = 1
FBOP_BUF        = 2
FBOP_RECOVER    = 3
FBOP_IMPRINT    = 4

BUF_FG          = 0             ; fb_seek's buffer numbers
BUF_BG          = 1
MAX_BYTES       = 80
FX_MIN          = 32            ; shorter fills: the plain loop (kernel/g/xfx.s)

.segment "BSS"

fbRow:	.res 2
fbCol:	.res 1
fbCnt:	.res 1
fbKeepL: .res 1
fbKeepR: .res 1
fbOp:	.res 1
fbPat:	.res 1
fbSel:	.res 1
fbXor:	.res 1
fbOff:	.res 2                  ; fbRow * stride + fbCol
fbSrc:	.res 1                  ; buffer numbers
fbDst:	.res 1
fbLast:	.res 1
fbKeep:	.res 1
fbB:	.res 1
fbD:	.res 1
fbE0:	.res 1
fbE1:	.res 1
fbTmp:	.res 1
fbRest:	.res 1                  ; Split: the bytes after the groups of 8
fbBlkN:	.res 2                  ; fb_block: rows

.segment "CODE"

;---------------------------------------------------------------
; fbOff = fbRow * stride + fbCol      Destroyed: a, x
;---------------------------------------------------------------
fb_calc_off:
	lda fbRow               ; row * 16
	sta fbOff
	lda fbRow+1
	asl fbOff
	rol
	asl fbOff
	rol
	asl fbOff
	rol
	asl fbOff
	rol
	sta fbOff+1
	ldx fbOff               ; + row * 64 = row * 80
	stx fbTmp
	asl fbTmp
	rol
	asl fbTmp
	rol
	tax                     ; (row * 64 high)
	lda fbTmp
	clc
	adc fbOff
	sta fbOff
	txa
	adc fbOff+1
	ldx kStride
	cpx #80
	beq @2
	lsr                     ; 40 a row: half
	ror fbOff
@2:	sta fbOff+1
	lda fbOff
	clc
	adc fbCol
	sta fbOff
	bcc @3
	inc fbOff+1
@3:	rts

;---------------------------------------------------------------
; fb_seek: data port x at buffer a, byte fbOff + y, increment 1
; Destroyed: a
;---------------------------------------------------------------
fb_seek:
	stx VERA_CTRL
	phx
	tax
	tya
	clc
	adc fbOff
	sta VERA_ADDR_L
	lda fbOff+1
	adc BufMid,x
	sta VERA_ADDR_M
	lda #VERA_INC1
	adc #0                  ; address bit 16 (the back screen crosses $10000)
	sta VERA_ADDR_H
	plx
	stz VERA_CTRL
	rts

BufMid:	.byte >VRAM_FG, >VRAM_BG ; (both start on a page; neither starts above $FFFF)

;---------------------------------------------------------------
; fb_span (see the top)        Destroyed: a, x, y
; fb_span_off: the same with fbOff already set (a rectangle's rows: the
; next row's is fbOff + the stride, V80)
;---------------------------------------------------------------
fb_span:
	lda clipOn              ; the clip rectangle (V81: kernel/g/clip.s)
	beq @nc
	jmp fb_clip
@nc:	jsr fb_calc_off
fb_span_off:
	lda fbCnt
	beq @rts
	lda fbOp
	cmp #FBOP_RECOVER
	beq @recover
	cmp #FBOP_IMPRINT
	beq @imprint
	cmp #FBOP_INV
	beq @inv
	; source: back screen if it is written, else foreground
	lda #BUF_FG
	bit fbSel
	bvc @1
	lda #BUF_BG
@1:	sta fbSrc
	bit fbSel
	bpl @2
	lda #BUF_FG
	jsr fb_pass
	; a fill on both screens: the back screen gets the same bytes
	lda fbOp
	bne @2
	bit fbSel
	bvc @rts
	jmp fb_fill_bg
@2:	bit fbSel
	bvc @rts
	lda #BUF_BG
	jmp fb_pass
; InvertLine reads the foreground if it is written, else the back screen;
; the back screen pass goes first, so both read the foreground unchanged
@inv:	lda #BUF_FG
	bit fbSel
	bmi @i1
	lda #BUF_BG
@i1:	sta fbSrc
	bit fbSel
	bvc @i2
	lda #BUF_BG
	jsr fb_pass
@i2:	bit fbSel
	bpl @rts
	lda #BUF_FG
	jmp fb_pass
@recover:
	LoadB fbSrc, BUF_BG
	lda #BUF_FG
	jmp fb_pass
@imprint:
	LoadB fbSrc, BUF_FG
	lda #BUF_BG
	jmp fb_pass
@rts:	rts

; one destination buffer (a): first byte, middle bytes, last byte
fb_pass:
	sta fbDst
	ldx fbSrc               ; port 1 at the source, port 0 at the
	lda #1                  ; destination: the span's first byte
	sta VERA_CTRL
	jsr SeekX
	stz VERA_CTRL
	ldx fbDst
	jsr SeekX
	ldy #0
	ldx fbCnt
	dex
	stx fbLast
	lda fbKeepL
	cpx #0
	bne @1
	ora fbKeepR
@1:	jsr fb_byte
	sta fbE0
	sta fbE1
	cpy fbCnt
	beq @rts
	cpy fbLast
	beq @last
	jsr fb_middle
@last:	lda fbKeepR
	jsr fb_byte
	sta fbE1
@rts:	rts

; the back screen after a fill pass on the foreground
fb_fill_bg:
	ldy #0
	lda #BUF_BG
	ldx #0
	jsr fb_seek
	lda fbE0
	sta VERA_DATA0
	ldx fbLast
	beq @rts
	dex
	lda fbPat
	jsr fb_fillx
	lda fbE1
	sta VERA_DATA0
@rts:	rts

; the selected data port at buffer x, byte fbOff, increment 1
SeekX:	lda fbOff
	sta VERA_ADDR_L
	lda fbOff+1
	clc
	adc BufMid,x
	sta VERA_ADDR_M
	lda #VERA_INC1
	adc #0                  ; address bit 16
	sta VERA_ADDR_H
	rts

; byte y of the span with keep mask a; y += 1; a = the byte written
fb_byte:
	sta fbKeep
	lda VERA_DATA1          ; source byte (port 1 advances)
	sta fbB
	ldx fbOp
	beq @fill
	dex
	beq @inv
	dex
	bne @data               ; recover / imprint: copy
	lda (fbBufPtr),y
	eor fbXor
	bra @data
@fill:	lda fbPat
	bra @data
@inv:	eor #$FF
@data:	ldx fbKeep
	beq @write
	sta fbD                 ; new = data XOR ((data XOR A) AND keep)
	lda fbOp
	cmp #FBOP_RECOVER
	bcc @src
	; A: the old destination byte, read through port 0 in place
	; (increment 0 for the read: V80; the old way sought back)
	ldx VERA_ADDR_H
	txa
	and #1
	sta VERA_ADDR_H
	lda VERA_DATA0
	stx VERA_ADDR_H
	bra @merge
@src:	lda fbB
@merge:	eor fbD
	and fbKeep
	eor fbD
@write:	sta VERA_DATA0
	iny
	rts

; x bytes: x = the groups of 8 (z set if none), fbRest = the rest
Split:	txa
	and #7
	sta fbRest
	txa
	lsr
	lsr
	lsr
	tax
	rts

; bytes y .. fbLast-1, no keep mask; leaves y = fbLast, both ports there
fb_middle:
	lda fbLast
	sty fbTmp
	sec
	sbc fbTmp
	tax
	lda fbOp
	bne @nf
	lda fbPat               ; fill
	jsr fb_fillx
	bra @seek1
@nf:	cmp #FBOP_BUF
	bne @ci
@buf:	lda (fbBufPtr),y
	eor fbXor
	sta VERA_DATA0
	iny
	dex
	bne @buf
@seek1:	ldy fbLast              ; port 1 was not read: to the last byte,
	lda fbKeepR             ; if its source is needed
	beq @r
	lda fbSrc
	ldx #1
	jmp fb_seek
@ci:	cmp #FBOP_INV
	beq @inv
	jsr Split               ; copy: groups of 8 unrolled, then the rest
	beq @cr
@cg:
.repeat 8
	lda VERA_DATA1
	sta VERA_DATA0
.endrepeat
	dex
	bne @cg
@cr:	ldx fbRest
	beq @done
@c1:	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @c1
@done:	ldy fbLast
@r:	rts
@inv:	jsr Split
	beq @ir
@ig:
.repeat 8
	lda VERA_DATA1
	eor #$FF
	sta VERA_DATA0
.endrepeat
	dex
	bne @ig
@ir:	ldx fbRest
	beq @done
@i1:	lda VERA_DATA1
	eor #$FF
	sta VERA_DATA0
	dex
	bne @i1
	bra @done

; a to port 0, x times (0-80): groups of 8 unrolled, then the rest (FX
; for long ones)
fb_fillx:
	cpx #FX_MIN
	bcc @plain
	bit kFx
	bpl @plain
	jmp fb_fxfill
@plain:	pha
	jsr Split
	pla
	cpx #0
	beq @r
@g:
.repeat 8
	sta VERA_DATA0
.endrepeat
	dex
	bne @g
@r:	ldx fbRest
	beq @e
@1:	sta VERA_DATA0
	dex
	bne @1
@e:	rts

.segment "RODATA"

