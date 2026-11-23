; Veranda bank G2: the classic GEOS drawing calls (8-bit y) on top of the
; wide ones in bank G, GraphicsString, bitmaps
;
; A shim moves the classic registers into the wide ones and keeps r11 and
; r12 (which the wide calls use and the classic ones do not).

.include "kernel.inc"

.import kRowBuf, kStride, RowOff, pcAddr, pcTmp

.export k_Rectangle, k_InvertRectangle, k_RecoverRectangle, k_ImprintRectangle
.export k_FrameRectangle, k_HorizontalLine, k_InvertLine, k_RecoverLine, k_VerticalLine
.export DrawLineA, DrawPointA, k_TestPoint, k_PutChar, k_SmallPutChar, k_PutString
.export k_PutDecimal, k_WPutDecimal, k_GraphicsString, k_BitmapUp, k_BitmapClip, k_WBitmapUp

.segment "BSS"

sA:	.res 1
s11:	.res 2
s12:	.res 2
penX:	.res 2
penY:	.res 2
; the bitmap decoder (a stream across rows)
bmSrc:	.res 2
bmLeft:	.res 1                  ; bytes left in the current op
bmLit:	.res 1                  ; $80: literal bytes, else repeat bmByte
bmByte:	.res 1
bmBig:	.res 1                  ; repeats of the pattern still to come
bmBigLen: .res 1                ; the pattern's length in raw bytes
bmBigUsed: .res 1
bmBigAt: .res 2                 ; where the pattern starts
bmW:	.res 1
bmRows:	.res 2
bmSkipL: .res 1
bmSkipR: .res 1
bmSkipT: .res 2
bmRaw:	.res 1                  ; $80: raw rows (V81)
digits:	.res 6                  ; WPutDecimal
dnum:	.res 2
dFmt:	.res 1
dR0:	.res 2

.segment "CODE"

Save:	sta sA
	MoveW r11, s11
	MoveW r12, s12
	rts
Restore:
	MoveW s11, r11
	MoveW s12, r12
	lda sA
	rts

; r2L top, r2H bottom -> r11, r12
Rect:	jsr Save
	lda r2L
	sta r11L
	stz r11H
	lda r2H
	sta r12L
	stz r12H
	rts

k_Rectangle:
	jsr Rect
	FARCALL k_WRectangle
	bra Restore
k_InvertRectangle:
	jsr Rect
	FARCALL k_WInvertRectangle
	bra Restore
k_RecoverRectangle:
	jsr Rect
	FARCALL k_WRecoverRectangle
	bra Restore
k_ImprintRectangle:
	jsr Rect
	FARCALL k_WImprintRectangle
	bra Restore
k_FrameRectangle:
	jsr Rect
	lda sA
	FARCALL k_WFrameRectangle
	bra Restore

; r3, r4, r11L
Row:	jsr Save
	stz r11H
	lda sA
	rts
k_HorizontalLine:
	jsr Row
	FARCALL k_WHorizontalLine
	bra Restore
k_InvertLine:
	jsr Row
	FARCALL k_WInvertLine
	bra Restore
k_RecoverLine:
	jsr Row
	FARCALL k_WRecoverLine
	bra Restore

; a pattern, r3L top, r3H bottom, r4 x
k_VerticalLine:
	jsr Save
	lda r3L
	sta r11L
	stz r11H
	lda r3H
	sta r12L
	stz r12H
	lda sA
	FARCALL k_WVerticalLine
	jmp Restore

; a = mode (the resident shims k_DrawLine, k_DrawPoint turned the flags
; into it: they do not survive the bank gate); r3, r11L to r4, r11H
DrawLineA:
	jsr Save
	lda r11H
	sta r12L
	stz r12H
	stz r11H
	lda sA
	FARCALL k_WDrawLine
	jmp Restore

; a = mode; r3, r11L
DrawPointA:
	jsr Save
	stz r11H
	lda sA
	FARCALL k_WDrawPoint
	jmp Restore

k_TestPoint:
	jsr Save
	stz r11H
	FARCALL k_WTestPoint
	php
	jsr Restore
	plp
	rts

