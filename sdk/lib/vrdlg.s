; Veranda SDK: vr_dlgbox (vr.h), DoDlgBox for a box whose C routines
; (its DB_USR_ROUT, keyVector, otherPressVec ...) may close it with
; RstrFrmDialogue. That call returns from DoDlgBox from inside the C
; routine's frame: the 6502 stack is put back by the kernel, cc65's C
; stack pointer (c_sp) is not; this keeps it on the 6502 stack around the
; call and puts it back. (In C, an asm("sta c_sp") after the call is
; removed by cc65's optimizer: it must be here.) cc65's register variables
; (regbank, 6 bytes: --register-vars) are kept the same way (V68).
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.importzp c_sp, regbank
.export _vr_dlgbox

.segment "CODE"

; a/x = the box; a = DoDlgBox's result (r0L)
_vr_dlgbox:
	sta r0L
	stx r0H
	lda c_sp
	pha
	lda c_sp+1
	pha
	ldx #5
@s:	lda regbank,x
	pha
	dex
	bpl @s
	jsr DoDlgBox
	ldx #0
@r:	pla
	sta regbank,x
	inx
	cpx #6
	bne @r
	pla
	sta c_sp+1
	pla
	sta c_sp
	lda r0L
	ldx #0
	rts
