; VeraBASIC Run: the evaluator (included by vb.s). Precedence climbing,
; from the lowest: OR XOR 1, AND 2, NOT 3, comparisons 4, SHL SHR 5, + - 6,
; * / \ MOD 7, unary - 8, ^ 9 (tools/vbasic.py BINPREC). The value is in acc
; (aty, ac0-ac4); a binary operator's left operand waits on the value stack.
; MIT licence (LICENSE).

; the operators' numbers (opidx)
OP_OR   = 1
OP_XOR  = 2
OP_AND  = 3
OP_EQ   = 4
OP_NE   = 5
OP_LT   = 6
OP_GT   = 7
OP_LE   = 8
OP_GE   = 9
OP_SHL  = 10
OP_SHR  = 11
OP_ADD  = 12
OP_SUB  = 13
OP_MUL  = 14
OP_DIV  = 15
OP_IDIV = 16
OP_MOD  = 17
OP_POW  = 18

; acc = the expression at ip
eval:	lda #1
evalp:	pha                     ; the lowest precedence taken
	jsr unary
ev_loop:
	lda (ip)
	jsr tok_prec
ev_next:
	jeq ev_done
	tsx
	cmp $0101,x             ; (the minimum, pushed above)
	jcc ev_done
	phy                     ; the operator
	INCIP
	cpy #OP_POW
	bne @quick
@slow:	jsr vpush               ; the left operand
	pla
	pha
	cmp #OP_POW
	bne @r
	jsr unary9
	bra @op
@r:	tax
	lda opprec,x
	inc a
	jsr evalp
@op:	pla
	jsr binop
	jmp ev_loop
@quick:	; the quick way (V107): a right operand that is a number or a global
	; numeric variable, followed by no operator that binds tighter, is
	; loaded at once, the left one into b (not through the value stack)
	lda opprec,y
	sta t3
	lda (ip)
	cmp #T_VAR
	beq @qv
	dec a                   ; (T_INTDEC .. T_INTBIN: 0 .. 2)
	cmp #3
	bcs @slow
	bra @qn
@qv:	ldy #2
	lda (ip),y
	cmp #$08
	bcc @slow               ; (a local)
	sta p0+1
	dey
	lda (ip),y
	sta p0
	ldy #7
	lda (p0),y
	cmp #TY_S
	bcs @slow               ; (a string, an array, a constant, a FUNCTION)
@qn:	ldy #3
	lda (ip),y
	cmp #'('
	beq @slow
	jsr tok_prec
	cmp t3
	beq @q
	bcs @slow
