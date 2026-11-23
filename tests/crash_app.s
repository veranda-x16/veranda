; gate crash (DECISIONS V50): an application that crashes; the panic box
; must come, and its OK must lead back to the shell with the kernel banks
; as they were loaded. -D KIND=
;   1  BRK, with a file open for writing, the colour map on and a red ink
;   2  Panic
;   3  the kernel's bank U overwritten with 0, then a call into it (a BRK
;      in the kernel bank)
;   4  a recursion without end (the stack overflows: the interrupt sees it)
;   5  a jump into the RAM after the program (0 since AppReset: a BRK)
; Return is put into the ROM's keyboard queue first: the panic box's OK
; takes it (-D NOKEY: not, for the screenshot, tools/gate_crash.sh).
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export Crash                   ; (its address in the label file)

.segment "CODE"
Start:
	LoadW r0, Msg
	jsr LogText
	lda #KIND + 1
	jsr SetPattern
	LoadW r3, 40
	LoadW r11, 40
	LoadW r4, 599
	LoadW r12, 439
	jsr WRectangle
.if KIND = 1
	LoadW r0, $0FF0         ; paper yellow, ink red, the colour map on
	LoadW r1, $0800
	jsr SetColors
	LoadB r3L, 10
	LoadB r3H, 20
	LoadB r11L, 10
	LoadB r11H, 20
	lda #6
	jsr ColorRect
	LoadW r0, FName         ; a file left open
	lda #'w'
	jsr FOpen
	sta a0L
	LoadW r0, FText
	LoadW r1, FTextEnd - FText
	lda a0L
	jsr FWrite
.endif
.ifndef NOKEY
	lda #13
	jsr k_kbdbuf_put
.endif
.if KIND = 1
Crash:	brk
	.byte 0
.elseif KIND = 2
Crash:	jsr Panic
.elseif KIND = 3
	sec                     ; the kernel banks: right above MEMTOP's copy
	jsr k_memtop            ; (a: the banks below the copy)
	clc
	adc #9 + 2              ; KERNEL_BANKS (9 since V83: bank W), then bank U (the third)
	sta ram_bank
	LoadW r0, 0             ; (MoveData would run in the bank it fills)
	ldy #0
	lda #$A0
	sta a1H
	stz a1L
@z:	lda #0
	sta (a1),y
	iny
	bne @z
	inc a1H
	lda a1H
	cmp #$C0
	bne @z
	lda #1
	sta ram_bank
	LoadW r0, NoIcons
Crash:	jsr DoIcons             ; (bank U: a BRK at its entry)
.elseif KIND = 4
Crash:	jsr Crash
.elseif KIND = 5
Crash:	jmp $7000
.endif
	LoadW r0, MsgBad
	jsr LogText
	jmp EnterDeskTop

.segment "RODATA"
Msg:	.byte 10, "CRASH ", '0' + KIND, " START", 0
MsgBad:	.byte 10, "CRASH DID NOT", 0
FName:	.byte "CRASH.TXT", 0
FText:	.byte "written before the crash", 10
FTextEnd:
NoIcons: .byte 0, 0, 0, 0
