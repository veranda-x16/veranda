; gate boot: the kernel starts this as TEST.PRG; it draws, says so on the
; emulator's console and quits to BASIC with "PRINT 6*7" typed

.include "veranda.inc"
.include "macros.inc"

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	jsr GetVersion
	cmp #API_LEVEL
	bne @bad
	lda #2
	jsr SetPattern
	LoadW r3, 100
	LoadW r11, 100
	LoadW r4, 539
	LoadW r12, 379
	jsr WRectangle
	LoadW r0, MsgDrawn
	jsr LogText
	LoadW r0, Cmd
	jmp ToBASIC
@bad:	LoadW r0, MsgBad
	jsr LogText
	LoadW r0, 0
	jmp ToBASIC

.segment "RODATA"

MsgStart:	.byte "BOOT START", 0
MsgDrawn:	.byte "BOOT DRAWN", 0
MsgBad:		.byte "BOOT BAD VERSION", 0
Cmd:		.byte "PRINT 6*7", 0
