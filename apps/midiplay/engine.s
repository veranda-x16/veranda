; engine.s -- MIDI Player (apps/midiplay; DECISIONS V205): the two engines
; under Veranda, in main RAM.
;
;   MIDI: Melodius's engine (vendor/melodius/midi.s, math.s), its notes on
;         the YM2151 through the ROM's audio calls (ROM bank $0A: GM
;         patches and drums by number);
;   ZSM:  ZSMKit v3 (vendor/zsmkit), run in place in overlays 2 and 3 (two
;         adjacent RAM banks: zsm_bank, zsm_bank + 1), priority 0.
;
; The tick: intTopVector (Veranda calls it in every interrupt, 60 a second,
; with the interrupt off and appBank mapped; the kernel puts the RAM bank
; back after). It maps what the engine needs and calls one tick; the
; frame counter counts the ticks played.
;
; ROM bank $0A (audio) has no interrupt vectors in R49 (its $FFFA-$FFFF
; are $AA): it is mapped only with the interrupt off. Every call from the
; main loop below runs with the interrupt off (php, sei ... plp), so the
; engines' own short windows (ZSMKit's _zsm_stop maps the bank before its
; sei) are covered too; neither engine has a cli.
;
; Zero page: Melodius's midizp (2 bytes, cc65's ZEROPAGE segment: $50-$7F);
; ZSMKit's PTR is $02-$03 (r0), which it saves and puts back; the ROM's
; audio calls use $A7-$A8 (the KERNAL's, kept for them).
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.include "vendor/zsmkit/src/zsmkit.inc"

.import midi_init, midi_parse, midi_play, midi_playtick, midi_restart
.import midi_is_playing, midi_stop, midi_set_master
.import midi_ntracks, midi_trk_startbank, midi_trk_startL, midi_trk_startH
.import midi_trk_curbank, midi_trk_curL, midi_trk_curH
.import lyrics, midi_format, midi_tempo, midibeat, midimeasure
.import midi_timesig_numerator, midi_timesig_denominator
; (Melodius's state, by C's names)
_lyrics = lyrics
_midi_format = midi_format
_midi_ntracks = midi_ntracks
_midi_tempo = midi_tempo
_midibeat = midibeat
_midimeasure = midimeasure
_midi_timesig_numerator = midi_timesig_numerator
_midi_timesig_denominator = midi_timesig_denominator
.export _lyrics, _midi_format, _midi_ntracks, _midi_tempo, _midibeat, _midimeasure
.export _midi_timesig_numerator, _midi_timesig_denominator
; (V206: what the keyboard and the meters read: each YM channel's note, 0
; released; its patch, $FF a drum; its MIDI channel; its attenuation; its
; calls since the note changed; each MIDI channel's program and its note-on
; mark, which the window clears)
.import ymnote, yminst, ymmidi, ymatten, midiinst, midi_msg_sent, midi_ym_callcnt
_ymnote = ymnote
_yminst = yminst
_ymmidi = ymmidi
_ymatten = ymatten
_midiinst = midiinst
_midi_msg_sent = midi_msg_sent
_midi_ym_callcnt = midi_ym_callcnt
.export _ymnote, _yminst, _ymmidi, _ymatten, _midiinst, _midi_msg_sent, _midi_ym_callcnt
.ifdef MP_TEST
.import midi_note_iter
.endif

.export _eng_ticks
.export _eng_mode, _eng_run, _eng_frames, _zsm_bank, _eng_loops
.export _eng_init, _eng_irq_on, _eng_irq_off
.export _eng_midi_load, _eng_zsm_load, _eng_go, _eng_pause, _eng_stop, _eng_rewind
.export _eng_silence, _eng_zsm_state, _eng_midi_playing, _eng_volume, _eng_voices
.export _eng_zsm_pos, _eng_midi_pos
.export _far_call, _far_bank, _eng_peek, _peek_bank, _peek_src, _peek_n, _eng_zsm_ym, _eng_psg
.importzp sreg, ptr1, ptr2

.ifdef MP_TEST
.export _t_cyc_max, _t_cyc_sum, _t_ticks, _t_gap_max, _t_log, _t_log_head
.export t_ym_playnote, t_ym_playdrum, t_ym_release
LOGN = 32                       ; the event log: 8 bytes an event (a ring in one page)
.endif

ROMB    = $01
RAMB    = $00
YM_INIT = $C063                 ; the ROM's audio calls (bank $0A)
VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
VERA_CTRL   = $9F25
AUDIO_CTRL  = $9F3B
AUDIO_RATE  = $9F3C

M_MIDI = 1
M_ZSM  = 2

.segment "BSS"
_eng_mode:	.res 1
_eng_run:	.res 1
_eng_frames:	.res 2
_eng_ticks:	.res 2
_zsm_bank:	.res 1
_eng_loops:	.res 2
lowram:		.res 256        ; ZSMKit's low RAM (its trampolines, PCM feeding)
ksptr:		.res 2          ; ZSMKit's key-on shadow (priority 0), in its bank
osptr:		.res 2          ; its YM2151 register shadow (V206: the notes shown)
_far_bank:	.res 1          ; far: the bank to map
_peek_bank:	.res 1          ; eng_peek: from this bank ...
_peek_src:	.res 2          ; ... this address ...
_peek_n:	.res 1          ; ... this many bytes
bankkeep:	.res 1
songbank:	.res 1
.ifdef MP_TEST
_t_cyc_max:	.res 4          ; a tick's cycles (the emulator's counter, $9FB8)
_t_cyc_sum:	.res 4
_t_ticks:	.res 4
_t_gap_max:	.res 4          ; the most cycles between two ticks
t_last:		.res 4
t_c0:		.res 4
_t_log_head:	.res 1
_t_log:		.res LOGN * 8   ; kind, channel, note, the frame (2 bytes)
t_kon:		.res 8          ; ZSM: the key-on shadow as last logged
t_psg:		.res 1          ; ZSM: PSG voice 0's volume as last logged
t_fresh:	.res 1
.endif

