; gate switch (DECISIONS V83): a test desktop (SHELL.cvt) that drives the
; switcher through TaskCtl, one step each time it starts. Its step is kept
; in the desktop's path (SysPrefs DESK_GET/DESK_SET, byte 60), which the
; kernel keeps across programs and the way back from BASIC.
;
; Each start logs "SWD <step> TASKS <n> FREE <banks> OF <banks>" and the
; tasks ("SWD TASK <i> <name> <banks> <note>"); then:
;   0  start SwOne (its note "one")      6  bring SwOne back: it quits
;   1  start SwTwo                       7  drop SwTwo (TASK_END); start
;   2  start SwPort (record file open)      SwBig: the kernel asks, it quits
;   3  bring SwOne back                  8  bring SwPort back: it quits
;   4  bring SwTwo back                  9  start SwOne again
;   5  bring SwPort back                10  BASIC (keep Veranda), SYS 35328
;                                       11  the end (a VRAM dump)
;
; -D ROOMY (V145, the switcher's Roomy mode): SwBig (-D HUGE: every bank it
; may take) goes to the card, SwOne and SwTwo aside in RAM over its banks;
; bringing SwBig back puts them onto the card first:
;   0  start SwBig                       5  bring SwBig back: it quits
;   1  start SwOne                       6  bring SwOne back: it quits
;   2  start SwTwo                       7  bring SwTwo back
;   3  bring SwBig back                  8  bring SwTwo back: it quits
;   4  bring SwOne back                  9  the end
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

STEPB   = 60

.segment "CODE"
	LoadW r0, desk
	lda #DESK_GET
	jsr SysPrefs
	lda desk + STEPB
	sta step
	inc desk + STEPB
	LoadW r0, desk
	lda #DESK_SET
	jsr SysPrefs
	; "SWD n TASKS c FREE f OF t"
	LoadW r0, sum
	ldx #$FF
	lda #TASK_INFO
	jsr TaskCtl
	ldy #0
	LoadW r0, MSwd
	jsr Cat
	lda step
	jsr Num
	LoadW r0, MTasks
	jsr Cat
	lda sum + TS_COUNT
	jsr Num
	LoadW r0, MFree
	jsr Cat
	lda sum + TS_FREE
	jsr Num
	LoadW r0, MOf
	jsr Cat
	lda sum + TS_BANKS
	jsr Num
	lda sum + TS_ERR
	beq @e
	LoadW r0, MErr
	jsr Cat
	lda sum + TS_ERR
	jsr Num
@e:	jsr Out
	; the tasks
	stz i
@t:	LoadW r0, rec
	ldx i
	lda #TASK_INFO
	jsr TaskCtl
	cmp #0
	beq @tn
	ldy #0
	LoadW r0, MTask
	jsr Cat
	lda i
	jsr Num
	lda #' '
	sta line,y
	iny
	LoadW r0, rec + TR_NAME
	jsr Cat
	lda #' '
	sta line,y
	iny
	lda rec + TR_BANKS
	jsr Num
	lda #' '
	sta line,y
	iny
	LoadW r0, rec + TR_NOTE
	jsr Cat
	jsr Out
@tn:	inc i
	lda i
	cmp #TASK_MAX
	bne @t
	; the step
	lda step
	asl
	tax
	jmp (Steps,x)

.ifdef ROOMY
Steps:	.word R0, R1, R2, R3, R4, R3, R4, R7, R7, S11
R0:	LoadW r6, NBig
	bra Start
R1:	LoadW r6, NOne
	bra Start
R2:	LoadW r6, NTwo
	bra Start
R3:	LoadW r1, NBig
	bra Resume
R4:	LoadW r1, NOne
	bra Resume
R7:	LoadW r1, NTwo
	bra Resume
.else
Steps:	.word S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11
.endif

S0:	LoadW r0, NoteOne
	lda #TASK_NOTE
	jsr TaskCtl
S9:	LoadW r6, NOne
	bra Start
S1:	LoadW r6, NTwo
	bra Start
S2:	LoadW r6, NPort
Start:	stz r0L
	jsr GetFile
	LoadW r0, MFail
	jsr LogText
	jmp Halt
S3:
S6:	LoadW r1, NOne
	bra Resume
S4:	LoadW r1, NTwo
	bra Resume
S5:
S8:	LoadW r1, NPort
Resume:	jsr Find
	lda #TASK_RESUME
	jsr TaskCtl
	LoadW r0, MFail
	jsr LogText
	jmp Halt
S7:	LoadW r1, NTwo
	jsr Find
	lda #TASK_END
	jsr TaskCtl
	LoadW r6, NBig
	bra Start
S10:	LoadW r0, Cmd
	LoadW r1, TOBASIC_KEEP
	jmp ToBASIC
S11:	LoadW r0, MDone
	jsr LogText
Halt:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; x = the task named r1 ($FF: none)
Find:	stz i
@1:	LoadW r0, rec
	ldx i
	lda #TASK_INFO
	jsr TaskCtl
	cmp #0
	beq @n
	ldy #$FF
@c:	iny
	lda (r1),y
	cmp rec + TR_NAME,y
	bne @n
	cmp #0
	bne @c
	ldx i
	rts
@n:	inc i
	lda i
	cmp #TASK_MAX
	bne @1
	ldx #$FF
	rts

; r0's text to line at y
Cat:	lda (r0)
	beq @2
	sta line,y
	iny
	inc r0L
	bne Cat
	inc r0H
	bra Cat
@2:	rts
; a as a decimal number at line,y
Num:	ldx #'0'
@h:	cmp #100
	bcc @h1
	sbc #100
	inx
	bra @h
@h1:	cpx #'0'
	beq @t0
	pha
	txa
	sta line,y
	iny
	pla
	ldx #'0'
@t:	cmp #10
	bcc @t1
	sbc #10
	inx
	bra @t
@t1:	pha
	txa
	sta line,y
	iny
	pla
	bra @o
@t0:	ldx #'0'
@t2:	cmp #10
	bcc @t3
	sbc #10
	inx
	bra @t2
@t3:	cpx #'0'
	beq @o
	pha
	txa
	sta line,y
	iny
	pla
@o:	ora #'0'
	sta line,y
	iny
	rts
Out:	lda #0
	sta line,y
	LoadW r0, line
	jmp LogText

.segment "RODATA"
MSwd:	.byte 10, "SWD ", 0
MTasks:	.byte " TASKS ", 0
MFree:	.byte " FREE ", 0
MOf:	.byte " OF ", 0
MErr:	.byte " ERR ", 0
MTask:	.byte 10, "SWD TASK ", 0
MFail:	.byte 10, "SWD FAILED", 0
MDone:	.byte 10, "SWD DONE", 0
NOne:	.byte "SwOne", 0
NTwo:	.byte "SwTwo", 0
NPort:	.byte "SwPort", 0
NBig:	.byte "SwBig", 0
NoteOne: .byte "one", 0
Cmd:	.byte "SYS35328", 0

.segment "BSS"
step:	.res 1
i:	.res 1
i2:	.res 1
desk:	.res DESK_SIZE
sum:	.res TASK_SUM
rec:	.res TASK_REC
line:	.res 160
