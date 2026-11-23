; VeraBASIC Run: the tokenizer on the X16 (DECISIONS V87; the token format:
; docs/vbasic/FORMAT.md). It reads a .BAS file's text from RAM banks and
; makes the four records of the program document there, byte for byte as
; tools/vbtokens.py does (guarantee G3, gate vb_tok): this file is the
; lexer (banked overlay 2), vbprep.s the prepare pass (overlay 3).
;
; The work is done one source line at a time, as the PC tokenizer does it:
; the line is read into overlay 2's own bank, lexed into a line record in
; main RAM (tb), written to record 1, and prepared (block partners,
; procedures, labels, names' uses) before the next line is read. The names
; (a hash table) and their attributes are in RAM banks of their own; code
; in an overlay's bank reaches another bank only through the few resident
; helpers below (fpeek, fpoke, sget, bcall).
;
; Floats: the spelling's exact value, correctly rounded to the 5-byte
; format (to nearest, ties to even), as vbtokens.py's float5 does with
; Python's fractions: big integers here (the digits, times 2^k, divided by
; ten as often as the spelling has decimals), so both sides agree to the
; last bit.
;
; MIT licence (LICENSE).

; ---- the zero page (the interpreter's, idle while a program is made)
fpp	= p2			; fpeek/fpoke: the pointer
fpb	= xb			; and its bank
rsp	= ip			; sget: the source's next byte
rsb	= pbank
fpt	= t3

;---------------------------------------------------------------
; resident: main RAM
;---------------------------------------------------------------
.segment "BSS"
_vt_ovl2: .res 1		; overlay 2's bank, 3's
_vt_ovl3: .res 1
_vt_ovl4: .res 1
_vt_ovl5: .res 1
_vt_name: .res 2			; the file
_vt_recb: .res 4			; the records' runs (0 none)
_vt_src: .res 1			; the source text: its run of banks, its length
_vt_srclen: .res 2
_vt_r1b: .res 1			; record 1's run of banks, how many
_vt_r1n: .res 1
_vt_r0b: .res 1			; record 0 (made at the end), its banks
_vt_r0n: .res 1
_vt_r2b: .res 1			; the line index (a bank)
_vt_r3b: .res 1			; the DATA index (a bank)
_vt_nb:	.res 1			; the names (the hash table and the spellings)
_vt_ab:	.res 1			; the names' attributes, 16 bytes each
_vt_pb:	.res 1			; the procedures (record 0's form)
_vt_cb:	.res 1			; the uses to check at the end (2 banks)
_vt_lb:	.res 1			; the lines the end's pass needs
_vt_size: .res 8		; the records' sizes, 0-3
_vt_err: .res 1			; 0 or an error: _vt_erl its line, _vt_msg the text
_vt_erl: .res 2
_vt_msg: .res 80
_vt_cyc: .res 4			; (the test build: the emulator's cycles it took)
_vt_lines: .res 2		; source lines read
.ifdef VB_IDE
; (VeraBASIC, the editor: DECISIONS V93) the text is in _vt_src already (a
; run of banks the editor wrote, _vt_srclen bytes); errors at lines up to
; _vt_after are left out (F8: the next error after the one shown)
_vt_inmem: .res 1
_vt_after: .res 2
.export _vt_inmem, _vt_after
.endif
vt_off:	.res 2			; the line record's offset in record 1
vt_src:	.res 2			; its source line
vt_nsym: .res 2
vt_tl:	.res 1			; the line record's length (tb[0])
xbk:	.res 1			; xcopy's bank, count
xn:	.res 1
vt_lexok: .res 1		; 0: a lexing error was found (prepare stops)
f5len:	.res 1			; a float's spelling (in sbounce): its length, value
f5m:	.res 5
; the first error (by line) of each kind: lexing, prepare
; (id, line, a name, two numbers, two keywords, a character)
VE_SIZE = 14
vt_le:	.res VE_SIZE
vt_pe:	.res VE_SIZE
vt_e:	.res VE_SIZE		; the one being raised
tb	= sbufa			; the line record being made (main RAM)

.segment "CODE"
.ifdef VB_PROF
.export _vt_prof
_vt_prof: .res 32
prof_t:	.res 4
.endif
; PROF n (VB_PROF): from the last mark to now into counter n
.macro PROF n
.ifdef VB_PROF
	php
	pha
	phx
	ldx #n*4
	jsr prof_add
	plx
	pla
	plp
.endif
.endmacro
.ifdef VB_PROF
prof_add:
	lda $9FB8
	sta prof_n
	lda $9FB9
	sta prof_n+1
	lda $9FBA
	sta prof_n+2
	lda $9FBB
	sta prof_n+3
	ldy #0
	sec
@d:	lda prof_n,y
	sbc prof_t,y
	sta prof_d,y
	lda prof_n,y
	sta prof_t,y
	iny
	tya
	eor #4
	bne @d1
	clc
	lda _vt_prof,x
	adc prof_d
	sta _vt_prof,x
	lda _vt_prof+1,x
	adc prof_d+1
	sta _vt_prof+1,x
	lda _vt_prof+2,x
	adc prof_d+2
	sta _vt_prof+2,x
	lda _vt_prof+3,x
	adc prof_d+3
	sta _vt_prof+3,x
	rts
@d1:	jmp @d
prof_n:	.res 4
prof_d:	.res 4
.endif
; a = (fpp),y in bank fpb; x, y kept
fpeek:	lda ram_bank
	pha
	lda fpb
	sta ram_bank
	lda (fpp),y
	sta fpt
	pla
	sta ram_bank
	lda fpt
	rts

; (fpp),y in bank fpb = a; a, x, y kept
fpoke:	sta fpt
	lda ram_bank
	pha
	lda fpb
	sta ram_bank
	lda fpt
	sta (fpp),y
	pla
	sta ram_bank
	lda fpt
	rts

; xn bytes (0: 256) from bank xbk at xp to main RAM at xm (xcopy_in)
; or back (xcopy_out); the bank's part must not cross $C000
xp	= p0
xm	= p1
xcopy_out:
	sec
	bra xc
xcopy_in:
	clc
xc:	lda ram_bank
	pha
	lda xbk
	sta ram_bank
	ldy #0
	ldx xn
	bcs @out
@in:	lda (xp),y
	sta (xm),y
	iny
	dex
	bne @in
	bra @d
@out:	lda (xm),y
	sta (xp),y
	iny
	dex
	bne @out
@d:	pla
	sta ram_bank
	rts

; a routine (a/x) of another overlay's bank (y), the caller's bank back after
bcall:	sta @j+1
	stx @j+2
	lda ram_bank
	pha
	sty ram_bank
@j:	jsr $FFFF
	pla
	sta ram_bank
	rts

; main.c: the file _vt_name (a .BAS) made into the records in the runs
; _vt_recb (vbprep.s compile; _vt_err: 0 done, 1 an error in the text:
; _vt_msg, 2 not opened, 3 no banks, 4 too big)
_vb_compile:
	lda #<P4::compile
	ldx #>P4::compile
	ldy _vt_ovl4
	jmp bcall
.ifdef VB_TEST
; the test build: the records in hex to the emulator's console
_vb_dump:
	lda #<P4::dump
	ldx #>P4::dump
	ldy _vt_ovl4
	jmp bcall
.export _vb_dump
.endif

.export _vb_compile, _vt_name, _vt_recb, _vt_ovl5, _vt_ovl2, _vt_ovl3, _vt_ovl4, _vt_src, _vt_srclen, _vt_r1b, _vt_r1n, _vt_r0b, _vt_r0n
.export _vt_r2b, _vt_r3b, _vt_nb, _vt_ab, _vt_pb, _vt_cb, _vt_size, _vt_err, _vt_erl, _vt_msg
.export _vt_cyc, _vt_lines

; error ids (vbprep.s has the texts, in this order)
VE_NONE	= 0
VE_CHAR	= 1			; Unexpected character 'c'
VE_LTOOLONG = 2
VE_STOOLONG = 3
VE_NTOOBIG = 4
VE_LNEXP = 5
VE_NTOOLONG = 6
VE_NAMELONG = 7
VE_LNRANGE = 8
VE_NAMES = 9			; Too many names
VE_PROGBIG = 10			; Program too big

;---------------------------------------------------------------
; overlay 2: the lexer
;---------------------------------------------------------------
.segment "OVERLAY2"

; the character classes
C_DIG	= $01
C_LET	= $02
C_WORD	= $04			; a letter, a digit, "_"
C_HEX	= $08
C_PUN	= $10			; ( ) + - * / ^ \ = < > , ; : #
C_SP	= $20			; Python's str.isspace (Latin-1)
C_BL	= $40			; a blank or a tab
cls:
.repeat 256, I
	.byte ((I >= '0') .and (I <= '9')) * (C_DIG | C_WORD | C_HEX) | (((I >= 'A') .and (I <= 'Z')) .or ((I >= 'a') .and (I <= 'z'))) * (C_LET | C_WORD) | ((I = '_') * C_WORD) | (((I >= 'A') .and (I <= 'F')) .or ((I >= 'a') .and (I <= 'f'))) * C_HEX | ((I = '(') .or (I = ')') .or (I = '+') .or (I = '-') .or (I = '*') .or (I = '/') .or (I = '^') .or (I = 92) .or (I = '=') .or (I = '<') .or (I = '>') .or (I = ',') .or (I = ';') .or (I = ':') .or (I = '#')) * C_PUN | (((I >= 9) .and (I <= 13)) .or ((I >= $1C) .and (I <= $1F)) .or (I = ' ') .or (I = $85) .or (I = $A0)) * C_SP | ((I = ' ') .or (I = 9)) * C_BL
.endrepeat

.segment "OVL2BSS"
LS:	.res 256		; the source line
ln:	.res 1			; its length
li:	.res 1			; the lexer's place
lo:	.res 1			; tb's next byte (the tokens from tb+6)
ss:	.res 1			; stmt_start
lab:	.res 1			; the line starts with a label
ref:	.res 1			; 0, REF_LINE, REF_PROC, REF_STMT
rlist:	.res 1			; ref_list
skwv:	.res 1			; the statement's keyword: 1 there is one
skw:	.res 2			; (code: lo, hi 0 or $FF)
argno:	.res 1
args:	.res 1			; arg_start
depth:	.res 1
dmode:	.res 1			; data_mode
iraw:	.res 1
lsp:	.res 1			; the stack at the line's start (errors)
kb:	.res 36			; a word, upper case
kl:	.res 1
ws:	.res 1			; the word's place, its end
we:	.res 1
code:	.res 2			; a keyword: lo, hi (0 page 1, $FF page 2)
c1:	.res 2			; a compound's first word
tp:	.res 2
we1:	.res 1
kfl:	.res 1			; its flags, its second flags
kxf:	.res 1
hsh:	.res 1
ent:	.res 2			; a name's entry in the names' bank
ntop:	.res 2			; the names' bank's top
sym:	.res 2
num:	.res 2			; a number's value
big:	.res 1			; it is over $FFFF
isf:	.res 1			; a float spelling
ni:	.res 1			; a number's start
col:	.res 1			; the indentation's columns
lnum:	.res 2			; the line's number
rleft:	.res 2			; source bytes not read yet
along:	.res 1			; the line was longer than 255
fh:	.res 2			; a 16-bit helper
kidx:	.res 9 * 26		; the keyword index (lengths 2-10)
rpos:	.res 1			; the source's block in rbuf: the next byte, the end
rend:	.res 1

.segment "OVERLAY2"
REF_LINE = 1
REF_PROC = 2
REF_STMT = 3

; the error vt_e: raise it (back to the line's start)
lexfail:
	sta vt_e
	ldx lsp
	txs
	sec
	rts

;---------------------------------------------------------------
; the driver: every line of the source, then prepare's end
;---------------------------------------------------------------
tok_main:
	stz _vt_err
	stz vt_off
	stz vt_off+1
	stz vt_src
	stz vt_src+1
	stz vt_nsym
	stz vt_nsym+1
	stz _vt_lines
	stz _vt_lines+1
	lda #1
	sta vt_lexok
	stz vt_le
	stz vt_pe
	lda _vt_src
	sta rsb
	stz rsp
	lda #$A0
	sta rsp+1
	lda _vt_srclen
	sta rleft
	lda _vt_srclen+1
	sta rleft+1
	jsr names_init
	jsr kw_index
	stz rpos
	stz rend
	lda #<P3::prep_init
	ldx #>P3::prep_init
	ldy _vt_ovl3
	jsr bcall
	PROF 7
@line:	jsr rdline
	PROF 0
	bcs @end
	inc vt_src
	bne @1
	inc vt_src+1
@1:	inc _vt_lines
	bne @2
	inc _vt_lines+1
@2:	jsr do_line
	bra @line
@end:	; record 1's last byte ($00)
	lda vt_off
	sta n0
	lda vt_off+1
	sta n0+1
	jsr r1at
	bcs @big
	lda #0
	ldy #0
	jsr fpoke
	lda vt_off
	clc
	adc #1
	sta _vt_size+2
	lda vt_off+1
	adc #0
	sta _vt_size+3
	lda vt_lexok
	beq @lerr
	PROF 7
	lda #<P3::prep_finish
	ldx #>P3::prep_finish
	ldy _vt_ovl3
	jsr bcall
	PROF 5
	rts
@big:	lda #VE_PROGBIG
	sta vt_le
	lda vt_src
	sta vt_le+1
	lda vt_src+1
	sta vt_le+2
@lerr:	lda #<P4::prep_lexerr	; the first lexing error: its text
	ldx #>P4::prep_lexerr
	ldy _vt_ovl4
	jmp bcall

; tb (vt_tl bytes) to record 1 at vt_off (xcopy, in two parts across a
; bank's end)
r1put:	lda vt_off
	sta n0
	lda vt_off+1
	sta n0+1
	jsr r1at
	lda fpb
	sta xbk
	lda fpp
	sta xp
	lda fpp+1
	sta xp+1
	lda #<tb
	sta xm
	lda #>tb
	sta xm+1
	; the bytes to the bank's end: $C000 - fpp
	lda #0
	sec
	sbc fpp
	sta fh
	lda #$C0
	sbc fpp+1
	bne @one		; (256 or more)
	lda fh
	cmp vt_tl
	bcs @one
	sta xn			; the first part
	jsr xcopy_out
	lda xm
	clc
	adc xn
	sta xm
	bcc @1
	inc xm+1
@1:	lda vt_tl
	sec
	sbc xn
	sta xn
	inc xbk
	stz xp
	lda #$A0
	sta xp+1
	jmp xcopy_out
@one:	lda vt_tl
	sta xn
	jmp xcopy_out

; n0: an offset in record 1 -> fpb/fpp; carry set: past the run
r1at:	lda n0+1
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	cmp _vt_r1n
	bcs @r
	adc _vt_r1b
	sta fpb
	lda n0
	sta fpp
	lda n0+1
	and #$1F
	ora #$A0
	sta fpp+1
	clc
@r:	rts

;---------------------------------------------------------------
; a source line into LS (ln): carry set at the end of the text; the
; text comes in blocks of 256 bytes to rbuf (main RAM) by BankCopy
;---------------------------------------------------------------
rbuf	= sbufb

; the next block of the source (min(256, rleft) bytes from rsb/rsp) to
; rbuf: x = 0; carry set: none left; y kept
refill:	lda rleft
	ora rleft+1
	bne @fill
	sec
	rts
@fill:	phy
	lda rleft+1
	bne @full
	lda rleft
	bra @n
@full:	lda #0			; (256)
@n:	sta rend
	sta xn
	lda rsp
	sta xp
	lda rsp+1
	sta xp+1
	lda #<rbuf
	sta xm
	lda #>rbuf
	sta xm+1
	lda rsb
	sta xbk
	jsr xcopy_in
	; the source's place and what is left
	lda rend
	beq @256
	clc
	adc rsp
	sta rsp
	bcc @n2
	inc rsp+1
	bra @n2
@256:	inc rsp+1		; (rsp stays at a page's start)
	lda rsp+1
	cmp #$C0
	bcc @n3
	lda #$A0
	sta rsp+1
	inc rsb
@n3:	dec rleft+1
	bra @n4
@n2:	lda rleft
	sec
	sbc rend
	sta rleft
	bcs @n4
	dec rleft+1
@n4:	ldx #0
	ply
	clc
	rts

rdline:	ldx rpos
	cpx rend
	bne @go
	lda rleft
	ora rleft+1
	bne @go
	sec
	rts
@go:	ldy #0
	stz along
@l:	cpx rend
	bne @g
	jsr refill
	bcs @done
@g:	lda rbuf,x
	inx
	cmp #10
	beq @done
	cmp #13
	beq @cr
	cpy #255
	bcs @long
	sta LS,y
	iny
	bra @l
@long:	lda #1
	sta along
	bra @l
@cr:	cpx rend		; CR LF is one line end; CR alone too
	bne @c2
	jsr refill
	bcs @done
@c2:	lda rbuf,x
	cmp #10
	bne @done
	inx
@done:	stx rpos
	sty ln
	clc
	rts

;---------------------------------------------------------------
; a line: its number, indentation, the lexer; written and prepared
;---------------------------------------------------------------
do_line:
	; rstrip(' \t')
@rs:	ldx ln
	beq @blank
	lda LS-1,x
	cmp #' '
	beq @rs1
	cmp #9
	bne @rs2
@rs1:	dec ln
	bra @rs
@rs2:	; a line of white space only is no line
	ldx #0
@ws:	lda LS,x
	tay
	lda cls,y
	and #C_SP
	beq @text
	inx
	cpx ln
	bne @ws
@blank:	rts
@text:	lda along
	beq @t0
	lda #VE_LTOOLONG
	jmp lexfail0
@t0:	; the indentation
	ldx #0
	stz col
	jsr blanks
	stz lnum
	stz lnum+1
	cpx ln
	bcs @nonum
	lda LS,x
	tay
	lda cls,y
	and #C_DIG
	beq @nonum
	jsr decnum		; x past the digits: num, big
	lda big
	jne @range
	lda num
	ora num+1
	jeq @range
	lda num
	sta lnum
	lda num+1
	sta lnum+1
	stz col
	jsr blanks
	lda col
	beq @nonum
	dec col
@nonum:	lda col
	lsr a
	cmp #15
	bcc @in
	lda #15
@in:	asl a
	asl a
	asl a
	asl a
	sta tb+5
	stx li
	PROF 1
	jsr lexer		; carry set: an error (vt_e)
	PROF 2
	jcs @lerr
	; the record: length, number, source line, flags, tokens, 0
	ldy lo
	lda #0
	sta tb,y
	iny
	sty tb
	sty vt_tl
	lda lnum
	sta tb+1
	lda lnum+1
	sta tb+2
	lda vt_src
	sta tb+3
	lda vt_src+1
	sta tb+4
	lda lab
	beq @nl
	lda tb+5
	ora #2
	sta tb+5
@nl:	; to record 1 at vt_off
	lda vt_off
	clc
	adc vt_tl
	lda vt_off+1
	adc #0
	cmp #$FF
	bcs @big		; (record 1 below 65,280 bytes)
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	cmp _vt_r1n
	bcs @big
	jsr r1put
	PROF 3
	lda vt_lexok
	beq @skip
	lda #<P3::prep_line
	ldx #>P3::prep_line
	ldy _vt_ovl3
	jsr bcall
	PROF 4
@skip:	lda vt_off
	clc
	adc vt_tl
	sta vt_off
	bcc @r
	inc vt_off+1
@r:	rts
@range:	lda #VE_LNRANGE
	jmp lexfail0
@big:	lda #VE_PROGBIG
	sta vt_e
@lerr:	jmp dl_lerr
dl_lerr:	; keep the first lexing error by line
.ifdef VB_IDE
	lda _vt_after+1         ; (the editor's F8: lines up to _vt_after left out)
	cmp vt_src+1
	bcc @ok
	bne @r2
	lda _vt_after
	cmp vt_src
	bcs @r2
@ok:
.endif
	stz vt_lexok
	lda vt_le
	bne @r2
	ldx #VE_SIZE - 1
@cp:	lda vt_e,x
	sta vt_le,x
	dex
	bpl @cp
	lda vt_src
	sta vt_le+1
	lda vt_src+1
	sta vt_le+2
@r2:	rts

; an error found outside the lexer proper (a: its id)
lexfail0:
	sta vt_e
	jmp dl_lerr

; blanks and tabs from x: col counts them (a tab 2)
blanks:	cpx ln
	bcs @r
	lda LS,x
	cmp #' '
	beq @b
	cmp #9
	bne @r
	inc col
	beq @s
@b:	inc col
	bne @n
@s:	dec col			; (255 at most)
@n:	inx
	bra blanks
@r:	rts

; decimal digits from x: num (16 bits), big (over $FFFF); x past them
decnum:	stz num
	stz num+1
	stz big
@l:	cpx ln
	bcs @r
	lda LS,x
	sec
	sbc #'0'
	cmp #10
	bcs @r
	pha
	; num = num * 10 + d
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

;---------------------------------------------------------------
; the lexer: LS from li to ln into tb (tokens from tb+6)
;---------------------------------------------------------------
lexer:	tsx
	stx lsp
	lda #6
	sta lo
	lda #1
	sta ss
	stz lab
	stz ref
	stz rlist
	stz skwv
	stz argno
	stz args
	stz depth
	stz dmode
@loop:	jsr pns			; x = the next non-blank
	stx li
	cpx ln
	jcs @end
	lda dmode
	beq @nd
	jsr lex_data
	bra @loop
@nd:	ldy LS,x		; letters and punctuation first: the commonest
	lda cls,y
	bit #C_LET
	beq @n0
	jsr lex_word
	bra @loop
@n0:	bit #C_DIG
	bne @num
	bit #C_PUN
	beq @n0a
	jsr lex_punct
	bra @loop
@n0a:	tya
	cmp #'"'
	bne @n1
	jsr lex_string
	jsr after_op
	bra @loop
@n1:	cmp #$27		; '
	bne @n2
	jsr emit
	inx
	jsr lex_comment
	bra @loop
@n2:	cmp #'?'
	bne @n3
	inc li
	lda #TK_PRINT
	sta code
	stz code+1
	jsr kwflags
	jsr keyword
	bra @loop
@n3:	cpy #'.'
	bne @n4
	inx
	cpx ln
	bcs @n4
	ldy LS,x
	lda cls,y
	and #C_DIG
	beq @n4
@num:	jsr lex_number
	jmp @loop
@n4:	ldx li
	ldy LS,x
	tya
	cmp #'$'
	beq @rad
	cmp #'%'
	bne @bad
	inx
	cpx ln
	bcs @bad
	lda LS,x
	cmp #'0'
	beq @rad
	cmp #'1'
	bne @bad
@rad:	jsr lex_radix
	jmp @loop
@bad:	sty vt_e+11
	lda #VE_CHAR
	jmp lexfail
@end:	clc
	rts

; x = the first non-blank from li (Python's peek_nonspace)
pns:	ldx li
pnsx:	cpx ln
	bcs @r
	lda LS,x
	cmp #' '
	beq @n
	cmp #9
	bne @r
@n:	inx
	bra pnsx
@r:	rts

; a byte to the record
emit:	ldy lo			; (y not kept)
	sta tb,y
	iny
	sty lo
	cpy #255
	bcs @long
	rts
@long:	lda #VE_LTOOLONG
	jmp lexfail

emit0:	lda #0
	jmp emit

after_op:
	stz ss
	stz args
	lda rlist
	bne @r
	stz ref
@r:	rts

new_stmt:
	lda #1
	sta ss
	stz ref
	stz rlist
	stz skwv
	stz argno
	stz depth
	stz args
	rts

; a string: from li (at its quote)
lex_string:
	lda #T_STRING
	jsr emit
	lda lo
	pha			; the length's place
	jsr emit0
	ldx li
	inx
@l:	cpx ln
	bcs @end
	lda LS,x
	cmp #'"'
	bne @c
	inx
	cpx ln
	bcs @end
	lda LS,x
	cmp #'"'
	bne @end
@c:	jsr emit
	inx
	bra @l
@end:	stx li
	ply
	sty fh
	lda lo
	clc
	sbc fh			; lo - y - 1: the bytes
	sta tb,y
	rts

; a comment from x to the line's end
lex_comment:
	lda #T_COMMENT
	jsr emit
	lda ln
	stx li
	sec
	sbc li
	jsr emit
@l:	cpx ln
	bcs @r
	lda LS,x
	jsr emit
	inx
	bra @l
@r:	stx li
	rts

; DATA's raw items from iraw up to ":" (outside quotes) or the end
lex_data:
	ldx iraw
@item:	stx ws
	stz fpt			; in quotes
@k:	cpx ln
	bcs @got
	lda LS,x
	cmp #'"'
	bne @k1
	lda fpt
	eor #1
	sta fpt
	bra @k2
@k1:	ldy fpt
	bne @k2
	cmp #','
	beq @got
	cmp #':'
	beq @got
@k2:	inx
	bra @k
@got:	stx we
	lda #T_DATA
	jsr emit
	lda we
	sec
	sbc ws
	jsr emit
	ldx ws
@cp:	cpx we
	bcs @cd
	lda LS,x
	jsr emit
	inx
	bra @cp
@cd:	cpx ln
	bcs @fin
	lda LS,x
	cmp #','
	bne @fin
	jsr emit
	inx
	bra @item
@fin:	stx li
	stz dmode
	stz ss
	rts

; a number: decimal, float
lex_number:
	ldx li
	stx ni
	stz isf
@d1:	jsr digits
	cpx ln
	bcs @e
	lda LS,x
	cmp #'.'
	bne @ex
	lda #1
	sta isf
	inx
	jsr digits
@ex:	cpx ln
	bcs @e
	lda LS,x
	ora #$20
	cmp #'e'
	bne @e
	phx
	inx
	cpx ln
	bcs @noe
	lda LS,x
	cmp #'+'
	beq @sg
	cmp #'-'
	bne @ed
@sg:	inx
	cpx ln
	bcs @noe
@ed:	ldy LS,x
	lda cls,y
	and #C_DIG
	beq @noe
	pla
	lda #1
	sta isf
	jsr digits
	bra @e
@noe:	plx
@e:	stx li
	; the value of the digits (the whole spelling when it is no float)
	lda isf
	bne @nv
	phx
	ldx ni
	jsr decnum
	plx
@nv:	lda ref
	cmp #REF_LINE
	beq @lr
	cmp #REF_STMT
	bne @val
@lr:	lda isf
	ora big
	beq @lr1
	lda #VE_LNEXP
	jmp lexfail
@lr1:	lda #T_LINEREF
	jsr emit
	lda num
	jsr emit
	lda num+1
	jsr emit
	jsr emit0
	jsr emit0
	jsr emit0
	stz ss
	lda rlist
	bne @l2
	stz ref
@l2:	stz args
	rts
@val:	lda isf
	ora big
	bne @fl
	lda num+1
	bmi @fl			; over 32767
	lda #T_INTDEC
	jsr emit
	lda num
	jsr emit
	lda num+1
	jsr emit
	jmp after_op
@fl:	; overlay 5: the spelling copied to FS (main RAM), its value
	ldx ni
	ldy #0
@fc:	cpx li
	bcs @fc1
	lda LS,x
	sta sbounce,y
	inx
	iny
	bra @fc
@fc1:	sty f5len
	lda #<F5::float5
	ldx #>F5::float5
	ldy _vt_ovl5
	jsr bcall
	lda vt_e		; (an error: its id)
	jcs lexfail
	lda #T_FLOAT
	jsr emit
	ldx #0
@f5:	lda f5m,x
	jsr emit
	inx
	cpx #5
	bne @f5
	lda li
	sec
	sbc ni
	jsr emit
	ldx ni
@sp:	cpx li
	bcs @spd
	lda LS,x
	jsr emit
	inx
	bra @sp
@spd:	jmp after_op

; x past the decimal digits from x
digits:	cpx ln
	bcs @r
	ldy LS,x
	lda cls,y
	and #C_DIG
	beq @r
	inx
	bra digits
@r:	rts

; $hex, %binary
lex_radix:
	ldx li
	stz num
	stz num+1
	stz big
	lda LS,x
	inx
	cmp #'$'
	bne @bin
	stx ws
@h:	cpx ln
	bcs @hd
	ldy LS,x
	lda cls,y
	and #C_HEX
	beq @hd
	tya
	cmp #'A'
	bcc @hn
	ora #$20
	sbc #'a' - 10
	bra @hv
@hn:	sbc #'0' - 1		; (carry clear)
@hv:	ldy #4
@hs:	asl num
	rol num+1
	bcc @hs1
	inc big
@hs1:	dey
	bne @hs
	ora num
	sta num
	inx
	bra @h
@hd:	cpx ws
	bne @tag
	lda #'$'
	sta vt_e+11
	lda #VE_CHAR
	jmp lexfail
@tag:	lda #T_INTHEX
	bra @fin
@bin:	cpx ln
	bcs @bd
	lda LS,x
	cmp #'0'
	beq @b
	cmp #'1'
	bne @bd
@b:	lsr a			; the digit to carry
	rol num
	rol num+1
	bcc @b1
	inc big
@b1:	inx
	bra @bin
@bd:	lda #T_INTBIN
@fin:	pha
	lda big
	beq @ok
	lda #VE_NTOOBIG
	jmp lexfail
@ok:	cpx ln
	bcs @ok2
	ldy LS,x
	lda cls,y
	and #C_WORD
	beq @ok2
	sty vt_e+11
	lda #VE_CHAR
	jmp lexfail
@ok2:	stx li
	pla
	jsr emit
	lda num
	jsr emit
	lda num+1
	jsr emit
	jmp after_op

; punctuation, the operators <= <> >=
lex_punct:
	ldx li
	lda LS,x
	sta fpt
	inx
	cpx ln
	bcs @one
	ldy LS,x
	cmp #'<'
	bne @g
	cpy #'='
	beq @le
	cpy #'>'
	beq @ne
	bra @one
@g:	cmp #'>'
	bne @one
	cpy #'='
	bne @one
	lda #TK_GE
	bra @two
@le:	lda #TK_LE
	bra @two
@ne:	lda #TK_NE
@two:	inx
	stx li
	jsr emit
	stz ss
	stz args
	rts
@one:	stx li
	lda fpt
	jsr emit
	cmp #':'
	bne @nc
	ldy depth
	bne @nc
	jmp new_stmt
@nc:	cmp #'('
	bne @c1
	inc depth
	bra @c2
@c1:	cmp #')'
	bne @c2
	lda depth
	beq @c2
	dec depth
@c2:	lda fpt
	cmp #','
	bne @na
	lda depth
	bne @na
	inc argno
	lda #1
	sta args
	lda rlist
	beq @ss
	rts
@na:	stz args
@ss:	stz ss
	lda fpt
	cmp #','
	bne @clr
	lda rlist
	bne @r
@clr:	stz ref
	stz rlist
@r:	rts

; a word from ws: kb (upper case), kl, we (its end, after a "$" or "%")
rdword:	ldx ws
	ldy #0
@l:	cpx ln
	bcs @e
	lda LS,x
	phy
	tay
	lda cls,y
	ply
	and #C_WORD
	beq @sfx
	lda LS,x
	cmp #'a'
	bcc @u
	cmp #'z' + 1
	bcs @u
	and #$DF
@u:	cpy #35
	bcs @n
	sta kb,y
	iny
@n:	inx
	bra @l
@sfx:	lda LS,x
	cmp #'$'
	beq @s
	cmp #'%'
	bne @e
@s:	cpy #35
	bcs @n2
	sta kb,y
	iny
@n2:	inx
@e:	stx we
	sty kl
	rts

; the keyword index: for each length and first letter, the bucket's
; first entry from that letter on (kidx: 26 a length)
KIL	= 2			; the lengths indexed: 2 .. KIH (1: none; longer: a scan)
KIH	= 10
kw_index:
	ldx #KIL		; the length
@len:	stx kl
	txa
	dec a
	sta fpt
	asl a
	adc fpt
	tay			; (kl - 1) * 3
	lda vb_kw_len,y
	sta n0
	lda vb_kw_len+1,y
	sta n0+1
	lda vb_kw_len+2,y
	sta n1			; the bucket's entries
	ldy kbase-KIL,x		; kidx's row
	stz fpt			; the entry
	lda #'A'
	sta fh
@let:	lda fpt
	cmp n1
	bcs @put
	lda (n0)
	cmp fh
	bcs @put
	; next entry: + kl + 2
	lda n0
	sec
	adc kl
	sta n0
	bcc @1
	inc n0+1
@1:	inc n0
	bne @2
	inc n0+1
@2:	inc fpt
	bra @let
@put:	lda fpt
	sta kidx,y
	iny
	inc fh
	lda fh
	cmp #'Z' + 1
	bne @let
	inx
	cpx #KIH + 1
	bne @len
	rts
kbase:
.repeat KIH - KIL + 1, I
	.byte I * 26
.endrepeat

; kb (kl) a keyword? carry set: code (lo, hi), kfl, kxf
kwfind:	ldx kl
	cpx #VB_KW_MAXLEN + 1
	jcs @no
	cpx #KIL
	jcc @no
	stz fh			; (longer than KIH: from the bucket's start)
	cpx #KIH + 1
	bcs @long
	lda kb
	sec
	sbc #'A'
	cmp #26
	jcs @no
	adc kbase-KIL,x
	tay
	lda kidx,y		; the first entry of the letter
	sta fh
@long:
	txa
	dec a
	sta fpt
	asl a
	adc fpt
	tax			; (kl - 1) * 3
	lda vb_kw_len+2,x
	sec
	sbc fh
	jeq @no
	jcc @no
	sta n1			; entries from it to the bucket's end
	; its address: the bucket + index * (kl + 2)
	lda vb_kw_len,x
	sta n0
	lda vb_kw_len+1,x
	sta n0+1
	lda kl
	clc
	adc #2
	sta fpt
	stz fh+1
@mul:	lsr fpt
	bcc @m1
	lda n0
	clc
	adc fh
	sta n0
	lda n0+1
	adc fh+1
	sta n0+1
@m1:	asl fh
	rol fh+1
	lda fpt
	bne @mul
@e:	lda (n0)
	cmp kb
	bne @nf			; (past the letter, or before it: a long one)
	ldy #1
	cpy kl
	beq @f
@c:	lda (n0),y
	cmp kb,y
	bne @ne
	iny
	cpy kl
	bne @c
@f:	; found: the token
	lda (n0),y
	cmp #$FF
	beq @p2
	sta code
	stz code+1
	bra @fl
@p2:	iny
	lda (n0),y
	sta code
	lda #$FF
	sta code+1
@fl:	jsr kwflags
	sec
	rts
@nf:	bcs @no
	ldy #0
@ne:	bcs @no			; (the bucket is sorted: past it)
	lda n0
	sec			; next entry: kl + 2 bytes on
	adc kl
	bcc @n1
	inc n0+1
	clc
@n1:	adc #1
	sta n0
	bcc @n2
	inc n0+1
@n2:	dec n1
	bne @e
@no:	clc
	rts

; code's flags -> kfl, kxf
kwflags:
	lda code+1
	bne @p2
	lda code
	sec
	sbc #VB_PAGE1_FIRST
	tax
	lda vb_flags1,x
	sta kfl
	lda vb_xflags1,x
	sta kxf
	rts
@p2:	ldx code
	dex
	lda vb_flags2,x
	sta kfl
	lda vb_xflags2,x
	sta kxf
	rts

; a word: a keyword (or a compound), else a name
lex_word:
	ldx li
	stx ws
	PROF 2
	jsr rdword
	jsr kwfind
	PROF 6
	jcc @name
	; a compound's first word?
	ldx #0
@cf:	lda vb_compound,x
	jeq @kw
	jsr tpair
	lda tp
	cmp code
	bne @cfn
	lda tp+1
	cmp code+1
	beq @try
@cfn:	txa
	clc
	adc #6
	tax
	bra @cf
@try:	lda code		; the first word kept
	sta c1
	lda code+1
	sta c1+1
	lda we
	sta we1
	sta li
	jsr pns
	cpx ln
	bcs @first
	ldy LS,x
	lda cls,y
	and #C_LET
	beq @first
	stx ws
	jsr rdword
	jsr kwfind
	bcc @first
	; (c1, code) a compound?
	ldx #0
@cc:	lda vb_compound,x
	beq @first
	jsr tpair
	lda tp
	cmp c1
	bne @ccn
	lda tp+1
	cmp c1+1
	bne @ccn
	inx
	inx
	jsr tpair
	dex
	dex
	lda tp
	cmp code
	bne @ccn
	lda tp+1
	cmp code+1
	beq @cyes
@ccn:	txa
	clc
	adc #6
	tax
	bra @cc
@cyes:	inx
	inx
	inx
	inx
	jsr tpair
	lda tp
	sta code
	lda tp+1
	sta code+1
	jsr kwflags
	bra @kw
@first:	lda c1
	sta code
	lda c1+1
	sta code+1
	jsr kwflags
	lda we1
	sta we
@kw:	lda we
	sta li
	jmp keyword
@name:	; a name: at most 32 characters and the suffix
	lda kl
	ldx we
	ldy LS-1,x
	cpy #'$'
	beq @sx
	cpy #'%'
	bne @ln
@sx:	dec a
@ln:	cmp #33
	bcc @ok
	lda #VE_NAMELONG
	jmp lexfail
@ok:	lda we
	sta li
	PROF 2
	jsr symfind		; -> sym
	PROF 1
	jsr pns			; nxt
	stx we
	lda ss
	jeq @nst
	; at a statement's start: a label, an assignment, a SUB call
	cpx ln
	bcs @call
	lda LS,x
	cmp #':'
	bne @nlab
	lda lo
	cmp #6
	bne @nlab
	jsr nameref
	lda #1
	sta lab
	rts
@nlab:	cmp #'='
	bne @npar
	inx
	cpx ln
	bcs @var
	lda LS,x
	cmp #'<'
	beq @call
	cmp #'>'
	beq @call
@var:	jmp var
@npar:	cmp #'('
	bne @call
	jsr mparen		; x past the ")"
	jsr pnsx
	cpx ln
	bcs @call
	lda LS,x
	cmp #'='
	beq @var
@call:	jsr nameref
	stz ss
	stz skwv
	stz argno
	lda #1
	sta args
	rts
@nst:	lda ref
	cmp #REF_LINE
	beq @nr
	cmp #REF_PROC
	bne @pp
@nr:	jsr nameref
	lda rlist
	bne @nr1
	stz ref
@nr1:	stz args
	rts
@pp:	; a procedure's place in a statement's arguments?
	lda skwv
	beq @var2
	lda depth
	bne @var2
	lda args
	beq @var2
	ldx #0
@pa:	lda vb_procarg,x
	beq @var2
	cmp #$FF
	bne @pa1
	lda vb_procarg+1,x
	cmp skw
	bne @pan
	lda skw+1
	cmp #$FF
	bne @pan
	bra @pa2
@pa1:	cmp skw
	bne @pan
	lda skw+1
	bne @pan
@pa2:	lda vb_procarg+2,x
	cmp argno
	beq @pay
@pan:	inx
	inx
	inx
	bra @pa
@pay:	ldx we
	cpx ln
	bcs @pref
	lda LS,x
	cmp #','
	beq @pref
	cmp #':'
	beq @pref
	cmp #$27
	bne @var2
@pref:	jsr nameref
	stz args
	rts
@var2:	jmp var

; the token at vb_compound,x (tk, 0 or $FF, nn) -> tp (lo; hi 0 or $FF)
tpair:	lda vb_compound,x
	cmp #$FF
	beq @p2
	sta tp
	stz tp+1
	rts
@p2:	sta tp+1
	lda vb_compound+1,x
	sta tp
	rts

; x at a "(": x past its ")" (or the end), quotes skipped
mparen:	stz fpt
	stz fh			; depth
@l:	cpx ln
	bcs @r
	lda LS,x
	cmp #'"'
	bne @q
	lda fpt
	eor #1
	sta fpt
	bra @n
@q:	ldy fpt
	bne @n
	cmp #'('
	bne @c
	inc fh
	bra @n
@c:	cmp #')'
	bne @n
	dec fh
	bne @n
	inx
	rts
@n:	inx
	bra @l
@r:	rts

var:	lda #T_VAR
	jsr emit
	lda sym
	jsr emit
	lda sym+1
	jsr emit
	jmp after_op

nameref:
	lda #T_NAMEREF
	jsr emit
	lda sym
	jsr emit
	lda sym+1
	jsr emit
	jsr emit0
	jsr emit0
	jmp emit0

; the keyword code (kfl, kxf): its token, the context it makes
keyword:
	lda ss
	sta fh			; at_start
	lda code+1
	beq @p1
	lda #T_EXT
	jsr emit
@p1:	lda code
	jsr emit
	lda kfl
	and #VBF_BLOCK
	beq @nb
	lda fh
	bne @blk
	lda code+1
	bne @nb
	lda code
	cmp #TK_ELSE
	bne @nb
@blk:	lda #T_BLOCK
	jsr emit
	jsr emit0
	jsr emit0
@nb:	lda kfl
	bpl @nraw
	lda kxf
	and #VBX_RAW_DATA
	bne @data
	ldx li			; REM: the rest of the line
	jmp lex_comment
@data:	lda fh
	beq @nraw
	lda #1
	sta dmode
	lda li
	sta iraw
	rts
@nraw:	stz rlist
	lda kfl
	and #VBF_REF_STMT
	beq @nst
	jsr pns
	cpx ln
	bcs @ns
	ldy LS,x
	lda cls,y
	and #C_DIG
	beq @ns
	lda #REF_STMT
	sta ref
	stz ss
	rts
@ns:	jmp new_stmt
@nst:	stz ref
	lda kfl
	and #VBF_REF_LINE
	beq @np
	lda #REF_LINE
	sta ref
	lda code+1
	bne @af
	lda code
	cmp #TK_GOTO
	beq @rl
	cmp #TK_GOSUB
	bne @af
@rl:	lda #1
	sta rlist
	bra @af
@np:	lda kfl
	and #VBF_REF_PROC
	beq @af
	lda #REF_PROC
	sta ref
@af:	lda fh
	beq @nas
	lda #1
	sta skwv
	lda code
	sta skw
	lda code+1
	sta skw+1
	stz argno
	lda #1
	sta args
	bra @e
@nas:	stz args
@e:	stz ss
	rts

;---------------------------------------------------------------
; the names: a hash table of 128 chains in _vt_nb ($A000: the heads;
; then the entries: next (2), symbol (2), length (1), the key, the
; spelling); their attributes in _vt_ab, 16 bytes a symbol:
;   0 flags (prepare: 1 scalar use, 2 DIM, 4 CONST, 8 SUB, 16 FUNCTION,
;     32 label, 64 used with "(", 128 assigned)
;   1 type, 2-3 target, 4-5 first line, 6-7 the label's line,
;   8-9 the first assignment's line, 10-11 the entry, 12 procedure + 1,
;   13 kind (K_BUILTIN at first; prepare's end: the symbol's kind),
;   14-15 a built-in constant's value
;---------------------------------------------------------------
SYMMAX	= 512

names_init:
	ldx #0			; the heads: 256 zero bytes (rbuf's, by xcopy)
@z:	stz rbuf,x
	inx
	bne @z
	lda _vt_nb
	sta xbk
	stz xp
	lda #$A0
	sta xp+1
	lda #<rbuf
	sta xm
	lda #>rbuf
	sta xm+1
	stz xn
	jsr xcopy_out
	stz ntop
	lda #$A1
	sta ntop+1
	rts

; the name kb (kl; spelling LS ws..we) -> sym (found or made)
symfind:
	; the hash
	lda kl
	ldx #0
@h:	asl a
	adc #0
	eor kb,x
	inx
	cpx kl
	bne @h
	and #$7F
	asl a
	sta fpp
	lda #$A0
	sta fpp+1
	lda _vt_nb
	sta fpb
	ldy #0
	jsr fpeek
	sta ent
	iny
	jsr fpeek
	sta ent+1
	lda fpp
	sta hsh			; the head's place
@chain:	lda ent+1
	beq @new
	lda ent
	sta fpp
	lda ent+1
	sta fpp+1
	ldy #4
	jsr fpeek
	cmp kl
	bne @next
	ldx #0
	ldy #5
@k:	jsr fpeek
	cmp kb,x
	bne @next
	iny
	inx
	cpx kl
	bne @k
	ldy #2
	jsr fpeek
	sta sym
	iny
	jsr fpeek
	sta sym+1
	rts
@next:	ldy #0
	jsr fpeek
	sta ent
	iny
	jsr fpeek
	sta ent+1
	bra @chain
@new:	; room?
	lda vt_nsym+1
	cmp #>SYMMAX
	jcs @full
	lda kl
	asl a
	adc #5
	adc ntop
	lda ntop+1
	adc #0
	cmp #$C0
	jcs @full
	; the old head -> ent; the head = the new entry (ntop)
	lda hsh
	sta fpp
	lda #$A0
	sta fpp+1
	ldy #0
	jsr fpeek
	sta ent
	lda ntop
	jsr fpoke
	iny
	jsr fpeek
	sta ent+1
	lda ntop+1
	jsr fpoke
	; the entry: next, symbol, length, key, spelling
	lda ntop
	sta fpp
	lda ntop+1
	sta fpp+1
	ldy #0
	lda ent
	jsr fpoke
	iny
	lda ent+1
	jsr fpoke
	iny
	lda vt_nsym
	sta sym
	jsr fpoke
	iny
	lda vt_nsym+1
	sta sym+1
	jsr fpoke
	iny
	lda kl
	jsr fpoke
	iny
	ldx #0
@wk:	lda kb,x
	jsr fpoke
	iny
	inx
	cpx kl
	bne @wk
	ldx ws
@ws:	lda LS,x
	jsr fpoke
	iny
	inx
	cpx we
	bne @ws
	lda ntop		; ent: the entry; ntop past it
	sta ent
	lda ntop+1
	sta ent+1
	tya
	clc
	adc ntop
	sta ntop
	bcc @at
	inc ntop+1
@at:	jsr symattr		; its attributes
	ldy #15
	lda #0
@z:	jsr fpoke
	dey
	bpl @z
	ldx kl			; the type: the suffix
	lda kb-1,x
	ldx #TY_S
	cmp #'$'
	beq @ty
	ldx #TY_I
	cmp #'%'
	beq @ty
	ldx #TY_F
@ty:	txa
	ldy #1
	jsr fpoke
	ldy #4
	lda vt_src
	jsr fpoke
	iny
	lda vt_src+1
	jsr fpoke
	ldy #10
	lda ent
	jsr fpoke
	iny
	lda ent+1
	jsr fpoke
@nb:	inc vt_nsym
	bne @r
	inc vt_nsym+1
@r:	rts
@full:	lda #VE_NAMES
	jmp lexfail

; sym's attributes -> fpb/fpp
symattr:
	lda _vt_ab
	sta fpb
	lda sym
	asl a
	asl a
	asl a
	asl a
	sta fpp
	lda sym+1
	sta fh
	lda sym
	lsr fh
	ror a
	lsr fh
	ror a
	lsr fh
	ror a
	lsr fh
	ror a
	and #$1F		; (sym * 16) >> 8
	ora #$A0
	sta fpp+1
	rts