.segment "CODE"

;---------------------------------------------------------------- set-up
; void eng_init(void): ZSMKit's engine (it resets the YM2151 and the PSG:
; the ROM's audio_init), the MIDI engine
_eng_init:
	php
	sei
	lda RAMB
	pha
	lda _zsm_bank
	sta RAMB
	ldx #<lowram
	ldy #>lowram
	jsr zsm_init_engine
	pla
	sta RAMB
	jsr midi_init
	stz _eng_mode
	stz _eng_run
	plp
	rts

_eng_irq_on:
	php
	sei
.ifdef MP_TEST
	lda #1                  ; (the first tick measures no gap: the hook was off)
	sta t_fresh
.endif
	lda #<Tick
	sta intTopVector
	lda #>Tick
	sta intTopVector+1
	plp
	rts

_eng_irq_off:
	php
	sei
	stz intTopVector
	stz intTopVector+1
	plp
	rts

;---------------------------------------------------------------- the tick
Tick:
	inc _eng_ticks
	bne @t
	inc _eng_ticks+1
@t:
.ifdef MP_TEST
	jsr TStart
.endif
	lda _eng_run
	beq @r
	lda ROMB
	pha
	lda _eng_mode
	cmp #M_MIDI
	bne @z
	lda #$0A
	sta ROMB
	jsr midi_playtick
	bra @c
@z:	lda _zsm_bank
	sta RAMB
	lda #0                  ; (music and PCM)
	jsr zsm_tick
.ifdef MP_TEST
	jsr TKon
.endif
@c:	pla
	sta ROMB
	inc _eng_frames
	bne @r
	inc _eng_frames+1
@r:
.ifdef MP_TEST
	jmp TEnd
.else
	rts
.endif

