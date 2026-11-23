; gate ui, session "640" (Veranda only, 640x480; tests/ui.s with -D MODE640):
; an application that draws to the foreground only, so menus and dialog
; boxes come back from the save-under stack. A main menu with a wide sub
; menu below line 255, an icon that opens a dialog box (the default
; position: centred) with a text input. After everything is closed the
; foreground must equal what it was before anything opened
; (tests/check_same.py).

.include "veranda.inc"
.include "macros.inc"

.export UiSession, UiScript, UiMask

.segment "CODE"

UiSession:
	LoadB dispBufferOn, ST_WR_FORE
	lda #2
	jsr SetPattern
	LoadW r3, 0
	LoadW r4, 639
	LoadW r11, 0
	LoadW r12, 479
	jsr WRectangle
	lda #1
	jsr SetPattern
	LoadW r3, 200
	LoadW r4, 260
	LoadW r11, 280
	LoadW r12, 340
	jsr WRectangle          ; something the sub menu covers
	LoadW r0, Title
	LoadW r11, 20
	LoadW r12, 470
	jsr WPutString
	LoadW r0, Icons
	jsr DoIcons
	LoadW r0, MainMenu
	lda #0
	jsr DoMenu
	jmp MainLoop

Open:	LoadW r5, Buffer
	LoadW r0, Box
	jsr DoDlgBox
	rts

Nothing: rts

.segment "DATA"

Buffer:	.byte "640", 0
	.res 16

.segment "RODATA"

Title:	.byte "Veranda 640x480: menus and a dialog box over a foreground-only screen", 0

MainMenu:
	.byte 0, 14
	.word 0, 100
	.byte HORIZONTAL | UN_CONSTRAINED | 2
	.word TFile
	.byte SUB_MENU
	.word Sub
	.word TView
	.byte MENU_ACTION
	.word Nothing

Sub:	.byte <290, <(290 + 3 * 14)
	.word 30, 150
	.byte VERTICAL | UN_CONSTRAINED | WIDE_MENU | 3
	.byte >290, >(290 + 3 * 14)
	.word TA
	.byte MENU_ACTION
	.word Nothing
	.word TB
	.byte MENU_ACTION
	.word Nothing
	.word TC
	.byte MENU_ACTION
	.word Nothing

Icons:	.byte 1
	.word 0
	.byte 0
	.word Pic
	.byte 70, 200, 3, 16
	.word Open
Pic:	.byte 3, $FF, 42, $C3, 3, $FF

Box:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y
	.word TBox
	.byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, 12
	.byte OK, DBI_X_0, DBI_Y_2
	.byte 0

TFile:	.byte "file", 0
TView:	.byte "view", 0
TA:	.byte "far below", 0
TB:	.byte "line 255", 0
TC:	.byte "and more", 0
TBox:	.byte "Centred at 640x480.", 0

; frame, x, y (low byte), flags (bit 0 the button, bit 6 y + 256, bit 7 a key)
.macro EV ef, ex, ey, eb
	.word ef, ex
	.byte <(ey), eb | ((ey) >> 8) << 6
.endmacro
.macro KEY ef, code
	.word ef, code
	.byte 0, $80
.endmacro
UiScript:
	EV 0, 320, 240, 0
	EV 10, 10, 7, 0         ; "file"
	EV 12, 10, 7, 1
	EV 13, 60, 300, 1       ; into the sub menu (y 290-332)
	EV 15, 60, 300, 0
	EV 30, 500, 100, 0      ; out: it closes
	EV 40, 570, 205, 0      ; the icon: the dialog box
	EV 42, 570, 205, 1
	EV 44, 570, 205, 0
	KEY 60, 'x'
	KEY 66, CR              ; closed
	.word $FFFF, 90
	.byte 0, 0
UiMask:	.byte $FF
