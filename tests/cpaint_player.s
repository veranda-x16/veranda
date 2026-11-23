; gate cpaint (V171): cp_play(script, bank), tests/sdk_play.s's player
; with its script at $A000 of RAM bank `bank` (Colour Paint's test build:
; overlay 6; main RAM is full), mapped while it reads; otherwise as
; sdk_play.s. gate sdk's vr_play(script) for C test programs: the script (tests/check_ui.py's
; format: frame, x, y, flags (bit 0 the button, bit 6 y + 256); $FFFF ends
; it with the last frame) played
; through mouseSource with absolute positions, keys into the keyboard
; queue; at the last frame a VRAM dump and the end
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export _cp_play
.import popa, popax

.segment "CODE"

; cp_play(script, bank)
_cp_play:
	sta sbank
	jsr popax
	sta a0
	stx a0+1
	lda $00
	pha
	lda sbank
	sta $00
	MoveW a0, a1            ; the end frame
@e:	ldy #0
	lda (a1),y
	iny
	and (a1),y
	cmp #$FF
	beq @e1
	AddVW 6, a1
	bra @e
@e1:	iny
	lda (a1),y
	sta endF
	iny
	lda (a1),y
	sta endF+1
	pla
	sta $00
	LoadW mouseSource, Player
	rts

Player:	lda $00
	pha
	lda sbank
	sta $00
	jsr Play
	tax                     ; (a: the buttons; c kept)
	pla
	sta $00
	txa
	rts
Play:	IncW frame
	lda frame
	cmp endF
	bne @next
	lda frame+1
	cmp endF+1
	bne @next
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@next:	ldy #0
	lda (a0),y
	tax
	iny
	lda (a0),y
	cmp #$FF
	beq @out
	cmp frame+1
	bcc @take
	bne @out
	cpx frame
	beq @take
	bcs @out
@take:	ldy #5
	lda (a0),y
	bmi @key
	and #1
	sta pb
	ldy #2
	lda (a0),y
	sta px
	iny
	lda (a0),y
	sta px+1
	iny
	lda (a0),y
	sta py
	iny
	lda (a0),y              ; flags bit 6: y + 256
	and #$40
	asl
	rol
	rol
	sta py+1
	bra @adv
@key:	ldy #2
	lda (a0),y
	jsr k_kbdbuf_put
@adv:
	AddVW 6, a0
	bra @next
@out:
	MoveW px, r0
	MoveW py, r1
	lda pb
	sec
	rts

.segment "DATA"
sbank:	.byte 0
endF:	.word 0
frame:	.word $FFFF
px:	.word 320
py:	.word 240
pb:	.byte 0