;---------------------------------------------------------------- MIDI
; unsigned char eng_midi_load(unsigned char bank): the file at $A000 of
; bank (the banks after it hold the rest): 0, else 1 (not a MIDI file the
; engine plays: format 0 or 1, up to 32 tracks, ticks per quarter note)
_eng_midi_load:
	php
	sei
	sta songbank
	ldx RAMB
	stx bankkeep
	stz _eng_run
	ldx #$00
	ldy #$A0
	jsr midi_parse
	bcs @err
	jsr midi_restart
	lda #M_MIDI
	sta _eng_mode
	lda #0
	bra @x
@err:	stz _eng_mode
	lda #1
@x:	ldx bankkeep
	stx RAMB
	plp
	ldx #0
	rts

;---------------------------------------------------------------- ZSM
; unsigned char eng_zsm_load(unsigned char bank): 0, else 1 (not a ZSM)
_eng_zsm_load:
	php
	sei
	sta songbank
	ldx RAMB
	stx bankkeep
	stz _eng_run
	ldx _zsm_bank
	stx RAMB
	ldx #0
	jsr zsm_setbank
	ldx #0
	lda #$00
	ldy #$A0
	jsr zsm_setmem
	ldx #0
	jsr zsm_getstate
	beq @err                ; (z: not playable)
	ldx #0
	jsr zsm_getksptr
	stx ksptr
	sty ksptr+1
	ldx #0
	jsr zsm_getosptr
	stx osptr
	sty osptr+1
.ifdef MP_TEST
	ldx #7
@k:	stz t_kon,x
	dex
	bpl @k
	stz t_psg
.endif
	lda #M_ZSM
	sta _eng_mode
	lda #0
	bra @x
@err:	stz _eng_mode
	lda #1
@x:	ldx bankkeep
	stx RAMB
	plp
	ldx #0
	rts

; unsigned char eng_zsm_state(void): bit 0 playing, bit 7 not playable;
; the loops in eng_loops
_eng_zsm_state:
	php
	sei
	lda RAMB
	sta bankkeep
	lda _zsm_bank
	sta RAMB
	ldx #0
	jsr zsm_getstate
	php                     ; (c: playing, z: not playable: the flags as
	sta _eng_loops          ; they came, bit 0 c, bit 1 z)
	sty _eng_loops+1
	pla
	tay
	and #1
	sta sreg
	tya
	and #2
	beq @p
	lda #$80
	tsb sreg
@p:	lda bankkeep
	sta RAMB
	plp
	lda sreg
	ldx #0
	rts

;---------------------------------------------------------------- both
; void eng_go(void): the song plays (from where it is)
_eng_go:
	php
	sei
	lda _eng_mode
	beq @x
	cmp #M_MIDI
	bne @z
	lda #1
	jsr midi_play
	bra @r
@z:	jsr ZBank
	ldx #0
	jsr zsm_play
	jsr ZBack
@r:	lda #1
	sta _eng_run
@x:	plp
	rts

; void eng_pause(void): the ticks stop, the voices are released
_eng_pause:
	php
	sei
	stz _eng_run
	lda _eng_mode
	beq @x
	cmp #M_MIDI
	bne @z
	jsr midi_stop           ; (releases every YM channel; ROM bank $0A inside)
	bra @x
@z:	jsr ZBank
	ldx #0
	jsr zsm_stop
	jsr ZBack
@x:	plp
	rts

; void eng_rewind(void): stopped, at the song's start
_eng_rewind:
	php
	sei
	jsr _eng_pause
	lda _eng_mode
	cmp #M_MIDI
	bne @z
	lda RAMB
	sta bankkeep
	jsr midi_restart
	lda bankkeep
	sta RAMB
	bra @x
@z:	cmp #M_ZSM
	bne @x
	jsr ZBank
	ldx #0
	jsr zsm_rewind
	jsr ZBack
@x:	stz _eng_frames
	stz _eng_frames+1
	plp
	rts

