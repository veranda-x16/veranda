; VeraBASIC Run: float spellings to the 5-byte format on the X16
; (DECISIONS V87), banked overlay 5: the exact value of the spelling,
; correctly rounded (to nearest, ties to even), as tools/vbtokens.py's
; float5 does with Python's fractions; big integers: the digits, times 2^k,
; divided by ten once for each decimal, so both sides agree to the last bit.
; vbtok.s copies the spelling to FS (main RAM) and calls float5 here.
;
; MIT licence (LICENSE).

.scope F5
FS	= sbounce		; the spelling (main RAM)
flen	= ::f5len		; its length (main RAM)
f5	= ::f5m			; the value (main RAM)

; (the editor's build, VB_IDE: in overlay 8's bank, which has room, so
; the editor takes one RAM bank fewer: V149)
.ifdef VB_IDE
.segment "OVL8BSS"
.else
.segment "OVL5BSS"
.endif
; floats: a big integer, little-endian
BNMAX	= 160
bn:	.res BNMAX
bl:	.res 1			; its bytes
nd:	.res 2			; significant digits
fx:	.res 2			; the decimal exponent (signed)
fk:	.res 2			; the binary shift (signed)
fe:	.res 2			; the exponent (signed)
fl:	.res 2			; bits
fm:	.res 4			; the mantissa
frnd:	.res 1
fst:	.res 1			; sticky
fpos:	.res 2
dvr:	.res 1
dlo:	.res 1
fesign:	.res 1
f5sp:	.res 1
num:	.res 2
big:	.res 1
fh:	.res 2

.ifdef VB_IDE
.segment "OVERLAY8"
.else
.segment "OVERLAY5"
.endif
;---------------------------------------------------------------
; floats: FS (flen bytes) -> f5, correctly rounded (vbtokens.py float5);
; carry set: an error, its id in vt_e
;---------------------------------------------------------------
float5:	tsx
	stx f5sp
	stz bl
	stz nd
	stz nd+1
	stz fx			; - the decimals (then + the exponent)
	stz fx+1
	ldx #0
	stz fesign		; 0 before ".", 1 after
@dg:	cpx flen
	bcs @mend
	lda FS,x
	cmp #'.'
	bne @d1
	lda #1
	sta fesign
	bra @dn
@d1:	sec
	sbc #'0'
	cmp #10
	bcs @mend		; "E"
	ldy fesign
	beq @d2
	pha
	lda fx
	bne @d3
	dec fx+1
@d3:	dec fx
	pla
@d2:	tay
	ora nd
	ora nd+1
	beq @dn			; a leading zero
	tya
	phx
	jsr bnmul10		; bn = bn * 10 + a
	plx
	inc nd
	bne @dn
	inc nd+1
@dn:	inx
	bra @dg
@mend:	; the exponent
	cpx flen
	bcs @noexp
	inx			; "E"
	stz fesign
	lda FS,x
	cmp #'+'
	beq @es
	cmp #'-'
	bne @ev
	inc fesign
@es:	inx
@ev:	jsr decnum5		; num (big: over 65535)
	lda big
	bne @esat
	lda num+1		; at most 9999
	cmp #>9999
	bcc @eok
	bne @esat
	lda num
	cmp #<9999
	bcc @eok
@esat:	lda #<9999
	sta num
	lda #>9999
	sta num+1
@eok:	lda fesign
	beq @eplus
	lda fx
	sec
	sbc num
	sta fx
	lda fx+1
	sbc num+1
	sta fx+1
	bra @noexp
@eplus:	lda fx
	clc
	adc num
	sta fx
	lda fx+1
	adc num+1
	sta fx+1
@noexp:	lda nd
	ora nd+1
	jeq zero5
	; nd - 1 + fx >= 39: too big; nd + fx <= -39: zero
	lda nd
	clc
	adc fx
	sta fh
	lda nd+1
	adc fx+1
	sta fh+1		; nd + fx (signed)
	bmi @neg
	lda fh+1
	bne @toobig
	lda fh
	cmp #40
	bcs @toobig
	bra @calc
@neg:	lda fh+1
	cmp #$FF
	bne @zero
	lda fh
	cmp #<-38
	bcc @zero
@calc:	lda fx+1
	bmi @div
	; fx >= 0: bn * 10^fx
