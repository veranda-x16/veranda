; VeraBASIC Run: the ROM's maths, numbers as text and from text, the
; console's text, PRINT, INPUT, GET, READ (included by vb.s).
; MIT licence (LICENSE).

;---------------------------------------------------------------
; the X16 ROM's maths library: ROM bank 4, through its jump table. The
; bank has no interrupt vectors, so the interrupt is off while it is in;
; its errors come through BASIC's error vector to fp_error.
;---------------------------------------------------------------
rom_in:	sei
	pha
	lda #<fp_error
	sta IERROR
	lda #>fp_error
	sta IERROR+1
	lda rom_bank
	sta romkeep
	lda #MATHBANK
	sta rom_bank
	pla
	rts

rom_out:
	php
	pha
	lda romkeep
	sta rom_bank
	pla
	plp
	cli
	rts

; the library's error: x its number (14 illegal quantity, 15 overflow,
; 20 division by zero)
fp_error:
	lda romkeep
	sta rom_bank
	cli
	lda #E_ILLQ
	cpx #15
	bne @1
	lda #E_OVER
@1:	cpx #20
	bne @2
	lda #E_DIV0
@2:	jmp raise

.macro ROMCALL addr
	jsr rom_in
	jsr addr
	jsr rom_out
.endmacro

; FAC = (ac0 .. ac4)
fac_acc:
	lda #<ac0
	ldy #>ac0
	ROMCALL FP_MOVFM
	rts

; (ac0 .. ac4) = FAC, acc a float
acc_fac:
	ldx #<ac0
	ldy #>ac0
	ROMCALL FP_MOVMF
	stz aty
	rts

; acc to a float (an integer converted; a string: Type mismatch). The
; conversion is done here, exactly as the ROM's givayf + movmf give it (a
; whole number has one 5-byte form; tools/vbrom.py and the gate's
; check_fpnative.py hold them to the ROM bit for bit)
toflt:	lda aty
	beq @r
	cmp #TY_S
	beq @e
	stz aty
	lda ac0
	ora ac1
	beq @z
	lda ac1
	and #$80
	sta t3                  ; the sign
	bpl @p
	lda #0
	sec
	sbc ac0
	sta ac0
	lda #0
	sbc ac1
	sta ac1
@p:	ldx #$90                ; the exponent; normalized: bit 15 set
	lda ac1
@n:	cmp #$80
	bcs @d
	asl ac0
	rol a
	dex
	bra @n
@d:	and #$7F
	ora t3
	sta ac1
	lda ac0
	sta ac2
	stx ac0
	stz ac3
	stz ac4
	rts
@z:	stz ac2
	stz ac3
	stz ac4
@r:	rts
@e:	ERR E_TYPE

; acc to an integer: a float as the ROM's ayint (the largest whole number
; not above it; outside -32768 .. 32767 Illegal quantity), done here
toint:	lda aty
	cmp #TY_I
	jeq @r
	cmp #TY_S
	jeq @e
	lda #TY_I
	sta aty
	lda ac0
	beq @zero
	cmp #$81
	bcc @small
	cmp #$90
	bcs @big
	; $81 .. $8F: the integer part is the top (e - $80) bits
	sbc #$80 - 1            ; (carry clear: e - $80 - 1 + 1 ... a = e - $80)
	sta t2                  ; bits
	lda ac1
	sta t3                  ; the sign
	ora #$80
	sta n0+1
	lda ac2
	sta n0
	; the fraction: the bits shifted out, and bytes 3 and 4
	lda ac3
	ora ac4
	sta t1
	lda #16
	sec
	sbc t2
	tax                     ; shifts (1 .. 15)
@s:	lsr n0+1
	ror n0
	bcc @s1
	lda #1                  ; a fraction bit
	tsb t1
@s1:	dex
	bne @s
	lda t3
	bpl @pos
	; negative: -(n0) - (fraction ? 1 : 0)
	lda #0
	sec
	sbc n0
	sta ac0
	lda #0
	sbc n0+1
	sta ac1
	lda t1
	beq @r
	lda ac0
	bne @d1
	dec ac1
@d1:	dec ac0
	rts
@pos:	lda n0
	sta ac0
	lda n0+1
	sta ac1
	rts
@zero:	stz ac1
	rts
@small:	lda ac1                 ; |x| < 1: 0, or -1 below 0
	bmi @m1
	stz ac0
	stz ac1
	rts
@m1:	lda #$FF
	sta ac0
	sta ac1
	rts
@big:	bne @ill                ; 65536 and up
	lda ac1                 ; only -32768 itself
	cmp #$80
	bne @ill
	lda ac2
	ora ac3
	ora ac4
	bne @ill
	stz ac0
	lda #$80
	sta ac1
@r:	rts
@ill:	lda #TY_F
	sta aty
	ERR E_ILLQ
@e:	ERR E_TYPE

; acc = fpa op acc: ARG = fpa, FAC = acc, the routine at $FE00 + y
fp_op_fpa_acc:
	sty @j+1
	jsr rom_in
	lda #<fpa
	ldy #>fpa
	jsr FP_CONUPK
	lda #<ac0
	ldy #>ac0
	jsr FP_MOVFM
	lda FAC                 ; (a = the exponent, as tools/vbrom.py calls them)
@j:	jsr $FE00
	ldx #<ac0
	ldy #>ac0
	jsr FP_MOVMF
	jsr rom_out
	stz aty
	rts

fp_add_fpa_acc:
	ldy #<FP_FADDT
	jmp fp_op_fpa_acc

