; VeraBASIC Run: overlay 6, the Veranda extensions' part 2 (phase 4,
; DECISIONS V90): the arguments of the dialogs, icons, pictures, sprites
; and the clipboard (run in overlay 8, vbdlg.s) and of the files and
; folders (overlay 9, vbfile.s), and the core statements with a file
; handle (PRINT #, INPUT #, LINE INPUT #, GET #), which run here and call
; overlay 9 for the bytes. Included by vbui.s (the same rules: arguments
; evaluated first, then converted and logged).
;
; MIT licence (LICENSE).


;---------------------------------------------------------------
; dialogs
;---------------------------------------------------------------
s_msgbox:
	jsr xspec8
	.byte "s[s", 0
	.addr d_msgbox
f_ask:	jsr xfspec8
	.byte "(s)", 0
	.addr d_ask
; INPUTBOX$(prompt$ [, default$ [, length]])
f_inputbox:
	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xs
	lda #','
	jsr tacc
	bcc @e
	jsr xs
	lda #','
	jsr tacc
	bcc @e
	jsr xan
@e:	lda #')'
	jsr texp
	pla
	jsr xa_func
	G8 d_inputbox
	jmp fr_str
; FILEOPEN$(title$ [, extension$])
f_fileopen:
	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xs
	lda #','
	jsr tacc
	bcc @e
	jsr xs
@e:	lda #')'
	jsr texp
	pla
	jsr xa_func
	G8 d_fileopen
	jmp fr_str
f_filesave:
	jsr xfspec8
	.byte "$(s,s)", 0
	.addr d_filesave
; DIALOG x, y, w, h (a block: its partner's offset first)
s_dialog:
	ldy #0
	jsr tpk
	cmp #T_BLOCK
	bne @n
	lda #3
	jsr tadv
@n:	jsr xspec8
	.byte "n,n,n,n", 0
	.addr d_dialog
s_enddialog:
	jsr xspec8
	.byte 0
	.addr d_enddialog
f_dresult:
	jsr xfspec8
	.byte 0
	.addr d_result
s_label:
	jsr xspec8
	.byte "n,n,s", 0
	.addr d_label
; FIELD x, y, string-variable, length: the variable's place kept, its
; value an argument
s_field:
	lda vsp
	pha
	jsr xan
	jsr xcn
	lda #','
	jsr texp
	lda ip+1
	pha
	lda ip
	pha
	PCALL lvalue            ; p0, xb, t0
	pla
	sta mx
	pla
	sta mx+1
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @s
	jmp tyerr
@s:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	lda mx                  ; the variable again, as a value
	sta ip
	lda mx+1
	sta ip+1
	jsr xs
	jsr xcn
	pla
	sta fdt
	pla
	sta fdt+1
	pla
	sta fdt+2
	pla
	sta fdt+3
	pla
	jsr xa_done
	lda fdt
	sta t0
	lda fdt+1
	sta xb
	lda fdt+2
	sta p0+1
	lda fdt+3
	sta p0
	G8 d_field
	clc
	rts
; BUTTON OK | CANCEL
s_button:
	lda vsp
	pha
	lda #<TX_OK
	jsr tword
	bcs @w
	lda #<TX_CANCEL
	jsr tword
	bcs @w
	jmp syn
@w:	lda t0
	jsr xw
	pla
	jsr xa_done
	G8 d_button
	clc
	rts

;---------------------------------------------------------------
; icons, tiles, pictures, sprites, the clipboard
;---------------------------------------------------------------
; ICON id, x, y, picture$, procedure | ICON OFF id
s_icon:	lda vsp
	pha
	lda #<TX_OFF
	jsr tword
	bcc @on
	lda #<TX_OFF
	sta lgsub
	jsr xan
	pla
	jsr xa_done
	G8 d_iconoff
	clc
	rts
@on:	jsr xan
	jsr xcn
	jsr xcn
	jsr xcs
	lda #','
	jsr texp
	jsr xap
	pla
	jsr xa_done
	G8 d_icon
	clc
	rts
; ICONS CLEAR
s_icons:
	lda vsp
	pha
	lda #<TX_CLEAR
	jsr tword
	bcs @c
	jmp syn
@c:	lda #<TX_CLEAR
	sta lgsub
	pla
	jsr xa_done
	G8 d_iconsclear
	clc
	rts
; TILE x, y, name$ [, colour] (TILE DATA: Make application's, phase 7)
s_tile:	lda #TK_DATA
	jsr tacc
	bcc @t
	PCALL skip_stmt
	clc
	rts
@t:	jsr xspec8
	.byte "n,n,s[n", 0
	.addr d_tile
s_bitmap:
	jsr xspec8
	.byte "n,n,s", 0
	.addr d_bitmap
; PICTURE$(file$) | PICTURE$(DATA)
f_picture:
	lda vsp
	pha
	lda #'('
	jsr texp
	PCALL eval
	jsr vpush
	lda #')'
	jsr texp
	pla
	jsr xa_func
	lda xa_s                ; 1: a file's name
	sta t3
	G9 f9_picture
	jmp fr_str
f_clipget:
	jsr xfspec8
	.byte "$", 0
	.addr d_clipget
; CLIPBOARD s$ | CLIPBOARD PICTURE x1, y1, x2, y2
s_clipboard:
	lda vsp
	pha
	lda #<TX_PICTURE
	jsr tword
	bcc @t
	lda #<TX_PICTURE
	sta lgsub
	jsr xan
	jsr xcn
	jsr xcn
	jsr xcn
	pla
	jsr xa_done
	G8 d_clippict
	clc
	rts
@t:	jsr xs
	pla
	jsr xa_done
	G8 d_clipput
	clc
	rts
; SPRITE n, picture$ | SPRITE n AT x, y | SPRITE n ON | OFF
s_sprite:
	lda vsp
	pha
	jsr xan
	lda #','
	jsr tacc
	bcc @1
	jsr xs
	pla
	jsr xa_done
	G8 d_sprite
	clc
	rts
@1:	lda #<TX_AT
	jsr tword
	bcc @2
	lda #<TX_AT
	sta lgsub
	jsr xan
	jsr xcn
	pla
	jsr xa_done
	G8 d_spriteat
	clc
	rts
@2:	lda #TK_ON
	jsr tacc
	lda #0
	bcs @op
	lda #<TX_OFF
	jsr tword
	bcs @off
	jmp syn
@off:	lda #1
@op:	jsr xw                  ; (logged @00 ON, @01 OFF)
	pla
	jsr xa_done
	G8 d_spriteon
	clc
	rts

;---------------------------------------------------------------
; files and folders
;---------------------------------------------------------------
; OPEN #h, name$, mode$
s_open:	lda vsp
	pha
	jsr xh
	jsr xcs
	jsr xcs
	pla
	jsr xa_done
	G9 f9_open
	clc
	rts
; CLOSE [#h [, #h] ...]
s_close:
	lda vsp
	pha
	jsr tend
	bcs @d
@l:	jsr xh
	lda #','
	jsr tacc
	bcs @l
@d:	pla
	jsr xa_done
	G9 f9_close
	clc
	rts
; PUT #h, s$
s_put:	lda vsp
	pha
	jsr xh
	jsr xcs
	pla
	jsr xa_done
	G9 f9_put
	clc
	rts
; SEEK #h, position (24 bits: xi + 2, its high byte at xi + 4)
s_seek:	lda vsp
	pha
	jsr xh
	lda #','
	jsr texp
	PCALL eval
	jsr to24
	lda #$42
	sta aty
	jsr vpush
	pla
	jsr xa_done
	G9 f9_seek
	clc
	rts
; acc (a number 0 .. 16,777,215, its fraction dropped) -> ac0-ac2
to24:	lda aty
	cmp #TY_S
	bne @n
	jmp tyerr
@n:	cmp #TY_I
	bne @f
	lda ac1
	bmi @ill
	stz ac2
	rts
@f:	lda ac0                 ; a float: exponent, sign and mantissa
	cmp #$81
	bcc @z
	ldx ac1
	bmi @ill
	cmp #$99
	bcs @ill
	lda ac1                 ; m = 1.ac1 ac2 ac3 >> ($98 - e)
	ora #$80
	sta mw+1
	lda ac2
	sta mw
	lda ac3
	sta mk
	lda #$98
	sec
	sbc ac0
	tax
	beq @d
@s:	lsr mw+1
	ror mw
	ror mk
	dex
	bne @s
@d:	lda mk
	sta ac0
	lda mw
	sta ac1
	lda mw+1
	sta ac2
	rts
@z:	stz ac0
	stz ac1
	stz ac2
	rts
@ill:	ERR E_ILLQ
s_kill:	jsr xspec9
	.byte "s", 0
	.addr f9_kill
; NAME old$ AS new$
s_name:	lda vsp
	pha
	jsr xs
	lda #<TX_AS
	jsr tword
	bcs @a
	jmp syn
@a:	jsr xs
	pla
	jsr xa_done
	G9 f9_name
	clc
	rts
s_mkdir:
	jsr xspec9
	.byte "s", 0
	.addr f9_mkdir
s_rmdir:
	jsr xspec9
	.byte "s", 0
	.addr f9_rmdir
s_chdir:
	jsr xspec9
	.byte "s", 0
	.addr f9_chdir
f_lof:	jsr xfspec9
	.byte "%(n)", 0
	.addr f9_lof
f_loc:	jsr xfspec9
	.byte "%(n)", 0
	.addr f9_loc
f_eof:	jsr xfspec9
	.byte "(n)", 0
	.addr f9_eof
f_curdir:
	jsr xfspec9
	.byte "$", 0
	.addr f9_curdir
; DIR$(pattern$) | DIR$() | DIR$
f_dir:	lda vsp
	pha
	lda #'('
	jsr tacc
	bcc @n
	lda #')'
	jsr tacc
	bcs @n
	jsr xs
	lda #')'
	jsr texp
@n:	pla
	jsr xa_func
	G9 f9_dir
	jmp fr_str
f_folder:
	jsr xfspec9
	.byte "$(n)", 0
	.addr f9_folder
f_document:
	jsr xfspec9
	.byte "$", 0
	.addr f9_document

;---------------------------------------------------------------
; PRINT #h, INPUT #h, LINE INPUT #h, GET #h (ip at the '#'): the core's
; statements; overlay 9 reads and writes the bytes (its "selected" file,
; chosen again after every evaluation: a FUNCTION may use another)
;---------------------------------------------------------------
; the handle after '#': on the 6502 stack (under the caller's return)
hnum:	lda #1
	jsr tadv
	PCALL eval
	PCALL toint
	lda ac1
	beq @1
	ERR E_FNUM
@1:	rts
; the handle (on the stack at $0100 + x) selected: a = 0 to read, 1 to
; write (n0, n1: t0-t3 may hold what is written)
hsel:	sta n1
	lda $0100,x
	sta n0
	G9 f9_sel
	rts

s_printh:
	jsr hnum
	lda ac0
	pha                     ; the handle
	lda #1
	pha                     ; a new line at the end
	jsr tend
	jcs @done
	lda #','
	jsr texp
@l:	jsr tend
	jcs @done
	ldy #0
	jsr tpk
	cmp #';'
	bne @2
	lda #1
	jsr tadv
	pla
	lda #0
	pha
	bra @l
@2:	cmp #','
	bne @3
	lda #1
	jsr tadv
	jsr psel                ; the next zone of 10
	G9 f9_col               ; x = the column
	txa
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
	adc t2                  ; (col / 10 + 1) * 10
	sta t2
	G9 f9_pad
	pla
	lda #0
	pha
	bra @l
@3:	cmp #TK_TAB
	beq @ts
	cmp #TK_SPC
	bne @val
@ts:	pha
	lda #1
	jsr tadv
	PCALL arg1
	PCALL toint
	lda ac1
	beq @t0
	ERR E_ILLQ
@t0:	jsr psel1
	pla
	cmp #TK_TAB
	bne @spc
	lda ac0                 ; TAB(n): to column n
	sta t2
	G9 f9_pad
	bra @t1
@spc:	lda ac0                 ; SPC(n): n blanks
	sta t2
	G9 f9_spc
@t1:	pla
	lda #1
	pha
	jmp @l
@val:	PCALL eval
	lda aty
	cmp #TY_S
	bne @num
	PCALL str_to_buf        ; sbufa, t0
	jsr psel
	G9 f9_wbuf
	bra @v1
@num:	PCALL num_text          ; numbuf, x
	stx t2
	jsr psel
	G9 f9_wnum
@v1:	pla
	lda #1
	pha
	jmp @l
@done:	pla
	beq @r
	jsr psel0
	G9 f9_wnl
@r:	pla
	PCALL need_end
	clc
	rts
; the handle (under the flag and psel's return) selected to write
psel:	tsx
	lda #1
	inx
	inx
	inx
	inx                     ; (the return, the flag)
	jmp hsel
psel0:	tsx                     ; (the flag taken off already)
	lda #1
	inx
	inx
	inx
	jmp hsel
psel1:	tsx                     ; (and a byte more: TAB's token)
	lda #1
	inx
	inx
	inx
	inx
	inx
	jmp hsel

; INPUT #h, v [, v] ... | LINE INPUT #h, v$ (inp_line)
s_inputh:
	jsr hnum
	lda ac0
	pha
	lda #','
	jsr texp
	lda inp_line
	jne @line
	jsr rline               ; the first line
@t:	PCALL lvalue
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	lda inp_pos
	cmp #$FF
	bne @f
	tsx                     ; no more fields: the next line
	inx
	inx
	inx
	inx
	inx
	lda #0
	jsr hsel
	G9 f9_rline
@f:	PCALL next_field        ; sbufa, t0
	tsx
	lda $0101,x             ; the target's type
	and #CT_TYPE
	cmp #TY_S
	beq @str
	PCALL field_blank       ; only blanks: 0
	bcc @num
	stz ac0
	stz ac1
	lda #TY_I
	sta aty
	bra @st
@num:	PCALL pnum1
	bcc @st
	ERR E_TYPE
@str:	PCALL btt0
@st:	pla
	sta t0
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	PCALL store
	PCALL accept_comma
	jcs @t
	pla
	PCALL need_end
	clc
	rts
@line:	PCALL lvalue
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @l1
	jmp tyerr
@l1:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	tsx
	inx
	inx
	inx
	inx
	inx
	lda #0
	jsr hsel
	G9 f9_rline
	ldx #0
@c:	cpx inp_len
	beq @c1
	lda inbuf,x
	sta sbufa,x
	inx
	bra @c
@c1:	stx t0
	PCALL btt0
	pla
	sta t0
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	PCALL store
	pla
	PCALL need_end
	clc
	rts
; the handle under rline's return: its next line (inbuf, inp_len, inp_pos 0)
rline:	tsx
	inx
	inx
	inx
	lda #0
	jsr hsel
	G9 f9_rline
	rts

; GET #h, v$, count
s_geth:	jsr hnum
	lda ac0
	pha
	lda #','
	jsr texp
	PCALL lvalue
	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @1
	jmp tyerr
@1:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	lda #','
	jsr texp
	PCALL eval
	PCALL toint
	lda ac1
	bne @ill
	lda ac0
	pha
	tsx
	inx
	inx
	inx
	inx
	inx
	inx
	lda #0
	jsr hsel
	pla
	sta t2
	G9 f9_get               ; sbufa, t0
	PCALL btt0
	pla
	sta t0
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	PCALL store
	pla
	PCALL need_end
	clc
	rts
@ill:	ERR E_ILLQ

;---------------------------------------------------------------
; a function's 24-bit result (LOF, LOC): an integer below 32768, else a
; float; logged as a whole number
;---------------------------------------------------------------
fr_u24:	lda ac2
	bne @f
	lda ac1
	bmi @f
	lda ac0
	ldx ac1
	jmp fr_int
@f:
.ifdef VB_TEST
	jsr lg_fn
	jsr lg_d24
	lda #10
	jsr lg_c
.endif
	; the float: 1.m * 2 ^ (e - $81), normalised from 24 bits
	lda ac0
	sta mk
	lda ac1
	sta mw
	lda ac2
	sta mw+1
	lda #$98
	sta mj
@n:	lda mw+1
	bmi @p
	asl mk
	rol mw
	rol mw+1
	dec mj
	bra @n
@p:	lda mj
	sta ac0
	lda mw+1
	and #$7F                ; (positive)
	sta ac1
	lda mw
	sta ac2
	lda mk
	sta ac3
	stz ac4
	lda #TY_F
	sta aty
	rts
.ifdef VB_TEST
; ac0-ac2 in decimal (not changed)
lg_d24:	lda ac0
	sta fdt
	lda ac1
	sta fdt+1
	lda ac2
	sta fdt+2
	ldy #0
@dv:	ldx #24                 ; fdt / 10, the remainder in a
	lda #0
@b:	asl fdt
	rol fdt+1
	rol fdt+2
	rol a
	cmp #10
	bcc @x
	sbc #10
	inc fdt
@x:	dex
	bne @b
	pha
	iny
	lda fdt
	ora fdt+1
	ora fdt+2
	bne @dv
@o:	pla
	ora #'0'
	jsr lg_c
	dey
	bne @o
	rts
.endif
