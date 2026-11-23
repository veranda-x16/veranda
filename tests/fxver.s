; gate fx: does the VERA have FX cache writes? DCSEL 63 reads "V", major,
; minor, patch (firmware 0.3.1 or later). Logs "VERA FX YES|NO a.b.c".

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:	lda #63 << 1
	sta VERA_CTRL
	ldx #3
@1:	lda VERA_VERSION,x
	sta ver,x
	dex
	bpl @1
	stz VERA_CTRL
	LoadW r0, Msg
	jsr Out
	lda ver
	cmp #'V'
	bne @no
	lda ver+1
	bne @yes
	lda ver+2
	cmp #3
	bcc @no
	bne @yes
	lda ver+3
	beq @no
@yes:	LoadW r0, Yes
	bra @2
@no:	LoadW r0, No
@2:	jsr Out
	lda ver+1
	jsr PutDec
	lda #'.'
	sta EMU_STDOUT
	lda ver+2
	jsr PutDec
	lda #'.'
	sta EMU_STDOUT
	lda ver+3
	jsr PutDec
	lda #10
	sta EMU_STDOUT
	jmp $FFFF

Out:	ldy #0
@1:	lda (r0),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts

; a as a decimal number
PutDec:	ldx #0
@h:	cmp #100
	bcc @t
	sbc #100
	inx
	bra @h
@t:	pha
	txa
	beq @t0
	ora #'0'
	sta EMU_STDOUT
@t0:	pla
	ldy #0
@u:	cmp #10
	bcc @o
	sbc #10
	iny
	bra @u
@o:	pha
	tya
	bne @p
	cpx #0
	beq @q
@p:	ora #'0'
	sta EMU_STDOUT
@q:	pla
	ora #'0'
	sta EMU_STDOUT
	rts

.segment "RODATA"
Msg:	.byte "VERA FX ", 0
Yes:	.byte "YES ", 0
No:	.byte "NO ", 0

.segment "BSS"
ver:	.res 4
