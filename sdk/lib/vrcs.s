; Veranda's character set, ISO-8859-16, and UTF-8 (vrcs.h, DECISIONS
; V140), for cc65 programs (fastcall). The table holds the 40 bytes of
; $A0-$FF whose character is not Latin-1's (the other 56 are Unicode
; U+00A0-U+00FF themselves); tests/check_vrcs.py checks every byte against
; Python's iso8859_16 codec.
;
; In veranda.lib (segments CODE, RODATA, BSS); for an overlay of one's
; own assemble src/vrcs.s with -D VRCS_OVL=n: code and tables go to
; OVERLAYn (the decoder's three bytes stay in BSS, below $A000). With -D
; VRCS_BYTE only cs_uni and cs_byte (198 bytes with the table; V143, Veranda
; FTP's names).
;
; MIT licence (see LICENSE).

	.setcpu "65C02"
	.export _cs_uni, _cs_byte
.ifndef VRCS_BYTE
	.export _cs_utf8, _cs_dec_reset, _cs_dec, _cs_from8
.endif
	.importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3
	.import popa

N = 40

.ifdef VRCS_OVL
	.segment .sprintf("OVERLAY%d", VRCS_OVL)
.else
	.rodata
.endif

csB:	.byte $A1, $A2, $A3, $A4, $A5, $A6, $A8, $AA, $AC, $AE
	.byte $AF, $B2, $B3, $B4, $B5, $B8, $B9, $BA, $BC, $BD
	.byte $BE, $BF, $C3, $C5, $D0, $D1, $D5, $D7, $D8, $DD
	.byte $DE, $E3, $E5, $F0, $F1, $F5, $F7, $F8, $FD, $FE
.define CSU $0104, $0105, $0141, $20AC, $201E, $0160, $0161, $0218, $0179, $017A, $017B, $010C, $0142, $017D, $201D, $017E, $010D, $0219, $0152, $0153, $0178, $017C, $0102, $0106, $0110, $0143, $0150, $015A, $0170, $0118, $021A, $0103, $0107, $0111, $0144, $0151, $015B, $0171, $0119, $021B
csUL:	.lobytes CSU
csUH:	.hibytes CSU

.ifndef VRCS_BYTE
.bss
csA:	.res 2                  ; the decoder's code point so far
csN:	.res 1                  ; continuation bytes to come; bit 7: past U+FFFF
.endif

.ifdef VRCS_OVL
	.segment .sprintf("OVERLAY%d", VRCS_OVL)
.else
	.code
.endif

; unsigned int cs_uni(unsigned char c)
_cs_uni:
	cmp #$A1
	bcc Same
	ldy #N - 1
@l:	cmp csB,y
	beq UniF
	dey
	bpl @l
Same:	ldx #0
	rts
UniF:	lda csUL,y
	ldx csUH,y
	rts

; unsigned char cs_byte(unsigned int u)
_cs_byte:
	cpx #0
	bne @hi
	cmp #$80
	bcc Same                ; (ASCII)
	cmp #$A0
	bcc Zero                ; ($80-$9F)
	ldy #N - 1              ; Latin-1's, unless the set has another there
@l1:	cmp csB,y
	beq Zero
	dey
	bpl @l1
	bra Same
@hi:	sta tmp1
	ldy #N - 1
@l2:	lda csUL,y
	cmp tmp1
	bne @n
	txa
	cmp csUH,y
	beq ByteF
@n:	dey
	bpl @l2
Zero:	lda #0
	tax
	rts
ByteF:	lda csB,y
	ldx #0
	rts

.ifndef VRCS_BYTE
; unsigned char cs_utf8(unsigned char c, char *out)
_cs_utf8:
	sta ptr1
	stx ptr1+1
	jsr popa
	jsr _cs_uni
	ldy #0
	cpx #0
	bne @2
	cmp #$80
	bcs @2
	sta (ptr1),y            ; one byte
	lda #1
	rts
@2:	sta tmp1                ; tmp3 = (u >> 6) AND $FF
	stx tmp2
	txa
	asl a
	asl a
	sta tmp3
	lda tmp1
	rol a
	rol a
	rol a
	and #3
	ora tmp3
	sta tmp3
	cpx #8
	bcs @3
	ora #$C0                ; two
	bra @w
@3:	lda tmp2                ; three
	lsr a
	lsr a
	lsr a
	lsr a
	ora #$E0
	sta (ptr1),y
	iny
	lda tmp3
	and #$3F
	ora #$80
@w:	sta (ptr1),y
	iny
	lda tmp1
	and #$3F
	ora #$80
	sta (ptr1),y
	iny
	tya
	ldx #0
	rts

; void cs_dec_reset(void)
_cs_dec_reset:
	stz csN
	rts

; unsigned int cs_dec(unsigned char b): 0 while a sequence goes on
_cs_dec:
	cmp #$80
	bcs @hi
	stz csN                 ; ASCII (a sequence cut short: dropped)
	ldx #0
	rts
@hi:	cmp #$C0
	bcs @lead
	tay                     ; a continuation
	lda csN
	and #$7F
	beq Bad
	ldx #6
@s:	asl csA
	rol csA+1
	dex
	bne @s
	tya
	and #$3F
	ora csA
	sta csA
	dec csN
	lda csN
	and #$7F
	bne More
	lda csN                 ; the end: past U+FFFF, overlong?
	stz csN
	cmp #0
	bne Bad
	ldx csA+1
	lda csA
	cpx #0
	bne @ok
	cmp #$80
	bcc Bad
@ok:	rts
@lead:	ldx #1
	ldy #$1F
	cmp #$E0
	bcc @l
	inx
	ldy #$0F
	cmp #$F0
	bcc @l
	ldx #$83
	ldy #0
@l:	stx csN
	sty tmp1
	and tmp1
	sta csA
	stz csA+1
More:	lda #0
	tax
	rts
Bad:	lda #$FD
	ldx #$FF
	rts

; unsigned int cs_from8(char *s)
_cs_from8:
	sta ptr1                ; read
	stx ptr1+1
	sta ptr2                ; write
	stx ptr2+1
	sta ptr3
	stx ptr3+1
	stz csN
@l:	lda (ptr1)
	beq @end
	inc ptr1
	bne @1
	inc ptr1+1
@1:	jsr _cs_dec
	cpx #0
	bne @c
	cmp #0
	beq @l
@c:	jsr _cs_byte
	cmp #0
	bne @w
	lda #'?'
@w:	sta (ptr2)
	inc ptr2
	bne @l
	inc ptr2+1
	bra @l
@end:	sta (ptr2)
	lda ptr2
	sec
	sbc ptr3
	pha
	lda ptr2+1
	sbc ptr3+1
	tax
	pla
	rts
.endif