; text: r1H is the baseline -> r12
Text:	jsr Save
	lda r1H
	sta r12L
	stz r12H
	lda sA
	rts
TextEnd:
	MoveW s12, r12          ; (r11 advanced: kept)
	rts
k_PutChar:
	jsr Text
	FARCALL k_WPutChar
	bra TextEnd
k_SmallPutChar:
	jsr Text
	FARCALL k_WSmallPutChar
	bra TextEnd
k_PutString:
	jsr Text
	FARCALL k_WPutString
	bra TextEnd
k_PutDecimal:
	jsr Text
	jsr k_WPutDecimal
	bra TextEnd

;---------------------------------------------------------------
; WPutDecimal: a = format, r0 = value, r11 x, r12 baseline (from bank G,
; V81: the digits go to WPutString from the stack)
;---------------------------------------------------------------
k_WPutDecimal:
	sta dFmt
	MoveW r0, dnum
	MoveW r0, dR0
	ldx #4                  ; five digits, last first
@d:	jsr Div10
	ora #'0'
	sta digits,x
	dex
	bpl @d
	stz digits+5
	ldx #0                  ; leading zeros
	bit dFmt
	bvc @s
@z:	lda digits,x
	cmp #'0'
	bne @s
	cpx #4
	beq @s
	inx
	bra @z
@s:	phx
	; right justified: x = r11 + field width - the string's width
	bit dFmt
	bmi @put
	stz dnum
@wl:	lda digits,x
	beq @wd
	phx
	FARCALL k_GetCharWidth
	plx
	clc
	adc dnum
	sta dnum
	inx
	bra @wl
@wd:	lda dFmt
	and #$3F
	sec
	sbc dnum
	bcc @put
	clc
	adc r11L
	sta r11L
	bcc @put
	inc r11H
@put:	pla                     ; the digits from x on to the stack, last first
	sta dnum
	ldx #5
@p:	lda digits,x
	pha
	dex
	bmi @p1
	cpx dnum
	bcs @p
@p1:	tsx                     ; r0: the first, at $0101 + s
	inx
	stx r0L
	LoadB r0H, $01
	FARCALL k_WPutString
	lda #6                  ; off the stack again: 6 - x bytes
	sec
	sbc dnum
	tax
@o:	pla
	dex
	bne @o
	MoveW dR0, r0
	rts

; dnum / 10 -> dnum, a = remainder
Div10:	lda #0
	ldy #16
@1:	asl dnum
	rol dnum+1
	rol
	cmp #10
	bcc @2
	sbc #10
	inc dnum
@2:	dey
	bne @1
	rts

;---------------------------------------------------------------
; GraphicsString: r0 -> commands; r0 ends past the 0
;---------------------------------------------------------------
k_GraphicsString:
	jsr Save
GsNext:	jsr Byte
	beq GsEnd
	cmp #11
	bcs GsNext              ; unknown: ignored
	asl
	tax
	jmp (GsTab-2,x)
GsEnd:	jsr Restore
	rts

GsTab:	.word GsMove, GsLine, GsRect, GsNone, GsPat, GsStr, GsFrame, GsDX, GsDY, GsDXY

GsNone:	jmp GsNext
GsMove:	jsr XY
	bra GsNext
GsLine:	MoveW penX, r3
	MoveW penY, r11
	jsr XY
	MoveW penX, r4
	MoveW penY, r12
	lda #DRAW_INK
	FARCALL k_WDrawLine
	bra GsNext
GsRect:	jsr PenRect
	FARCALL k_WRectangle
	bra GsNext
GsFrame: jsr PenRect
	lda #$FF
	FARCALL k_WFrameRectangle
	bra GsNext
GsPat:	jsr Byte
	FARCALL k_SetPattern
	bra GsNext
GsStr:	jsr XY
	MoveW penX, r11
	MoveW penY, r12
	FARCALL k_WPutString    ; r0 ends past the string
	jmp GsNext
GsDX:	jsr Word
	clc
	adc penX
	sta penX
	txa
	adc penX+1
	sta penX+1
	jmp GsNext
GsDY:	jsr Word
	clc
	adc penY
	sta penY
	txa
	adc penY+1
	sta penY+1
	jmp GsNext
