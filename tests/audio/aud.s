; tests/audio/aud.s -- PCM from VERA's AFLOW interrupt through
; intFirstVector (DECISIONS V41, V52): gate audio's synthetic mixer.
;
; On AFLOW (ISR AND IEN AND $08: AFLOW's status stays set while it is
; masked): AFLOW masked, cli (VSYNC goes on through Veranda's interrupt),
; 1024 stereo frames written with _burn cycles of fake mixing each, sei,
; AFLOW unmasked while armed; c set. Anything else: c clear.
        .export _aud_install, _aud_arm, _aud_disarm
        .export _aud_under, _aud_batches, _burn, _aud_frames
VERA_IEN  = $9F26
VERA_ISR  = $9F27
ACTRL     = $9F3B
ARATE     = $9F3C
ADATA     = $9F3D
IFV       = $0578               ; intFirstVector
        .bss
_aud_under:     .res 2
_aud_batches:   .res 2
_aud_frames:    .res 4
pages:          .res 1
armed:          .res 1
        .data
_burn:          .byte 62
sq:             .byte $30
        .code
; the FIFO reset and 2 KB of silence in it, the routine in intFirstVector,
; 16,022 Hz, AFLOW on
_aud_install:
        php
        sei
        stz ARATE
        lda #$80
        sta ACTRL
        lda #$1F                ; 8-bit stereo, volume 15
        sta ACTRL
        ldx #0
        ldy #8
@f:     stz ADATA
        inx
        bne @f
        dey
        bne @f
        lda #<Disp
        sta IFV
        lda #>Disp
        sta IFV+1
        plp
_aud_arm:
        php
        sei
        lda #1
        sta armed
        lda #42                 ; 16021.7 Hz
        sta ARATE
        lda VERA_IEN
        ora #$08
        sta VERA_IEN
        plp
        rts
_aud_disarm:
        php
        sei
        stz armed
        lda VERA_IEN
        and #$F7
        sta VERA_IEN
        stz ARATE
        stz IFV+1
        stz IFV
        plp
        rts

Disp:   lda VERA_ISR
        and VERA_IEN
        and #$08
        bne @a
        clc
        rts
@a:     lda VERA_IEN
        and #$F7
        sta VERA_IEN
        bit ACTRL
        bvc @ok
        inc _aud_under
        bne @ok
        inc _aud_under+1
@ok:    inc _aud_batches
        bne @b
        inc _aud_batches+1
@b:     cli
        lda #4
        sta pages
        ldy #0
@fr:    ldx _burn
@bu:    dex
        bne @bu
        lda sq
        sta ADATA
        sta ADATA
        dey
        bne @fr
        lda sq
        eor #$60                ; a square wave, 128 frames a half
        sta sq
        dec pages
        bne @fr
        sei
        clc
        lda _aud_frames+1
        adc #4
        sta _aud_frames+1
        bcc @n
        inc _aud_frames+2
@n:     lda armed
        beq @x
        lda VERA_IEN
        ora #$08
        sta VERA_IEN
@x:     sec
        rts
