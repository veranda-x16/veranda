; Veranda Update: CRC-32 (zlib's: the reflected polynomial $EDB88320, from
; $FFFFFFFF, inverted at the end), table-driven, in assembly (DECISIONS
; V130). The table: 256 entries of 4 bytes, kept as four 256-byte columns
; (T0 the low bytes .. T3 the high ones) at $A000-$A3FF of the RAM bank
; crcbank (main RAM is short), made once by crc_init; crc_add maps that
; bank while it runs and the bank before back after (its callers' code
; may be an overlay at $A000: crc_add is in main RAM, and so must its
; buffer be). A byte costs about 50 cycles (the running value in zero
; page during a call): some 160 KB a second at 8 MHz, faster than the
; card reads it and far faster than the modem brings it.
;
;   crc_init()           the table
;   crc_start()          crcv = $FFFFFFFF
;   crc_add(buf, n)      n bytes of buf (below $A000) into crcv
;   crc_end()            crcv inverted, returned (unsigned long)
;
; MIT licence (see LICENSE).

.export _crc_init, _crc_start, _crc_add, _crc_end, _crcv, _crcbank
.import popax
.importzp ptr1, tmp1, tmp2, tmp3, tmp4, sreg

.segment "BSS"

_crcv:	.res 4
_crcbank: .res 1
cnt:	.res 2
keep:	.res 1

RAMBANK = $00
T0 = $A000
T1 = $A100
T2 = $A200
T3 = $A300

.segment "CODE"

; the table: T[i] = i shifted right 8 times, $EDB88320 in when a 1 falls out
_crc_init:
	lda RAMBANK
	pha
	lda _crcbank
	sta RAMBANK
	ldx #0
@i:	stx tmp1                ; c = i (tmp1 low .. tmp4 high)
	stz tmp2
	stz tmp3
	stz tmp4
	ldy #8
@b:	lsr tmp4
	ror tmp3
	ror tmp2
	ror tmp1
	bcc @n
	lda tmp1
	eor #$20
	sta tmp1
	lda tmp2
	eor #$83
	sta tmp2
	lda tmp3
	eor #$B8
	sta tmp3
	lda tmp4
	eor #$ED
	sta tmp4
@n:	dey
	bne @b
	lda tmp1
	sta T0,x
	lda tmp2
	sta T1,x
	lda tmp3
	sta T2,x
	lda tmp4
	sta T3,x
	inx
	bne @i
	pla
	sta RAMBANK
	rts

_crc_start:
	lda #$FF
	sta _crcv
	sta _crcv+1
	sta _crcv+2
	sta _crcv+3
	rts

; crc_add(buf, n): n in a/x, buf on the C stack
_crc_add:
	sta cnt
	stx cnt+1
	jsr popax
	sta ptr1
	stx ptr1+1
	lda RAMBANK
	sta keep
	lda _crcbank
	sta RAMBANK
	lda _crcv               ; the value in zero page while it runs
	sta tmp1
	lda _crcv+1
	sta tmp2
	lda _crcv+2
	sta tmp3
	lda _crcv+3
	sta tmp4
	ldy #0
	lda cnt+1               ; whole pages first
	beq @part
@page:	jsr bytes256
	inc ptr1+1
	dec cnt+1
	bne @page
@part:	ldy #0
	lda cnt
	beq @done
@p:	lda (ptr1),y
	eor tmp1
	tax
	lda tmp2
	eor T0,x
	sta tmp1
	lda tmp3
	eor T1,x
	sta tmp2
	lda tmp4
	eor T2,x
	sta tmp3
	lda T3,x
	sta tmp4
	iny
	cpy cnt
	bne @p
@done:	lda tmp1
	sta _crcv
	lda tmp2
	sta _crcv+1
	lda tmp3
	sta _crcv+2
	lda tmp4
	sta _crcv+3
	lda keep
	sta RAMBANK
	rts

; 256 bytes at ptr1 (y = 0 on entry and on return)
bytes256:
@l:	lda (ptr1),y
	eor tmp1
	tax
	lda tmp2
	eor T0,x
	sta tmp1
	lda tmp3
	eor T1,x
	sta tmp2
	lda tmp4
	eor T2,x
	sta tmp3
	lda T3,x
	sta tmp4
	iny
	bne @l
	rts

; crcv inverted: the CRC-32 (a/x/sreg)
_crc_end:
	lda _crcv+3
	eor #$FF
	sta _crcv+3
	sta sreg+1
	lda _crcv+2
	eor #$FF
	sta _crcv+2
	sta sreg
	lda _crcv+1
	eor #$FF
	sta _crcv+1
	tax
	lda _crcv
	eor #$FF
	sta _crcv
	rts
