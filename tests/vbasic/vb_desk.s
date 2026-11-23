; gate vb_core: a test desktop (SHELL.cvt) for the program put aside in
; the middle of a loop (VBTEST.LST "!aside n NAME"): when it starts it
; logs "DESK RESUME <task> <name>" and brings the first task put aside
; back (TaskCtl TASK_RESUME); with none aside it logs "DESK NONE" and the
; emulator stops.
; MIT licence (LICENSE).
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"
	stz i
@t:	LoadW r0, rec
	ldx i
	lda #TASK_INFO
	jsr TaskCtl
	cmp #TASK_ASIDE
	beq @found
	inc i
	lda i
	cmp #TASK_MAX
	bne @t
	ldx #0
@n:	lda MNone,x
	beq @nd
	sta EMU_STDOUT
	inx
	bra @n
@nd:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@found:	ldx #0
@m:	lda MResume,x
	beq @md
	sta EMU_STDOUT
	inx
	bra @m
@md:	lda i
	ora #'0'
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	ldx #0
@nm:	lda rec + TR_NAME,x
	beq @ne
	sta EMU_STDOUT
	inx
	cpx #16
	bne @nm
@ne:	lda #10
	sta EMU_STDOUT
	ldx i
	lda #TASK_RESUME
	jsr TaskCtl
	ldx #0
@f:	lda MFail,x
	beq @fd
	sta EMU_STDOUT
	inx
	bra @f
@fd:	jmp $FFFF

.segment "RODATA"
MNone:	.byte "DESK NONE", 10, 0
MResume: .byte "DESK RESUME ", 0
MFail:	.byte "DESK RESUME FAILED", 10, 0

.segment "BSS"
i:	.res 1
rec:	.res TASK_REC
