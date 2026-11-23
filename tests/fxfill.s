; gate fx: fills of every kind, for comparing the FX kernel's screens
; with the plain engine's (-D NOFX): 300 rectangles from a pseudo-random
; sequence (left, width, top, height, pattern, screens), short and long
; spans, edges in mid-card, whole rows; then 200 CopyRects (V80: rows
; through the FX cache; any alignment, overlapping, up and down, either
; screen); then the VRAM dump.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:	LoadW seed, $ACE1
	LoadW n, 300
@r:	jsr Rand                ; left 0-639
	and #3
	sta r3H
	jsr Rand
	sta r3L
	CmpWI r3, 640
	bcc @1
	LoadB r3H, 0
@1:	jsr Rand                ; width 0-511 (+ left, clipped by the kernel)
	and #1
	sta r4H
	jsr Rand
	clc
	adc r3L
	sta r4L
	lda r4H
	adc r3H
	sta r4H
	jsr Rand                ; top 0-255, height 0-255
	sta r11L
	stz r11H
	jsr Rand
	and #1
	beq @2
	inc r11H                ; (top 256-511)
@2:	jsr Rand
	clc
	adc r11L
	sta r12L
	lda r11H
	adc #0
	sta r12H
	jsr Rand                ; one in eight: whole rows
	and #7
	bne @3
	LoadW r3, 0
	LoadW r4, 639
@3:	jsr Rand                ; the screens: 1 fore, 2 back, 3 both
	and #3
	bne @4
	lda #3
@4:	tax
	lda Screens,x
	sta dispBufferOn
	jsr Rand
	and #31
	jsr SetPattern
	jsr WRectangle
	lda n
	bne @5
	dec n+1
@5:	dec n
	lda n
	ora n+1
	beq @c
	jmp @r
@c:	LoadW n, 200            ; CopyRects on the screen
@cr:	jsr Rand
	and #63
	sta r3L                 ; x 0-63, width 1-16: within the row
	jsr Rand
	and #15
	sta r3H
	inc r3H
	jsr Rand
	sta r11L                ; y 0-255, height 1-128, to y 0-255
	stz r11H
	jsr Rand
	and #127
	sta r12L
	stz r12H
	inc r12L
	jsr Rand
	and #63
	sta r4L
	jsr Rand
	and #3                  ; one in four: near the source (overlapping)
	bne @c1
	lda r3L
	clc
	adc #1
	and #63
	sta r4L
	lda r11L
	sta r13L
	jsr Rand
	and #3
	clc
	adc r13L
	sta r13L
	bra @c2
@c1:	jsr Rand
	sta r13L
@c2:	stz r13H
	jsr Rand
	and #3
	bne @c3
	lda #3
@c3:	tax
	lda Screens,x
	sta dispBufferOn
	jsr CopyRect
	lda n
	bne @c4
	dec n+1
@c4:	dec n
	lda n
	ora n+1
	beq @end
	jmp @cr
@end:
	LoadW r0, Done
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; a 16-bit LFSR step; a = the low byte
Rand:	lda seed+1
	lsr
	ror seed
	bcc @1
	eor #$B4
@1:	sta seed+1
	lda seed
	eor seed+1
	rts

.segment "RODATA"
Screens: .byte 0, ST_WR_FORE, ST_WR_BACK, ST_WR_FORE | ST_WR_BACK
Done:	.byte "FXFILL DONE", 0

.segment "BSS"
seed:	.res 2
n:	.res 2
