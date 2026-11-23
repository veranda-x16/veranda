; gate gfx1, the clip rectangle (DECISIONS V81), run as TEST.PRG
;
; NCASE random cases, each on a screen of noise (both screens the same
; bytes, a generator's): a random clip rectangle and a random call
; (WRectangle, WInvertRectangle in a random pattern, narrow and wide;
; WFrameRectangle; WHorizontalLine, WInvertLine; WVerticalLine; WDrawLine;
; WDrawPoint; WPutString in the system font, the UI font and bold;
; WBitmapUp, compacted and raw rows); the
; call drawn with the clip on into the foreground alone, and without it
; into the back screen alone. Then every byte of the foreground must be
; the back screen's inside the clip and the noise outside it, pixel for
; pixel at the clip's edges. Console: CLIP <cases> <bad bytes> <first bad
; case>, CLIP DONE.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

NCASE = 100
NROWS = 256                     ; the rows noised and checked

.segment "CODE"

Start:
	lda #MODE_640x480
	jsr SetVideoMode
	LoadW seed, $1D2B
	stz nbad
	stz nbad+1
	LoadB firstBad, $FF
	stz ncase
@case:	jsr Noise
	; the clip: x0 0-639, x1 x0..639; y0 0-479, y1 y0..479
	jsr Rx
	MoveW rv, cl
	jsr Rx
	CmpW rv, cl
	bcs @1
	ldx rv
	ldy rv+1
	MoveW cl, rv
	stx cl
	sty cl+1
@1:	MoveW rv, cr
	jsr Ry
	MoveW rv, ct
	jsr Ry
	CmpW rv, ct
	bcs @2
	ldx rv
	ldy rv+1
	MoveW ct, rv
	stx ct
	sty ct+1
@2:	MoveW rv, cb
	; the call and its arguments
	jsr Rnd
	and #15
	sta op
	jsr Rx
	MoveW rv, q3
	jsr Rx
	MoveW rv, q4
	jsr Ry
	MoveW rv, q11
	jsr Ry
	MoveW rv, q12
	jsr Rnd
	sta aa
	; with the clip, the foreground
	LoadB dispBufferOn, ST_WR_FORE
	MoveW cl, leftMargin
	MoveW cr, rightMargin
	MoveW ct, windowTopW
	MoveW cb, windowBottomW
	LoadB clipOn, $80
	jsr Call
	stz clipOn
	; without, the back screen
	LoadB dispBufferOn, ST_WR_BACK
	LoadW leftMargin, 0
	LoadW rightMargin, 639
	LoadW windowTopW, 0
	LoadW windowBottomW, 479
	jsr Call
	MoveW nbad, lastBad
	jsr Compare
.ifdef VERBOSE
	lda op                  ; (each case: its call and its bad bytes)
	jsr LogHex
	lda #' '
	sta EMU_STDOUT
	lda nbad
	sec
	sbc lastBad
	pha
	lda nbad+1
	sbc lastBad+1
	jsr LogHex
	pla
	jsr LogHex
	lda #10
	sta EMU_STDOUT
.endif
	inc ncase
	lda ncase
	cmp #NCASE
	beq @done
	jmp @case
@done:	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	jsr UseSystemFont
	LoadW r0, MsgClip
	jsr Log
	lda ncase
	jsr LogDec
	lda nbad+1
	jsr LogHex
	lda nbad
	jsr LogHex
	lda #' '
	sta EMU_STDOUT
	lda firstBad
	jsr LogHex
	lda #10
	sta EMU_STDOUT
	LoadW r0, MsgDone
	jsr Log
	lda #10
	sta EMU_STDOUT
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; the call op with q3, q4, q11, q12, aa (r3 <= r4, r11 <= r12 where needed)
Call:	MoveW q3, r3
	MoveW q4, r4
	MoveW q11, r11
	MoveW q12, r12
	lda op
	asl
	tax
	jmp (Ops,x)
Ops:	.word ORect, ORect, ONarrow, OInv, ONInv, OFrame, OHLine, OILine
	.word OLine, OPoint, OSys, OUi, OBold, OBitmap, OVLine, ORaw

Order:	CmpW r4, r3             ; r3 <= r4, r11 <= r12
	bcs @1
	ldx r3
	ldy r3+1
	MoveW r4, r3
	stx r4
	sty r4+1
@1:	CmpW r12, r11
	bcs @2
	ldx r11
	ldy r11+1
	MoveW r12, r11
	stx r12
	sty r12+1
@2:	rts
Pat:	lda aa
	and #31
	cmp #34
	bcc @1
	lda #2
@1:	jmp SetPattern
ORect:	jsr Order
	jsr Pat
	jmp WRectangle
Thin:	lda aa                  ; r4 = r3 + 0..31
	and #31
	clc
	adc r3
	sta r4
	lda r3+1
	adc #0
	sta r4+1
	CmpWI r4, 640
	bcc @1
	LoadW r4, 639
@1:	jmp Order
ONarrow: jsr Thin
	jsr Pat
	jmp WRectangle
OInv:	jsr Order
	jmp WInvertRectangle
ONInv:	jsr Thin
	jmp WInvertRectangle
OFrame:	jsr Order
	lda aa
	jmp WFrameRectangle
OHLine:	jsr Order
	lda aa
	jmp WHorizontalLine
OILine:	jsr Order
	jmp WInvertLine
OLine:	lda aa
	and #1
	jmp WDrawLine
OVLine:	jsr Order               ; (bank T's, V81)
	lda aa
	jmp WVerticalLine
ORaw:	jsr OBitmap1            ; raw rows (WBitmapUp's height bit 15, V81)
	LoadW r0, Bitmap + 1
	LoadW r12, $8020
	jmp WBitmapUp
OPoint:	lda aa
	and #1
	jmp WDrawPoint
; text at x < 400 (it ends on the screen: past it the call without the
; clip stops at the margin)
TextAt:	MoveW r3, r11           ; x 0 .. 399
	CmpWI r11, 400
	bcc @0
	dec r11+1
	CmpWI r11, 400
	bcc @0
	dec r11+1
@0:	MoveW q11, r12          ; the baseline: 12 .. 239
	CmpWI r12, 12
	bcs @2
	LoadW r12, 12
@2:	LoadW r0, Text
	rts
OSys:	jsr UseSystemFont
	jsr TextAt
	jmp WPutString
OUi:	lda #FONT_UI
	jsr UseFont
	jsr TextAt
	jsr WPutString
	jmp UseSystemFont
OBold:	lda #FONT_UI
	jsr UseFont
	jsr TextAt
	LoadB currentMode, SET_BOLD
	jsr WPutString
	stz currentMode
	jmp UseSystemFont
OBitmap: jsr OBitmap1
	jmp WBitmapUp
OBitmap1: lda r3+1              ; card x 0-75, 4 cards, y 0-223, 32 rows
	lsr
	lda r3
	ror
	lsr
	lsr
	cmp #76
	bcc @1
	lda #75
@1:	sta r1L
	LoadB r2L, 4
	CmpWI r11, 224
	bcc @2
	LoadW r11, 223
@2:	LoadW r12, 32
	LoadW r0, Bitmap
	rts

; both screens: noise from the generator (seed kept: Compare makes it again)
Noise:	MoveW seed, nseed
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	LoadB VERA_ADDR_H, VERA_INC1
	lda #1
	sta VERA_CTRL
	stz VERA_ADDR_L
	LoadB VERA_ADDR_M, >VRAM_BG
	LoadB VERA_ADDR_H, VERA_INC1
	stz VERA_CTRL
	LoadW cnt, NROWS * 80
@n:	jsr NRnd
	sta VERA_DATA0
	sta VERA_DATA1
	lda cnt
	bne @d
	dec cnt+1
@d:	dec cnt
	lda cnt
	ora cnt+1
	bne @n
	rts

; the foreground against the expected bytes: inside the clip the back
; screen's, outside the noise
Compare:
	MoveW seed, nseed
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	LoadB VERA_ADDR_H, VERA_INC1
	lda #1
	sta VERA_CTRL
	stz VERA_ADDR_L
	LoadB VERA_ADDR_M, >VRAM_BG
	LoadB VERA_ADDR_H, VERA_INC1
	stz VERA_CTRL
	stz yy
	stz yy+1
@row:	stz col
@col:	jsr NRnd
	sta nz
	lda VERA_DATA1
	sta bk
	lda VERA_DATA0
	sta fg
	; the clip's mask of this byte: 0 outside
	CmpW yy, ct
	bcc @m0
	CmpW cb, yy
	bcc @m0
	jsr Mask
	bra @m
@m0:	lda #0
@m:	sta msk
	lda bk                  ; expected = bk AND m OR nz AND NOT m
	and msk
	sta bk
	lda msk
	eor #$FF
	and nz
	ora bk
	cmp fg
	beq @ok
	IncW nbad
	lda firstBad
	cmp #$FF
	bne @ok
	lda ncase
	sta firstBad
	MoveB op, firstOp
@ok:	inc col
	lda col
	cmp #80
	beq @nr
	jmp @col
@nr:	IncW yy
	CmpWI yy, NROWS
	beq @end
	jmp @row
@end:
	; the next case's noise
	jsr NRnd
	sta seed
	jsr NRnd
	sta seed+1
	rts

; a = the mask of column col's pixels in cl .. cr
Mask:	lda cl+1                ; cl / 8, cr / 8
	ldx cl
	jsr Div8
	sta c0
	lda cr+1
	ldx cr
	jsr Div8
	sta c1
	lda col
	cmp c0
	bcc @0
	beq @l
	cmp c1
	beq @r
	bcs @0
	lda #$FF
	rts
@l:	lda cl                  ; first column: from bit cl AND 7 on
	and #7
	tax
	lda RMask,x
	ldx col
	cpx c1
	bne @r1
	sta c0
	lda cr
	and #7
	tax
	lda LMask,x
	and c0
@r1:	rts
@r:	lda cr
	and #7
	tax
	lda LMask,x
	rts
@0:	lda #0
	rts

; a:x / 8 (a high, x low; up to 1023)
Div8:	asl
	asl
	asl
	asl
	asl
	sta dtmp
	txa
	lsr
	lsr
	lsr
	ora dtmp
	rts

; random words: rv = 0 .. 639 (Rx), 0 .. 479 (Ry)
Rx:	jsr Rnd
	sta rv
	jsr Rnd
	and #3
	sta rv+1
	CmpWI rv, 640
	bcs Rx
	rts
Ry:	jsr Rnd                 ; (0 .. 239: the noise and the check cover rows 0-255)
	cmp #240
	bcs Ry
	sta rv
	stz rv+1
	rts
; the cases' generator (its own state: the noise's does not depend on it)
Rnd:	lda rs
	asl
	rol rs+1
	bcc @1
	eor #$2D
@1:	sta rs
	eor rs+1
	rts
; the noise's (nseed)
NRnd:	lda nseed
	asl
	rol nseed+1
	bcc @1
	eor #$39
@1:	sta nseed
	adc nseed+1
	rts

Log:	ldy #0
@1:	lda (r0),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts
LogDec:	ldx #'0' - 1            ; a < 200: hundreds, tens, ones
	sec
@h:	inx
	sbc #100
	bcs @h
	adc #100
	stx EMU_STDOUT
	ldx #'0' - 1
	sec
@t:	inx
	sbc #10
	bcs @t
	adc #10 + '0'
	stx EMU_STDOUT
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	rts
LogHex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	sta EMU_STDOUT
	rts

.segment "RODATA"

RMask:	.byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01     ; from bit n on
LMask:	.byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF     ; up to bit n
MsgClip: .byte "CLIP ", 0
MsgDone: .byte "CLIP DONE", 0
Text:	.byte "Clip: Wg|jy, 0123 Mm @% folders.", 0
Bitmap:	.byte $80 + 64
.repeat 64, I
	.byte <(I * 53 + 7)
.endrepeat
	.byte $80 + 64
.repeat 64, I
	.byte <(I * 29 + 101)
.endrepeat

.segment "DATA"

rs:	.word $ACE1

.segment "BSS"

seed:	.res 2
nseed:	.res 2
cnt:	.res 2
cl:	.res 2
cr:	.res 2
ct:	.res 2
cb:	.res 2
rv:	.res 2
q3:	.res 2
q4:	.res 2
q11:	.res 2
q12:	.res 2
aa:	.res 1
op:	.res 1
ncase:	.res 1
nbad:	.res 2
lastBad: .res 2
firstBad: .res 1
firstOp: .res 1
yy:	.res 2
col:	.res 1
nz:	.res 1
bk:	.res 1
fg:	.res 1
msk:	.res 1
c0:	.res 1
c1:	.res 1
dtmp:	.res 1
