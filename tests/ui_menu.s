; gate ui, session "menu": menus on classic tables, GEOS 64 against Veranda
; (tests/check_ui.py). Assembled with -D GEOS64 for GEOS 64.
;
; A gray background on both screens; a horizontal main menu (geos, file,
; edit); "file" opens a vertical sub menu whose "quit" action draws a
; block and goes back to the main menu (the sub menu recovered from the
; back screen); "geos" opens one the pointer then leaves (a fault closes
; it); "edit" is a dynamic sub menu, constrained, still open at the end
; with its parent's item inverted.

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
	LoadB windowTop, 0
	LoadB windowBottom, 199
	LoadW leftMargin, 0
	LoadW rightMargin, 319
	lda #2
	jsr SetPattern
	LoadB r2L, 0
	LoadB r2H, 199
	LoadW r3, 0
	LoadW r4, 319
	jsr Rectangle
	LoadW r0, MainMenu
	lda #0
	jsr DoMenu
	jmp MainLoop

Quit:	lda #1
	jsr SetPattern
	LoadB r2L, 100
	LoadB r2H, 150
	LoadW r3, 200
	LoadW r4, 300
	jsr Rectangle
	jmp GotoFirstMenu

About:	rts

Edit:	LoadW r0, EditMenu      ; a dynamic sub menu: its table in r0
	rts

.segment "RODATA"

MainMenu:
	.byte 0, 14
	.word 0, 120
	.byte HORIZONTAL | UN_CONSTRAINED | 3
	.word TGeos
	.byte SUB_MENU
	.word GeosMenu
	.word TFile
	.byte SUB_MENU
	.word FileMenu
	.word TEdit
	.byte DYN_SUB_MENU
	.word Edit

GeosMenu:
	.byte 14, 14 + 2 * 14
	.word 0, 80
	.byte VERTICAL | UN_CONSTRAINED | 2
	.word TAbout
	.byte MENU_ACTION
	.word About
	.word TInfo
	.byte MENU_ACTION
	.word About

FileMenu:
	.byte 14, 14 + 3 * 14
	.word 30, 100
	.byte VERTICAL | UN_CONSTRAINED | 3
	.word TOpen
	.byte MENU_ACTION
	.word About
	.word TClose
	.byte MENU_ACTION
	.word About
	.word TQuit
	.byte MENU_ACTION
	.word Quit

EditMenu:
	.byte 14, 14 + 3 * 14
	.word 70, 140
	.byte VERTICAL | CONSTRAINED | 3
	.word TCut
	.byte MENU_ACTION
	.word About
	.word TCopy
	.byte MENU_ACTION
	.word About
	.word TPaste
	.byte MENU_ACTION
	.word About

TGeos:	.byte "geos", 0
TFile:	.byte "file", 0
TEdit:	.byte "edit", 0
TAbout:	.byte "about", 0
TInfo:	.byte "info", 0
TOpen:	.byte "open", 0
TClose:	.byte "close", 0
TQuit:	.byte "quit", 0
TCut:	.byte "cut", 0
TCopy:	.byte "copy", 0
TPaste:	.byte "paste", 0

; frame, x, y, flags (bit 0: the button down)
.macro EV ef, ex, ey, eb
	.word ef, ex
	.byte ey, eb
.endmacro
UiScript:
	EV 0, 160, 100, 0
	EV 10, 40, 7, 0         ; on "file"
	EV 12, 40, 7, 1         ; press: its sub menu opens
	EV 13, 50, 22, 1        ; into it
	EV 15, 50, 22, 0
	EV 30, 50, 49, 0        ; on "quit"
	EV 32, 50, 49, 1        ; press: the flash, then Quit
	EV 34, 50, 49, 0
	EV 70, 10, 7, 0         ; on "geos"
	EV 72, 10, 7, 1
	EV 73, 20, 22, 1        ; into its sub menu
	EV 75, 20, 22, 0
	EV 90, 200, 120, 0      ; out of it: a fault closes it
	EV 110, 75, 7, 0        ; on "edit"
	EV 112, 75, 7, 1        ; press: the dynamic sub menu
	EV 113, 80, 30, 1       ; into it (constrained)
	EV 115, 80, 30, 0
	.word $FFFF, 140        ; the end: compared at frame 140
	.byte 0, 0
UiMask:	.byte $FF
