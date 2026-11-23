; gate review (DECISIONS V68), finding 8: how long interrupts stay off.
; intFirstVector (called first in every interrupt) reads VERA's scanline:
; the VSYNC interrupt is raised at line 480, so (scanline - 480) mod 525
; is its latency in lines (254 cycles at 8 MHz each). The largest over
; 60 frames idle, then over 40 full-screen fills of both screens (whole
; rows: the FX block path, fb_block): "IRQ idle n fill n" (hex lines).

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:	LoadW intFirstVector, Irq
	; idle: 60 interrupts
@w:	lda count
	cmp #60
	bcc @w
	php
	sei
	MoveW max, idle
	stz max
	stz max+1
	plp
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadB n, 40
@f:	lda n
	and #1
	jsr SetPattern
	LoadW r3, 0
	LoadW r4, 639
	LoadW r11, 0
	LoadW r12, 479
	jsr WRectangle
	dec n
	bne @f
	php
	sei
	MoveW max, fill
	plp
	lda #0                  ; (the high byte first: V41)
	sta intFirstVector+1
	sta intFirstVector
	lda #10
	jsr Put
	ldx #0
@t:	lda TIrq,x
	beq @n
	jsr Put
	inx
	bra @t
@n:	lda idle+1
	jsr Hex
	lda idle
	jsr Hex
	ldx #0
@t2:	lda TFill,x
	beq @n2
	jsr Put
	inx
	bra @t2
@n2:	lda fill+1
	jsr Hex
	lda fill
	jsr Hex
	lda #10
	jsr Put
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; the interrupt, first: the latency of this one; c clear (not ours)
Irq:	lda VERA_IRQ_LINE_L     ; (read: the scanline, bit 8 in IEN bit 6)
	sta d
	lda VERA_IEN
	and #$40
	asl
	asl
	rol
	sta d+1                 ; 0 or 1
	lda d
	sec
	sbc #<480
	sta d
	lda d+1
	sbc #>480
	sta d+1
	bcs @1
	lda d
	clc
	adc #<525
	sta d
	lda d+1
	adc #>525
	sta d+1
@1:	lda max+1               ; max = the larger
	cmp d+1
	bcc @new
	bne @k
	lda max
	cmp d
	bcs @k
@new:	lda d
	sta max
	lda d+1
	sta max+1
@k:	inc count
	bne @r
	dec count
@r:	clc
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

count:	.byte 0
n:	.byte 0
d:	.word 0
max:	.word 0
idle:	.word 0
fill:	.word 0

.segment "RODATA"

TIrq:	.byte "IRQ idle ", 0
TFill:	.byte " fill ", 0
