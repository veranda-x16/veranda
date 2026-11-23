; gate term, session aside (DECISIONS V91): a test desktop (SHELL.cvt).
; Veranda Term's test build puts itself aside (TaskCtl TASK_ASIDE) while
; the fake BBS streams to its UART; this desktop then waits 3 seconds
; (the jiffies of the ROM's interrupt handler: with an interrupt nobody
; serves, the machine would crawl and never get there), logs
; "TERMDESK WAITED" and brings the task put aside, Term, back.
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

RDTIM   = $FFDE

.segment "CODE"
	LoadW r0, MStart
	jsr LogText
	jsr RDTIM
	sta t0
@w:	jsr RDTIM
	sec
	sbc t0
	cmp #180
	bcc @w
	LoadW r0, MWaited
	jsr LogText
	stz i                   ; the task put aside (the only one)
@f:	LoadW r0, rec
	ldx i
	lda #TASK_INFO
	jsr TaskCtl
	cmp #0
	bne @r
	inc i
	lda i
	cmp #TASK_MAX
	bne @f
@r:	ldx i
	lda #TASK_RESUME
	jsr TaskCtl
	LoadW r0, MFail         ; (it returns only on an error)
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

.segment "RODATA"
MStart:	.byte "TERMDESK", 0
MWaited: .byte "TERMDESK WAITED", 0
MFail:	.byte "TERMDESK NO RESUME", 0

.segment "BSS"
t0:	.res 1
i:	.res 1
rec:	.res TASK_REC
