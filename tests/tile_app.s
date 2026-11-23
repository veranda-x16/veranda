; gate tile (DECISIONS V101): a program started from the tile desktop.
;
; It logs "TILEAPP <what> L0 <L0_CONFIG> TB <L0_TILEBASE> PAL <sum>" (the
; sum: palette entries 32-255's 448 bytes added, 16 bits) when it starts
; (START: the shell's tile mode must be off, the rows 2-15 not the
; picture's), after it set entries 100-103 of its own and turned the
; colour map on (SET: a 1 bpp map, $60 / $F4) and, ten main loop passes
; later, quits (EnterDeskTop). -D ASIDE: it asks to be put aside first
; (TaskCtl TASK_ASIDE: the switcher, as Alt + Tab) and logs BACK when it
; runs again, ten passes later quits: its rows must be its own again.
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"
	LoadW r0, MStart
	jsr Show
	stz VERA_CTRL           ; entries 100-103 its own
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 200)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 200)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldx #0
@p:	lda Own,x
	sta VERA_DATA0
	inx
	cpx #8
	bne @p
	LoadB r3L, 0            ; the colour map: rows 2-5 colour 6
	LoadB r3H, 80
	LoadB r11L, 2
	LoadB r11H, 4
	lda #6
	jsr ColorRect
	LoadW r0, MSet
	jsr Show
	LoadW appMain, Main
	rts

Main:	inc passes
	lda passes
	cmp #10
	bne @r
	stz passes
.ifdef ASIDE
	lda state
	bne @back
	inc state
	lda #TASK_ASIDE
	jmp TaskCtl
@back:	LoadW r0, MBack
	jsr Show
.endif
	LoadW r0, MQuit
	jsr LogText
	jmp EnterDeskTop
@r:	rts

; r0's word, then the state, on the console
Show:	ldy #0
@c:	lda (r0),y
	beq @1
	sta line,y
	iny
	bra @c
@1:	ldx #0
@l0:	lda TL0,x
	sta line,y
	iny
	inx
	cpx #4
	bne @l0
	lda VERA_L0_CONFIG
	jsr Hex
	ldx #0
@l1:	lda TTB,x
	sta line,y
	iny
	inx
	cpx #4
	bne @l1
	lda VERA_L0_TILEBASE
	jsr Hex
	ldx #0
@l2:	lda TPal,x
	sta line,y
	iny
	inx
	cpx #5
	bne @l2
	phy
	stz VERA_CTRL           ; entries 32-255
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	stz r2L
	stz r2H
	ldx #224
@s:	lda VERA_DATA0
	jsr Add
	lda VERA_DATA0
	jsr Add
	dex
	bne @s
	ply
	lda r2H
	jsr Hex
	lda r2L
	jsr Hex
	lda #0
	sta line,y
	LoadW r0, line
	jmp LogText
Add:	clc
	adc r2L
	sta r2L
	bcc @r
	inc r2H
@r:	rts
Hex:	pha
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
	sta line,y
	iny
	rts

.segment "RODATA"
Own:	.word $0123, $0456, $0789, $0ABC
MStart:	.byte 10, "TILEAPP START", 0
MSet:	.byte 10, "TILEAPP SET", 0
MBack:	.byte 10, "TILEAPP BACK", 0
MQuit:	.byte 10, "TILEAPP QUIT", 0
TL0:	.byte " L0 "
TTB:	.byte " TB "
TPal:	.byte " PAL "

.segment "DATA"
passes:	.byte 0
state:	.byte 0

.segment "BSS"
line:	.res 64
