; gate input (phase 3): the main loop's events, in order
;
; A scripted mouse (mouseSource) moves the pointer, clicks, and pushes it
; out of its region on the right and at the top; three processes (one
; freezes itself after two runs, one types two keys into the ROM's
; keyboard queue, one ends the test); a routine sleeps. Every event is a
; line on the console; tests/check_input.py compares them with the
; expected ones and the pointer sprite's attributes with the position.
;
; Frames (the script's count, from its first call):
;   1-10   x += 10            the pointer 320 -> 420
;   12, 14 button down, up    "D 01A4 00F0", "U 01A4 00F0"
;   16-25  x += 20            right edge 539 from frame 21: "F 10"
;   70     y -= 300           top edge 50: "F 80"
; processes: Tick every 33 ("T1", "T2", then frozen), Keys at 45 ("K 61",
; "K 0D", then API 2's keys), Keys2 at 50 (Backspace, left, right), Ctrl at 55 (Ctrl+A, Ctrl+B), Finish at 110 ("E 021B 0032 32"); Sleep 60 ("W").

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	; the region
	LoadW r3, 100
	LoadW r11, 50
	LoadW r4, 539
	LoadW r12, 429
	jsr WSetMouseRegion
	; the vectors
	LoadW keyVector, OnKey
	LoadW otherPressVec, OnPress
	LoadW mouseVector, OnMouse      ; (it passes the changes on: DefMouse)
	LoadW mouseFaultVec, OnFault
	; the processes
	LoadW r0, Procs
	lda #5
	jsr InitProcesses
	ldx #0
	jsr RestartProcess
	ldx #1
	jsr RestartProcess
	ldx #2
	jsr RestartProcess
	ldx #3
	jsr RestartProcess
	ldx #4
	jsr RestartProcess
	; the mouse script
	LoadW mouseSource, Script
	jsr Nap                 ; returns at once; "W" 60 frames later
	jmp MainLoop

Nap:	LoadW r0, 60
	jsr Sleep               ; back to Start; the rest from the main loop
	lda #'W'
	jsr PutC
	jmp NL

; a key
OnKey:	lda #'K'
	jsr PutC
	jsr Space
	lda keyData
	jsr PutHex
	jsr Space
	lda keyDataMods
	jsr PutHex
	lda keyDataMods         ; Ctrl + B: the last key with Ctrl; let go
	beq @n
	lda keyData
	cmp #2
	bne @n
	lda #0
	jsr Shflag
@n:	jmp NL

; the ROM's modifier keys (shflag in RAM bank 0: 4 = Ctrl), as if held
SHFLAG = $A80C                  ; (this ROM's kernal.sym; tools/gate.sh checks)
Shflag:	ldx ram_bank
	stz ram_bank
	sta SHFLAG
	stx ram_bank
	rts

; a button change (presses and releases)
; a button change through the program's mouseVector: "M", then the
; system's handling (DefMouse: no menu or icon here, so otherPressVec)
OnMouse:
	lda #'M'
	jsr PutC
	jsr NL
	jmp DefMouse

OnPress:
	lda #'D'
	bit mouseData
	bpl @1
	lda #'U'
@1:	jsr PutC
	jsr Space
	lda mouseXPos+1
	jsr PutHex
	lda mouseXPos
	jsr PutHex
	jsr Space
	lda mouseYPosW+1
	jsr PutHex
	lda mouseYPosW
	jsr PutHex
	jmp NL

; the pointer left its region: a line when the bits change
OnFault:
	lda faultData
	cmp lastFault
	beq @r
	sta lastFault
	lda #'F'
	jsr PutC
	jsr Space
	lda faultData
	jsr PutHex
	jsr NL
@r:	rts

Tick:	inc ticks
	lda #'T'
	jsr PutC
	lda ticks
	ora #'0'
	jsr PutC
	jsr NL
	lda ticks
	cmp #2
	bcc @r
	ldx #0
	jsr FreezeProcess
@r:	rts

Keys:	ldx #1
	jsr FreezeProcess
	lda #'a'
	jsr k_kbdbuf_put
	lda #$0D
	jsr k_kbdbuf_put
	; API 2: PgUp, PgDn, End, F9-F12 (the codes of Ctrl + B, D, P, U, V,
	; W), F1, Backspace, left and right (KEYM_ARROW)
	ldx #0
@k:	lda IsoKeys,x
	phx
	jsr k_kbdbuf_put
	plx
	inx
	cpx #IsoEnd - IsoKeys
	bne @k
	rts
IsoKeys: .byte $82, $02, $04, $10, $15, $16, $17, $85
IsoEnd:

; (the ROM's queue holds 10 keys) Backspace, left, right
Keys2:	ldx #4
	jsr FreezeProcess
	lda #$14
	jsr k_kbdbuf_put
	lda #$9D
	jsr k_kbdbuf_put
	lda #$1D
	jmp k_kbdbuf_put

; Ctrl held: Ctrl + A and Ctrl + B (the codes of F1's GEOS code and PgDn)
Ctrl:	ldx #3
	jsr FreezeProcess
	lda #4
	jsr Shflag
	lda #$01
	jsr k_kbdbuf_put
	lda #$02
	jmp k_kbdbuf_put

Finish:	lda #'E'
	jsr PutC
	jsr Space
	lda mouseXPos+1
	jsr PutHex
	lda mouseXPos
	jsr PutHex
	jsr Space
	lda mouseYPosW+1
	jsr PutHex
	lda mouseYPosW
	jsr PutHex
	jsr Space
	lda mouseYPos
	jsr PutHex
	jsr NL
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; mouseSource (in the interrupt, every frame): r0 = x, r1 = y, a = buttons
Script:
	inc frame
	lda frame
	cmp #11
	bcs @b
	AddVW 10, devX          ; 1-10
	bra @out
@b:	cmp #12
	bne @b1
	LoadB btn, 1
	bra @out
@b1:	cmp #14
	bne @c
	stz btn
	bra @out
@c:	cmp #16
	bcc @out
	cmp #26
	bcs @d
	AddVW 20, devX          ; 16-25
	bra @out
@d:	cmp #70
	bne @out
	lda devY
	sec
	sbc #<300
	sta devY
	lda devY+1
	sbc #>300
	sta devY+1
@out:	MoveW devX, r0
	MoveW devY, r1
	lda btn
	clc                     ; relative
	rts

PutC:	sta EMU_STDOUT
	rts
Space:	lda #' '
	bra PutC
NL:	lda #10
	bra PutC
PutHex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @n
	pla
	and #$0F
@n:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra PutC

.segment "DATA"

frame:		.byte $FF               ; (the first call, a new source's start, makes it 0)
devX:		.word 1000
devY:		.word 1000
btn:		.byte 0
ticks:		.byte 0
lastFault:	.byte 0

.segment "RODATA"

Procs:	.word Tick, 33
	.word Keys, 45
	.word Finish, 110
	.word Ctrl, 55
	.word Keys2, 50
MsgStart:	.byte "INPUT START", 0
MsgDone:	.byte "INPUT DONE", 0
