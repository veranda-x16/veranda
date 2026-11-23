; gate ui (phase 4), Veranda's side: a session (tests/ui_*.s) in the
; 320x240 mode; its script (UiScript, see tests/check_ui.py) played through
; mouseSource with absolute positions, keys into the ROM's keyboard queue;
; at the script's last frame "UI DONE" and a VRAM dump

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.import UiSession, UiScript
.export UiFrame                 ; (the frame: tests/review_flash.s)

.segment "CODE"

Start:
.ifdef MODE640
	lda #MODE_640x480
.else
	lda #MODE_320x240
.endif
	jsr SetVideoMode
	LoadW a0, UiScript
	ldy #2                  ; the first entry's position: the pointer's start
	jsr Pos
	; the end frame: the table's last entry ($FFFF, the frame)
	MoveW a0, a1
@end:	ldy #0
	lda (a1),y
	iny
	and (a1),y
	cmp #$FF
	beq @e1
	AddVW 6, a1
	bra @end
@e1:	iny
	lda (a1),y
	sta endF
	iny
	lda (a1),y
	sta endF+1
	LoadW mouseSource, Player
	jmp UiSession

; px, py = the entry's position (flags bit 6: y + 256)
Pos:	ldy #2
	lda (a0),y
	sta px
	iny
	lda (a0),y
	sta px+1
	iny
	lda (a0),y
	sta py
	iny
	lda (a0),y
	and #$40
	asl
	rol
	rol
	sta py+1
	rts

; mouseSource, every frame (in the interrupt)
Player:
	IncW frame
	lda frame
	cmp endF
	bne @next
	lda frame+1
	cmp endF+1
	bne @next
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@next:	ldy #0                  ; entries whose frame has come
	lda (a0),y
	tax
	iny
	lda (a0),y
	cmp #$FF
	bne @e
	cpx #$FF
	bne @e
	bra @out                ; (the end: above)
@e:	cmp frame+1             ; entry frame (x low, a high) <= frame?
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
	jsr Pos
	bra @adv
@key:	ldy #2
	lda (a0),y
	jsr k_kbdbuf_put
@adv:	AddVW 6, a0
	bra @next
@out:	MoveW px, r0
	MoveW py, r1
	lda pb
	sec                     ; absolute
	rts

.segment "DATA"

endF:	.word 0
UiFrame:
frame:	.word $FFFF             ; (the first call: frame 0)
px:	.word 0
py:	.word 0
pb:	.byte 0

.segment "RODATA"

MsgDone:	.byte "UI DONE", 0
