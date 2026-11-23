; gate ui, session "640box" (Veranda only, 640x480; tests/ui.s with
; -D MODE640; DECISIONS V84): an application that draws to the foreground
; only (dispBufferOn = ST_WR_FORE) opens two dialog boxes from icons and
; closes each with Return; after each the foreground must equal what it
; was before (tests/check_same.py), while the box was open it must not.
;   A: Lighthouse Pinball's box (its own position, 160-479 by 140-251,
;      shadow pattern 1): it fits on the save-under stack
;   B: a box of 100-639 by 100-479 (WIDE_DB): 69 cards by 388 rows, more
;      than the stack's 16 KB, its shadow off the screen's right and
;      bottom edges: the kernel keeps what it covers on the back screen,
;      which this program does not use (before V84 the box and its shadow
;      came back from the back screen as it was: noise)
; The back screen is filled with a pattern of its own first, so that a
; recovery from it shows.

.include "veranda.inc"
.include "macros.inc"

.export UiSession, UiScript, UiMask

.segment "CODE"

UiSession:
	LoadB dispBufferOn, ST_WR_BACK  ; the back screen: noise of its own
	lda #7
	jsr SetPattern
	LoadW r3, 0
	LoadW r4, 639
	LoadW r11, 0
	LoadW r12, 479
	jsr WRectangle
	LoadB dispBufferOn, ST_WR_FORE  ; from here the foreground only
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
	LoadW r11, 200
	LoadW r12, 300
	jsr WRectangle          ; something under both boxes
	LoadW r3, 600
	LoadW r4, 639
	LoadW r11, 440
	LoadW r12, 479
	jsr WRectangle          ; the corner under B's shadow
	LoadW r0, Title
	LoadW r11, 20
	LoadW r12, 20
	jsr WPutString
	LoadW r0, Icons
	jsr DoIcons
	jmp MainLoop

OpenA:	LoadW r0, BoxA
	bra Open
OpenB:	LoadW r0, BoxB
Open:	LoadW r5, TA
	LoadW r6, TB
	jmp DoDlgBox

.segment "RODATA"

Title:	.byte "Veranda 640x480: dialog boxes over a foreground-only screen", 0
TA:	.byte "A box over a foreground-only screen.", 0
TB:	.byte "Return closes it.", 0

Icons:	.byte 2
	.word 0
	.byte 0
	.word Pic
	.byte 2, 40, 3, 16
	.word OpenA
	.word Pic
	.byte 8, 40, 3, 16
	.word OpenB
Pic:	.byte 3, $FF, 42, $C3, 3, $FF

BoxA:	.byte 1, 140, 251       ; (Lighthouse Pinball's)
	.word 160, 479
	.byte DBVARSTR, 16, 18, r5
	.byte DBVARSTR, 16, 34, r6
	.byte OK, 15, 88
	.byte 0
BoxB:	.byte WIDE_DB | 1
	.word 100, 479
	.word 100, 639
	.byte DBVARSTR, 16, 18, r5
	.byte DBVARSTR, 16, 34, r6
	.byte OK, 15, 88
	.byte 0

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
	EV 40, 26, 46, 0        ; icon A: box A
	EV 42, 26, 46, 1
	EV 44, 26, 46, 0
	KEY 70, CR              ; closed
	EV 100, 74, 46, 0       ; icon B: box B
	EV 102, 74, 46, 1
	EV 104, 74, 46, 0
	KEY 130, CR             ; closed
	.word $FFFF, 160
	.byte 0, 0
UiMask:	.byte $FF
