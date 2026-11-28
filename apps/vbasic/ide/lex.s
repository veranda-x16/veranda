; VeraBASIC, the editor: B_LEX's colouring in assembly (DECISIONS V215;
; colour.c's lexer as it was in C, the same classes): a row's line
; (lexbuf, n bytes, no LF) into the classes of the columns shown
; (lexcls[0 .. COLS): textkit's hs the first), and a row's cards for
; textkit's tk_putrow (its characters and styles) with the colour map's
; paper of each.
;
;   strings ("..., "" inside) K_STR, the rest of a line after ' or the
;   keyword REM K_REM, numbers (digits, '.', $ or % before a digit or a
;   letter; then digits, '.', A-F) K_NUM, keywords (a letter, then
;   letters, digits, _, a $ or % after them; 11 characters at most, in
;   the generated table kw_wtxt / kw_woff: a binary search among the
;   words of its first letter) K_WORD; a tab
;   takes the columns to the next eighth.
;
; Its variables in its own bank's code segment (RAM: B8 has no BSS).
;
; MIT licence (LICENSE).

	.setcpu "65C02"
	.export _ide_lex, _ide_cards, _ide_ptab
	.import _IDEDYN, _hs, _tk_cols, _tk_x0, _tk_pn, _kw_wtxt, _kw_woff, _gb_line
	.importzp ptr1, ptr2, tmp1, tmp2

LEXBUF	= _IDEDYN + 1200        ; (ide.h: lexbuf, lexcls, ide_paper)
LEXCLS	= _IDEDYN + 1456
PAPER	= _IDEDYN + 1536
ROWC	= LEXBUF                ; (colour.c: the row's characters, styles)
ROWF	= LEXBUF + 128
NWORDS	= 207                   ; (idekw.h: KW_NWORDS)
.assert NWORDS < 256, error, "the keywords' search: a byte"

K_PLAIN	= 0
K_WORD	= 1
K_STR	= 2
K_REM	= 3
K_NUM	= 4

.segment "B8CODE"

n:	.res 1                  ; the line's bytes
i:	.res 1                  ; the one looked at
col:	.res 2                  ; the column the lexer is at
cls:	.res 1                  ; the class put
rest:	.res 1                  ; 1: a comment's rest
w:	.res 1                  ; the word's characters
klo:	.res 1                  ; the search
khi:	.res 1
mid:	.res 1
wbuf:	.res 14
kix:	.res 1                  ; 1: the index made
kfirst:	.res 26                 ; each letter's first and last word in the table
klast:	.res 26
_ide_ptab: .res 5               ; (colour.c's) the paper of each class

; void __fastcall__ ide_lex(unsigned char n)
_ide_lex:
	sta n
	ldx _tk_cols            ; lexcls all K_PLAIN
	lda #K_PLAIN
@cl:	dex
	cpx #$FF
	beq @c0
	sta LEXCLS,x
	bra @cl
@c0:	stz col
	stz col+1
	stz i
	stz rest
Next:	ldx i
	cpx n
	bcc @1
	rts
@1:	lda LEXBUF,x
	ldy rest
	beq @2
	ldy #K_REM              ; a comment's rest
	jsr Put1
	bra Next
@2:	cmp #'"'
	bne @q
	ldy #K_STR              ; a string
	jsr Put1
@s:	ldx i
	cpx n
	bcs Next
	lda LEXBUF,x
	ldy #K_STR
	jsr Put1                ; (i + 1)
	cmp #'"'
	bne @s
	ldx i                   ; "" inside: on
	cpx n
	bcs Next
	lda LEXBUF,x
	cmp #'"'
	bne Next
	ldy #K_STR
	jsr Put1
	bra @s
@q:	cmp #$27                ; '
	bne @3
	inc rest
	bra Next
@3:	jsr Letter
	bcs Word
	cmp #'.'
	beq Num
	cmp #'0'
	bcc @4
	cmp #'9' + 1
	bcc Num
@4:	cmp #'$'
	beq @5
	cmp #'%'
	bne Plain
@5:	inx                     ; $ or % before a digit or a letter
	cpx n
	bcs Plain
	lda LEXBUF,x
	cmp #'0'
	bcc @6
	cmp #'9' + 1
	bcc @7
@6:	and #$DF
	cmp #'A'
	bcc Plain
@7:	ldx i
	lda LEXBUF,x
	bra Num
Nx:	jmp Next
Num:	ldy #K_NUM
	jsr Put1
@n:	ldx i
	cpx n
	bcs Nx
	lda LEXBUF,x
	cmp #'.'
	beq @n1
	cmp #'0'
	bcc @n2
	cmp #'9' + 1
	bcc @n1
@n2:	pha
	and #$DF
	cmp #'A'
	bcc @n3
	cmp #'F' + 1
	bcs @n3
	pla
@n1:	ldy #K_NUM
	jsr Put1
	bra @n
@n3:	pla
	jmp Next
Plain:	ldx i
	lda LEXBUF,x
	ldy #K_PLAIN
	jsr Put1
	jmp Next

; a word from i: wbuf (upper case, 12 at most), its class, its columns
Word:	stz w
@w:	cpx n                   ; x = j
	bcs @e
	lda LEXBUF,x
	jsr Letter
	bcc @w1
	and #$DF                ; (a letter: upper case)
	bra @w2
@w1:	cmp #'_'
	beq @w2
	cmp #'0'
	bcc @e
	cmp #'9' + 1
	bcs @e
@w2:	ldy w
	cpy #12
	bcs @w3
	sta wbuf,y
	inc w
@w3:	inx
	bra @w
@e:	cpx n                   ; a $ or % after it
	bcs @z
	lda LEXBUF,x
	cmp #'$'
	beq @d
	cmp #'%'
	bne @z
@d:	ldy w
	cpy #12
	bcs @d1
	sta wbuf,y
	inc w
@d1:	inx
@z:	stx tmp2                ; j
	ldy w
	lda #0
	sta wbuf,y
	lda w
	cmp #12
	bcs @k                  ; (carry set: 12, too long)
	jsr Keyword
	ldy #K_WORD
	bcs @k1
@k:	ldy #K_PLAIN
@k1:	sty cls
@p:	ldx i                   ; i .. j - 1: the class
	cpx tmp2
	bcs @r
	lda LEXBUF,x
	ldy cls
	jsr Put1
	bra @p
@r:	lda cls                 ; the keyword REM: the rest a comment
	cmp #K_WORD
	bne @x
	lda w
	cmp #3
	bne @x
	lda wbuf
	cmp #'R'
	bne @x
	lda wbuf+1
	cmp #'E'
	bne @x
	lda wbuf+2
	cmp #'M'
	bne @x
	inc rest
@x:	jmp Next

; c: a = a letter (A-Z, a-z); a and x kept
Letter:	pha
	and #$DF
	cmp #'A'
	bcc @n
	cmp #'Z' + 1
	bcs @n
	pla
	sec
	rts
@n:	pla
	clc
	rts

; the columns of character a (a tab: to the next eighth) get class y; i + 1;
; a kept
Put1:	sty cls
	inc i
	pha
	ldy #1
	cmp #9
	bne @1
	lda col
	and #7
	eor #7
	tay
	iny                     ; 8 - (col AND 7)
@1:	lda col                 ; column col - hs, if shown
	sec
	sbc _hs
	tax
	lda col+1
	sbc _hs+1
	bne @2                  ; (before hs, or past 255 shown)
	cpx _tk_cols
	bcs @2
	lda cls
	sta LEXCLS,x
@2:	inc col
	bne @3
	inc col+1
@3:	dey
	bne @1
	pla
	rts

; c: wbuf is in the table (a binary search)
Keyword:
	lda kix                 ; (the first time: the index)
	bne @k
	jsr Index
@k:	lda wbuf                ; its first letter's entries (a word starts
	sec                     ; with a letter: wbuf is upper case)
	sbc #'A'
	tax
	lda kfirst,x
	sta klo
	lda klast,x
	sta khi
@l:	lda khi
	cmp klo
	bcc @no                 ; (klo > khi)
	clc
	adc klo
	ror                     ; (klo + khi) / 2 (9 bits: the carry)
	sta mid
	jsr Entry
	ldy #0
@c:	lda wbuf,y
	cmp (ptr2),y
	bne @d
	tax
	beq @yes
	iny
	bra @c
@d:	bcc @lt                 ; wbuf before it
	ldx mid
	inx
	stx klo
	bra @l
@lt:	ldx mid
	beq @no
	dex
	stx khi
	bra @l
@yes:	sec
	rts
@no:	clc
	rts

; ptr2 = the table's word mid (kw_wtxt + kw_woff[mid])
Entry:	lda mid
	asl                     ; ptr1 = kw_woff + 2 * mid
	sta ptr1
	lda #0
	rol
	sta ptr1+1
	lda ptr1
	clc
	adc #<_kw_woff
	sta ptr1
	lda ptr1+1
	adc #>_kw_woff
	sta ptr1+1
	ldy #0
	lda (ptr1),y
	clc
	adc #<_kw_wtxt
	sta ptr2
	iny
	lda (ptr1),y
	adc #>_kw_wtxt
	sta ptr2+1
	rts

; the index: each letter's first and last entry in the sorted table (none:
; first 255, last 0)
Index:	ldx #25
@i:	lda #$FF
	sta kfirst,x
	stz klast,x
	dex
	bpl @i
	stz mid
@e:	jsr Entry
	lda (ptr2)
	sec
	sbc #'A'
	cmp #26
	bcs @n
	tax
	lda kfirst,x
	cmp #$FF
	bne @1
	lda mid
	sta kfirst,x
@1:	lda mid
	sta klast,x
@n:	inc mid
	lda mid
	cmp #NWORDS
	bne @e
	inc kix
	rts

; void __fastcall__ ide_cards(unsigned char mark): the text's cards from
; column X0 of the row (ROWC: gb_line's characters, ROWF: bold for
; K_WORD) and their paper (mark, or ide_ptab of the class): textkit's
; tk_pn of them (the ones drawn)
_ide_cards:
	sta tmp1
	ldy _tk_x0
	ldx #0
@c:	cpx _tk_pn
	bcs @r
	lda _gb_line,x
	sta ROWC,y
	lda LEXCLS,x
	phx
	tax
	lda #0
	cpx #K_WORD
	bne @1
	lda #2
@1:	sta ROWF,y
	lda tmp1
	bne @2
	lda _ide_ptab,x
@2:	sta PAPER,y
	plx
	inx
	iny
	bra @c
@r:	rts