GsDXY:	jsr Word
	clc
	adc penX
	sta penX
	txa
	adc penX+1
	sta penX+1
	bra GsDY

; the pen to (word x, byte y) .. as a rectangle with the old pen
PenRect:
	MoveW penX, r3
	MoveW penY, r11
	jsr XY
	MoveW penX, r4
	MoveW penY, r12
	CmpW r4, r3             ; left <= right, top <= bottom
	bcs @1
	ldx r3L
	lda r4L
	sta r3L
	stx r4L
	ldx r3H
	lda r4H
	sta r3H
	stx r4H
@1:	CmpW r12, r11
	bcs @2
	ldx r11L
	lda r12L
	sta r11L
	stx r12L
	ldx r11H
	lda r12H
	sta r11H
	stx r12H
@2:	rts

XY:	jsr Word
	sta penX
	stx penX+1
	jsr Byte
	sta penY
	stz penY+1
	rts
Byte:	ldy #0
	lda (r0),y
	pha
	IncW r0
	pla
	rts
Word:	jsr Byte
	pha
	jsr Byte
	tax
	pla
	rts

;---------------------------------------------------------------
; bitmaps (GEOS compacted format):
;   count < $80        repeat the next byte count times
;   $80 .. $DB         count - $80 literal bytes follow
;   $DC ..             a pattern of count - $DC raw bytes (itself
;                      compacted) follows the next byte, its repeat count
;---------------------------------------------------------------
; classic: r0 data, r1L x (cards), r1H y, r2L width (cards), r2H height
k_BitmapUp:
	jsr Save
	lda r1H
	sta r11L
	stz r11H
	lda r2H
	sta r12L
	stz r12H
	jsr k_WBitmapUp
	jmp Restore

; wide: r0 data, r1L x, r2L width (cards), r11 y, r12 height; r12 bit 15
; (V81): raw rows (r2L bytes each, no compaction)
k_WBitmapUp:
	stz bmSkipL
	stz bmSkipR
	stz bmSkipT
	stz bmSkipT+1
	bit r12H
	bpl BitmapRows
	jmp BitmapRaw

; classic: as BitmapUp, r11L cards to skip on the left, r11H on the right,
; r12 rows to skip at the top: draws the part between
k_BitmapClip:
	jsr Save
	MoveB r11L, bmSkipL
	MoveB r11H, bmSkipR
	MoveW r12, bmSkipT
	lda r1H
	sta r11L
	stz r11H
	lda r2H
	sta r12L
	stz r12H
	jsr BitmapRows
	jmp Restore

BitmapRows:
	MoveW r0, bmSrc
	MoveW r12, bmRows
RowsFrom:
	stz bmLeft
	stz bmBig
	; the full rows to skip
@skip:	lda bmSkipT
	ora bmSkipT+1
	beq @rows
	lda bmSkipL
	clc
	adc r2L
	adc bmSkipR
	sta bmW
	jsr DecodeRow
	lda bmSkipT
	bne @s1
	dec bmSkipT+1
@s1:	dec bmSkipT
	bra @skip
@rows:	lda bmRows
	ora bmRows+1
	beq @end
	lda bmSkipL             ; decode skip + width + skip, write the width
	clc
	adc r2L
	adc bmSkipR
	sta bmW
	jsr DecodeRow
	PushW r0
	PushW r3
	lda #<kRowBuf
	clc
	adc bmSkipL
	sta r0L
	lda #>kRowBuf
	adc #0
	sta r0H
	MoveB r1L, r3L
	MoveB r2L, r3H
	FARCALL k_WriteRow
	PopW r3
	PopW r0
	IncW r11
	lda bmRows
	bne @r1
	dec bmRows+1
@r1:	dec bmRows
	bra @rows
@end:	stz bmRaw
	rts

