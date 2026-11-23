; gate sound (DECISIONS V69): the system sounds' PSG registers, frame by
; frame (TEST.PRG; tools/gate_sound.sh, tests/check_sound.py).
;
; A watch in intFirstVector (it runs first in every interrupt, before
; Veranda's work: it sees what the last interrupt's sound player wrote;
; VERA's control and port 0's address kept) counts frames and logs PSG
; voices 15 and 14 whenever they change:
;   "F frame f15 v15 w15 f14 v14 w14" (hex: the frequency word, the
;   volume byte, the waveform byte)
; and runs the script (steps.inc, tests/sound_script.py) from there, so
; that every line on the console comes from the interrupt:
;   OP_PLAY id   PlaySound(id)            "P frame id"
;   OP_BEEP      Beep                     "P frame 01"
;   OP_PREFS f a the main loop sets the settings (SysPrefs PREFS_GET,
;                byte 6 = f, PREFS_VOLUME = a, PREFS_SET); the script
;                waits for it                    "R frame f a"
;   OP_SENT      voices 14 and 15 set to a sentinel (frequency $1234,
;                volume 0, waveform $3F)  "S frame"
;   OP_WAIT n    n frames
;   OP_WAV       the emulator's WAV recording on ($9FB6 = 1)   "W frame"
;   OP_END       the end (the main loop: the emulator stops)    "E frame"

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

OP_PLAY  = 1
OP_BEEP  = 2
OP_PREFS = 3
OP_SENT  = 4
OP_WAIT  = 5
OP_WAV   = 6
OP_END   = 7

EMU_WAV  = $9FB6
ip       = $50                  ; the script (application zero page)

.segment "CODE"

Start:	ldx #BSS_END - frame - 1
@z:	stz frame,x            ; (a .PRG's variables are not cleared)
	dex
	bpl @z
	ldx #7
	lda #$FF                ; (the first frame logs the voices)
@w:	sta was,x
	dex
	bpl @w
	LoadW ip, Steps
	LoadW appMain, Main
	php
	sei
	LoadW intFirstVector, First
	plp
	jmp MainLoop

;---------------------------------------------------------------- the main loop
Main:	bit busy
	bpl @e
	LoadW r0, buf
	lda #PREFS_GET
	jsr SysPrefs
	lda pFlags
	sta buf + 6
	lda pAtt
	sta buf + PREFS_VOLUME
	LoadW r0, buf
	lda #PREFS_SET
	jsr SysPrefs
	stz busy
@e:	bit endF
	bpl @r
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@r:	rts

;---------------------------------------------------------------- the interrupt
First:	lda VERA_CTRL
	pha
	stz VERA_CTRL
	lda VERA_ADDR_L
	pha
	lda VERA_ADDR_M
	pha
	lda VERA_ADDR_H
	pha
	inc frame
	bne @1
	inc frame+1
@1:	jsr Watch
	jsr Run
	stz VERA_CTRL
	pla
	sta VERA_ADDR_H
	pla
	sta VERA_ADDR_M
	pla
	sta VERA_ADDR_L
	pla
	sta VERA_CTRL
	clc
	rts

; voices 15 and 14 against the last frame's: a line if they changed
Watch:	jsr Psg
	ldx #0
@r:	lda VERA_DATA0          ; (voice 14's 4 bytes, then voice 15's)
	sta now,x
	inx
	cpx #8
	bne @r
	ldx #7
@c:	lda now,x
	cmp was,x
	bne @log
	dex
	bpl @c
	rts
@log:	ldx #7
@cp:	lda now,x
	sta was,x
	dex
	bpl @cp
	lda #'F'
	jsr Head
	ldx #4                  ; voice 15
	jsr Voice
	ldx #0                  ; voice 14
	jsr Voice
	jmp NL
Voice:	lda now+1,x
	jsr PutHex
	lda now,x
	jsr PutHex
	jsr Space
	lda now+2,x
	jsr PutHex
	jsr Space
	lda now+3,x
	jsr PutHex
	jmp Space

Psg:	LoadB VERA_ADDR_L, <(VRAM_PSG + 56)
	LoadB VERA_ADDR_M, >(VRAM_PSG + 56)
	LoadB VERA_ADDR_H, ^VRAM_PSG | VERA_INC1
	rts

; the script's steps due now
Run:	bit endF
	bmi @r
	bit busy
	bmi @r                  ; (the main loop sets the settings)
	lda pLog
	beq @w
	stz pLog
	lda #'R'
	jsr Head
	lda pFlags
	jsr PutHex
	jsr Space
	lda pAtt
	jsr PutHex
	jsr NL
@w:	lda wait
	beq @next
	dec wait
	bne @r
@next:	jsr Byte
	jsr Op
	bcc @next
@r:	rts

; one step (a = its op); c set: the frame's steps end here
Op:	cmp #OP_PLAY
	bne @2
	jsr Byte
	pha
	jsr PlaySound
	pla
@p:	pha
	lda #'P'
	jsr Head
	pla
	jsr PutHex
	jsr NL
	clc
	rts
@2:	cmp #OP_BEEP
	bne @3
	jsr Beep
	lda #SND_ERROR
	bra @p
@3:	cmp #OP_PREFS
	bne @4
	jsr Byte
	sta pFlags
	jsr Byte
	sta pAtt
	LoadB pLog, 1
	LoadB busy, $80
	sec
	rts
@4:	cmp #OP_SENT
	bne @5
	jsr Psg
	ldx #1
@s:	lda #$34
	sta VERA_DATA0
	lda #$12
	sta VERA_DATA0
	stz VERA_DATA0
	lda #$3F
	sta VERA_DATA0
	dex
	bpl @s
	lda #'S'
	jsr Head
	jsr NL
	clc
	rts
@5:	cmp #OP_WAIT
	bne @6
	jsr Byte
	sta wait
	sec
	rts
@6:	cmp #OP_WAV
	bne @7
	LoadB EMU_WAV, 1
	lda #'W'
	jsr Head
	jsr NL
	clc
	rts
@7:	lda #'E'                ; OP_END
	jsr Head
	jsr NL
	LoadB endF, $80
	sec
	rts

Byte:	lda (ip)
	inc ip
	bne @1
	inc ip+1
@1:	rts

; "c frame " (a = c)
Head:	jsr PutC
	jsr Space
	lda frame+1
	jsr PutHex
	lda frame
	jsr PutHex
	jmp Space

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

.segment "RODATA"

Steps:
.include "steps.inc"

.segment "BSS"

frame:	.res 2
now:	.res 8
was:	.res 8
wait:	.res 1
busy:	.res 1
endF:	.res 1
pFlags:	.res 1
pAtt:	.res 1
pLog:	.res 1
buf:	.res PREFS_SIZE
BSS_END:
