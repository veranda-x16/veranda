; About this X16: the machine's own numbers (DECISIONS V119), each read the
; documented way and given back as it was found:
;   hw_kernal()      the KERNAL's version byte, $FF80 of ROM bank 0 (the
;                    release number, R49: 49; negative: a pre-release of
;                    that number, $FF a custom build)
;   hw_vera(buf)     VERA's DC_VER0-3 ($9F29-$9F2C with DCSEL = 63: "V",
;                    major, minor, patch on VERA 0.3.1 and later; anything
;                    else there: an older VERA, no version); DCSEL put back
;   hw_rambanks()    the RAM banks there are, found as the KERNAL's ramtas
;                    finds them: a byte written to $A000 of bank 64 (then
;                    128) that does not stay there (no RAM: x16emu's -ram)
;                    or shows in bank 0's (the RAM wraps round) ends the
;                    RAM there (512 KB, 1 MB; else 2 MB); both bytes put
;                    back at once, the interrupt off; 0 means 256
;   hw_jiffies(buf)  the KERNAL's jiffy clock (RDTIM: 1/60 s since reset,
;                    from 0 again after 24 hours), 3 bytes
;   hw_smc(reg)      a register of the SMC (the system management
;                    controller) over I2C (the KERNAL's i2c_read_byte,
;                    device $42): its value, or -1 if it does not answer
;   hw_version(buf)  Veranda's GetVersion: a (the API level), x.y
;   hw_frame()       the CPU's loops of 13 cycles in one frame of VERA's
;                    (59.52 Hz): its speed, measured with the interrupt
;                    off for two frames (the one VSYNC taken is the
;                    interrupt's only loss)
; MIT licence (see LICENSE).

RDTIM   = $FFDE
I2CREAD = $FEC6
SMC     = $42
VCTRL   = $9F25
DCVER   = $9F29
VISR    = $9F27

.include "veranda.inc"

.export _hw_kernal, _hw_vera, _hw_rambanks, _hw_jiffies, _hw_smc, _hw_version, _hw_frame
.importzp ptr1

.segment "BSS"
b0:	.res 1
bn:	.res 1

.segment "CODE"

_hw_kernal:
	php
	sei
	ldx $01
	stz $01
	lda $FF80
	stx $01
	plp
	ldx #0
	rts

_hw_vera:
	sta ptr1
	stx ptr1+1
	php
	sei
	lda VCTRL
	pha
	and #$01                ; (ADDRSEL kept; bit 7, the reset, never set)
	ora #63 << 1
	sta VCTRL
	ldy #0
@1:	lda DCVER,y
	sta (ptr1),y
	iny
	cpy #4
	bne @1
	pla
	sta VCTRL
	plp
	rts

_hw_rambanks:
	php
	sei
	lda $00
	pha
	ldx #64
@t:	stz $00
	lda $A000
	sta b0
	stx $00
	lda $A000
	sta bn
	eor #$FF
	sta $A000               ; bank x
	ldy #0
	cmp $A000               ; (a: the byte written) not kept: no RAM there
	beq @kept
	iny
@kept:	stz $00
	lda $A000
	cmp b0                  ; bank 0 changed: x wraps to it
	beq @same
	iny
@same:	stx $00
	lda bn
	sta $A000               ; (put back: in bank x, which is bank 0 if it wrapped)
	cpy #0
	bne @wrap
	txa
	asl
	tax
	bne @t                  ; 64, 128, then 0 (256)
@wrap:	pla
	sta $00
	plp
	txa
	ldx #0
	rts

_hw_jiffies:
	sta ptr1
	stx ptr1+1
	jsr RDTIM
	pha
	tya
	ldy #2
	sta (ptr1),y
	txa
	dey
	sta (ptr1),y
	pla
	dey
	sta (ptr1),y
	rts

_hw_smc:
	tay
	ldx #SMC
	jsr I2CREAD
	bcs @e
	ldx #0
	rts
@e:	lda #$FF
	tax
	rts

_hw_version:
	sta ptr1
	stx ptr1+1
	jsr GetVersion
	phy
	ldy #0
	sta (ptr1),y
	iny
	txa
	sta (ptr1),y
	iny
	pla
	sta (ptr1),y
	rts

_hw_frame:
	php
	sei
	lda #1
	sta VISR                ; (VSYNC's flag cleared: the next one starts the frame)
@w:	lda VISR
	lsr
	bcc @w
	lda #1
	sta VISR
	ldx #0
	ldy #0
@l:	lda VISR                ; 4
	lsr                     ; 2
	bcs @d                  ; 2
	inx                     ; 2
	bne @l                  ; 3: 13 cycles a loop
	iny                     ; (+5 every 256)
	bra @l
@d:	plp
	txa
	phy
	plx
	rts
