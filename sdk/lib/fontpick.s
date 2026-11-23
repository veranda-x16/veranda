; Veranda's font picker: FontPick (fontpick.h; DECISIONS V62)
; MIT licence (see LICENSE).
;
; A dialog box of its own position (WIDE_DB): the font list (9 rows, a
; strip under it: up, down), the size list, the preview, OK and Cancel.
; DB_USR_ROUT draws it, DBOPVEC takes the clicks (otherPressVec). For C
; (fastcall: the struct's address in a/x) and assembly alike: it uses
; r0-r15 only, never cc65's zero page or stack.

.include "veranda.inc"
.include "macros.inc"

.export _FontPick, FontPick

NF      = 16                    ; fonts listed
ROWS    = 9                     ; rows shown
ROWH    = 14                    ; a row's height
BT      = 130                   ; the box
BB      = 349
BL      = 160
BR      = 479
LT      = 150                   ; the lists' first row
FL0     = 168                   ; the font list
FL1     = 343
SL0     = 352                   ; the size list
SL1     = 399
ST0     = LT + ROWS * ROWH + 3  ; their strips (up | down)
ST1     = ST0 + 11
PV0     = 296                   ; the preview
PV1     = 343
PX0     = 168
PX1     = 471

.segment "BSS"

fp:	.res 2
names:	.res NF * FONT_NAME_LEN
sizes:	.res 64
nf:	.res 1
ns:	.res 1
selF:	.res 1
selS:	.res 1
topF:	.res 1
topS:	.res 1
want:	.res 1
row:	.res 1
idx:	.res 1
yy:	.res 2
wb:	.res 2

.segment "CODE"

_FontPick:
FontPick:
	sta fp
	stx fp+1
	LoadW r0, names
	lda #NF
	jsr FontList
	sta nf
	stz selF                ; fp->name in the list?
	ldx #0
@f:	cpx nf
	beq @fd
	txa
	jsr NameX               ; r1 = name x
	MoveW fp, r2
	ldy #0
@c:	lda (r1),y
	cmp (r2),y
	bne @n
	iny
	cmp #0
	bne @c
	stx selF
	bra @fd
@n:	inx
	bra @f
@fd:	lda selF                ; on the screen
	sec
	sbc #ROWS - 1
	bcs @t
	lda #0
@t:	sta topF
	MoveW fp, r14
	ldy #FONT_NAME_LEN      ; the size wanted
	lda (r14),y
	sta want
	jsr Sizes
	LoadW r0, Dlg
	jsr DoDlgBox
	lda r0L
	cmp #OK
	bne @cancel
	lda selF                ; the choice to fp, loaded
	jsr NameX
	MoveW fp, r14
	ldy #0
@cp:	lda (r1),y
	sta (r14),y
	beq @cd
	iny
	bra @cp
@cd:	ldx selS
	lda sizes,x
	ldy #FONT_NAME_LEN
	sta (r14),y
	MoveW r1, r0
	ldx selS
	lda sizes,x
	jsr LoadFont
	pha
	MoveW fp, r14
	pla
	ldy #FONT_NAME_LEN + 1
	sta (r14),y
	lda #OK
	ldx #0
	rts
@cancel:
	lda #CANCEL
	ldx #0
	rts

; a = font index -> r1 = its name (x kept)
NameX:	stz r1H
	asl
	asl
	asl
	asl
	rol r1H
	asl
	rol r1H
	clc
	adc #<names
	sta r1L
	lda r1H
	adc #>names
	sta r1H
	rts

; the sizes of font selF; selS = want's, else the next larger, else the
; largest; topS so that it shows
Sizes:	lda selF
	jsr NameX
	MoveW r1, r0
	LoadW r1, sizes
	jsr FontSizes
	sta ns
	stz selS
	ldx #0
@s:	cpx ns
	beq @last
	lda sizes,x
	cmp want
	bcs @got
	inx
	bra @s
@last:	dex
	bpl @got
	ldx #0
@got:	stx selS
	txa
	sec
	sbc #ROWS - 1
	bcs @t
	lda #0
@t:	sta topS
	rts

;---------------------------------------------------------------
; drawing (DB_USR_ROUT, and after a click)
;---------------------------------------------------------------
Draw:	ldx #0                  ; the frames
@fr:	ldy #0
@fw:	lda Frames,x
	sta r3,y                ; (r3 left, r4 right, then r11 top, r12 bottom)
	inx
	iny
	cpy #4
	bne @fw
	ldy #0
@fv:	lda Frames,x
	sta r11,y
	inx
	iny
	cpy #4
	bne @fv
	phx
	lda #$FF
	jsr WFrameRectangle
	plx
	cpx #8 * 5
	bne @fr
	LoadW r11, FL0 + 2
	LoadW r12, BT + 4
	jsr Base
	LoadW r0, Title
	jsr WPutString
	LoadW r11, PX0 + 2      ; the strips' marks
	LoadW r12, ST0 + 1
	jsr Base
	LoadW r0, Marks
	jsr WPutString
	jsr DrawF
	jsr DrawS
	jmp DrawP

; r12 (a row's top) + 1 + baselineOffset: the baseline
Base:	lda r12L
	sec
	adc baselineOffset
	sta r12L
	bcc @1
	inc r12H
@1:	rts

; the font list
DrawF:	stz row
@r:	jsr RowY                ; yy = the row's top
	LoadW r3, FL0
	LoadW r4, FL1
	jsr Clear
	lda topF
	clc
	adc row
	sta idx
	cmp nf
	bcs @n
	jsr NameX
	MoveW r1, r0
	LoadW rightMargin, FL1 - 2
	LoadW r11, FL0 + 3
	MoveW yy, r12
	jsr Base
	inc r12L                ; (2 below the row's top)
	bne @b
	inc r12H
@b:	jsr WPutString
	LoadW rightMargin, 639
	lda idx
	cmp selF
	bne @n
	LoadW r3, FL0
	LoadW r4, FL1
	jsr Invert
@n:	inc row
	lda row
	cmp #ROWS
	beq :+
	jmp @r
:
	rts

; the size list
DrawS:	stz row
@r:	jsr RowY
	LoadW r3, SL0
	LoadW r4, SL1
	jsr Clear
	lda topS
	clc
	adc row
	sta idx
	cmp ns
	bcs @n
	tax
	lda sizes,x
	sta r0L
	stz r0H
	LoadW r11, SL0 + 3
	MoveW yy, r12
	jsr Base
	inc r12L
	bne @b
	inc r12H
@b:	lda #SET_LEFTJUST | $40       ; (left, no leading zeros)
	jsr WPutDecimal
	lda idx
	cmp selS
	bne @n
	LoadW r3, SL0
	LoadW r4, SL1
	jsr Invert
@n:	inc row
	lda row
	cmp #ROWS
	bne @r
	rts

; the preview: the sample in the font chosen, clipped to its box
DrawP:	LoadW r3, PX0
	LoadW r4, PX1
	LoadW r11, PV0
	LoadW r12, PV1
	lda #0
	jsr SetPattern
	jsr WRectangle
	lda ns
	bne :+
	jmp @r
:
	lda selF
	jsr NameX
	MoveW r1, r0
	ldx selS
	lda sizes,x
	jsr LoadFont
	cmp #FONT_NONE
	beq @r
	jsr UseFont
	MoveW windowTopW, yy    ; (kept: the window is the box's)
	MoveW windowBottomW, wb
	LoadW r11, PV0 + 1
	LoadW r12, PV1 - 1
	jsr WSetWindow
	LoadW rightMargin, PX1 - 1
	LoadW r11, PX0 + 4
	LoadW r12, PV0 + 4
	jsr Base
	LoadW r0, Sample
	jsr WPutString
	LoadW rightMargin, 639
	MoveW yy, r11
	MoveW wb, r12
	jsr WSetWindow
	lda uiFont              ; the box's font again
	jsr UseFont
@r:	rts

; yy = row's top
RowY:	LoadW yy, LT
	ldx row
	beq @r
@1:	AddVW ROWH, yy
	dex
	bne @1
@r:	rts

; r3-r4 x yy .. yy + ROWH - 1: cleared / inverted
Clear:	jsr RowR
	lda #0
	jsr SetPattern
	jmp WRectangle
Invert:	jsr RowR
	jmp WInvertRectangle
RowR:	MoveW yy, r11
	lda yy
	clc
	adc #ROWH - 1
	sta r12L
	lda yy+1
	adc #0
	sta r12H
	rts

;---------------------------------------------------------------
; clicks (otherPressVec): a press in a list or on a strip
;---------------------------------------------------------------
Click:	lda mouseData
	bpl :+                  ; (a release)
	jmp @r
:
	MoveW mouseYPosW, yy
	CmpWI yy, LT
	bcs :+
	rts
:
	CmpWI yy, ST0
	bcc :+
	jmp @strip
:
	lda yy                  ; the row: (y - LT) / ROWH
	sec
	sbc #<LT
	sta yy
	lda yy+1
	sbc #>LT
	sta yy+1
	ldx #0
@d:	CmpWI yy, ROWH
	bcc @dd
	AddVW $10000 - ROWH, yy
	inx
	bra @d
@dd:	stx row
	CmpWI mouseXPos, FL0
	bcc @r
	CmpWI mouseXPos, FL1 + 1
	bcc @font
	CmpWI mouseXPos, SL0
	bcc @r
	CmpWI mouseXPos, SL1 + 1
	bcs @r
	lda topS                ; a size
	clc
	adc row
	cmp ns
	bcs @r
	sta selS
	tax
	lda sizes,x
	sta want
	jsr DrawS
	jmp DrawP
@r:	rts
@font:	lda topF
	clc
	adc row
	cmp nf
	bcs @r
	cmp selF
	beq @r
	sta selF
	jsr Sizes
	jsr DrawF
	jsr DrawS
	jmp DrawP
@r2:	rts
@strip:	CmpWI yy, ST1 + 1
	bcs @r2
	CmpWI mouseXPos, FL0
	bcc @r2
	CmpWI mouseXPos, FL1 + 1
	bcc @fs
	CmpWI mouseXPos, SL0
	bcc @r2
	CmpWI mouseXPos, SL1 + 1
	bcs @r2
	CmpWI mouseXPos, (SL0 + SL1) / 2  ; sizes: up | down
	bcs @sd
	lda topS
	beq @r2
	dec topS
	jmp DrawS
@sd:	lda topS
	clc
	adc #ROWS
	cmp ns
	bcs @r2
	inc topS
	jmp DrawS
@fs:	CmpWI mouseXPos, (FL0 + FL1) / 2  ; fonts: up | down
	bcs @fd
	lda topF
	beq @r2
	dec topF
	jmp DrawF
@fd:	lda topF
	clc
	adc #ROWS
	cmp nf
	bcc :+
	rts
:
	inc topF
	jmp DrawF

.segment "RODATA"

Dlg:	.byte WIDE_DB | SET_DB_POS | 1
	.word BT, BB, BL, BR
	.byte DB_USR_ROUT
	.word Draw
	.byte DBOPVEC
	.word Click
	.byte OK, (408 - BL) / 8, LT - BT
	.byte CANCEL, (408 - BL) / 8, LT - BT + 30
	.byte 0

; the frames (left, right, top, bottom): the lists with their strips, the
; lines over the strips, the preview
Frames:	.word FL0 - 1, FL1 + 1, LT - 1, ST1 + 1
	.word SL0 - 1, SL1 + 1, LT - 1, ST1 + 1
	.word FL0 - 1, FL1 + 1, ST0 - 1, ST0 - 1
	.word SL0 - 1, SL1 + 1, ST0 - 1, ST0 - 1
	.word PX0 - 1, PX1 + 1, PV0 - 1, PV1 + 1

Title:	.byte "Font", 0
Marks:	.byte "up", GOTOX
	.word (FL0 + FL1) / 2 + 2
	.byte "down", GOTOX
	.word SL0 + 2
	.byte "up", GOTOX
	.word (SL0 + SL1) / 2 + 2
	.byte "dn", 0
Sample:	.byte "AaBbGg Quick 123", 0