; void eng_stop(void): the song closed, everything silent
_eng_stop:
	php
	sei
	jsr _eng_pause
	lda _eng_mode
	cmp #M_ZSM
	bne @s
	jsr ZBank
	ldx #0
	jsr zsm_close
	jsr ZBack
@s:	stz _eng_mode
	jsr _eng_silence
	plp
	rts

; void eng_silence(void): the YM2151 reset (the ROM's ym_init: keys off,
; registers cleared), PSG voices 0-13 silent (14 and 15 are Veranda's
; system sounds'), VERA's PCM stopped (a ZSM's)
_eng_silence:
	php
	sei
	lda RAMB
	sta bankkeep
	lda ROMB
	pha
	lda #$0A
	sta ROMB
	jsr YM_INIT
	pla
	sta ROMB
	lda VERA_CTRL
	pha
	and #$FE                ; (ADDRSEL 0)
	sta VERA_CTRL
	lda VERA_ADDR_L
	pha
	lda VERA_ADDR_M
	pha
	lda VERA_ADDR_H
	pha
	lda #$01                ; $1F9C2: voice 0's volume, step 0
	sta VERA_ADDR_H
	lda #$F9
	sta VERA_ADDR_M
	ldx #0
@v:	txa
	asl
	asl
	ora #$C2
	sta VERA_ADDR_L
	stz VERA_DATA0
	inx
	cpx #14
	bcc @v
	pla
	sta VERA_ADDR_H
	pla
	sta VERA_ADDR_M
	pla
	sta VERA_ADDR_L
	pla
	sta VERA_CTRL
	stz AUDIO_RATE
	lda #$80                ; (the FIFO emptied)
	sta AUDIO_CTRL
	lda bankkeep
	sta RAMB
	plp
	rts

; unsigned char eng_midi_playing(void)
_eng_midi_playing:
	jsr midi_is_playing
	ldx #0
	rts

; void eng_volume(unsigned char v): 0 (silent) to 10 (full): 3 dB a step;
; MIDI: an attenuation added to every YM channel's (0.75 dB a step), ZSM:
; ZSMKit's master attenuation (0.5 dB a step)
_eng_volume:
	cmp #11
	bcc @1
	lda #10
@1:	tax
	php
	sei
	lda MidiAtt,x
	phx
	jsr midi_set_master
	plx
	lda ZsmAtt,x
	pha
	jsr ZBank
	pla
	ldx #0
	jsr zsm_setatten
	jsr ZBack
	plp
	rts
MidiAtt: .byte $7F, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0
ZsmAtt:	.byte $3F, 54, 48, 42, 36, 30, 24, 18, 12, 6, 0

; void eng_voices(unsigned char *buf): 8 bytes for the YM2151's channels
; (1: a key down: MIDI, the engine's note; ZSM, ZSMKit's key-on shadow),
; 16 for the PSG's voices (1: its volume is not 0, from VERA)
_eng_voices:
	sta ptr1
	stx ptr1+1
	php
	sei
	lda RAMB
	sta bankkeep
	ldy #23
	lda #0
@0:	sta (ptr1),y
	dey
	bpl @0
	lda _eng_mode
	bne @1
	jmp @x
@1:	cmp #M_MIDI
	bne @z
	ldy #7
@m:	lda ymnote,y
	beq @m1
	lda #1
	sta (ptr1),y
@m1:	dey
	bpl @m
	jmp @x
@z:	lda _zsm_bank
	sta RAMB
	lda ksptr
	sta @ks+1
	lda ksptr+1
	sta @ks+2
	ldy #7
@k:
@ks:	lda $FFFF,y
	and #$78                ; (M1 C1 M2 C2)
	beq @k1
	lda #1
	sta (ptr1),y
@k1:	dey
	bpl @k
	; the PSG's volumes, from VERA
	lda VERA_CTRL
	pha
	and #$FE
	sta VERA_CTRL
	lda VERA_ADDR_L
	pha
	lda VERA_ADDR_M
	pha
	lda VERA_ADDR_H
	pha
	lda #$01
	sta VERA_ADDR_H
	lda #$F9
	sta VERA_ADDR_M
	ldy #8
@p:	tya
	sec
	sbc #8
	asl
	asl
	ora #$C2
	sta VERA_ADDR_L
	lda VERA_DATA0
	and #$3F
	beq @p1
	lda #1
	sta (ptr1),y
@p1:	iny
	cpy #24
	bcc @p
	pla
	sta VERA_ADDR_H
	pla
	sta VERA_ADDR_M
	pla
	sta VERA_ADDR_L
	pla
	sta VERA_CTRL
@x:	lda bankkeep
	sta RAMB
	plp
	rts

; unsigned long eng_zsm_pos(void): the ZSM cursor's offset from the file's
; start (its bank and address against songbank and $A000)
_eng_zsm_pos:
	php
	sei
	lda RAMB
	sta bankkeep
	lda _zsm_bank
	sta RAMB
	ldx #0
	jsr zsm_getptr          ; (c: not playable; a bank, x y the address)
	bcs @none
	jsr Off
	bra @x
@none:	stz sreg
	stz sreg+1
	lda #0
	ldx #0
@x:	pha
	lda bankkeep
	sta RAMB
	pla
	plp
	rts

; (a bank, x low, y high) -> the offset in the file: (bank - songbank) *
; 8192 + address - $A000, as cc65's long (a, x, sreg, sreg+1)
Off:	sec
	sbc songbank
	sta offb
	tya
	sec
	sbc #$A0                ; (the page in the bank: 0-31)
	sta offh
	lda offb
	asl
	asl
	asl
	asl
	asl
	ora offh
	sta offh                ; (bits 8-15: the bank's low 3 bits, the page)
	lda offb
	lsr
	lsr
	lsr
	sta sreg                ; (bits 16-23)
	stz sreg+1
	txa
	ldx offh
	rts
.segment "BSS"
offb:	.res 1
offh:	.res 1
.segment "CODE"

; unsigned long eng_midi_pos(void): the bytes the tracks have played (each
; track's cursor less its start)
_eng_midi_pos:
	php
	sei
	stz acc
	stz acc+1
	stz acc+2
	lda midi_ntracks
	beq @x
	stz trk
@t:	ldy trk
	lda midi_trk_curH,y
	pha
	ldx midi_trk_curL,y
	lda midi_trk_curbank,y
	ply
	jsr Off
	sta cur
	stx cur+1
	lda sreg
	sta cur+2
	ldy trk
	lda midi_trk_startH,y
	pha
	ldx midi_trk_startL,y
	lda midi_trk_startbank,y
	ply
	jsr Off
	sta beg
	stx beg+1
	lda sreg
	sta beg+2
	sec                     ; acc += cur - beg
	lda cur
	sbc beg
	sta cur
	lda cur+1
	sbc beg+1
	sta cur+1
	lda cur+2
	sbc beg+2
	sta cur+2
	clc
	lda acc
	adc cur
	sta acc
	lda acc+1
	adc cur+1
	sta acc+1
	lda acc+2
	adc cur+2
	sta acc+2
	inc trk
	lda trk
	cmp midi_ntracks
	bcc @t
@x:	plp
	lda acc+2
	sta sreg
	stz sreg+1
	lda acc
	ldx acc+1
	rts

.segment "BSS"
acc:	.res 3
trk:	.res 1
cur:	.res 3
beg:	.res 3
.segment "CODE"

ZBank:	lda RAMB
	sta zkeep
	lda _zsm_bank
	sta RAMB
	rts
ZBack:	lda zkeep
	sta RAMB
	rts
.segment "BSS"
zkeep:	.res 1
.segment "CODE"

;---------------------------------------------------------------- the window's (V206)
; void far_call(void (*f)(void)): f called with RAM bank far_bank mapped (an
; overlay's routine, from another overlay or main RAM), the caller's bank
; back after
_far_call:
	sta @j+1
	stx @j+2
	lda RAMB
	pha
	lda _far_bank
	sta RAMB
	jsr @j
	pla
	sta RAMB
	rts
@j:	jmp $FFFF

; void eng_peek(unsigned char *dst): peek_n bytes (1-255) from peek_src in
; RAM bank peek_bank to dst (below $A000), the caller's bank back after
_eng_peek:
	sta ptr1
	stx ptr1+1
	lda _peek_src
	sta ptr2
	lda _peek_src+1
	sta ptr2+1
	lda RAMB
	pha
	lda _peek_bank
	sta RAMB
	ldy #0
@l:	lda (ptr2),y
	sta (ptr1),y
	iny
	cpy _peek_n
	bne @l
	pla
	sta RAMB
	rts

; void eng_zsm_ym(unsigned char *buf): a ZSM's YM2151 as ZSMKit last wrote
; it: buf[0-7] each channel's key-on shadow (bits 3-6 its operators keyed),
; buf[8-23] registers $20-$2F (pan and connection, the notes' key codes)
_eng_zsm_ym:
	sta ptr1
	stx ptr1+1
	lda RAMB
	pha
	lda _zsm_bank
	sta RAMB
	lda ksptr
	sta ptr2
	lda ksptr+1
	sta ptr2+1
	ldy #7
@k:	lda (ptr2),y
	sta (ptr1),y
	dey
	bpl @k
	clc
	lda osptr
	adc #$20-8
	sta ptr2
	lda osptr+1
	adc #0
	sta ptr2+1
	ldy #8
@o:	lda (ptr2),y
	sta (ptr1),y
	iny
	cpy #24
	bne @o
	pla
	sta RAMB
	rts

; void eng_psg(unsigned char *buf): the PSG's 64 registers from VERA
; ($1F9C0: each voice's frequency, low and high, its volume and sides, its
; wave), with the interrupt off (its handler moves VERA's address; the
; window's reading is short: a C loop took 5,000 cycles), VERA's port 0
; put back
_eng_psg:
	sta ptr1
	stx ptr1+1
	php
	sei
	lda VERA_CTRL
	pha
	and #$FE
	sta VERA_CTRL
	lda VERA_ADDR_L
	pha
	lda VERA_ADDR_M
	pha
	lda VERA_ADDR_H
	pha
	lda #$C0
	sta VERA_ADDR_L
	lda #$F9
	sta VERA_ADDR_M
	lda #$11                ; (step 1)
	sta VERA_ADDR_H
	ldy #0
@r:	lda VERA_DATA0
	sta (ptr1),y
	iny
	cpy #64
	bne @r
	pla
	sta VERA_ADDR_H
	pla
	sta VERA_ADDR_M
	pla
	sta VERA_ADDR_L
	pla
	sta VERA_CTRL
	plp
	rts

;---------------------------------------------------------------- the test build
.ifdef MP_TEST
; the emulator's cycle counter ($9FB8-$9FBB: the first read latches all four)
TStart:	ldx #0
@c:	lda $9FB8,x
	sta t_c0,x
	inx
	cpx #4
	bne @c
	sec                     ; the gap since the last tick
	lda t_c0
	sbc t_last
	sta t_last
	lda t_c0+1
	sbc t_last+1
	sta t_last+1
	lda t_c0+2
	sbc t_last+2
	sta t_last+2
	lda t_c0+3
	sbc t_last+3
	sta t_last+3
	lda t_fresh
	stz t_fresh
	bne @n
	lda _eng_run            ; (only while the song plays)
	beq @n
	lda t_last+3
	cmp _t_gap_max+3
	bne @g
	lda t_last+2
	cmp _t_gap_max+2
	bne @g
	lda t_last+1
	cmp _t_gap_max+1
	bne @g
	lda t_last
	cmp _t_gap_max
@g:	bcc @n
	ldx #3
@g1:	lda t_last,x
	sta _t_gap_max,x
	dex
	bpl @g1
@n:	ldx #3
@n1:	lda t_c0,x
	sta t_last,x
	dex
	bpl @n1
	rts

TEnd:	lda _eng_run
	ora _eng_mode
	beq @r
	lda $9FB8               ; d = now - t_c0
	sta t_d
	lda $9FB9
	sta t_d+1
	lda $9FBA
	sta t_d+2
	lda $9FBB
	sta t_d+3
	sec
	ldx #0
	ldy #4
@s:	lda t_d,x
	sbc t_c0,x
	sta t_d,x
	inx
	dey
	bne @s
	clc
	ldx #0
	ldy #4
@a:	lda _t_cyc_sum,x
	adc t_d,x
	sta _t_cyc_sum,x
	inx
	dey
	bne @a
	inc _t_ticks
	bne @m
	inc _t_ticks+1
	bne @m
	inc _t_ticks+2
@m:	lda t_d+3
	cmp _t_cyc_max+3
	bne @g
	lda t_d+2
	cmp _t_cyc_max+2
	bne @g
	lda t_d+1
	cmp _t_cyc_max+1
	bne @g
	lda t_d
	cmp _t_cyc_max
@g:	bcc @r
	ldx #3
@g1:	lda t_d,x
	sta _t_cyc_max,x
	dex
	bpl @g1
@r:	rts
.segment "BSS"
t_d:	.res 4
.segment "CODE"

; a logged event: a kind, x the channel, y the note (any banks mapped)
TLog:	sta tk
	stx tch
	lda _t_log_head
	asl
	asl
	asl
	tax
	lda tk
	sta _t_log,x
	lda tch
	sta _t_log+1,x
	tya
	sta _t_log+2,x
	lda _eng_frames
	sta _t_log+3,x
	lda _eng_frames+1
	sta _t_log+4,x
	inc _t_log_head
	lda _t_log_head
	cmp #LOGN
	bcc @1
	stz _t_log_head
@1:	rts
.segment "BSS"
tk:	.res 1
tch:	.res 1
.segment "CODE"

; Melodius's three calls, logged, then the ROM's (bank $0A is mapped)
t_ym_playnote:                  ; a = YM channel, x kc, y kf
	pha
	phx
	phy
	pha
	lda #1
	plx
	ldy midi_note_iter
	jsr TLog
	ply
	plx
	pla
	jmp $C072
t_ym_playdrum:                  ; a = YM channel, x = the drum's note
	pha
	phx
	phy
	pha
	txa
	tay
	lda #2
	plx
	jsr TLog
	ply
	plx
	pla
	jmp $C06F
t_ym_release:                   ; a = YM channel
	pha
	phx
	phy
	tax
	lda #3
	ldy #0
	jsr TLog
	ply
	plx
	pla
	jmp $C084

; ZSM: the key-on shadow's changes after a tick (ZSMKit's bank mapped),
; kind 4 (x the channel, y the shadow's byte); PSG voice 0's volume, kind 5
TKon:	lda ksptr
	sta @ks+1
	lda ksptr+1
	sta @ks+2
	ldx #7
@k:
@ks:	lda $FFFF,x
	and #$78
	cmp t_kon,x
	beq @n
	sta t_kon,x
	tay
	lda #4
	phx
	jsr TLog
	plx
@n:	dex
	bpl @k
	lda VERA_CTRL           ; (the kernel puts VERA's address back after)
	and #$FE
	sta VERA_CTRL
	lda #$C2
	sta VERA_ADDR_L
	lda #$F9
	sta VERA_ADDR_M
	lda #$01
	sta VERA_ADDR_H
	lda VERA_DATA0
	and #$3F
	cmp t_psg
	beq @r
	sta t_psg
	tay
	ldx #0
	lda #5
	jsr TLog
@r:	rts
.endif
