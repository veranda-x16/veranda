; gate feedback (DECISIONS V51): the pointer's shapes, the beep, blanking.
;
; A monitor in the interrupt (intBotVector, after Veranda's work) counts
; frames and logs a line whenever sprite 0's picture address or size,
; DC_VIDEO, DC_VSTOP (the display window's end, V96), palette entry 0 or
; PSG voice 15 change:
;   "F frame A addr size V dcvideo W vstop P pal0 Q freq vol wave"
; The program (appMain) at its frames:
;   10 SetPointer(PTR_IBEAM), 20 PTR_CROSS, 30 PTR_BUSY (animated),
;   80 PTR_ARROW ("R" and the shape before);
;   90 "SPIN START", a long call: 70 frames without the main loop (the
;      kernel shows the busy pointer by itself), "SPIN END";
;   180 Beep;
;   220 blankDelay = 2 s, "IDLE"; once blanked: 20 frames later a key
;      ('x', must not reach keyVector), "KEY";
;   once awake: "IDLE2"; blanked again: 20 frames later a press through
;      mouseSource at (300, 200) for 10 frames ("PRESS": no click may
;      reach otherPressVec), then 30 frames later a click ("CLICK": it does);
;   then PTR_CROSS, blankDelay 0, 10 frames later the dump and the end.
; keyVector logs "K code", otherPressVec "C mouseData".

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	LoadW keyVector, OnKey
	LoadW otherPressVec, OnPress
	LoadW appMain, Main
	LoadW intBotVector, Monitor
	jmp MainLoop

;---------------------------------------------------------------- the monitor
Monitor:
	IncW frame
	stz VERA_CTRL
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	LoadB VERA_ADDR_M, >VRAM_SPRATTR
	stz VERA_ADDR_L
	lda VERA_DATA0
	sta now
	lda VERA_DATA0
	sta now+1
	LoadB VERA_ADDR_L, <(VRAM_SPRATTR + 7)
	lda VERA_DATA0
	sta now+2
	lda VERA_DC_VIDEO
	and #$7F                ; (bit 7: the current field)
	sta now+3
	LoadB VERA_CTRL, 2      ; DCSEL 1
	lda VERA_DC_VSTOP
	sta now+10
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	lda VERA_DATA0
	sta now+4
	lda VERA_DATA0
	sta now+5
	LoadB VERA_ADDR_L, <(VRAM_PSG + 60)
	LoadB VERA_ADDR_M, >(VRAM_PSG + 60)
	ldx #0
@q:	lda VERA_DATA0
	sta now+6,x
	inx
	cpx #4
	bne @q
	ldx #NOW - 1
@c:	lda now,x
	cmp was,x
	bne @log
	dex
	bpl @c
	rts
@log:	ldx #NOW - 1
@cp:	lda now,x
	sta was,x
	dex
	bpl @cp
	lda #10
	jsr PutC
	lda #'F'
	jsr PutC
	jsr Space
	lda frame+1
	jsr PutHex
	lda frame
	jsr PutHex
	lda #'A'
	jsr Sp
	lda now+1
	jsr PutHex
	lda now
	jsr PutHex
	jsr Space
	lda now+2
	jsr PutHex
	lda #'V'
	jsr Sp
	lda now+3
	jsr PutHex
	lda #'W'
	jsr Sp
	lda now+10
	jsr PutHex
	lda #'P'
	jsr Sp
	lda now+5
	jsr PutHex
	lda now+4
	jsr PutHex
	lda #'Q'
	jsr Sp
	lda now+7
	jsr PutHex
	lda now+6
	jsr PutHex
	jsr Space
	lda now+8
	jsr PutHex
	jsr Space
	lda now+9
	jsr PutHex
	jmp NL
Sp:	pha
	jsr Space
	pla
	jsr PutC
	jmp Space

;---------------------------------------------------------------- the steps
; appMain: the next step when its frame has come
Main:	ldx step
	lda frame+1
	cmp AtH,x
	bcc @r
	bne @go
	lda frame
	cmp AtL,x
	bcc @r
@go:	inc step
	txa
	asl
	tax
	jmp (Steps,x)
@r:	rts

AtL:	.byte <10, <20, <30, <80, <90, <180, <220, $FF
AtH:	.byte >10, >20, >30, >80, >90, >180, >220, $FF
Steps:	.word S1, S2, S3, S4, S5, S6, S7, Wait

S1:	lda #PTR_IBEAM
	jmp SetPointer
S2:	lda #PTR_CROSS
	jmp SetPointer
S3:	lda #PTR_BUSY
	jmp SetPointer
S4:	lda #PTR_ARROW
	jsr SetPointer
	pha
	lda #'R'
	jsr PutC
	jsr Space
	pla
	jsr PutHex
	jmp NL
S5:	LoadW r0, MsgSpin
	jsr LogText
	lda frame               ; 70 frames in here
	clc
	adc #70
	sta kt
@w:	lda frame
	cmp kt
	bne @w
	LoadW r0, MsgSpinEnd
	jmp LogText
S6:	jmp Beep
S7:	LoadW blankDelay, 2
	LoadW r0, MsgIdle
	jsr LogText
	LoadW appMain, Phase2
	stz ph
	rts
Wait:	rts

; blanking: wait for it, a key; again, a press; a click; the end
Phase2:	lda ph
	asl
	tax
	jmp (Ph,x)
Ph:	.word PBlank, PKey, PAwake, PBlank, PPress, PClick, PEnd, Wait

; wait until blanked, then 20 frames
PBlank:	jsr VStop
	bne @r
	lda frame
	clc
	adc #20
	sta kt
	inc ph
@r:	rts
PKey:	lda frame
	cmp kt
	bne @r
	LoadW r0, MsgKey
	jsr LogText
	lda #'x'
	jsr k_kbdbuf_put
	inc ph
@r:	rts
PAwake:	jsr VStop
	beq @r
	LoadW r0, MsgIdle2
	jsr LogText
	inc ph
@r:	rts
PPress:	lda frame
	cmp kt
	bne @r
	LoadW r0, MsgPress
	jsr LogText
	LoadB pb, 1
	lda frame
	clc
	adc #10
	sta kt
	LoadW mouseSource, Source
	inc ph
@r:	rts
PClick:	lda frame
	cmp kt
	bne @r
	stz pb
	lda frame
	clc
	adc #30
	sta kt
	inc ph
@r:	rts
PEnd:	lda frame
	cmp kt
	bne @r
	lda kt+1
	bne @2
	LoadW r0, MsgClick
	jsr LogText
	LoadB pb, 1
	lda frame
	clc
	adc #4
	sta kt
	inc kt+1
	rts
@2:	cmp #1
	bne @3
	stz pb
	lda frame
	clc
	adc #10
	sta kt
	inc kt+1
	lda #PTR_CROSS
	jsr SetPointer
	stz blankDelay
	stz blankDelay+1
	rts
@3:	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@r:	rts

; z set: blanked (DC_VSTOP 0: no active line)
VStop:	LoadB VERA_CTRL, 2
	lda VERA_DC_VSTOP
	stz VERA_CTRL
	tax
	rts

; mouseSource: the pointer at (300, 200), the button pb
Source:	LoadW r0, 300
	LoadW r1, 200
	lda pb
	sec
	rts

;---------------------------------------------------------------- events
OnKey:	lda #'K'
	jsr PutC
	jsr Space
	lda keyData
	jsr PutHex
	jmp NL
OnPress:
	lda #'C'
	jsr PutC
	jsr Space
	lda mouseData
	jsr PutHex
	jmp NL

;---------------------------------------------------------------- the console
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
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra PutC

.segment "DATA"
frame:	.word 0
step:	.byte 0
ph:	.byte 0
kt:	.byte 0, 0
pb:	.byte 0
NOW = 11
now:	.res NOW
was:	.res NOW, $EE

.segment "RODATA"
MsgStart:	.byte "FEEDBACK START", 0
MsgSpin:	.byte "SPIN START", 0
MsgSpinEnd:	.byte "SPIN END", 0
MsgIdle:	.byte "IDLE", 0
MsgKey:		.byte "KEY", 0
MsgIdle2:	.byte "IDLE2", 0
MsgPress:	.byte "PRESS", 0
MsgClick:	.byte "CLICK", 0
MsgDone:	.byte "FEEDBACK DONE", 0
