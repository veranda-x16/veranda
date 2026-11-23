; gate review (DECISIONS V68): small tests, one TEST.PRG, a line each.
;
;   SPR n lo hi    DrawSprite for sprites 0-7 (picture n: 63 bytes of
;                  n * 37 + 5): the picture address bytes of its
;                  attributes (finding 3); the gate checks sprites 1-7's
;                  pictures in the VRAM dump at those addresses
;   FT name        FindFTypes's list of APPL_DATA files (finding 10;
;                  the gate puts the files there)

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:	; sprites 0-7
	stz n
@s:	lda n                   ; picture n: 63 bytes of n * 37 + 5
	asl
	asl
	asl
	clc
	adc n
	asl
	asl
	clc
	adc n                   ; (n * 37)
	clc
	adc #5
	ldx #62
@pf:	sta Pic,x
	dex
	bpl @pf
	MoveB n, r3L
	LoadW r4, Pic
	jsr DrawSprite
	jsr NL
	lda #'S'
	jsr Put
	lda #'P'
	jsr Put
	lda #'R'
	jsr Put
	lda n
	jsr Hex
	php
	sei
	stz VERA_CTRL
	lda n
	asl
	asl
	asl
	clc
	adc #<VRAM_SPRATTR
	sta VERA_ADDR_L
	lda #>VRAM_SPRATTR
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	lda VERA_DATA0
	sta t
	lda VERA_DATA0
	sta t+1
	plp
	lda t
	jsr Hex
	lda t+1
	jsr Hex
	inc n
	lda n
	cmp #8
	beq @sd
	jmp @s
@sd:	ldx #7                  ; off again, the arrow back
@off:	stx r3L
	phx
	jsr DisablSprite
	plx
	dex
	bne @off
	lda #PTR_ARROW
	jsr SetPointer

	; FindFTypes: APPL_DATA, any class
	LoadW r6, dbFileNames
	LoadB r7L, APPL_DATA
	LoadB r7H, 15
	LoadW r10, 0
	jsr FindFTypes
	lda #15
	sec
	sbc r7H
	sta n
	LoadW a0, dbFileNames
@f:	lda n
	beq @fe
	jsr NL
	lda #'F'
	jsr Put
	lda #'T'
	jsr Put
	lda #' '
	jsr Put
	ldy #0
@c:	lda (a0),y
	beq @c1
	jsr Put
	iny
	bra @c
@c1:	AddVW 17, a0
	dec n
	bra @f
@fe:	jsr NL
	LoadW r0, TDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Put:	sta EMU_STDOUT
	rts
NL:	lda #10
	bra Put
Hex:	pha
	lda #' '
	jsr Put
	pla
	pha
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
t:	.word 0
Pic:	.res 63

.segment "RODATA"

TDone:	.byte "MISC DONE", 0
