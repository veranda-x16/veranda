; gate ui, session "icons": DoIcons, GEOS 64 against Veranda
;
; Three icon slots (the middle one empty: not drawn, not clickable), the
; default ST_FLASH. Every service call draws a small block, the next one
; along: single clicks on row 30, double clicks (r0H = $FF) on row 50;
; otherPressVec (presses and releases off the icons) on row 90. Clicks: a
; single one, a double one (the second press after the first flash, within
; 30 frames), one on the empty slot, one on nothing, and one still
; flashing at the end.

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
	LoadW otherPressVec, Other
	LoadW r0, Icons
	jsr DoIcons
	jmp MainLoop

Serv:	lda #30
	bit r0H
	bpl Block
	lda #50
	jmp Block
Other:	lda #90
; a block at row a, the next column
Block:	sta r2L
	clc
	adc #8
	sta r2H
	lda n
	asl
	asl
	asl
	asl                     ; * 16
	clc
	adc #100
	sta r3L
	lda #0
	adc #0
	sta r3H
	lda r3L
	clc
	adc #10
	sta r4L
	lda r3H
	adc #0
	sta r4H
	inc n
	lda #1
	jsr SetPattern
	jmp Rectangle

.segment "DATA"

n:	.byte 0

.segment "RODATA"

Icons:	.byte 3
	.word 0                 ; the pointer stays
	.byte 0
	.word Pic
	.byte 5, 40, 3, 16
	.word Serv
	.word 0                 ; an empty slot
	.byte 10, 40, 3, 16
	.word Serv
	.word Pic
	.byte 15, 80, 3, 16
	.word Serv

; 3 cards by 16 rows: a frame with a bar
Pic:	.byte 3, $FF
	.repeat 6
	.byte $83, $80, $00, $01
	.endrepeat
	.byte $83, $8F, $FF, $F1
	.repeat 7
	.byte $83, $80, $00, $01
	.endrepeat
	.byte 3, $FF

.macro EV ef, ex, ey, eb
	.word ef, ex
	.byte ey, eb
.endmacro
UiScript:
	EV 0, 160, 120, 0
	EV 10, 50, 48, 1        ; icon 0: a single click
	EV 12, 50, 48, 0
	EV 60, 50, 48, 1        ; a double click
	EV 62, 50, 48, 0
	EV 75, 50, 48, 1
	EV 77, 50, 48, 0
	EV 120, 90, 48, 1       ; the empty slot: otherPressVec (twice)
	EV 122, 90, 48, 0
	EV 140, 300, 150, 1     ; nothing: otherPressVec (twice)
	EV 142, 300, 150, 0
	EV 160, 125, 85, 1      ; icon 2: still flashing at the end
	EV 161, 125, 85, 0
	.word $FFFF, 165
	.byte 0, 0
UiMask:	.byte $FF
