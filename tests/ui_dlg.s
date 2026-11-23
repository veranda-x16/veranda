; gate ui, session "dlg": dialog boxes and GetString, GEOS 64 against
; Veranda. The system icons' pictures are Veranda's own: their areas are
; not compared (UiMask).
;
; A gray background; an icon whose routine opens a dialog box (the default
; position, shadow pattern 1): two text lines, a text input with a default
; text, OK and CANCEL. The session types into it (a backspace, letters),
; presses Return: the box closes (result DBGETSTRING), the application
; draws the result and the typed text; then a second box at its own
; position with a DBVARSTR line, YES and NO and DBSYSOPV, closed by a click
; outside; it draws that result too; at the end a third box is open. The
; typed text is compared in the box (frame 55: gate ui's dlg:55); drawn
; again after the box, it made GEOS 64 in the simulator write into its
; own code (y changed inside PutString), so it is not.

.ifdef GEOS64
.include "geos64.inc"
.include "geos64vars.inc"
.else
.include "veranda.inc"
.endif
.include "macros.inc"

.export UiSession, UiScript, UiMask

.segment "CODE"

UiSession:
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	lda #2
	jsr SetPattern
	LoadB r2L, 0
	LoadB r2H, 199
	LoadW r3, 0
	LoadW r4, 319
	jsr Rectangle
	LoadW r0, Icons
	jsr DoIcons
	jmp MainLoop

; the icon: three boxes, one after the other
Open:	LoadW r5, Buffer
	LoadW r0, Box1
	jsr DoDlgBox
	lda r0L
	ldx #150
	jsr Show
	LoadW r6, Msg
	LoadW r0, Box2
	jsr DoDlgBox
	lda r0L
	ldx #160
	jsr Show
	LoadW r0, Box3
	jsr DoDlgBox
	rts

; a result: a block a * 4 pixels wide at row x
Show:	stx r2L
	txa
	clc
	adc #6
	sta r2H
	asl r0L
	asl r0L
	lda r0L
	clc
	adc #20
	sta r4L
	lda #0
	sta r4H
	LoadW r3, 20
	lda #1
	jsr SetPattern
	jmp Rectangle

.segment "DATA"

Buffer:	.byte "dlg", 0
	.res 20

.segment "RODATA"

Icons:	.byte 1
	.word 0
	.byte 0
	.word Pic
	.byte 2, 160, 3, 16
	.word Open

Pic:	.byte 3, $FF, 42, $81, 3, $FF

Box1:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y
	.word T1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word T2
	.byte DBGETSTRING, TXT_LN_X, TXT_LN_3_Y, r5, 12
	.byte OK, DBI_X_0, DBI_Y_2
	.byte CANCEL, DBI_X_2, DBI_Y_2
	.byte 0

Box2:	.byte SET_DB_POS | 2
	.byte 50, 140
	.word 40, 230
	.byte DBVARSTR, 10, 20, r6
	.byte YES, DBI_X_0, 50
	.byte NO, DBI_X_1 + 2, 50
	.byte DBSYSOPV
	.byte 0

Box3:	.byte DEF_DB_POS
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word T3
	.byte OK, DBI_X_1, DBI_Y_2
	.byte 0

T1:	.byte "A dialog box.", 0
T2:	.byte BOLDON, "Bold", PLAINTEXT, " and plain.", 0
T3:	.byte "The third one.", 0
Msg:	.byte "From a register.", 0

.macro EV ef, ex, ey, eb
	.word ef, ex
	.byte ey, eb
.endmacro
.macro KEY ef, code
	.word ef, code
	.byte 0, $80
.endmacro
UiScript:
	EV 0, 30, 170, 0
	EV 10, 30, 168, 1       ; the icon: the first box
	EV 12, 30, 168, 0
	EV 30, 160, 100, 0
	KEY 40, 8               ; a backspace: "dl"
	KEY 44, 'o'
	KEY 48, 'g'
	KEY 52, '!'
	KEY 60, CR              ; Return: closed, result 13; the second box
	EV 90, 300, 190, 1      ; a click outside: closed, result 14; the third
	EV 92, 300, 190, 0
	.word $FFFF, 120
	.byte 0, 0

; the system icons (cards, rows inclusive): boxes 1 and 3 (left card 8, top
; 32), box 2 (left card 5, top 50)
.macro SYSI cx, ry
	.byte cx, cx + 5, ry, ry + 15
.endmacro
UiMask:	SYSI 8 + DBI_X_0, 32 + DBI_Y_2
	SYSI 8 + DBI_X_1, 32 + DBI_Y_2
	SYSI 8 + DBI_X_2, 32 + DBI_Y_2
	SYSI 5 + DBI_X_0, 50 + 50
	SYSI 5 + DBI_X_1 + 2, 50 + 50
	.byte $FF
