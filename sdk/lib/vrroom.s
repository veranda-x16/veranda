; Veranda SDK: vr_room (vr.h, DECISIONS V145), the RAM banks a program
; may still take with BankAlloc and be put aside by the switcher
; (TaskCtl TASK_ROOM): in Fast mode the free banks less the desktop's
; reserve, in Roomy mode (programs aside onto the card) nearly all.
; On a kernel without TASK_ROOM (before API 7's switcher): $FF, unknown.
;
;   unsigned char vr_room(void);
;
; MIT licence (see LICENSE).

.include "veranda.inc"

.export _vr_room

.segment "CODE"

_vr_room:
	lda #TASK_ROOM
	jsr TaskCtl
	cpx #0
	beq @r
	lda #$FF
@r:	ldx #0
	rts
