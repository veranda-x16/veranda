; Veranda resident core: small calls that need no bank

.include "kernel.inc"

.export k_Unsupported, k_GetVersion, k_LogText, IsEmu, kNotEmu, LogStr, LogNL, k_DrawLine, k_DrawPoint

VERSION_MAJOR = 0
VERSION_MINOR = 1

.segment "CODE"

; a dropped GEOS call (docs/API.md): x = UNSUPPORTED, c set
k_Unsupported:
	ldx #UNSUPPORTED
	sec
	rts

; a = API level, x.y = the version
k_GetVersion:
	lda #API_LEVEL
	ldx #VERSION_MAJOR
	ldy #VERSION_MINOR
	rts

; r0 = a 0-terminated string: a line on the emulator's console
k_LogText:
	jsr IsEmu
	bne @r
	ldx r0L
	ldy r0H
	jsr LogStr
	bra LogNL
@r:	rts

; z set when running in x16emu (a destroyed): bank S's EmuCheck read the
; emulator's detection bytes once, at the start (V106: on hardware
; $9FB0-$9FBF is an expansion card's, IO5; nothing else of it is touched
; there, and not even that later); kNotEmu 0 in x16emu
IsEmu:	lda kNotEmu
	rts

.segment "DATA"
kNotEmu: .byte 1
.segment "CODE"

; x/y = string (low/high): to the console (destroys a, y, kPtr)
LogStr:
	stx kPtr
	sty kPtr+1
	ldy #0
@1:	lda (kPtr),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts

LogNL:
	lda #10
	sta EMU_STDOUT
	rts

; the classic calls that take flags: N set recover, else C set ink, C clear
; paper. The flags would not survive the bank gate: a = the wide mode.
k_DrawLine:
	jsr FlagMode
	FARCALL DrawLineA
	rts
k_DrawPoint:
	jsr FlagMode
	FARCALL DrawPointA
	rts
FlagMode:
	php
	pla
	bmi @rec
	and #1                  ; DRAW_INK or DRAW_ERASE
	rts
@rec:	lda #DRAW_RECOVER
	rts
