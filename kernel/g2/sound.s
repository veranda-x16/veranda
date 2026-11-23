; Veranda bank G2: the system sounds (DECISIONS V69)
;
; PlaySound (resident: it only stores the id in kSndReq; Beep is
; PlaySound(SND_ERROR)) asks; SndStep, in every interrupt (FbIrq, bank G2
; mapped by the resident entry), plays. A sound is one or two tracks of
; notes (tools/mksounds.py: the table, sounds.inc): track A on PSG voice
; 15, track B on voice 14. Every frame of a note writes its voice's
; frequency, volume (both sides) and waveform; the volume decays, the
; frequency slides; the frame after a track's last note writes frequency 0
; and volume 0. Nothing waits in the caller.
;
; kSndReq: 0 nothing; an id (1-127) asked for; $80 a sound playing (the
; request taken). ToBASIC waits for 0. A new sound replaces the one
; playing (both voices silent first), except that nothing replaces the
; alarm. The settings (kPrefs, V56): bit 7 the sounds off (every request
; dropped before any PSG write, but the alarm's), bit 6 the menu ticks on
; (SND_MENU dropped without it); kSndAtt (0-63, from the settings' byte
; 15: kernel/s/prefs.s) is subtracted from every volume but the alarm's
; (down to 0): VERA's volume is logarithmic, 0.5 dB a step, so the
; settings attenuate (V72; V69 multiplied, which on a log scale took
; "half" to -16 dB).
; sndLog keeps the last 16 ids played (for the gates: tools/gate_sound.sh).

.include "kernel.inc"

.export SndStep, sndLog, sndLogN
.import kSndReq, kSndAtt, kPrefs

N_FL   = 0                      ; a note (tools/mksounds.py)
N_WAVE = 2
N_VOL  = 3
N_DEC  = 4
N_LEN  = 5
N_SL   = 6
NOTE   = 8

.segment "BSS"

; per track (x = 0: track A, voice 15; x = 2: track B, voice 14)
tPtr:	.res 4                  ; the note (high byte 0: the track ended)
tLeft:	.res 4                  ; its frames left (0: the next note starts)
tVol:	.res 4                  ; the volume now
tFreq:	.res 4                  ; the frequency now
sndCur:	.res 1                  ; the id playing (0 none)
sndLog:	.res 16                 ; the last ids played
sndLogN: .res 1                 ; how many were (the next one at its low 4 bits)

.segment "CODE"

SndStep:
	lda kSndReq
	beq @r                  ; (most frames)
	bmi @play
	jsr New
@play:	ldx #0
	jsr Track
	ldx #2
	jsr Track
	lda tPtr+1
	ora tPtr+3
	bne @r
	stz sndCur              ; both tracks ended
	stz kSndReq
@r:	rts

; a = the id asked for
New:	tax
	cpx #SND_ALARM
	beq @take               ; (the alarm: always)
	lda sndCur
	cmp #SND_ALARM
	beq @drop               ; (nothing cuts the alarm)
	lda kPrefs
	bmi @drop               ; the sounds off
	asl
	bmi @t                  ; the menu ticks on
	cpx #SND_MENU
	beq @drop
@t:	cpx #SND_COUNT + 1
	bcs @drop
@take:	stx sndCur
	lda sndLogN
	and #15
	tay
	txa
	sta sndLog,y
	inc sndLogN
	asl                     ; the tracks
	asl
	tay
	lda SndTab - 4,y
	sta tPtr
	lda SndTab - 3,y
	sta tPtr+1
	lda SndTab - 2,y
	sta tPtr+2
	lda SndTab - 1,y
	sta tPtr+3
	stz tLeft
	stz tLeft+2
	ldx #0                  ; both voices silent first
	jsr Quiet
	ldx #2
	jsr Quiet
	lda #$80
	sta kSndReq
	rts
@drop:	lda sndCur              ; (what plays goes on)
	beq @0
	lda #$80
@0:	sta kSndReq
	rts

; track x's frame
Track:	lda tPtr+1,x
	bne @1
	rts
@1:	sta kPtr+1
	lda tPtr,x
	sta kPtr
	lda tLeft,x
	bne @run
	ldy #N_LEN              ; the next note
	lda (kPtr),y
	beq @end
	sta tLeft,x
	ldy #N_VOL
	lda (kPtr),y
	sta tVol,x
	ldy #N_FL
	lda (kPtr),y
	sta tFreq,x
	iny
	lda (kPtr),y
	sta tFreq+1,x
@run:	jsr Voice
	lda tFreq,x
	sta VERA_DATA0
	lda tFreq+1,x
	sta VERA_DATA0
	lda tVol,x
	jsr Scale
	ora #$C0                ; both sides
	sta VERA_DATA0
	ldy #N_WAVE
	lda (kPtr),y
	sta VERA_DATA0
	; the envelope: the volume down by the decay (to 0), the slide
	lda tVol,x
	ldy #N_DEC
	sec
	sbc (kPtr),y
	bcs @d
	lda #0
@d:	sta tVol,x
	ldy #N_SL
	lda tFreq,x
	clc
	adc (kPtr),y
	sta tFreq,x
	iny
	lda tFreq+1,x
	adc (kPtr),y
	sta tFreq+1,x
	dec tLeft,x
	bne @r
	lda kPtr                ; its last frame: the next note
	clc
	adc #NOTE
	sta tPtr,x
	lda kPtr+1
	adc #0
	sta tPtr+1,x
@r:	rts
@end:	stz tPtr+1,x
	; (falls into Quiet)

; voice x: frequency 0, volume 0
Quiet:	jsr Voice
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	rts

; a = the volume less kSndAtt, at least 0 (the alarm's: a); x kept
Scale:	ldy sndCur
	cpy #SND_ALARM
	beq @r
	sec
	sbc kSndAtt
	bcs @r
	lda #0
@r:	rts

; VERA's port 0 at voice x's registers (x = 0: voice 15, 2: voice 14)
Voice:	stz VERA_CTRL
	lda VoiceL,x
	sta VERA_ADDR_L
	LoadB VERA_ADDR_M, >(VRAM_PSG + 56)
	LoadB VERA_ADDR_H, ^VRAM_PSG | VERA_INC1
	rts

.assert >(VRAM_PSG + 56) = >(VRAM_PSG + 63), error, "sound.s: voices 14 and 15 in one page"

.segment "RODATA"

VoiceL:	.byte <(VRAM_PSG + 60), 0, <(VRAM_PSG + 56)

.include "sounds.inc"