@m:	lda fx
	beq @mul
	lda #0
	jsr bnmul10
	dec fx
	bra @m
@mul:	jsr bnbits		; fl
	lda fl
	sta fe
	lda fl+1
	sta fe+1
	jmp round5
@toobig:
	lda #VE_NTOOBIG
	jmp f5fail
@zero:	jmp zero5
@div:	; k = 4 d + 35 - bits(M) (0 at least); bn << k; bn / 10 d times
	jsr bnbits
	lda fx
	eor #$FF
	sta fh
	lda fx+1
	eor #$FF
	sta fh+1
	inc fh
	bne @d0
	inc fh+1		; d = -fx
@d0:	lda fh
	sta fpos
	lda fh+1
	sta fpos+1		; (d kept)
	asl fh
	rol fh+1
	asl fh
	rol fh+1
	lda fh
	clc
	adc #35
	sta fk
	lda fh+1
	adc #0
	sta fk+1
	lda fk
	sec
	sbc fl
	sta fk
	lda fk+1
	sbc fl+1
	sta fk+1
	bpl @k1
	stz fk
	stz fk+1
@k1:	jsr bnshl		; bn << fk
	stz fst
@dv:	lda fpos
	ora fpos+1
	beq @dvd
	jsr bndiv10
	lda dvr
	beq @dv1
	lda #1
	sta fst
@dv1:	lda fpos
	bne @dv2
	dec fpos+1
@dv2:	dec fpos
	bra @dv
@dvd:	jsr bnbits
	lda fl
	sec
	sbc fk
	sta fe
	lda fl+1
	sbc fk+1
	sta fe+1
	bra round5a
round5:	stz fst
round5a:
	; m: bits fl-1 .. fl-32, the round bit fl-33, the rest sticky
	stz fm
	stz fm+1
	stz fm+2
	stz fm+3
	lda fl
	sec
	sbc #1
	sta fpos
	lda fl+1
	sbc #0
	sta fpos+1
	ldx #32
@b:	jsr bnbit		; carry = bit fpos (0 below 0)
	rol fm
	rol fm+1
	rol fm+2
	rol fm+3
	jsr posdec
	dex
	bne @b
	jsr bnbit
	lda #0
	rol a
	sta frnd
	; sticky: any bit below fpos (fpos - 1 .. 0)
	jsr posdec
	lda fpos+1
	bmi @st
@sb:	jsr bnbit
	bcs @st1
	lda fpos
	and #7
	bne @sb0
	; a whole byte: the bytes below it at once
	lda fpos+1
	sta fh+1
	lda fpos
	sta fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh			; the byte index
	ldx fh
@sbb:	dex
	cpx #$FF
	beq @st
	lda bn,x
	bne @st1
	bra @sbb
@sb0:	jsr posdec
	lda fpos+1
	bpl @sb
	bra @st
@st1:	lda #1
	sta fst
@st:	lda frnd
	beq @pack
	lda fst
	bne @up
	lda fm
	and #1
	beq @pack
@up:	inc fm
	bne @pack
	inc fm+1
	bne @pack
	inc fm+2
	bne @pack
	inc fm+3
	bne @pack
	lda #$80		; 2^32: 2^31, the exponent + 1
	sta fm+3
	inc fe
	bne @pack
	inc fe+1
@pack:	lda fe
	clc
	adc #128
	tax
	lda fe+1
	adc #0
	bmi zero5
	bne @big2
	txa
	beq zero5
	sta f5
	lda fm+3
	and #$7F
	sta f5+1
	lda fm+2
	sta f5+2
	lda fm+1
	sta f5+3
	lda fm
	sta f5+4
	clc
	rts
@big2:	lda #VE_NTOOBIG
	jmp f5fail
zero5:	stz f5
	stz f5+1
	stz f5+2
	stz f5+3
	stz f5+4
	clc
	rts

; an error: id a, out of float5 at once
f5fail:	sta vt_e
	ldx f5sp
	txs
	sec
	rts

; decimal digits from x (FS, flen): num (16 bits), big (over $FFFF)
decnum5:
	stz num
	stz num+1
	stz big
