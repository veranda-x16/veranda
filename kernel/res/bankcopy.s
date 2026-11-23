; Veranda resident core: BankCopy
;
; r0 source, r1 destination, r2 count, r3L the source's bank, r3H the
; destination's: an address at $A000-$BFFF is in that bank (and goes on
; into the next one at $C000); below $A000 the bank does not matter.
; Forward and in order, as byte by byte (an overlap copies as it always
; did), in runs that end where either address leaves its page (V158).
; A run with at most one side at $A000-$BFFF, or both in the same bank:
; that bank mapped once, a plain loop (18 cycles a byte); two different
; banks: switched for each byte (32). r0-r4 and y are kept; a is the
; caller's bank, mapped again.

.include "kernel.inc"

.export k_BankCopy, VramBank

.segment "BSS"

bcN:	.res 1                  ; the run's bytes (0: 256); then the run - 1

.segment "CODE"

k_BankCopy:
	phy
	ldx #11                 ; ram_bank, rom_bank, r0-r4 kept
@sv:	lda 0,x
	pha
	dex
	bpl @sv
	lda r3H                 ; the banks at r3L + x for r0 + x
	sta r4L
@run:	lda r2L
	ora r2H
	beq @done
	lda r0L                 ; the run: to the nearer page end, at most r2
	cmp r1L
	bcs @1
	lda r1L
@1:	eor #$FF
	ina                     ; (0: 256)
	ldx r2H
	bne @2
	tax
	beq @3                  ; (256 > r2)
	cmp r2L
	bcc @2
@3:	lda r2L
@2:	sta bcN
	ldy #0
	ldx r3L                 ; the bank: the source's if the destination is
	lda r1H                 ; not in one, else the destination's if the
	eor #$A0                ; source is not, else the same bank's
	and #$E0
	bne @map
	ldx r4L
	lda r0H
	eor #$A0
	and #$E0
	bne @map
	cpx r3L
	bne @sw
@map:	stx ram_bank
	ldx bcN
@cp:	lda (r0),y
	sta (r1),y
	iny
	dex
	bne @cp
@adv:	dey                     ; y = the run - 1 ($FF: 256)
	sty bcN
	ldx #2                  ; r1, then r0: + the run; $C000 is $A000 of
@ad:	lda r0,x                ; the next bank
	sec
	adc bcN
	sta r0,x
	bne @4
	inc r0+1,x
	lda r0+1,x
	cmp #$C0
	bne @4
	lda #$A0
	sta r0+1,x
	inc r3L,x
@4:	dex
	dex
	bpl @ad
	lda r2L                 ; r2 - the run
	clc
	sbc bcN
	sta r2L
	bcs @run
	dec r2H
	bra @run
@done:	ldx #256 - 12
@rs:	pla
	sta 12,x
	inx
	bne @rs
	ply
	lda ram_bank
	rts
@sw:	ldx r3L                 ; two banks
	stx ram_bank
	lda (r0),y
	ldx r4L
	stx ram_bank
	sta (r1),y
	iny
	cpy bcN
	bne @sw
	bra @adv

; VramBank (desk accessories, bank S): x pages (1-255) between VERA's data
; port 0 (set by the caller) and bank r3L from r1 ($A000-$BFFF, going on
; into the next bank); a = 0 from VRAM to the bank, else back. r1 and r3L
; are left after the last page (a second call goes on). About 15 cycles
; a byte.
VramBank:
	ldy ram_bank
	phy
	ldy r3L
	sty ram_bank
	ldy #0
	cmp #0
	bne @in
@out:	lda VERA_DATA0
	sta (r1),y
	iny
	bne @out
	jsr @next
	bne @out
	bra @done
@in:	lda (r1),y
	sta VERA_DATA0
	iny
	bne @in
	jsr @next
	bne @in
@done:	pla
	sta ram_bank
	rts
@next:	inc r1H
	lda r1H
	cmp #$C0
	bne @1
	lda #$A0
	sta r1H
	inc r3L
	lda r3L
	sta ram_bank
@1:	dex
	rts
