; gate term: a player for Veranda Term's test build (tests/term_test.c).
; term_play(script) plays a script from now on: entries of three words,
; frame (from the call), x, y (low byte) | flags << 8: bit 0 the button,
; bit 6 y + 256, bit 7 a key (x is its ISO code, into the keyboard
; queue), bit 5 the end: VRAM dumped (the emulator's -dump) and the
; emulator stopped, bit 4 a wait: the script holds until the byte at
; address x is not 0, then counts its frames from 0 again. Frame $FFFF ends a script (the pointer stays where it
; is, the button up). The positions go through mouseSource as absolute
; ones (as tests/sdk_play.s).
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export _term_play, _term_dump

wp = $AB                        ; (a wait's address)
sp0 = $A9                       ; the script (app-c-ovl.cfg leaves $A9-$D3 to the ROM's maths)

.segment "CODE"

_term_play:
	php
	sei
	sta sp0
	stx sp0+1
	stz frame
	stz frame+1
	LoadW mouseSource, Player
	plp
	rts

_term_dump:
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Player:	IncW frame
@next:	ldy #1
	lda (sp0),y
	cmp #$FF
	bne @1
	dey
	lda (sp0),y
	cmp #$FF
	beq @out                ; the end of the script
@1:	ldy #1                  ; due? (frame <= now)
	lda (sp0),y
	cmp frame+1
	bcc @take
	bne @out
	dey
	lda (sp0),y
	cmp frame
	beq @take
	bcs @out
@take:	ldy #5
	lda (sp0),y
	bit #$20
	bne _term_dump
	bit #$10
	beq @nw
	ldy #2                  ; a wait: the byte at x
	lda (sp0),y
	sta wp
	iny
	lda (sp0),y
	sta wp+1
	lda (wp)
	bne @go
	jmp @out
@go:
	stz frame
	stz frame+1
	bra @adv
@nw:	bit #$80
	bne @key
	and #1
	sta pb
	ldy #2
	lda (sp0),y
	sta px
	iny
	lda (sp0),y
	sta px+1
	iny
	lda (sp0),y
	sta py
	iny
	lda (sp0),y
	and #$40
	asl
	rol
	rol
	sta py+1
	bra @adv
@key:	ldy #2
	lda (sp0),y
	jsr k_kbdbuf_put
@adv:	AddVW 6, sp0
	jmp @next
@out:	MoveW px, r0
	MoveW py, r1
	lda pb
	sec
	rts

.segment "DATA"
frame:	.word 0
px:	.word 320
py:	.word 300
pb:	.byte 0