@l:	cpx flen
	bcs @r
	lda FS,x
	sec
	sbc #'0'
	cmp #10
	bcs @r
	pha
	lda num
	sta fh
	lda num+1
	sta fh+1
	asl num
	rol num+1
	bcs @o1
	asl num
	rol num+1
	bcs @o1
	lda num
	adc fh
	sta num
	lda num+1
	adc fh+1
	sta num+1
	bcs @o1
	asl num
	rol num+1
	bcs @o1
	pla
	adc num
	sta num
	bcc @n
	inc num+1
	bne @n
	bra @o2
@o1:	pla
@o2:	lda #1
	sta big
@n:	inx
	bra @l
@r:	rts

posdec:	lda fpos
	bne @1
	dec fpos+1
@1:	dec fpos
	rts

; carry = bn's bit fpos (0 when fpos < 0 or past bl)
bnbit:	lda fpos+1
	bmi @z
	sta fh+1
	lda fpos
	sta fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh
	lda fh+1
	bne @z
	lda fh
	cmp bl
	bcs @z
	tay
	lda fpos
	and #7
	tay
	lda bitm,y
	ldy fh
	and bn,y
	cmp #1			; carry: not zero
	rts
@z:	clc
	rts
bitm:	.byte 1, 2, 4, 8, 16, 32, 64, 128

; bn = bn * 10 + a
bnmul10:
	sta fh			; the carry in
	ldx #0
@l:	cpx bl
	beq @top
	lda bn,x
	stz dlo
	asl a
	rol dlo			; * 2
	sta fpt
	ldy dlo
	asl a
	rol dlo
	asl a
	rol dlo			; * 8
	clc
	adc fpt
	pha
	tya
	adc dlo
	sta dlo
	pla
	clc
	adc fh
	sta bn,x
	lda dlo
	adc #0
	sta fh
	inx
	bra @l
@top:	lda fh
	beq @r
	cpx #BNMAX
	bcs @long
	sta bn,x
	inc bl
@r:	rts
@long:	lda #VE_NTOOLONG
	jmp f5fail

; bn = bn / 10, dvr the remainder; bl trimmed
bndiv10:
	stz dvr
	ldx bl
@l:	dex
	cpx #$FF
	beq @t
	lda bn,x
	sta dlo
	ldy #8
@b:	asl dlo
	rol dvr
	lda dvr
	cmp #10
	bcc @n
	sbc #10
	sta dvr
	inc dlo
@n:	dey
	bne @b
	lda dlo
	sta bn,x
	bra @l
@t:	ldx bl			; trim
@t1:	beq @r
	lda bn-1,x
	bne @r
	dex
	stx bl
	bra @t1
@r:	rts

; bn = bn << fk
bnshl:	lda fk+1		; whole bytes: fk >> 3
	sta fh+1
	lda fk
	sta fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh
	lsr fh+1
	ror fh
	lda fh+1
	bne @long
	lda fh
	clc
	adc bl
	bcs @long
	cmp #BNMAX - 1
	bcs @long
	sta fpt			; the new length (before the bits)
	; move up by fh bytes
	ldx bl
	ldy fpt
@mv:	dex
	cpx #$FF
	beq @z
	dey
	lda bn,x
	sta bn,y
	bra @mv
@z:	ldx fh			; the bytes below: 0
	beq @bits
@z1:	dex
	stz bn,x
	bne @z1
@bits:	lda fpt
	sta bl
	ldx bl			; one byte more for the bits
	stz bn,x
	inc bl
	lda fk
	and #7
	beq @trim
	tay
@bl:	ldx #0
	lda bl
	sta fpt			; (a count: cpx would lose the carry)
	clc
@br:	rol bn,x
	inx
	dec fpt
	bne @br
	dey
	bne @bl
@trim:	ldx bl
@t1:	beq @r
	lda bn-1,x
	bne @r
	dex
	stx bl
	bra @t1
@r:	rts
@long:	lda #VE_NTOOLONG
	jmp f5fail

; fl = the bits of bn (0 for 0)
bnbits:	ldx bl
@t:	beq @zero
	lda bn-1,x
	bne @top
	dex
	stx bl
	bra @t
@zero:	stz fl
	stz fl+1
	rts
@top:	ldy #0
@c:	iny
	lsr a
	bne @c
	dex			; (bl - 1) * 8 + y
	stx fl
	stz fl+1
	asl fl
	rol fl+1
	asl fl
	rol fl+1
	asl fl
	rol fl+1
	tya
	clc
	adc fl
	sta fl
	bcc @r
	inc fl+1
@r:	rts

.endscope
