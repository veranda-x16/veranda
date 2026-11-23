; VeraBASIC Run: the program's tokens made ready to run (included by vb.s;
; main.c has laid record 1 out in the program's banks and the line index,
; record 2, in _vb_relbank). Each operand that names something gets the
; runtime's own form, in this copy only (the document is not changed):
;   TAG_VAR    a global: the address of its cell (cellbase + 8 * symbol,
;              $0800 or above); a local ($8000 + slot): its slot's offset in
;              the frame (8 * slot, below $0800)
;   TAG_LINEREF  its target: the line record's address and bank
;   TAG_NAMEREF  a label: 0, its line record's address and bank; a SUB or
;              FUNCTION: $8000 + its procedure; after SUB/FUNCTION (the
;              definition) the body's place into the procedure's entry
; A byte written in a bank's last 256 bytes is written in the next bank's
; first 256 too (the same bytes of record 1), and the other way.
; MIT licence (LICENSE).

_vb_rewrite:
	lda ram_bank
	sta rw_keep
	lda _pbase
	sta pbank
	sta ram_bank
	lda #<$A000
	sta ip
	lda #>$A000
	sta ip+1
	stz rw_def
@rec:	lda (ip)
	bne @r1
	jmp @done
@r1:	ADDIP 6
@tok:	lda (ip)
	bne @t1
	; the record's end: the next one (its bank)
	INCIP
	lda ip+1
	cmp #$A0 + PSTRIDE
	bcc @rec
	sbc #PSTRIDE
	sta ip+1
	inc pbank
	MAPP
	bra @rec
@t1:	cmp #T_VAR
	bne @t2
	ldy #2
	lda (ip),y
	bpl @glob
	; a local: its slot's offset in the frame (slot * 8)
	and #$7F
	sta n0+1
	dey
	lda (ip),y
	asl a
	rol n0+1
	asl a
	rol n0+1
	asl a
	rol n0+1
	sta n0
	lda n0
	ldy #1
	jsr rw_sta
	lda n0+1
	iny
	jsr rw_sta
	bra @skip3
@glob:	; cellbase + w * 8
	sta n0+1
	dey
	lda (ip),y
	asl a
	rol n0+1
	asl a
	rol n0+1
	asl a
	rol n0+1
	clc
	adc _cellbase
	sta n0
	lda n0+1
	adc _cellbase+1
	sta n0+1
	lda n0
	ldy #1
	jsr rw_sta
	lda n0+1
	iny
	jsr rw_sta
@skip3:	stz rw_def
	ADDIP 3
	bra @tok
@t2:	cmp #T_LINEREF
	bne @t3
	jsr rw_line
	stz rw_def
	ADDIP 6
	jmp @tok
@t3:	cmp #T_NAMEREF
	bne @t4
	jsr rw_name
	stz rw_def
	ADDIP 6
	jmp @tok
@t4:	cmp #TK_SUB
	beq @def
	cmp #TK_FUNCTION
	beq @def
	cmp #T_BLOCK
	beq @blk
	stz rw_def
	jsr skip_tok
	jmp @tok
@def:	lda #1
	sta rw_def
	INCIP
	jmp @tok
@blk:	ADDIP 3                 ; (rw_def kept: SUB [$0B] Name)
	jmp @tok
@done:	lda _pbase
	sta pbank
	lda rw_keep
	sta ram_bank
	rts
rw_def:	.byte 0
rw_keep: .byte 0

; a at (ip),y; the same byte in the neighbour bank's copy (a, x, y kept;
; the carry not)
rw_sta:	sta (ip),y
	sta rw_v
	sty rw_y
	phx
	tya
	clc
	adc ip
	sta bp1
	lda ip+1
	adc #0
	sta bp1+1
	cmp #$BF
	bcc @low
	lda pbank               ; the next bank's first 256 bytes
	sec
	sbc _pbase
	inc a
	cmp _npb
	bcs @r
	lda pbank
	inc a
	sta ram_bank
	lda bp1+1
	sec
	sbc #PSTRIDE
	sta bp1+1
	lda rw_v
	sta (bp1)
	bra @r
@low:	cmp #$A1                ; the previous bank's last 256 bytes
	bcs @r
	lda pbank
	cmp _pbase
	beq @r
	dec a
	sta ram_bank
	lda bp1+1
	clc
	adc #PSTRIDE
	sta bp1+1
	lda rw_v
	sta (bp1)
@r:	MAPP
	plx
	ldy rw_y
	lda rw_v
	rts
rw_y:	.byte 0
rw_v:	.byte 0

; the TAG_LINEREF at ip: its target from the line index (binary search)
rw_line:
	ldy #1
	lda (ip),y
	sta rl_n
	iny
	lda (ip),y
	sta rl_n+1
	stz rl_lo
	stz rl_lo+1
	lda _vb_reln
	sta rl_hi
	lda _vb_reln+1
	sta rl_hi+1             ; [lo, hi)
@l:	lda rl_lo
	cmp rl_hi
	lda rl_lo+1
	sbc rl_hi+1
	bcs @none
	; mid = (lo + hi) / 2
	lda rl_lo
	clc
	adc rl_hi
	sta rl_m
	lda rl_lo+1
	adc rl_hi+1
	ror a
	sta rl_m+1
	ror rl_m
	jsr rl_entry            ; n1 = its number, n0 = its offset
	lda n1
	cmp rl_n
	bne @ne
	lda n1+1
	cmp rl_n+1
	beq @found
@ne:	lda n1
	cmp rl_n
	lda n1+1
	sbc rl_n+1
	bcc @up
	lda rl_m                ; hi = mid
	sta rl_hi
	lda rl_m+1
	sta rl_hi+1
	bra @l
@up:	lda rl_m                ; lo = mid + 1
	clc
	adc #1
	sta rl_lo
	lda rl_m+1
	adc #0
	sta rl_lo+1
	bra @l
@none:	lda #0
	ldy #3
	jsr rw_sta
	iny
	jsr rw_sta
	iny
	jmp rw_sta
@found:	jmp rw_target
rl_n:	.word 0
rl_lo:	.word 0
rl_hi:	.word 0
rl_m:	.word 0

; entry rl_m of the line index -> n1 its number, n0 its record's offset
rl_entry:
	lda rl_m
	sta n0
	lda rl_m+1
	asl n0
	rol a
	asl n0
	rol a                   ; a:n0 = 4 * m
	pha
	and #$1F
	ora #$A0
	sta bp1+1
	lda n0
	sta bp1
	pla
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc _vb_relbank
	sta ram_bank
	ldy #0
	lda (bp1),y
	sta n1
	iny
	lda (bp1),y
	sta n1+1
	iny
	lda (bp1),y
	sta n0
	iny
	lda (bp1),y
	sta n0+1
	MAPP
	rts

; the offset n0 as (address, bank) into the operand's target (ip + 3 .. 5)
rw_target:
	lda n0+1
	jsr div31
	stx rt_b
	sta rt_p
	lda n0
	ldy #3
	jsr rw_sta
	lda rt_p
	clc
	adc #$A0
	iny
	jsr rw_sta
	lda rt_b
	clc
	adc _pbase
	iny
	jmp rw_sta
rt_b:	.byte 0
rt_p:	.byte 0

; the TAG_NAMEREF at ip
rw_name:
	ldy #2
	lda (ip),y
	sta n0+1
	dey
	lda (ip),y
	asl a
	rol n0+1
	asl a
	rol n0+1
	asl a
	rol n0+1
	clc
	adc _cellbase
	sta p0
	lda n0+1
	adc _cellbase+1
	sta p0+1
	ldy #6
	lda (p0),y
	cmp #1
	beq @label
	cmp #2
	beq @proc
	rts
@label:	ldy #0
	lda (p0),y
	sta n0
	iny
	lda (p0),y
	sta n0+1
	lda #0
	ldy #1
	jsr rw_sta
	iny
	jsr rw_sta
	jmp rw_target
@proc:	lda (p0)
	sta rn_i
	ldy #1
	jsr rw_sta
	lda #$80
	iny
	jsr rw_sta
	lda rw_def
	bne @body
	rts
@body:	; the body: past the name and its parameters' parentheses
	lda ip
	pha
	lda ip+1
	pha
	ADDIP 6
	lda (ip)
	cmp #'('
	bne @at
	stz t3
@p:	lda (ip)
	beq @at
	cmp #'('
	bne @p1
	inc t3
@p1:	cmp #')'
	bne @p2
	dec t3
	bne @p2
	INCIP
	bra @at
@p2:	jsr skip_tok
	bra @p
@at:	lda rn_i
	jsr proc_ptr
	ldy #3
	lda ip
	sta (p2),y
	iny
	lda ip+1
	sta (p2),y
	iny
	lda pbank
	sta (p2),y
	pla
	sta ip+1
	pla
	sta ip
	rts
rn_i:	.byte 0

.ifdef VB_LOG
; the test build's console line: "VB| " and the row's _ccol characters
_vb_logline:
	ldx #0
@p:	lda MLog,x
	beq @t
	sta EMU_STDOUT
	inx
	bra @p
@t:	lda crowp
	sta bp1
	lda crowp+1
	sta bp1+1
	lda _cbank
	sta ram_bank
	ldy #0
@c:	cpy _ccol
	beq @e
	lda (bp1),y
	sta EMU_STDOUT
	iny
	bra @c
@e:	MAPP
	lda #10
	sta EMU_STDOUT
	rts

.segment RO_SEG
MLog:	.byte "VB| ", 0
.segment "CODE"
.endif