;---------------------------------------------------------------
; raw rows (V81: the shell's tiles and glyphs): with the clip off and
; the bitmap on the screen, a column of bytes at a time, VERA's address
; stepping by the stride (as PutCards does), each screen in turn; else
; row by row through WriteRow (the clip's, the screen's edges)
;---------------------------------------------------------------
BitmapRaw:
	MoveW r0, bmSrc
	lda r12H
	and #$7F
	sta bmRows+1
	MoveB r12L, bmRows
	lda clipOn
	ora bmRows+1            ; (under 256 rows)
	bne @slow
	lda r1L                 ; x + w <= the stride
	clc
	adc r2L
	cmp kStride
	beq @y
	bcs @slow
@y:	lda r11L                ; y + h <= the height
	clc
	adc bmRows
	tax
	lda r11H
	adc #0
	cmp screenHeight+1
	bne @c
	cpx screenHeight
@c:	beq Columns
	bcc Columns
@slow:	LoadB bmRaw, $80
	jmp RowsFrom

; kTmp = y * stride + x (PutCards' RowOff), kTmp+2 = ADDR_H's step (the stride)
Columns:
	MoveW r11, pcTmp
	lda r3L
	pha
	MoveB r1L, r3L
	jsr RowOff
	pla
	sta r3L
	MoveW pcAddr, kTmp
	ldx #$C0                ; increment 80
	lda kStride
	cmp #80
	beq @80
	ldx #$B0                ; 40
@80:	stx kTmp+2
@a:	stz VERA_CTRL
	lda #>VRAM_FG
	bit dispBufferOn
	bpl @nf
	jsr Pass
@nf:	bit dispBufferOn
	bvc @nb
	lda #>VRAM_BG
	jsr Pass
@nb:	rts

; one screen (a: its base's middle byte), column after column
Pass:	sta kTmp+3
	stz bmW
@col:	lda kTmp
	clc
	adc bmW
	sta VERA_ADDR_L
	lda kTmp+1
	adc kTmp+3
	sta VERA_ADDR_M
	lda kTmp+2
	adc #0                  ; (bit 16)
	sta VERA_ADDR_H
	lda bmSrc
	clc
	adc bmW
	sta kPtr
	lda bmSrc+1
	adc #0
	sta kPtr+1
	ldy #0
	ldx bmRows
@row:	lda (kPtr),y
	sta VERA_DATA0
	tya
	clc
	adc r2L
	tay
	bcc @n
	inc kPtr+1
@n:	dex
	bne @row
	inc bmW
	lda bmW
	cmp r2L
	bne @col
	rts

; bmW bytes into kRowBuf
DecodeRow:
	bit bmRaw
	bpl @dec
	MoveW bmSrc, kPtr       ; raw rows: copied, bmSrc on
	ldy #0
@c:	cpy bmW
	beq @e
	lda (kPtr),y
	sta kRowBuf,y
	iny
	bra @c
@e:	tya
	clc
	adc bmSrc
	sta bmSrc
	bcc @r
	inc bmSrc+1
	rts
@dec:	ldx #0
@1:	cpx bmW
	beq @r
	phx
	jsr Decode
	plx
	sta kRowBuf,x
	inx
	bra @1
@r:	rts

; the next decoded byte
Decode:
	lda bmLeft
	beq @new
	dec bmLeft
	bit bmLit
	bmi Raw
	lda bmByte
	rts
@new:	jsr Raw
	cmp #$DC
	bcc @2
	sbc #$DC                ; a pattern
	sta bmBigLen
	jsr Raw                 ; its repeat count
	sec
	sbc #1
	sta bmBig
	MoveW bmSrc, bmBigAt
	stz bmBigUsed
	bra Decode
@2:	cmp #$80
	bcc @3
	sbc #$80                ; literal bytes
	sta bmLeft
	LoadB bmLit, $80
	bra Decode
@3:	sta bmLeft              ; a repeated byte
	stz bmLit
	jsr Raw
	sta bmByte
	bra Decode

; the next raw byte; inside a pattern, back to its start when it is used up
Raw:	MoveW bmSrc, kPtr       ; (bank G may use kPtr between rows)
	ldy #0
	lda (kPtr),y
	pha
	IncW bmSrc
	lda bmBig
	beq @r
	inc bmBigUsed
	lda bmBigUsed
	cmp bmBigLen
	bne @r
	dec bmBig
	MoveW bmBigAt, bmSrc
	stz bmBigUsed
@r:	pla
	rts
