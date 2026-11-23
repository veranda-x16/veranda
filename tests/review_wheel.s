; gate review (DECISIONS V68), finding 9: the wheel's steps add up until
; GetMouse. The ROM's mouse_scan adds a packet's wheel step to its
; variable wheel (RAM bank 0, WHEEL: the ROM's kernal.sym, checked by the
; gate) and mouse_get returns it and clears it; the interrupt calls
; mouse_get every frame. Here a step of 1 is put there three times, each
; time waiting until the interrupt took it; then a few frames more and
; GetMouse: "WHEEL x" (3; before the fix the next frame's 0 overwrote
; each step: 0).

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

WHEEL = $A88F

.segment "CODE"

Start:	LoadB n, 3
@s:	php
	sei
	stz ram_bank
	lda #1
	sta WHEEL
	lda #1
	sta ram_bank
	plp
@w:	php                     ; until the interrupt's mouse_get took it
	sei
	stz ram_bank
	ldx WHEEL
	lda #1
	sta ram_bank
	plp
	cpx #0
	bne @w
	jsr Frames
	dec n
	bne @s
	jsr Frames
	jsr GetMouse
	stx n
	lda #10
	jsr Put
	ldx #0
@t:	lda TWheel,x
	beq @n
	jsr Put
	inx
	bra @t
@n:	lda n
	jsr Hex
	lda #10
	jsr Put
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; three frames (random changes every interrupt)
Frames:	ldy #3
@1:	lda random
@2:	cmp random
	beq @2
	dey
	bne @1
	rts

Put:	sta EMU_STDOUT
	rts
Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @n
	pla
	and #$0F
@n:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra Put

.segment "DATA"

n:	.byte 0

.segment "RODATA"

TWheel:	.byte "WHEEL ", 0
