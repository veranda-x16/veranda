; VeraBASIC Run: the prepare pass's helpers (DECISIONS V87), assembled
; into overlays 3 and 4 alike (each in its own .scope; HBSS names the
; overlay's BSS segment). MIT licence (LICENSE).

.segment HBSS
ab:	.res 2			; abs() results
nt:	.res 1			; the line's tokens, decoded
tkp:	.res ::NTOK		; place (from the tokens' start)
tkt:	.res ::NTOK		; class
tkv:	.res ::NTOK		; value: low byte (a keyword: its id)
tkh:	.res ::NTOK		; high byte
nfr:	.res 1
frs:	.res ::NFRAME * 2
frf:	.res ::NFRAME
pk:	.res 1			; helpers
pk2:	.res 1
pw:	.res 2
pw2:	.res 2
psy:	.res 2
fbuf:	.res 4
.segment HCODE

;---------------------------------------------------------------
; helpers
;---------------------------------------------------------------
; ab = the absolute offset of token x
absof:	lda tkp,x
	clc
	adc #6
	php
	clc
	adc vt_off
	sta ab
	lda vt_off+1
	adc #0
	plp
	adc #0
	sta ab+1
	rts

; n0 = an offset of record 1 -> fpb/fpp
r1at3:	lda n0+1
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc _vt_r1b
	sta fpb
	lda n0
	sta fpp
	lda n0+1
	and #$1F
	ora #$A0
	sta fpp+1
	rts

; the sym in psy: its attributes -> fpb/fpp
pattr:	lda _vt_ab
	sta fpb
	lda psy
	asl a
	asl a
	asl a
	asl a
	sta fpp
	lda psy+1
	sta pw2
	lda psy
	lsr pw2
	ror a
	lsr pw2
	ror a
	lsr pw2
	ror a
	lsr pw2
	ror a
	and #$1F
	ora #$A0
	sta fpp+1
	rts

; psy's attribute flags |= a
aor:	pha
	jsr pattr
	ldy #0
	pla
	sta pk2
	jsr fpeek
	ora pk2
	jmp fpoke

; a's flag set in psy's attributes? (z clear: yes)
aflag:	pha
	jsr pattr
	ldy #0
	pla
	sta pk2
	jsr fpeek
	and pk2
	rts

; psy = token x's value
tsym:	lda tkv,x
	sta psy
	lda tkh,x
	sta psy+1
	rts

; token x a punctuation a? (z set)
ispc:	pha
	lda tkt,x
	cmp #KC_P
	bne @no
	pla
	cmp tkv,x
	rts
@no:	pla
	lda #1			; (z clear)
	rts

; token x the keyword a? (z set)
iskw:	pha
	lda tkt,x
	cmp #KC_KW
	bne @no
	pla
	cmp tkv,x
	rts
@no:	pla
	lda #1
	rts

perr2:	; at vt_e's own line: kept when it is the first by line
.if .defined(VB_IDE) .and .xmatch(HCODE, "OVERLAY3")
	phx                     ; (the editor: overlay 4's, which leaves out the
	phy                     ; lines up to _vt_after: overlay 3 has no room;
	lda #<P4::perr2         ; x and y kept, as this perr2 keeps them)
	ldx #>P4::perr2
	ldy _vt_ovl4
	jsr bcall
	ply
	plx
	rts
.else
.ifdef VB_IDE
	lda vt_e+1              ; (the editor's F8: lines up to _vt_after left
	ora vt_e+2              ; out; an error of no line, Program too big,
	beq @ok                 ; never)
	lda _vt_after+1
	cmp vt_e+2
	bcc @ok
	bne @r
	lda _vt_after
	cmp vt_e+1
	bcs @r
@ok:
.endif
	lda vt_pe
	beq @take
	lda vt_e+2
	cmp vt_pe+2
	bcc @take
	bne @r
	lda vt_e+1
	cmp vt_pe+1
	bcs @r
@take:	ldx #VE_SIZE - 1
@c:	lda vt_e,x
	sta vt_pe,x
	dex
	bpl @c
@r:	rts
.endif


; tb's tokens -> nt, tkp, tkt, tkv, tkh
decode:	stz nt
	ldy #6			; y: tb's place
@l:	tya
	sec
	sbc #6
	ldx nt
	sta tkp,x
	lda tb,y
	bne @1
	rts			; the $00
@1:	cmp #T_FLOAT
	beq @flt
	bcc @int
	cmp #T_VAR
	bcc @str		; 5
	jeq @var
	cmp #T_COMMENT
	jcc @ref		; 7, 8
	cmp #T_BLOCK
	jcc @str2		; 9, 10
	jeq @blk
	cmp #T_EXT
	beq @ext
	cmp #$80
	bcs @kw
	sta tkv,x		; punctuation
	lda #KC_P
	iny
	jmp @put
@kw:	sta tkv,x
	lda #KC_KW
	iny
	jmp @put
@ext:	lda tb+1,y
	ldx #KD_DIALOG
	cmp #TX_DIALOG
	beq @e1
	ldx #KD_ENDDIALOG
	cmp #TX_END_DIALOG
	beq @e1
	ldx #KD_EXT
@e1:	txa
	ldx nt
	sta tkv,x
	lda #$FF
	sta tkh,x
	lda #KC_KW
	iny
	iny
	jmp @put2
@int:	lda tb+1,y
	sta tkv,x
	lda tb+2,y
	sta tkh,x
	iny
	iny
	iny
	lda #KC_INT
	bra @put2
@flt:	lda tb+6,y		; 7 + its spelling
	clc
	adc #7
	sta pk
	tya
	clc
	adc pk
	tay
	lda #KC_FLT
	bra @put
@str:	lda #KC_STR
@strs:	sta pk2
	lda tb+1,y
	clc
	adc #2
	sta pk
	tya
	clc
	adc pk
	tay
	lda pk2
	bra @put
@str2:	cmp #T_COMMENT
	bne @dat
	lda #KC_REM
	bra @strs
@dat:	lda #KC_DATA
	bra @strs
@var:	lda tb+1,y
	sta tkv,x
	lda tb+2,y
	sta tkh,x
	iny
	iny
	iny
	lda #KC_VAR
	bra @put2
@ref:	pha
	lda tb+1,y
	sta tkv,x
	lda tb+2,y
	sta tkh,x
	tya
	clc
	adc #6
	tay
	pla
	cmp #T_LINEREF
	bne @nr
	lda #KC_LREF
	bra @put2
@nr:	lda #KC_NREF
	bra @put2
@blk:	iny
	iny
	iny
	lda #KC_BLK
	bra @put
@put:	stz tkh,x		; (keywords of page 1, punctuation: hi 0)
@put2:	sta tkt,x
	inc nt
	jmp @l

; psy's spelling's length -> pw, its first key letter -> pk; fpp: the
; names' entry
symname:
	jsr pattr
	ldy #10
	jsr fpeek
	pha
	iny
	jsr fpeek
	sta fpp+1
	pla
	sta fpp
	lda _vt_nb
	sta fpb
	ldy #4
	jsr fpeek
	sta pw
	iny
	jsr fpeek
	sta pk
	rts

; psy in the current frame? carry clear: yes (x its slot)
inframe:
	ldx #0
@l:	cpx nfr
	bcs @no
	txa
	asl a
	tay
	lda frs,y
	cmp psy
	bne @n
	lda frs+1,y
	cmp psy+1
	bne @n
	clc
	rts
@n:	inx
	bra @l
@no:	sec
	rts

bitm3:	.byte 1, 2, 4, 8, 16, 32, 64, 128