@q:	sta qprec               ; (ev_loop's next look, done)
	sty qidx
	lda aty                 ; b = acc
	sta bty
	lda ac0
	sta b0
	lda ac1
	sta b1
	lda ac2
	sta b2
	lda ac3
	sta b3
	lda ac4
	sta b4
	lda (ip)
	cmp #T_VAR
	beq @lv
	ldy #1
	lda (ip),y
	sta ac0
	iny
	lda (ip),y
	sta ac1
	lda #TY_I
	sta aty
	bra @ld
@lv:	ldy #7
	lda (p0),y
	sta aty
	ldy #4
@c:	lda (p0),y
	sta ac0,y
	dey
	bpl @c
@ld:	ADDIP 3
	pla
	jsr binop_b
	ldy qidx
	lda qprec
	jmp ev_next
ev_done:
	pla
	rts

qprec:	.byte 0
qidx:	.byte 0

; a = a token -> a its precedence as a binary operator, y its number;
; a = 0 (z set): not an operator
tok_prec:
	cmp #$60
	bcs @hi
	sbc #$2A - 1            ; (carry clear: a - $2A)
	bcc @no
	tax
	bra @t
@hi:	cmp #$C8
	bcc @no
	cmp #$D2
	bcs @no
	sbc #$C8 - 54 - 1       ; (carry clear: a - $C8 + 54)
	tax
@t:	ldy opidx,x
	lda opprec,y
	rts
@no:	lda #0
	rts

; a unary operator or a primary
unary:	lda (ip)
	cmp #'-'
	bne @1
	INCIP
	lda #8
	jsr evalp
	jmp negate
@1:	cmp #'+'
	bne @2
	INCIP
	lda #8
	jsr evalp
	jmp need_num
@2:	cmp #TK_NOT
	beq not_op
	jmp primary
not_op:	INCIP
	lda #4
	jsr evalp
	jsr toint
	lda ac0
	eor #$FF
	sta ac0
	lda ac1
	eor #$FF
	sta ac1
	rts

; ^'s right operand: its - takes a primary only
unary9:	lda (ip)
	cmp #'-'
	bne @1
	INCIP
	jsr primary
	jmp negate
@1:	cmp #'+'
	bne @2
	INCIP
	lda #8
	jsr evalp
	jmp need_num
@2:	cmp #TK_NOT
	beq not_op
	jmp primary

need_num:
	lda aty
	cmp #TY_S
	beq type_err
	rts
type_err:
	ERR E_TYPE

negate:	lda aty
	cmp #TY_I
	bne @f
	lda ac1
	cmp #$80
	bne @i
	lda ac0
	bne @i
	; -(-32768): a float
	jsr toflt
	bra @f
@i:	lda #0
	sec
	sbc ac0
	sta ac0
	lda #0
	sbc ac1
	sta ac1
	rts
@f:	cmp #TY_S
	beq type_err
	lda ac0                  ; the sign bit turned over (0 stays 0)
	beq @r
	lda ac1
	eor #$80
	sta ac1
@r:	rts

;---------------------------------------------------------------
; primaries
;---------------------------------------------------------------
primary:
	lda (ip)
	cmp #T_VAR
	bne @1
	jmp pvar
@1:	cmp #T_FLOAT
	bcc @int
	beq @flt
	cmp #T_STRING
	beq @str
	cmp #'('
	beq @par
	cmp #$80
	bcc @syn
	cmp #T_EXT
	beq @ext
	jmp function
@syn:	ERR E_SYNTAX
@int:	cmp #T_INTDEC
	bcc @syn                ; (the line's end)
	ldy #1
	lda (ip),y
	sta ac0
	iny
	lda (ip),y
	sta ac1
	lda #TY_I
	sta aty
	ADDIP 3
	rts
@flt:	ldy #1
@f:	lda (ip),y
	sta ac0-1,y
	iny
	cpy #6
	bne @f
	stz aty                 ; TY_F
	ldy #6
	lda (ip),y
	clc
	adc #7
	adc ip
	sta ip
	bcc @r
	inc ip+1
@r:	rts
@str:	ldy #1
	lda (ip),y
	sta ac0
	lda ip
	clc
	adc #2
	sta ac1
	lda ip+1
	adc #0
	sta ac2
	lda pbank
	sta ac3
	lda #SK_LIT
	sta ac4
	lda #TY_S
	sta aty
	lda ac0
	clc
	adc ac1
	sta ip
	lda ac2
	adc #0
	sta ip+1
	rts
@par:	INCIP
	jsr eval
	jmp expect_rp
@ext:	jmp ext_func            ; a Veranda function or word (vbx.s)

; a variable, an array element, a FUNCTION call
pvar:	ldy #2                  ; the fast way: a global integer
	lda (ip),y
	cmp #$08
	bcc @slow
	sta p0+1
	dey
	lda (ip),y
	sta p0
	ldy #7
	lda (p0),y
	cmp #TY_I
	bne @slow
	sta aty
	ldy #3
	lda (ip),y
	cmp #'('
	beq @slow
	lda (p0)
	sta ac0
	ldy #1
	lda (p0),y
	sta ac1
	ADDIP 3
	rts
@slow:	jsr cellref             ; p0, xb, t0
	lda t0
	and #CT_FUNC
	beq @v
	; a FUNCTION: cell byte 0 its procedure
	lda (p0)
	jsr proc_ptr
	jmp fcall
@v:	lda t0
	and #CT_ARRAY
	bne @e
	lda (ip)
	cmp #'('
	bne @load
@e:	jsr element             ; p0, xb, t0: the element
@load:	lda t0
	and #CT_TYPE
	sta aty
	cmp #TY_S
	beq @s
	lda xb
	beq @m
	sta ram_bank
@m:	ldy #4
@c:	lda (p0),y
	sta ac0,y
	dey
	bpl @c
	MAPP
	rts
@s:	lda p0                  ; a string: a reference to its cell
	sta ac1
	lda p0+1
	sta ac2
	lda xb
	sta ac3
	lda #SK_VAR
	sta ac4
	rts

; the TAG_VAR at ip -> p0 its cell, xb its bank (0: main RAM), t0 its type
; byte (a parameter's reference followed); ip past it
cellref:
	ldy #2
	lda (ip),y
	cmp #$08
	bcc @loc                ; (vb_rewrite: a local is its slot's offset, below $0800)
	sta p0+1
	dey
	lda (ip),y
	sta p0
	stz xb
	ldy #7
	lda (p0),y
	sta t0
	ADDIP 3
	rts
@loc:	sta p0+1                ; fp + the slot's offset
	dey
	lda (ip),y
	clc
	adc fp
	sta p0
	lda p0+1
	adc fp+1
	sta p0+1
	lda _sbank
	sta xb
	sta ram_bank
	ldy #7
	lda (p0),y
	sta t0
	bpl @r
	; a reference: the caller's cell
	ldy #2
	lda (p0),y
	tax
	dey
	lda (p0),y
	pha
	lda (p0)
	sta p0
	pla
	sta p0+1
	stx xb
	txa
	beq @mm
	sta ram_bank
@mm:	ldy #7
	lda (p0),y
	sta t0
@r:	MAPP
	ADDIP 3
	rts

; an assignment's target at ip: p0, xb, t0 (its type byte); t1 = 1 for an
; array element
lvalue:	lda (ip)
	cmp #T_VAR
	beq @1
	ERR E_SYNTAX
@1:	jsr cellref
	stz t1
	lda t0
	and #CT_CONST | CT_FUNC
	beq @2
	lda t0
	and #CT_CONST
	beq @2                  ; (a FUNCTION's name outside it: as the reference, a call's error)
	ERR E_SYNTAX
@2:	lda t0
	and #CT_ARRAY
	bne @e
	lda (ip)
	cmp #'('
	bne @r
@e:	jsr element
	lda #1
	sta t1
@r:	rts

;---------------------------------------------------------------
; the value stack: 6 bytes a value (type, 5)
;---------------------------------------------------------------
vpush:	ldx vsp
	cpx #VSTK
	bcc @1
	ERR E_COMPLEX
@1:	lda aty
	sta vstk,x
	lda ac0
	sta vstk+1,x
	lda ac1
	sta vstk+2,x
	lda aty
	cmp #TY_I
	beq @i
	lda ac2
	sta vstk+3,x
	lda ac3
	sta vstk+4,x
	lda ac4
	sta vstk+5,x
@i:	txa
	clc
	adc #6
	sta vsp
	rts

; b = the value stack's top, popped
vpop_b:	lda vsp
	sec
	sbc #6
	sta vsp
	tax
	lda vstk,x
	sta bty
	lda vstk+1,x
	sta b0
	lda vstk+2,x
	sta b1
	lda bty
	cmp #TY_I
	beq @i
	lda vstk+3,x
	sta b2
	lda vstk+4,x
	sta b3
	lda vstk+5,x
	sta b4
@i:	rts

; acc = the value 12 (6) bytes under x (the value stack's top), not popped
vpeek_x12:
	txa
	sec
	sbc #12
	bra vpk
vpeek_x6:
	txa
	sec
	sbc #6
vpk:	tax
	lda vstk,x
	sta aty
	lda vstk+1,x
	sta ac0
	lda vstk+2,x
	sta ac1
	lda vstk+3,x
	sta ac2
	lda vstk+4,x
	sta ac3
	lda vstk+5,x
	sta ac4
	rts

;---------------------------------------------------------------
; binary operators: acc = (the value stack's top) op acc
;---------------------------------------------------------------
binop:	pha
	jsr vpop_b
	pla
binop_b:			; acc = b op acc; a = the operator
	asl a
	tax
	jmp (optab,x)

; both integers? (carry set if so)
both_int:
	lda aty
	cmp #TY_I
	bne @no
	lda bty
	cmp #TY_I
	bne @no
	sec
	rts
@no:	clc
	rts

; neither a string (else Type mismatch)
both_num:
	lda aty
	cmp #TY_S
	beq @e
	lda bty
	cmp #TY_S
	beq @e
	rts
@e:	ERR E_TYPE

op_add:	lda aty                 ; (both integers: aty & bty = 1)
	and bty
	cmp #TY_I
	beq @int
	lda aty
	cmp #TY_S
	bne @n
	lda bty
	cmp #TY_S
	bne @e
	jmp sconcat
@e:	ERR E_TYPE
@n:	jsr both_num
	jsr both_int
	bcc @f
@int:	lda b0
	clc
	adc ac0
	tax
	lda b1
	adc ac1
	bvs @f
	sta ac1
	stx ac0
	rts
@f:	ldy #<FP_FADDT
	jmp fp_binop

op_sub:	lda aty
	and bty
	cmp #TY_I
	beq @int
	jsr both_num
	jsr both_int
	bcc @f
@int:	lda b0
	sec
	sbc ac0
	tax
	lda b1
	sbc ac1
	bvs @f
	sta ac1
	stx ac0
	rts
@f:	ldy #<FP_FSUBT
	jmp fp_binop

op_mul:	lda aty
	and bty
	cmp #TY_I
	beq @int
	jsr both_num
	jsr both_int
	bcc @f
@int:	jsr imul                ; ac0/ac1 = b * a; carry set: it did not fit
	bcs @f
	rts
@f:	ldy #<FP_FMULTT
	jmp fp_binop

op_div:	jsr both_num
	ldy #<FP_FDIVT
	jmp fp_binop

op_pow:	jsr both_num
	jsr both_int
	bcc @f
	lda ac1
	bmi @f
	jmp ipow
@f:	ldy #<FP_FPWRT
	jmp fp_binop

; b and acc as floats, then the ROM's op (y: its jump table's low byte):
; ARG = b, FAC = acc, FAC = ARG op FAC, acc = FAC
fp_binop:
	phy
	jsr toflt
	jsr b_to_fpa
	ply
	jmp fp_op_fpa_acc

; fpa = b as a float
b_to_fpa:
	lda bty
	cmp #TY_I
	bne @f
	lda aty
	pha
	ldx #4
@s:	lda ac0,x
	pha
	dex
	bpl @s
	lda b0
	sta ac0
	lda b1
	sta ac1
	lda #TY_I
	sta aty
	jsr toflt
	ldx #4
@c:	lda ac0,x
	sta fpa,x
	dex
	bpl @c
	ldx #0
@r:	pla
	sta ac0,x
	inx
	cpx #5
	bne @r
	pla
	sta aty
	rts
@f:	ldx #4
@d:	lda b0,x
	sta fpa,x
	dex
	bpl @d
	rts

; integers: \ and MOD, truncated towards zero
op_idiv:
	jsr idiv_prep
	jsr udiv                ; n0 = quotient, n1 = remainder (of |b| / |a|)
	lda dv_sq
	bpl @p
	lda #0
	sec
	sbc n0
	sta n0
	lda #0
	sbc n0+1
	sta n0+1
	bra @s
@p:	lda n0+1                ; 32768: -32768 \ -1, a float
	bpl @s
	lda #$00
	sta ac0
	lda #$80
	sta ac1
	lda #TY_I
	sta aty
	jsr toflt               ; (-32768 as a float, then its sign turned)
	lda ac1
	eor #$80
	sta ac1
	rts
@s:	lda n0
	sta ac0
	lda n0+1
	sta ac1
	lda #TY_I
	sta aty
	rts

op_mod:	jsr idiv_prep
	jsr udiv
	lda dv_sr               ; the remainder has the dividend's sign
	bpl @p
	lda #0
	sec
	sbc n1
	sta n1
	lda #0
	sbc n1+1
	sta n1+1
@p:	lda n1
	sta ac0
	lda n1+1
	sta ac1
	lda #TY_I
	sta aty
	rts

; both to integers: n0 = |b|, n1 = |a|; dv_sq the quotient's sign, dv_sr
; the remainder's
idiv_prep:
	jsr both_num
	jsr toint
	jsr b_toint
	lda ac0
	ora ac1
	bne @1
	ERR E_DIV0
@1:	lda b1
	sta dv_sr
	eor ac1
	sta dv_sq
	lda b0
	sta n0
	lda b1
	sta n0+1
	bpl @2
	lda #0
	sec
	sbc n0
	sta n0
	lda #0
	sbc n0+1
	sta n0+1
@2:	lda ac0
	sta n1
	lda ac1
	sta n1+1
	bpl @3
	lda #0
	sec
	sbc n1
	sta n1
	lda #0
	sbc n1+1
	sta n1+1
@3:	rts
dv_sq:	.byte 0
dv_sr:	.byte 0

; n0 / n1 (unsigned 16 bits) -> n0 the quotient, n1 the remainder
udiv:	lda n1+1
	bne @w
	; (V107) a divisor below 256: the remainder in a
	ldx #16
@b:	asl n0
	rol n0+1
	rol a
	bcs @bs
	cmp n1
	bcc @bn
@bs:	sbc n1
	inc n0
@bn:	dex
	bne @b
	sta n1
	rts
@w:	lda #0
	sta t0
	sta t1
	ldx #16
@l:	asl n0
	rol n0+1
	rol t0
	rol t1
	lda t0
	sec
	sbc n1
	tay
	lda t1
	sbc n1+1
	bcc @n
	sta t1
	sty t0
	inc n0
@n:	dex
	bne @l
	lda t0
	sta n1
	lda t1
	sta n1+1
	rts

; b to an integer, in place
b_toint:
	lda bty
	cmp #TY_I
	beq @r
	ldx #5
@s:	lda aty,x
	pha
	dex
	bpl @s
	ldx #5
@c:	lda bty,x
	sta aty,x
	dex
	bpl @c
	jsr toint
	lda ac0
	sta b0
	lda ac1
	sta b1
	lda #TY_I
	sta bty
	ldx #0
@r2:	pla
	sta aty,x
	inx
	cpx #6
	bne @r2
@r:	rts

; the bitwise operators on integers
op_and:	jsr bit_prep
	lda b0
	and ac0
	sta ac0
	lda b1
	and ac1
	sta ac1
	rts
op_or:	jsr bit_prep
	lda b0
	ora ac0
	sta ac0
	lda b1
	ora ac1
	sta ac1
	rts
op_xor:	jsr bit_prep
	lda b0
	eor ac0
	sta ac0
	lda b1
	eor ac1
	sta ac1
	rts
op_shl:	jsr bit_prep
	lda ac1
	bne @z
	ldx ac0
	cpx #16
	bcs @z
	lda b0
	sta ac0
	lda b1
	sta ac1
	cpx #0
	beq @r
@l:	asl ac0
	rol ac1
	dex
	bne @l
@r:	rts
@z:	stz ac0
	stz ac1
	rts
op_shr:	jsr bit_prep
	lda ac1
	bne @z
	ldx ac0
	cpx #16
	bcs @z
	lda b0
	sta ac0
	lda b1
	sta ac1
	cpx #0
	beq @r
@l:	lsr ac1
	ror ac0
	dex
	bne @l
@r:	rts
@z:	stz ac0
	stz ac1
	rts
bit_prep:
	jsr both_num
	jsr toint
	jmp b_toint

; comparisons: -1 (true) or 0
op_eq:	jsr compare             ; a = -1, 0, 1 (b against acc)
	cmp #0
	beq ctrue
	bra cfalse
op_ne:	jsr compare
	cmp #0
	bne ctrue
	bra cfalse
op_lt:	jsr compare
	cmp #$FF
	beq ctrue
	bra cfalse
op_gt:	jsr compare
	cmp #1
	beq ctrue
	bra cfalse
op_le:	jsr compare
	cmp #1
	bne ctrue
	bra cfalse
op_ge:	jsr compare
	cmp #$FF
	bne ctrue
cfalse:	stz ac0
	stz ac1
	bra cset
ctrue:	lda #$FF
	sta ac0
	sta ac1
cset:	lda #TY_I
	sta aty
	rts

; a = the comparison of b with acc: -1, 0, 1
compare:
	lda aty
	and bty
	cmp #TY_I
	beq @int
	lda aty
	cmp #TY_S
	beq @s
	lda bty
	cmp #TY_S
	beq @e
	jsr both_int
	bcc @f
@int:	lda b0
	cmp ac0
	lda b1
	sbc ac1
	bvc @1
	eor #$80
@1:	bmi @lt
	lda b0
	cmp ac0
	bne @gt
	lda b1
	cmp ac1
	bne @gt
	lda #0
	rts
@lt:	lda #$FF
	rts
@gt:	lda #1
	rts
@f:	jsr toflt
	jsr b_to_fpa
	jmp fcmp_fpa_acc
@s:	lda bty
	cmp #TY_S
	beq @ss
@e:	ERR E_TYPE
@ss:	jmp scompare

; acc = b * acc (integers); carry set when the product does not fit
imul:	lda b1                  ; a factor of 0-255 and the other 0-32767: 8 steps
	ora ac1
	bmi imul_full
	lda ac1
	beq @a8
	lda b1
	bne imul_full
	lda b0                  ; b is the small one
	ldx ac0
	sta ac0
	stx b0
	lda ac1
	sta b1
	stz ac1
@a8:	; b (0-32767) * ac0 (0-255) -> 24 bits
	stz pr
	stz pr+1
	stz pr+2
	lda b0
	sta n0
	lda b1
	sta n0+1
	stz n1
	lda ac0
@l:	lsr a
	bcc @n
	tax
	lda pr
	clc
	adc n0
	sta pr
	lda pr+1
	adc n0+1
	sta pr+1
	lda pr+2
	adc n1
	sta pr+2
	txa
@n:	beq @d8                 ; (no bits left: V107)
	asl n0
	rol n0+1
	rol n1
	bra @l
@d8:	lda pr+2
	bne @big8
	lda pr+1
	bmi @big8
	sta ac1
	lda pr
	sta ac0
	clc
	rts
@big8:	sec
	rts
imul_full:
	lda b1
	eor ac1
	sta t2                  ; the sign
	lda b0
	sta n0
	lda b1
	sta n0+1
	bpl @a
	lda #0
	sec
	sbc n0
	sta n0
	lda #0
	sbc n0+1
	sta n0+1
@a:	lda ac0
	sta n1
	lda ac1
	sta n1+1
	bpl @b
	lda #0
	sec
	sbc n1
	sta n1
	lda #0
	sbc n1+1
	sta n1+1
@b:	stz pr
	stz pr+1
	stz pr+2
	stz pr+3
	ldx #16
@l:	asl pr
	rol pr+1
	rol pr+2
	rol pr+3
	asl n1
	rol n1+1
	bcc @n
	lda pr
	clc
	adc n0
	sta pr
	lda pr+1
	adc n0+1
	sta pr+1
	lda pr+2
	adc #0
	sta pr+2
	lda pr+3
	adc #0
	sta pr+3
@n:	dex
	bne @l
	; fits in 16 signed bits?
	lda pr+2
	ora pr+3
	bne @big
	lda t2
	bmi @neg
	lda pr+1
	bmi @big
	lda pr
	sta ac0
	lda pr+1
	sta ac1
	clc
	rts
@neg:	lda pr+1                ; up to 32768
	cmp #$80
	bcc @ok
	bne @big
	lda pr
	bne @big
@ok:	lda #0
	sec
	sbc pr
	sta ac0
	lda #0
	sbc pr+1
	sta ac1
	clc
	rts
@big:	sec
	rts
pr:	.res 4

; an integer (b) to the power acc (0 or more): products of floats by
; squaring (tools/vbasic.py ipow)
ipow:	lda ac0
	sta pw_e
	lda ac1
	sta pw_e+1
	; pw_b = float(b), pw_r = 1.0
	lda b0
	sta ac0
	lda b1
	sta ac1
	lda #TY_I
	sta aty
	jsr toflt
	ldx #4
@1:	lda ac0,x
	sta pw_b,x
	lda one_f,x
	sta pw_r,x
	dex
	bpl @1
@l:	lda pw_e
	ora pw_e+1
	beq @d
	lda pw_e
	and #1
	beq @2
	; r = r * b
	ldx #4
@3:	lda pw_r,x
	sta fpa,x
	lda pw_b,x
	sta ac0,x
	dex
	bpl @3
	ldy #<FP_FMULTT
	jsr fp_op_fpa_acc
	ldx #4
@4:	lda ac0,x
	sta pw_r,x
	dex
	bpl @4
@2:	lsr pw_e+1
	ror pw_e
	lda pw_e
	ora pw_e+1
	beq @d
	; b = b * b
	ldx #4
@5:	lda pw_b,x
	sta fpa,x
	sta ac0,x
	dex
	bpl @5
	ldy #<FP_FMULTT
	jsr fp_op_fpa_acc
	ldx #4
@6:	lda ac0,x
	sta pw_b,x
	dex
	bpl @6
	bra @l
@d:	ldx #4
@7:	lda pw_r,x
	sta ac0,x
	dex
	bpl @7
	stz aty
	rts
pw_e:	.word 0
pw_b:	.res 5
pw_r:	.res 5
one_f:	.byte $81, 0, 0, 0, 0

;---------------------------------------------------------------
; conversions
;---------------------------------------------------------------
; acc to the type a (TY_*): numbers converted, a string must stay one
convert:
	and #CT_TYPE
	cmp #TY_S
	beq @s
	tax
	lda aty
	cmp #TY_S
	beq @e
	cpx #TY_I
	jeq toint
	jmp toflt
@s:	lda aty
	cmp #TY_S
	bne @e
	rts
@e:	ERR E_TYPE

; acc = 1 as a (TY_I or TY_F)
one_of:	cmp #TY_I
	bne @f
	sta aty
	lda #1
	sta ac0
	stz ac1
	rts
@f:	stz aty
	ldx #4
@c:	lda one_f,x
	sta ac0,x
	dex
	bpl @c
	rts

; acc as a truth value: zero flag set if false (a string: Type mismatch)
truth:	lda aty
	cmp #TY_I
	bne @f
	lda ac0
	ora ac1
	rts
@f:	cmp #TY_S
	beq @e
	lda ac0                  ; a float: its exponent
	rts
@e:	ERR E_TYPE

; acc as an address 0-65535 -> n1 (a float: 0 <= x < 65536, as INT: the
; reference's int_of_float_u16)
to_address:
	lda aty
	cmp #TY_I
	bne @f
	lda ac0
	sta n1
	lda ac1
	sta n1+1
	rts
@f:	cmp #TY_S
	bne @g
	ERR E_TYPE
@g:	lda ac0
	beq @low
	lda ac1
	bmi @ill
	lda ac0
	cmp #$91                ; 65536 and up
	bcs @ill
	cmp #$90                ; below 32768
	bcc @low
	ldx #4                  ; x - 32768: ARG = x, FAC = 32768
@s:	lda ac0,x
	sta fpa,x
	stz ac0,x
	dex
	bpl @s
	lda #$90
	sta ac0
	ldy #<FP_FSUBT
	jsr fp_op_fpa_acc
	jsr toint
	lda ac0
	sta n1
	lda ac1
	ora #$80
	sta n1+1
	rts
@low:	jsr toint
	lda ac0
	sta n1
	lda ac1
	sta n1+1
	rts
@ill:	ERR E_ILLQ

;---------------------------------------------------------------
; functions: ip at the token
;---------------------------------------------------------------
function:
	INCIP
	cmp #$D2
	bcc @lo
	cmp #$F0
	bcs fn_syn
	sbc #$D2 - 1            ; (carry clear: a - $D2)
	asl a
	tax
	jmp (fntab,x)
@lo:	cmp #$89                ; DATA
	bne @1
	jmp fn_data
@1:	cmp #$9F                ; SELECT
	bne fn_syn
	jmp fn_select

fn_syn:	ERR E_SYNTAX

; ( x ) -> acc
arg1:	jsr expect_lp
	jsr eval
	jmp expect_rp

fn_err:	lda errno
	bra fn_byte
fn_errfile:
	lda errfile
fn_byte:
	sta ac0
	stz ac1
	lda #TY_I
	sta aty
	rts
fn_erl:	lda erl
	sta ac0
	lda erl+1
	sta ac1
	lda #TY_I
	sta aty
	rts
fn_errs:
	ldx #0
@l:	lda errmsg,x
	beq @d
	sta sbufa,x
	inx
	bra @l
@d:	txa
	jmp buf_to_temp         ; acc = a temporary of sbufa's x bytes
fn_select:
	lda #4
	bra fn_byte
fn_data:
	lda #5
	bra fn_byte

fn_ti:	jsr K_RDTIM             ; frames since the program started, a float
	sec
	sbc ti0
	sta n0
	txa
	sbc ti0+1
	sta n0+1
	tya
	sbc ti0+2
	sta n1                  ; 24 bits: n1, n0+1, n0
	; as a float: (n1 * 65536 + n0) computed with the ROM
	lda n0
	sta ac0
	lda n0+1
	and #$7F
	sta ac1
	lda #TY_I
	sta aty
	jsr toflt
	ldx #4
@s:	lda ac0,x
	sta fpa,x
	dex
	bpl @s
	; + (n0 bit 15 + n1 * 2) * 32768
	lda n0+1
	asl a                   ; bit 15 into carry
	lda n1
	rol a
	sta ac0
	lda #0
	rol a
	sta ac1
	lda #TY_I
	sta aty
	jsr toflt
	lda ac0
	beq @z
	clc
	adc #15                 ; * 32768
	sta ac0
@z:	ldy #<FP_FADDT
	jmp fp_op_fpa_acc

fn_tis:	; "HHMMSS"
	lda hour
	jsr two_digits
	stx sbufa
	sta sbufa+1
	lda minutes
	jsr two_digits
	stx sbufa+2
	sta sbufa+3
	lda seconds
	jsr two_digits
	stx sbufa+4
	sta sbufa+5
	lda #6
	jmp buf_to_temp

; a (0-99) -> x tens, a units (digits)
two_digits:
	ldx #'0'
@l:	cmp #10
	bcc @d
	sbc #10
	inx
	bra @l
@d:	ora #'0'
	rts

fn_left:
	lda #0
	bra fn_lr
fn_right:
	lda #1
fn_lr:	pha
	jsr expect_lp
	jsr eval
	jsr need_str
	jsr vpush
	lda #','
	jsr expect
	jsr eval
	jsr toint
	jsr expect_rp
	lda ac1
	bne @ill
	lda ac0
	sta t2                  ; n
	jsr vpop_b              ; the string
	jsr b_to_a
	jsr slen                ; t0 = its length
	pla
	beq @left
	; RIGHT$: from len - n (all if n >= len)
	lda t2
	cmp t0
	bcs @all
	lda t0
	sec
	sbc t2
	tax
	lda t2
	jmp substr              ; x = from (0-based), a = count
@left:	lda t2
	cmp t0
	bcc @l2
	lda t0
@l2:	ldx #0
	jmp substr
@all:	rts                     ; the string itself
@ill:	ERR E_ILLQ

fn_mid:	jsr expect_lp
	jsr eval
	jsr need_str
	jsr vpush
	lda #','
	jsr expect
	jsr eval
	jsr toint
	lda ac0
	pha
	lda ac1
	pha
	lda #255
	sta t2
	jsr accept_comma
	bcc @n
	jsr eval
	jsr toint
	lda ac1
	bne @ill2
	lda ac0
	sta t2
@n:	jsr expect_rp
	pla
	bne @ill
	pla
	beq @ill1
	sta t3                  ; start (1-255)
	jsr vpop_b
	jsr b_to_a
	jsr slen
	lda t3
	dec a
	cmp t0
	bcc @in
	lda t0                  ; past the end: ""
	tax
	lda #0
	jmp substr
@in:	tax                     ; from
	lda t0
	stx t3
	sec
	sbc t3                  ; what is left
	cmp t2
	bcc @c
	lda t2
@c:	jmp substr
@ill2:	pla
@ill:	pla
@ill1:	ERR E_ILLQ

fn_len:	jsr arg1
	jsr need_str
	jsr slen
	jsr sfree               ; (a temporary's slot back)
	lda t0
	jmp fn_byte

fn_asc:	jsr arg1
	jsr need_str
	jsr slen
	lda t0
	bne @1
	ERR E_ILLQ
@1:	jsr sfirst              ; a = the first character
	pha
	jsr sfree
	pla
	jmp fn_byte

fn_chr:	jsr arg1
	jsr toint
	lda ac1
	bne @ill
	lda ac0
	sta sbufa
	lda #1
	jmp buf_to_temp
@ill:	ERR E_ILLQ

fn_str:	jsr arg1
	jsr need_num
	jsr num_text            ; numbuf, x = its length
	ldy #0
@c:	lda numbuf,y
	sta sbufa,y
	iny
	dex
	bne @c
	tya
	jmp buf_to_temp

fn_val:	jsr arg1
	jsr need_str
	jsr str_to_buf          ; sbufa, t0
	lda #0                  ; not whole
	jmp parse_num           ; acc = the number

fn_peek:
	jsr arg1
	jsr to_address
	lda (n1)
	jmp fn_byte

fn_fre:	jsr arg1
	jsr fre_bytes           ; acc = a float
	rts

fn_tab:
fn_spc:	jsr arg1
	jsr toint
	lda ac1
	bne @ill
	ldx ac0
	beq @z
	lda #' '
@l:	dex
	sta sbufa,x
	bne @l
@z:	lda ac0
	jmp buf_to_temp
@ill:	ERR E_ILLQ

fn_ubound:
	jsr expect_lp
	lda (ip)
	cmp #T_VAR
	beq @1
	ERR E_NOTARR
@1:	jsr cellref
	lda t0
	and #CT_ARRAY
	bne @2
	ERR E_NOTARR
@2:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda #1
	sta ac0
	stz ac1
	jsr accept_comma
	bcc @3
	jsr eval
	jsr toint
@3:	jsr expect_rp
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	jmp array_ubound        ; acc = the dimension ac0's largest index

fn_sgn:	jsr arg1
	jsr need_num
	lda aty
	cmp #TY_I
	bne @f
	lda ac1
	bmi @m
	ora ac0
	beq @z
@p:	lda #1
	sta ac0
	stz ac1
	rts
@m:	lda #$FF
	sta ac0
	sta ac1
	rts
@z:	rts                     ; 0 (TY_I)
@f:	lda #TY_I
	sta aty
	lda ac0
	beq @zz
	lda ac1
	bmi @m
	bra @p
@zz:	stz ac1
	rts

fn_abs:	jsr arg1
	jsr need_num
	lda aty
	cmp #TY_I
	bne @f
	lda ac1
	bpl @r
	cmp #$80
	bne @n
	lda ac0
	bne @n
	jsr toflt               ; 32768: a float
	lda ac1
	and #$7F
	sta ac1
	rts
@n:	lda #0
	sec
	sbc ac0
	sta ac0
	lda #0
	sbc ac1
	sta ac1
@r:	rts
@f:	ldy #<FP_ABS
	jmp fp_fn

fn_int:	jsr arg1
	jsr need_num
	lda aty
	cmp #TY_I
	beq @r
	ldy #<FP_INT
	jmp fp_fn
@r:	rts

fn_sqr:	ldy #<FP_SQR
	bra fn_math
fn_sin:	ldy #<FP_SIN
	bra fn_math
fn_cos:	ldy #<FP_COS
	bra fn_math
fn_tan:	ldy #<FP_TAN
	bra fn_math
fn_atn:	ldy #<FP_ATN
	bra fn_math
fn_exp:	ldy #<FP_EXP
	bra fn_math
fn_log:	ldy #<FP_LOG
fn_math:
	phy
	jsr arg1
	jsr need_num
	jsr toflt
	ply
	jmp fp_fn

fn_rnd:	jsr arg1
	jsr need_num
	jsr toflt
	jmp fp_rnd

fn_inkey:
	jsr key_get             ; a = a key, carry clear if none
	bcc @none
	sta sbufa
	lda #1
	jmp buf_to_temp
@none:	lda #0
	jmp buf_to_temp

;---------------------------------------------------------------
.segment RO_SEG
; the operator's number by token (0: none): $2A-$5F from 0, $C8-$D1 from
; 54 (tok_prec gives the place); its precedence by number
opidx:	.byte OP_MUL, OP_ADD, 0, OP_SUB, 0, OP_DIV, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, OP_LT, OP_EQ, OP_GT, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, OP_IDIV, 0, OP_POW, 0, OP_AND, OP_OR, OP_XOR, 0, OP_MOD, OP_SHL, OP_SHR, OP_LE, OP_NE, OP_GE
opprec:	.byte 0, 1, 1, 2, 4, 4, 4, 4, 4, 4, 5, 5, 6, 6, 7, 7, 7, 7, 9
optab:	.word fn_syn, op_or, op_xor, op_and, op_eq, op_ne, op_lt, op_gt, op_le, op_ge
	.word op_shl, op_shr, op_add, op_sub, op_mul, op_div, op_idiv, op_mod, op_pow

; the functions by token ($80-$FE)
.define FNS fn_left, fn_mid, fn_right, fn_len, fn_str, fn_val, fn_chr, fn_asc, fn_int, fn_abs, fn_sgn, fn_sqr, fn_sin, fn_cos, fn_tan, fn_atn, fn_exp, fn_log, fn_rnd, fn_peek, fn_ti, fn_tis, fn_fre, fn_tab, fn_spc, fn_ubound, fn_err, fn_errs, fn_erl, fn_errfile
fntab:				; ($D2-$EF; DATA and SELECT by function)
.repeat $1E, I
	.word .mid(I * 2, 1, {FNS})
.endrepeat
.segment "CODE"