; acc = f(acc): the routine at $FE00 + y
fp_fn:	sty @j+1
	jsr rom_in
	lda #<ac0
	ldy #>ac0
	jsr FP_MOVFM
@j:	jsr $FE00
	ldx #<ac0
	ldy #>ac0
	jsr FP_MOVMF
	jsr rom_out
	stz aty
	rts

; a = fpa compared with the float at ac0 / b0 / the value stack: -1, 0, 1
; (done here as the ROM's fcomp does it: the 5-byte forms are exact)
fcmp_fpa_acc:
	ldx #4
@c:	lda ac0,x
	sta fcb,x
	dex
	bpl @c
	bra fcmp
fcmp_fpa_b:
	ldx #4
@c:	lda b0,x
	sta fcb,x
	dex
	bpl @c
	bra fcmp
fcmp_fpa_vstk:			; x = vsp: the value at vstk - 6 (its 5 bytes)
	ldy #0
@c:	lda vstk-5,x
	sta fcb,y
	inx
	iny
	cpy #5
	bne @c
fcmp:	lda fpa
	bne @an
	lda fcb                 ; a = 0
	beq @eq
	lda fcb+1
	bmi @gt
	bra @lt
@an:	lda fcb
	bne @both
	lda fpa+1               ; b = 0
	bmi @lt
	bra @gt
@both:	lda fpa+1
	eor fcb+1
	bpl @same
	lda fpa+1               ; signs differ
	bmi @lt
	bra @gt
@same:	lda fpa                 ; magnitudes
	cmp fcb
	bne @mag
	lda fpa+1
	and #$7F
	sta t3
	lda fcb+1
	and #$7F
	sta t2
	lda t3
	cmp t2
	bne @mag
	ldx #2
@m:	lda fpa,x
	cmp fcb,x
	bne @mag
	inx
	cpx #5
	bne @m
@eq:	lda #0
	rts
@mag:	bcc @smaller            ; (they differ: carry set, a is the larger)
	lda fpa+1
	bmi @lt
	bra @gt
@smaller:
	lda fpa+1
	bmi @gt
@lt:	lda #$FF
	rts
@gt:	lda #1
	rts
fcb:	.res 5

; acc = RND(acc) (a float): the flags of its sign, as tools/vbrom.py
fp_rnd:	jsr rom_in
	lda #<ac0
	ldy #>ac0
	jsr FP_MOVFM
	jsr FP_SIGN
	sta t2
	ldx #0
	ldy #0
	lda t2
	beq @zero
	bmi @neg
	lda #1
	bra @go
@neg:	lda #$80
	bra @go
@zero:	lda VERA_SCAN_L         ; RND(0): entropy
	ldx t_slice
	ldy t_slice+1
	bit zerob
@go:	jsr FP_RND
	ldx #<ac0
	ldy #>ac0
	jsr FP_MOVMF
	jsr rom_out
	stz aty
	rts
zerob:	.byte 0

;---------------------------------------------------------------
; numbers as text
;---------------------------------------------------------------
; a (low), x (high): a signed integer -> numbuf (" 12" or "-12", 0 at
; its end), x = its length
int_to_text:
	sta it_v
	stx it_v+1
	lda #' '
	sta numbuf
	lda it_v+1
	bpl @p
	lda #'-'
	sta numbuf
	lda #0
	sec
	sbc it_v
	sta it_v
	lda #0
	sbc it_v+1
	sta it_v+1
@p:	; digits, highest first: by 10000 .. 1
	ldx #1
	stz it_z
	ldy #0
@d:	lda #'0'
	sta it_c
@s:	lda it_v
	sec
	sbc pow10l,y
	pha
	lda it_v+1
	sbc pow10h,y
	bcc @n
	sta it_v+1
	pla
	sta it_v
	inc it_c
	bra @s
@n:	pla
	lda it_c
	cmp #'0'
	bne @w
	lda it_z
	bne @w
	cpy #4
	bne @x                  ; leading zeros left out (not the last)
@w:	lda it_c
	sta numbuf,x
	inx
	lda #1
	sta it_z
@x:	iny
	cpy #5
	bne @d
	stz numbuf,x
	rts
it_v:	.word 0
it_c:	.byte 0
it_z:	.byte 0
pow10l:	.byte <10000, <1000, <100, <10, <1
pow10h:	.byte >10000, >1000, >100, >10, >1

; acc (a number) -> numbuf as PRINT shows it (no blank after), x its length
num_text:
	lda aty
	cmp #TY_I
	bne @f
	lda ac0
	ldx ac1
	jmp int_to_text
@f:	jsr fac_acc
	ROMCALL FP_FOUT
	ldx #0
@c:	lda FBUFFR,x
	sta numbuf,x
	beq @d
	inx
	cpx #39
	bcc @c
	stz numbuf,x
@d:	rts

;---------------------------------------------------------------
; numbers from text (VAL, INPUT, READ: tools/vbasic.py parse_number):
; sbufa, t0 its length; a = 1: all of it (but blanks) must be the number,
; else carry set. acc = the number (an integer when it is a whole one
; that fits, written without "." or an exponent)
;---------------------------------------------------------------
parse_num:
	sta pn_arg
	lda #<parse_num1
	ldx #>parse_num1
	jsr ovl_call
	lda pn_ok
	lsr a                   ; (carry: its result)
	rts
pn_arg:	.byte 0
pn_ok:	.byte 0

;---------------------------------------------------------------
; the console's text (main.c draws it): CON_W columns; a character past
; the last column starts the next line first
;---------------------------------------------------------------
_con_reset:
	lda ram_bank
	pha
	jsr con_reset2
	pla
	sta ram_bank
	rts
con_reset2:
	stz _ctop
	stz _ccy
	stz _ccol
	stz _cscroll
	stz _cwait
	ldx #0
@d:	lda #1
	sta _cdirty,x
	inx
	cpx #CON_H
	bne @d
	; every row blank
	lda _cbank
	sta ram_bank
	lda #<$A000
	sta bp1
	lda #>$A000
	sta bp1+1
	ldx #CON_H
@r:	ldy #CON_W - 1
	lda #' '
@c:	sta (bp1),y
	dey
	bpl @c
	lda bp1
	clc
	adc #CON_W
	sta bp1
	bcc @n
	inc bp1+1
@n:	dex
	bne @r
	MAPP
	jmp con_rowp

; crowp = the cursor row's text
con_rowp:
	lda _ctop
	clc
	adc _ccy
	cmp #CON_H
	bcc @1
	sbc #CON_H
@1:	tax
	lda rowl,x
	sta crowp
	lda rowh,x
	sta crowp+1
	rts

; a character
con_putc:
	ldx _ccol
	cpx #CON_W
	bcc @1
	pha
	jsr con_newline
	pla
	ldx _ccol
@1:	pha
	lda crowp
	sta bp1
	lda crowp+1
	sta bp1+1
	txa
	tay
	lda _cbank
	sta ram_bank
	pla
	sta (bp1),y
	MAPP
	inc _ccol
	ldx _ccy
	lda #1
	sta _cdirty,x
	rts

; the line ends: logged (the test build), the cursor to the next row
con_newline:
.ifdef VB_LOG
	lda _vb_test
	beq @nl
	jsr _vb_logline         ; (main.c: "VB| " and the row's _ccol characters)
@nl:
.endif
	stz _ccol
	lda _ccy
	cmp #CON_H - 1
	bcs @scroll
	inc _ccy
	jsr con_rowp
	rts
@scroll:
	lda _ctop
	inc a
	cmp #CON_H
	bcc @2
	lda #0
@2:	sta _ctop
	lda _cscroll
	cmp #CON_H
	bcs @3
	inc _cscroll
@3:	ldx #0                  ; the rows' flags move up with them
@m:	lda _cdirty+1,x
	sta _cdirty,x
	inx
	cpx #CON_H - 1
	bne @m
	lda #1
	sta _cdirty + CON_H - 1
	jsr con_rowp
	lda crowp
	sta bp1
	lda crowp+1
	sta bp1+1
	lda _cbank
	sta ram_bank
	ldy #CON_W - 1
	lda #' '
@c:	sta (bp1),y
	dey
	bpl @c
	MAPP
	rts

; x bytes from numbuf
con_putnum:
	stx t3
	ldx #0
@l:	cpx t3
	beq @r
	phx
	lda numbuf,x
	jsr con_putc
	plx
	inx
	bra @l
@r:	rts

; t0 bytes from sbufa
con_putbuf:
	ldx #0
@l:	cpx t0
	beq @r
	phx
	lda sbufa,x
	jsr con_putc
	plx
	inx
	bra @l
@r:	rts

; the 0-ended text at p1
con_puts:
	ldy #0
@l:	lda (p1),y
	beq @r
	phy
	jsr con_putc
	ply
	iny
	bne @l
@r:	rts

; a line of its own: the 0-ended text at p1 (a new line first if needed)
con_message:
	lda _ccol
	beq @1
	lda p1
	pha
	lda p1+1
	pha
	jsr con_newline
	pla
	sta p1+1
	pla
	sta p1
@1:	jsr con_puts
	jmp con_newline

; "Error n, message, in line l" or "Stopped in line l"
con_message_err:
	ldx #0
	lda errno
	cmp #E_STOP
	bne @e
	lda #<MStopped
	sta p1
	lda #>MStopped
	sta p1+1
	jsr cat
	bra @line
@e:	lda #<MError
	sta p1
	lda #>MError
	sta p1+1
	jsr cat
	phx
	lda errno
	ldx #0
	jsr int_to_text
	plx
	jsr cat_num
	lda #<MComma
	sta p1
	lda #>MComma
	sta p1+1
	jsr cat
	lda #<errmsg
	sta p1
	lda #>errmsg
	sta p1+1
	jsr cat
	lda #<MInLine
	sta p1
	lda #>MInLine
	sta p1+1
	jsr cat
@line:	phx
	lda erl
	ldx erl+1
	jsr int_to_text
	plx
	jsr cat_num
	stz sbufb,x
	lda #<sbufb
	sta p1
	lda #>sbufb
	sta p1+1
	jmp con_message
; the 0-ended text at p1 onto sbufb at x
cat:	ldy #0
@l:	lda (p1),y
	beq @r
	sta sbufb,x
	inx
	iny
	bne @l
@r:	rts
; numbuf without its first character (the blank of a positive number)
cat_num:
	ldy #1
@l:	lda numbuf,y
	beq @r
	sta sbufb,x
	inx
	iny
	bra @l
@r:	rts

; the program's end: an open line closed
con_end:
	lda _ccol
	beq @r
	jsr con_newline
@r:	rts

;---------------------------------------------------------------
; keys
;---------------------------------------------------------------
; a = the next key, carry set; carry clear if none (the test: its keys)
key_get:
	ldx _kqh
	cpx _kqt
	beq @none
	lda _kq,x
	pha
	inx
	txa
	and #31
	sta _kqh
	pla
	sec
	rts
@none:	lda _vb_test
	beq @no
	lda _scr_ptr+1
	beq @no
	lda _scr_ptr
	cmp _scr_end
	lda _scr_ptr+1
	sbc _scr_end+1
	bcs @no
	lda _scr_ptr
	sta bp1
	lda _scr_ptr+1
	sta bp1+1
	lda _tbank
	sta ram_bank
	lda (bp1)
	tax
	MAPP
	txa
	inc _scr_ptr
	bne @1
	inc _scr_ptr+1
@1:	cmp #10
	bne @2
	lda #13
@2:	sec
	rts
@no:	clc
	rts

; the test: no keys left at all? (carry set)
keys_out:
	lda _vb_test
	beq @no
	ldx _kqh
	cpx _kqt
	bne @no
	lda _scr_ptr
	cmp _scr_end
	lda _scr_ptr+1
	sbc _scr_end+1
	bcc @no
	sec
	rts
@no:	clc
	rts

;---------------------------------------------------------------
; PRINT
;---------------------------------------------------------------
st_print:
	lda (ip)
	cmp #'#'
	bne @1
	lda #XP_PRINT           ; PRINT #: overlay 6 (phase 4, vbui.s)
	jmp ext_stmt_a
@1:	lda #1
	sta pr_nl
@l:	jsr at_end
	jeq @done
	lda (ip)
	cmp #';'
	bne @2
	INCIP
	stz pr_nl
	bra @l
@2:	cmp #','
	bne @3
	INCIP
	; the next zone of 10
	lda _ccol
	ldx #0
@z:	cmp #10
	bcc @zz
	sbc #10
	inx
	bra @z
@zz:	inx
	txa
	asl a
	sta t2
	asl a
	asl a
	clc
	adc t2                  ; (col / 10 + 1) * 10
	cmp #CON_W
	bcc @pad
	jsr con_newline
	bra @c0
@pad:	sta t2
@p:	lda _ccol
	cmp t2
	bcs @c0
	lda #' '
	jsr con_putc
	bra @p
@c0:	stz pr_nl
	bra @l
@3:	cmp #TK_TAB
	beq @ts
	cmp #TK_SPC
	bne @val
@ts:	pha
	INCIP
	jsr arg1
	jsr toint
	pla
	ldx ac1
	bne @ill
	cmp #TK_TAB
	bne @spc
	lda ac0                  ; n mod CON_W
@md:	cmp #CON_W
	bcc @mok
	sbc #CON_W
	bra @md
@mok:	sta t2
	lda _ccol
	cmp #CON_W
	bcc @tp
	jsr con_newline
@tp:	lda _ccol
	cmp t2
	bcs @t1
	lda #' '
	jsr con_putc
	bra @tp
@spc:	lda ac0
	sta t2
@sp:	lda t2
	beq @t1
	lda #' '
	jsr con_putc
	dec t2
	bra @sp
@t1:	lda #1
	sta pr_nl
	jmp @l
@ill:	ERR E_ILLQ
@val:	jsr eval            ; (pr_nl is set after it: a FUNCTION may PRINT)
	lda aty
	cmp #TY_S
	bne @num
	jsr str_to_buf
	jsr con_putbuf
	bra @v1
@num:	jsr num_text
	jsr con_putnum
	lda #' '
	jsr con_putc
@v1:	lda #1
	sta pr_nl
	jmp @l
@done:	lda pr_nl
	beq @r
	jsr con_newline
@r:	rts
pr_nl:	.byte 0

;---------------------------------------------------------------
; INPUT ["prompt";|,] v [, v] ... / LINE INPUT ["prompt";] v$: the line is
; typed over several slices (the statement runs again until Return)
;---------------------------------------------------------------
st_lineinput:
	lda #1
	bra in_go
st_input:
	lda #0
in_go:	ldx inp_on
	beq @first
	jmp in_edit
@first:	sta inp_line
	lda (ip)
	cmp #'#'
	bne @1
	lda #XP_INPUT           ; INPUT #, LINE INPUT # (inp_line): overlay 6
	jmp ext_stmt_a
@1:	stz inp_q
	stz inp_pr
	cmp #T_STRING
	bne @np
	; the prompt: a string, then ; or ,
	ldy #1
	lda (ip),y
	sta inp_pr
	lda ip
	clc
	adc #2
	sta inp_pp
	lda ip+1
	adc #0
	sta inp_pp+1
	lda pbank
	sta inp_pb
	jsr skip_tok
	lda (ip)
	cmp #';'
	beq @semi
	cmp #','
	beq @com
	ERR E_SYNTAX
@semi:	lda inp_line
	bne @com
	lda #1
	sta inp_q               ; "? " after it
@com:	INCIP
	bra @tg
@np:	lda inp_line
	bne @tg
	lda #1
	sta inp_q
@tg:	lda ip
	sta inp_t0
	lda ip+1
	sta inp_t0+1
	lda pbank
	sta inp_t0b
	lda inp_line
	beq in_start
	; LINE INPUT: the target must be a string (before the line is typed)
	jsr lvalue
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq in_start
	ERR E_TYPE

; the prompt out, a new line to type from the first target
in_start:
	lda inp_t0
	sta inp_tgt
	lda inp_t0+1
	sta inp_tgt+1
	lda inp_t0b
	sta inp_tgtb
	jsr in_prompt
	stz inp_more
in_newline:
	stz inp_len
	stz inp_ok
	lda #1
	sta inp_on
in_edit:
	jsr key_get
	bcc @nokey
	cmp #13
	beq @ret
	cmp #$14
	beq @bs
	cmp #BACKSPACE
	beq @bs
	cmp #32
	bcc in_edit
	cmp #$80
	bcc @ch
	cmp #$A0
	bcc in_edit
@ch:	ldx inp_len
	cpx #250
	bcs in_edit
	sta inbuf,x
	inc inp_len
	jsr con_putc
	bra in_edit
@bs:	lda inp_len
	beq in_edit
	dec inp_len
	lda _ccol
	beq in_edit
	dec _ccol
	ldy _ccol
	lda crowp
	sta bp1
	lda crowp+1
	sta bp1+1
	lda _cbank
	sta ram_bank
	lda #' '
	sta (bp1),y
	MAPP
	ldx _ccy
	lda #1
	sta _cdirty,x
	bra in_edit
@nokey:	jsr keys_out
	bcc @wait
	; the test has no keys left: the program ends here
	lda #2
	sta _vb_how
	jmp stop_program
@wait:	lda #1
	sta _cwait
	lda sip
	sta ip
	lda sip+1
	sta ip+1
	lda sipb
	sta pbank
	jmp yield
@ret:	stz _cwait
	jsr con_newline
	; the line is in inbuf: to the targets
	lda inp_line
	beq in_fields
	stz inp_on
	lda inp_tgt
	sta ip
	lda inp_tgt+1
	sta ip+1
	lda inp_tgtb
	sta pbank
	sta ram_bank
	jsr lvalue
	jsr push_target
	ldx inp_len
@lc:	dex
	bmi @ld
	lda inbuf,x
	sta sbufa,x
	bra @lc
@ld:	lda inp_len
	jsr buf_to_temp
	jsr pull_target
	jsr store
	jmp in_end

in_fields:
	lda #0                  ; the line's first field
	sta inp_pos
	lda inp_more
	bne in_assign
	; from the first target
in_assign:
	lda inp_tgt
	sta ip
	lda inp_tgt+1
	sta ip+1
	lda inp_tgtb
	sta pbank
	sta ram_bank
@t:	; this target: a field for it
	lda ip
	sta inp_tgt
	lda ip+1
	sta inp_tgt+1
	lda pbank
	sta inp_tgtb
	lda inp_pos
	cmp #$FF
	bne @have
	; none left: "?? " and another line
	lda #<MMore
	sta p1
	lda #>MMore
	sta p1+1
	jsr con_puts
	lda #1
	sta inp_more
	jmp in_newline
@have:	jsr next_field          ; sbufa, t0
	jsr lvalue
	lda t0
	pha
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @str
	; a number: empty is 0
	pla
	jsr push_target
	jsr field_blank         ; carry set: only blanks
	bcc @num
	stz ac0
	stz ac1
	lda #TY_I
	sta aty
	bra @st
@num:	lda #1
	jsr parse_num
	bcc @st
	; not a number: Redo from start
	jsr pull_target
	lda #<MRedo
	sta p1
	lda #>MRedo
	sta p1+1
	jsr con_message
	jmp in_start
@str:	pla
	jsr push_target
	lda fld_n
	jsr buf_to_temp
@st:	jsr pull_target
	jsr store
	jsr accept_comma
	bcc @end
	jmp @t
@end:	lda inp_pos
	cmp #$FF
	beq in_end
	lda #<MExtra
	sta p1
	lda #>MExtra
	sta p1+1
	jsr con_message
in_end:	stz inp_on
	jmp need_end

; the prompt: its text and "? "
in_prompt:
	lda inp_pr
	beq @q
	lda inp_pp
	sta bp1
	lda inp_pp+1
	sta bp1+1
	lda inp_pb
	sta ram_bank
	ldy #0
@c:	lda (bp1),y
	sta sbufb,y
	iny
	cpy inp_pr
	bne @c
	MAPP
	ldx #0
@o:	phx
	lda sbufb,x
	jsr con_putc
	plx
	inx
	cpx inp_pr
	bne @o
@q:	lda inp_q
	beq @r
	lda #'?'
	jsr con_putc
	lda #' '
	jmp con_putc
@r:	rts
inp_q:	.byte 0
inp_pr:	.byte 0
inp_pp:	.word 0
inp_pb:	.byte 0
inp_t0:	.word 0
inp_t0b: .byte 0

; the next INPUT field from inbuf at inp_pos -> sbufa, t0 = fld_n its length;
; inp_pos past it ($FF: no more), as tools/vbasic.py fields()
next_field:
	ldx inp_pos
@sp:	cpx inp_len
	bcs @plain
	lda inbuf,x
	cmp #' '
	bne @q
	inx
	bra @sp
@q:	cmp #'"'
	bne @plain
	inx
	ldy #0
@qc:	cpx inp_len
	bcs @qe
	lda inbuf,x
	cmp #'"'
	beq @qd
	sta sbufa,y
	iny
	inx
	bra @qc
@qd:	inx
@qs:	cpx inp_len             ; on to the comma
	bcs @qe
	lda inbuf,x
	cmp #','
	beq @qe
	inx
	bra @qs
@qe:	sty fld_n
	bra @next
@plain:	ldy #0
@pc:	cpx inp_len
	bcs @pe
	lda inbuf,x
	cmp #','
	beq @pe
	sta sbufa,y
	iny
	inx
	bra @pc
@pe:	; trailing blanks off
@tb:	cpy #0
	beq @tz
	lda sbufa-1,y
	cmp #' '
	bne @tz
	dey
	bra @tb
@tz:	sty fld_n
@next:	cpx inp_len
	bcc @more
	lda #$FF
	sta inp_pos
	bra @r
@more:	inx                     ; past the comma
	stx inp_pos
@r:	lda fld_n
	sta t0
	rts
fld_n:	.byte 0

; sbufa (t0) only blanks? carry set
field_blank:
	ldx #0
@l:	cpx fld_n
	beq @y
	lda sbufa,x
	cmp #' '
	bne @n
	inx
	bra @l
@y:	sec
	rts
@n:	lda fld_n
	sta t0
	clc
	rts

; GET v$: the next key, "" if none
st_get:	lda (ip)
	cmp #'#'
	bne @1
	lda #XP_GET             ; GET #: overlay 6
	jmp ext_stmt_a
@1:	jsr lvalue
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @2
	ERR E_TYPE
@2:	jsr push_target
	jsr key_get
	bcc @none
	sta sbufa
	lda #1
	bra @t
@none:	lda #0
@t:	jsr buf_to_temp
	jsr pull_target
	jmp store

;---------------------------------------------------------------
; READ, RESTORE: the DATA index in mbank (2 bytes an item: its offset)
;---------------------------------------------------------------
st_read:
@l:	jsr lvalue
	jsr push_target
	lda dataptr
	cmp _ndata
	lda dataptr+1
	sbc _ndata+1
	bcc @1
	ERR E_DATA
@1:	; the item's offset
	lda dataptr
	asl a
	sta bp1
	lda dataptr+1
	rol a
	ora #$A0
	sta bp1+1
	lda _mbank
	sta ram_bank
	ldy #0
	lda (bp1),y
	sta n0
	iny
	lda (bp1),y
	sta n0+1
	MAPP
	inc dataptr
	bne @2
	inc dataptr+1
@2:	; the item: TAG_DATA, length, text (in the program's banks)
	lda n0+1
	jsr div31
	clc
	adc #$A0
	sta bp1+1
	txa
	clc
	adc _pbase
	sta rd_b
	lda n0
	sta bp1
	lda rd_b
	sta ram_bank
	ldy #1
	lda (bp1),y
	sta rd_n
	; the text without its blanks: from rd_s for rd_n
	lda #2
	sta rd_s
@lb:	lda rd_n
	beq @tr
	ldy rd_s
	lda (bp1),y
	cmp #' '
	bne @tr
	inc rd_s
	dec rd_n
	bra @lb
@tr:	lda rd_n
	beq @td
	clc
	adc rd_s
	tay
	dey
	lda (bp1),y
	cmp #' '
	bne @td
	dec rd_n
	bra @tr
@td:	MAPP
	jsr pull_target
	lda t0
	and #CT_TYPE
	cmp #TY_S
	bne @num
	; a string: the item's own bytes, quotes off
	jsr push_target
	lda rd_b
	sta ram_bank
	lda rd_n
	beq @sl
	ldy rd_s
	lda (bp1),y
	cmp #'"'
	bne @sl
	inc rd_s
	dec rd_n
	ldx #0
	ldy rd_s
@qf:	cpx rd_n
	beq @qd
	lda (bp1),y
	cmp #'"'
	beq @qd
	inx
	iny
	bra @qf
@qd:	stx rd_n
@sl:	MAPP
	lda bp1
	clc
	adc rd_s
	sta ac1
	lda bp1+1
	adc #0
	sta ac2
	lda rd_n
	sta ac0
	lda rd_b
	sta ac3
	lda #SK_LIT
	sta ac4
	lda #TY_S
	sta aty
	jsr pull_target
	jsr store
	bra @nx
@num:	; a number: the whole item (empty: 0)
	jsr push_target
	lda rd_b
	sta ram_bank
	ldx #0
	ldy rd_s
@cp:	cpx rd_n
	beq @cd
	lda (bp1),y
	sta sbufa,x
	inx
	iny
	bra @cp
@cd:	MAPP
	stx t0
	cpx #0
	bne @pn
	stz ac0
	stz ac1
	lda #TY_I
	sta aty
	bra @ps
@pn:	lda #1
	jsr parse_num
	bcc @ps
	ERR E_TYPE
@ps:	jsr pull_target
	jsr store
@nx:	jsr accept_comma
	bcc @r
	jmp @l
@r:	rts
rd_b:	.byte 0
rd_n:	.byte 0
rd_s:	.byte 0

st_restore:
	jsr at_end
	bne @t
	stz dataptr
	stz dataptr+1
	rts
@t:	jsr ref_target          ; p1, a: the line record
	pha
	jsr need_end
	pla
	; its offset: (bank - pbase) * 31 * 256 + p1 - $A000
	sec
	sbc _pbase
	tax
	lda mul31,x
	clc
	adc p1+1
	sec
	sbc #$A0
	sta n0+1
	lda p1
	sta n0
	; the first item at or after it
	stz dataptr
	stz dataptr+1
	lda #<$A000
	sta bp1
	lda #>$A000
	sta bp1+1
@l:	lda dataptr
	cmp _ndata
	lda dataptr+1
	sbc _ndata+1
	bcs @d
	lda _mbank
	sta ram_bank
	ldy #0
	lda (bp1),y
	cmp n0
	iny
	lda (bp1),y
	sbc n0+1
	bcs @d
	lda bp1
	clc
	adc #2
	sta bp1
	bcc @1
	inc bp1+1
@1:	inc dataptr
	bne @l
	inc dataptr+1
	bra @l
@d:	MAPP
	rts

.segment RO_SEG
MStopped: .byte "Stopped in line ", 0
MError:	.byte "Error ", 0
MComma:	.byte ", ", 0
MInLine: .byte ", in line ", 0
MMore:	.byte "?? ", 0
MRedo:	.byte "Redo from start", 0
MExtra:	.byte "Extra ignored", 0
rowl:
.repeat CON_H, I
	.byte <($A000 + I * CON_W)
.endrepeat
rowh:
.repeat CON_H, I
	.byte >($A000 + I * CON_W)
.endrepeat
.segment "CODE"

; overlay 1 (main.c's bank, appBank): what runs seldom
.segment "OVERLAY1"
; ERR$ for errno into errmsg
err_fetch:
	lda errno
	jsr errtext
	ldy #0
@m:	lda (p1),y
	sta errmsg,y
	beq @r
	iny
	cpy #63
	bcc @m
	lda #0
	sta errmsg,y
@r:	rts

; x = 0: a = the error -> p1 its message (errmsg for ERROR's own)
errtext:
	cmp #E_MENUS + 1
	bcs @fe
	asl a
	tax
	lda errtab,x
	sta p1
	lda errtab+1,x
	sta p1+1
	rts
@fe:	cmp #E_FNF              ; 50 ..: files, pictures, dialogs (phase 4)
	bcc @own
	cmp #E_DLG + 1
	bcs @own
	sbc #E_FNF - 1          ; (carry clear: a - 50)
	asl a
	tax
	lda errtab2,x
	sta p1
	lda errtab2+1,x
	sta p1+1
	rts
@own:	sta t0                  ; "Error n"
	ldx #0
@c:	lda MErrN,x
	sta numbuf+20,x
	beq @d
	inx
	bra @c
@d:	phx
	lda t0
	ldx #0
	jsr int_to_text         ; numbuf: " n"
	plx
	ldy #0
@e:	lda numbuf,y
	sta numbuf+20,x
	beq @f
	inx
	iny
	bra @e
@f:	lda #<(numbuf+20)
	sta p1
	lda #>(numbuf+20)
	sta p1+1
	rts

parse_num1:
	lda pn_arg
	sta pn_whole
	ldx #0
@sp:	cpx t0
	jeq @nodig
	lda sbufa,x
	cmp #' '
	bne @s1
	inx
	bra @sp
@s1:	stz pn_neg
	cmp #'+'
	beq @sg
	cmp #'-'
	bne @dg0
	lda #1
	sta pn_neg
@sg:	inx
@dg0:	; acc = 0.0
	stz aty
	stz ac0
	stz ac1
	stz ac2
	stz ac3
	stz ac4
	stz pn_dig
	stz pn_frac
	stz pn_dot
	stz pn_iv
	stz pn_iv+1
	stz pn_big
@dg:	cpx t0
	jeq @dend
	lda sbufa,x
	cmp #'.'
	bne @dd
	lda pn_dot
	jne @dend
	inc pn_dot
	inx
	bra @dg
@dd:	sec
	sbc #'0'
	cmp #10
	jcs @dend
	sta pn_d
	stx pn_i
	; acc = mul10(acc) + d (ARG = mul10(acc), FAC = d)
	ldy #<FP_MUL10
	jsr fp_fn
	ldx #4
@c1:	lda ac0,x
	sta fpa,x
	dex
	bpl @c1
	lda pn_d
	sta ac0
	stz ac1
	lda #TY_I
	sta aty
	jsr toflt
	ldy #<FP_FADDT
	jsr fp_op_fpa_acc
	; the integer, while it fits
	lda pn_big
	bne @nb
	lda pn_iv               ; iv * 10 + d
	sta n0
	lda pn_iv+1
	sta n0+1
	asl n0
	rol n0+1
	bcs @big
	asl n0
	rol n0+1
	bcs @big
	lda n0
	clc
	adc pn_iv
	sta n0
	lda n0+1
	adc pn_iv+1
	bcs @big
	sta n0+1
	asl n0
	rol n0+1
	bcs @big
	lda n0
	clc
	adc pn_d
	sta pn_iv
	lda n0+1
	adc #0
	sta pn_iv+1
	bcs @big
	bpl @nb
@big:	lda #1
	sta pn_big
@nb:	inc pn_dig
	lda pn_dot
	beq @nf
	inc pn_frac
@nf:	ldx pn_i
	inx
	jmp @dg
@nodig:	stz pn_dig
@dend:	stx pn_i
	lda pn_dig
	bne @hasd
	lda pn_whole
	bne @fail
	; no number: 0.0
	stz aty
	stz ac0
	stz ac1
	stz ac2
	stz ac3
	stz ac4
	stz pn_ok
	rts
@fail:	lda #1
	sta pn_ok
	rts
@hasd:	; an exponent
	stz pn_exp
	stz pn_exp+1
	stz pn_es
	cpx t0
	jeq @noe
	lda sbufa,x
	cmp #'E'
	beq @e
	cmp #'e'
	jne @noe
@e:	inx
	stz pn_eneg
	cpx t0
	jeq @noe0
	lda sbufa,x
	cmp #'+'
	beq @es
	cmp #'-'
	bne @ed0
	lda #1
	sta pn_eneg
@es:	inx
@ed0:	stx pn_k
@ed:	cpx t0
	beq @eend
	lda sbufa,x
	sec
	sbc #'0'
	cmp #10
	bcs @eend
	sta pn_d
	; exp = min(exp * 10 + d, 999)
	lda pn_exp
	sta n0
	lda pn_exp+1
	sta n0+1
	asl n0
	rol n0+1
	asl n0
	rol n0+1
	lda n0
	clc
	adc pn_exp
	sta n0
	lda n0+1
	adc pn_exp+1
	sta n0+1
	asl n0
	rol n0+1
	lda n0
	clc
	adc pn_d
	sta pn_exp
	lda n0+1
	adc #0
	sta pn_exp+1
	lda pn_exp
	cmp #<1000
	lda pn_exp+1
	sbc #>1000
	bcc @eok
	lda #<999
	sta pn_exp
	lda #>999
	sta pn_exp+1
@eok:	inx
	bra @ed
@eend:	cpx pn_k
	beq @noe0               ; no digits: not an exponent
	lda #1
	sta pn_es
	stx pn_i
	lda pn_eneg
	beq @noe
	lda #0
	sec
	sbc pn_exp
	sta pn_exp
	lda #0
	sbc pn_exp+1
	sta pn_exp+1
	bra @noe
@noe0:	stz pn_exp
	stz pn_exp+1
@noe:	; whole: only blanks after it
	lda pn_whole
	beq @w
	ldx pn_i
@tb:	cpx t0
	beq @w
	lda sbufa,x
	cmp #' '
	jne @fail
	inx
	bra @tb
@w:	; a whole number that fits: the integer
	lda pn_dot
	ora pn_es
	ora pn_big
	bne @flt
	lda pn_iv
	sta ac0
	lda pn_iv+1
	sta ac1
	lda #TY_I
	sta aty
	lda pn_neg
	beq @ok
	lda #0
	sec
	sbc ac0
	sta ac0
	lda #0
	sbc ac1
	sta ac1
@ok:	stz pn_ok
	rts
@flt:	; e = exp - frac
	lda pn_exp
	sec
	sbc pn_frac
	sta pn_e
	lda pn_exp+1
	sbc #0
	sta pn_e+1
@up:	lda pn_e+1
	bmi @down
	ora pn_e
	beq @sign
	ldy #<FP_MUL10
	jsr fp_fn
	lda pn_e
	bne @u1
	dec pn_e+1
@u1:	dec pn_e
	bra @up
@down:	ldy #<FP_DIV10
	jsr fp_fn
	inc pn_e
	bne @down2
	inc pn_e+1
@down2:	lda pn_e+1
	bmi @down
	ora pn_e
	bne @down
@sign:	lda pn_neg
	beq @ok2
	lda ac0
	beq @ok2
	lda ac1
	eor #$80
	sta ac1
@ok2:	stz aty
	stz pn_ok
	rts
pn_whole: .byte 0
pn_neg:	.byte 0
pn_dig:	.byte 0
pn_frac: .byte 0
pn_dot:	.byte 0
pn_iv:	.word 0
pn_big:	.byte 0
pn_d:	.byte 0
pn_i:	.byte 0
pn_k:	.byte 0
pn_exp:	.word 0
pn_es:	.byte 0
pn_eneg: .byte 0
pn_e:	.word 0

errtab:	.word MErr0, MErr1, MErr2, MErr3, MErr4, MErr5, MErr6, MErr7, MErr8, MErr9
	.word MErr10, MErr11, MErr12, MErr13, MErr14, MErr15, MErr16, MErr17, MErr18
	.word MErr19, MErr20, MErr21, MErr22, MErr23, MErr24, MErr25, MErr26
MErr0:	.byte "Error 0", 0
MErr1:	.byte "Stopped", 0
MErr2:	.byte "Syntax error", 0
MErr3:	.byte "RETURN without GOSUB", 0
MErr4:	.byte "Out of DATA", 0
MErr5:	.byte "Illegal quantity", 0
MErr6:	.byte "Overflow", 0
MErr7:	.byte "Out of memory", 0
MErr8:	.byte "Undefined line", 0
MErr9:	.byte "Subscript out of range", 0
MErr10:	.byte "Array already dimensioned", 0
MErr11:	.byte "Division by zero", 0
MErr12:	.byte "Not an array", 0
MErr13:	.byte "Type mismatch", 0
MErr14:	.byte "String too long", 0
MErr15:	.byte "Formula too complex", 0
MErr16:	.byte "Stack overflow", 0
MErr17:	.byte "RESUME without error", 0
MErr18:	.byte "NEXT without FOR", 0
MErr19:	.byte "Wrong number of arguments", 0
MErr20:	.byte "Not available yet", 0
MErr21:	.byte "Made by a newer VeraBASIC", 0
MErr22:	.byte "Not inside a SUB", 0
MErr23:	.byte "BYREF needs a variable", 0
MErr24:	.byte "Font not found", 0
MErr25:	.byte "No such window", 0
MErr26:	.byte "Too many menus or items", 0
MErrN:	.byte "Error", 0
errtab2: .word MErr50, MErr51, MErr52, MErr53, MErr54, MErr55, MErr56, MErr57, MErr58, MErr59, MErr60
MErr50:	.byte "File not found", 0
MErr51:	.byte "Too many files", 0
MErr52:	.byte "Bad file number", 0
MErr53:	.byte "File not open", 0
MErr54:	.byte "File already open", 0
MErr55:	.byte "Bad file mode", 0
MErr56:	.byte "Input past end", 0
MErr57:	.byte "Disk error", 0
MErr58:	.byte "File exists", 0
MErr59:	.byte "Bad picture", 0
MErr60:	.byte "Not in a DIALOG", 0
.segment "CODE"
