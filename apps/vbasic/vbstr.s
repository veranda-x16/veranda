; VeraBASIC Run: strings, the heap, arrays, assignment (included by vb.s).
;
; The heap is in RAM banks (hbanks): entries [length][owner: address,
; bank] then the bytes, never across a bank (a filler, owner bank $FE,
; ends a bank early). The owner is where the string's descriptor (length,
; address, bank) lives: a variable's cell, an array element, a frame's
; slot, a temporary's slot. The collector is one pass: an entry whose
; owner still holds its descriptor is live and moves down, its owner told;
; any other is garbage (owner bank $FF: known dead). The heap's top is
; (hv, hp), a bank's index in hbanks and an address: vb_reset puts it at
; the start with no bank, and a bank comes in as it is (not cleared): the
; collector walks the entries from each bank's start to the top and reads
; no byte the heap has not written (DECISIONS V88). MIT licence (LICENSE).

.segment "ZEROPAGE"
bp1:	.res 2                  ; bcopy's source, destination
bp2:	.res 2

.segment "CODE"

need_str:
	lda aty
	cmp #TY_S
	beq @r
	ERR E_TYPE
@r:	rts

b_to_a:	ldx #5
@c:	lda bty,x
	sta aty,x
	dex
	bpl @c
	rts

; the string in acc -> t0 its length, p1 its address, t1 its bank
sres:	lda ac4
	cmp #SK_TMP
	beq @t
	cmp #SK_VAR
	beq @v
	lda ac0
	sta t0
	lda ac1
	sta p1
	lda ac2
	sta p1+1
	lda ac3
	sta t1
	rts
@t:	lda ac1
	asl a
	asl a
	tax
	lda temps,x
	sta t0
	lda temps+1,x
	sta p1
	lda temps+2,x
	sta p1+1
	lda temps+3,x
	sta t1
	rts
@v:	lda ac1
	sta bp1
	lda ac2
	sta bp1+1
	lda ac3
	beq @m
	sta ram_bank
@m:	ldy #0
	lda (bp1),y
	sta t0
	iny
	lda (bp1),y
	sta p1
	iny
	lda (bp1),y
	sta p1+1
	iny
	lda (bp1),y
	sta t1
	MAPP
	rts

slen	= sres

; a = the first character of acc's string (not empty)
sfirst:	jsr sres
	lda t1
	sta ram_bank
	lda (p1)
	tax
	MAPP
	txa
	rts

; acc's temporary (if it is one) given back
sfree:	lda aty
	cmp #TY_S
	bne @r
	lda ac4
	cmp #SK_TMP
	bne @r
	lda ac1
	jmp temp_free
@r:	rts

; b's temporary likewise
bfree:	lda bty
	cmp #TY_S
	bne @r
	lda b4
	cmp #SK_TMP
	bne @r
	lda b1
	jmp temp_free
@r:	rts

; a new temporary's slot: x = 4 * it, a = it
temp_slot:
	lda ttop
	cmp #NTEMP
	bcc @1
	ERR E_COMPLEX
@1:	inc ttop
	pha
	asl a
	asl a
	tax
	pla
	rts

; temporary a: its string dead, its slot free (the top slots let go)
temp_free:
	asl a
	asl a
	tax
	lda temps+3,x
	beq @c
	sta t3
	lda temps+1,x
	sta bp1
	lda temps+2,x
	sta bp1+1
	lda t3
	jsr heap_dead
@c:	stz temps,x
	stz temps+1,x
	stz temps+2,x
	stz temps+3,x
@top:	lda ttop
	cmp tbase
	beq @r
	beq @r
	dec a
	asl a
	asl a
	tax
	lda temps+3,x
	bne @r
	dec ttop
	bra @top
@r:	rts

; the temporaries from tbase up given back
free_temps:
@l:	lda ttop
	cmp tbase
	beq @r
	bcc @r
	dec a
	sta ttop
	asl a
	asl a
	tax
	lda temps+3,x
	beq @l
	sta t3
	lda temps+1,x
	sta bp1
	lda temps+2,x
	sta bp1+1
	lda t3
	jsr heap_dead
	stz temps,x
	stz temps+1,x
	stz temps+2,x
	stz temps+3,x
	bra @l
@r:	rts

; the heap string at bp1 in bank a (if it is the heap's): dead
heap_dead:
	tay
	lda bkind,y
	cmp #2
	bne @r
	sty ram_bank
	lda bp1
	sec
	sbc #1
	sta bp2
	lda bp1+1
	sbc #0
	sta bp2+1
	lda #$FF
	sta (bp2)               ; the owner's bank byte
	MAPP
@r:	rts

; the cell at p1 in bank a: its string dead, the cell emptied
cell_dead:
	sta ram_bank
	ldy #3
	lda (p1),y
	pha
	dey
	lda (p1),y
	sta bp1+1
	dey
	lda (p1),y
	sta bp1                 ; (y = 1)
	lda #0
	sta (p1)
	sta (p1),y
	iny
	sta (p1),y
	iny
	sta (p1),y
	pla
	beq @r
	jsr heap_dead
@r:	MAPP
	rts

; the heap entry of the string at p1 (bank t1): its owner := (p0, xb)
set_owner:
	lda t1
	sta ram_bank
	lda p1
	sec
	sbc #3
	sta bp2
	lda p1+1
	sbc #0
	sta bp2+1
	lda p0
	sta (bp2)
	ldy #1
	lda p0+1
	sta (bp2),y
	iny
	lda xb
	sta (bp2),y
	MAPP
	rts

;---------------------------------------------------------------
; bcopy: a (1-255) bytes from bp1 (bank bc_sb) to bp2 (bank bc_db);
; forward, so an overlap down is fine
;---------------------------------------------------------------
bcopy:	sta bc_n
	tax
	beq @r
	lda bp1+1
	cmp #$A0
	bcc @direct_d           ; the source in main RAM
	lda bp2+1
	cmp #$A0
	bcc @direct_s           ; the destination in main RAM
	lda bc_sb
	cmp bc_db
	beq @direct_s
	; two banks: through sbounce
	sta ram_bank
	ldy #0
@b1:	lda (bp1),y
	sta sbounce,y
	iny
	cpy bc_n
	bne @b1
	lda bc_db
	sta ram_bank
	ldy #0
@b2:	lda sbounce,y
	sta (bp2),y
	iny
	cpy bc_n
	bne @b2
	bra @done
@direct_d:
	lda bc_db
	bra @d
@direct_s:
	lda bc_sb
@d:	sta ram_bank
	ldy #0
@c:	lda (bp1),y
	sta (bp2),y
	iny
	cpy bc_n
	bne @c
@done:	MAPP
@r:	rts
bc_n:	.byte 0
bc_sb:	.byte 0
bc_db:	.byte 0

;---------------------------------------------------------------
; the heap
;---------------------------------------------------------------
; t0 = a length (1-255) -> p1 room for it in the heap, t1 its bank; the
; entry's owner is none yet (dead) until set_owner
salloc:	stz sa_gc
@try:	lda hv
	cmp nhb
	bcs @nob
	tax
	lda hbanks,x
	sta sa_bank
	; room in this bank: hp + t0 + 4 <= $C000
	lda t0
	clc
	adc #4
	adc hp
	tax
	lda hp+1
	adc #0
	cmp #$C0
	jcc @ok
	bne @next
	cpx #0
	jeq @ok
@next:	; a filler (4 bytes left at least: below $BFFD), the next bank
	lda hp+1
	cmp #$C0
	bcs @nf                 ; (the bank is full to its end)
	cmp #$BF
	bne @f
	lda hp
	cmp #$FD
	bcs @nf                 ; under 4 bytes: nothing written
@f:	lda sa_bank
	sta ram_bank
	lda hp
	sta bp2
	lda hp+1
	sta bp2+1
	ldy #3
	lda #$FE
	sta (bp2),y
	MAPP
@nf:	inc hv
	lda #<$A000
	sta hp
	lda #>$A000
	sta hp+1
	bra @try
@nob:	; no bank with room: collect, then a new bank
	lda sa_gc
	bne @grow
	inc sa_gc
	jsr gc
	jsr gc_roomy            ; carry set: a quarter free or more
	bcs @try
@grow:	lda _nbanks
	cmp _limitb
	bcs @mem
	jsr new_bank
	beq @mem
	ldx nhb
	sta hbanks,x
	tay
	lda #2
	sta bkind,y
	inc nhb
	; the heap's top: the new bank, unless the top bank has room still
	lda hv
	cmp nhb
	jcc @try
	dec a
	sta hv
	lda #<$A000
	sta hp
	lda #>$A000
	sta hp+1
	jmp @try
@mem:	ERR E_MEM
@ok:	; the entry: [t0][owner $FF], the bytes after
	lda sa_bank
	sta t1
	sta ram_bank
	lda hp
	sta bp2
	lda hp+1
	sta bp2+1
	lda t0
	sta (bp2)
	ldy #3
	lda #$FF
	sta (bp2),y
	MAPP
	lda hp
	clc
	adc #4
	sta p1
	lda hp+1
	adc #0
	sta p1+1
	lda p1
	clc
	adc t0
	sta hp
	lda p1+1
	adc #0
	sta hp+1
	rts
sa_gc:	.byte 0
sa_bank: .byte 0

; a new RAM bank for the heap or the arrays: a = it, zero flag if none
new_bank:
	lda #1
	jsr BankAlloc
	cmp #0
	beq @r
	inc _nbanks
@r:	rts

; after a collection: carry set if the heap has a quarter or more free
; (counted in its last bank: at least 2 KB there, or a bank not used yet)
gc_roomy:
	lda nhb
	beq @no
	lda hv
	inc a
	cmp nhb
	bcc @yes
	lda hp+1
	cmp #$B8
	bcc @yes
@no:	clc
	rts
@yes:	sec
	rts

; the collector: one pass, the live entries moved down
gc:	ldx #0                  ; zero page kept
@s:	lda $D4,x
	sta gc_zp,x
	inx
	cpx #44
	bne @s
	stz gc_sv
	stz gc_dv
	lda #<$A000
	sta gc_sp
	sta gc_dp
	lda #>$A000
	sta gc_sp+1
	sta gc_dp+1
@l:	; past the top?
	lda gc_sv
	cmp hv
	bcc @in
	jne @done
	lda gc_sp
	cmp hp
	lda gc_sp+1
	sbc hp+1
	jcs @done
@in:	; under 4 bytes left in this bank (an entry may end at $C000): the next
	lda gc_sp+1
	cmp #$C0
	bcs @nb
	cmp #$BF
	bne @h
	lda gc_sp
	cmp #$FD
	bcc @h
@nb:	inc gc_sv
	lda #<$A000
	sta gc_sp
	lda #>$A000
	sta gc_sp+1
	bra @l
@h:	ldx gc_sv
	lda hbanks,x
	sta gc_sbank
	sta ram_bank
	lda gc_sp
	sta bp1
	lda gc_sp+1
	sta bp1+1
	; the header, no byte of it read that the heap has not written: a
	; filler is its owner's bank byte alone, an entry without an owner
	; yet (salloc's) its length and that byte
	ldy #3
	lda (bp1),y
	cmp #$FE
	beq @nb                 ; a filler
	sta gc_hdr+3
	lda (bp1)
	sta gc_hdr
	lda gc_hdr+3
	cmp #$FF
	jeq @skip               ; dead
	ldy #1
	lda (bp1),y
	sta gc_hdr+1
	iny
	lda (bp1),y
	sta gc_hdr+2
	; the owner holds it? (length, address + 4, bank)
	lda gc_sp
	clc
	adc #4
	sta gc_dat
	lda gc_sp+1
	adc #0
	sta gc_dat+1
	lda gc_hdr+1
	sta bp2
	lda gc_hdr+2
	sta bp2+1
	lda gc_hdr+3
	sta ram_bank
	ldy #0
	lda (bp2),y
	cmp gc_hdr
	jne @skip
	iny
	lda (bp2),y
	cmp gc_dat
	jne @skip
	iny
	lda (bp2),y
	cmp gc_dat+1
	jne @skip
	iny
	lda (bp2),y
	cmp gc_sbank
	jne @skip
	; live: room at the destination?
	lda gc_hdr
	clc
	adc #4
	sta gc_size
	adc gc_dp
	tax
	lda gc_dp+1
	adc #0
	cmp #$C0
	bcc @fit
	bne @dnext
	cpx #0
	beq @fit
@dnext:	lda gc_dp+1
	cmp #$C0
	bcs @nofill
	cmp #$BF
	bne @fill
	lda gc_dp
	cmp #$FD
	bcs @nofill
@fill:	ldx gc_dv
	lda hbanks,x
	sta ram_bank
	lda gc_dp
	sta bp2
	lda gc_dp+1
	sta bp2+1
	ldy #3
	lda #$FE
	sta (bp2),y
@nofill:
	inc gc_dv
	lda #<$A000
	sta gc_dp
	lda #>$A000
	sta gc_dp+1
@fit:	ldx gc_dv
	lda hbanks,x
	sta gc_dbank
	; moved (unless it is where it is)
	cmp gc_sbank
	bne @move
	lda gc_dp
	cmp gc_sp
	bne @move
	lda gc_dp+1
	cmp gc_sp+1
	beq @tell
@move:	lda gc_sbank
	sta bc_sb
	lda gc_dbank
	sta bc_db
	lda gc_sp
	sta bp1
	lda gc_sp+1
	sta bp1+1
	lda gc_dp
	sta bp2
	lda gc_dp+1
	sta bp2+1
	lda #4
	jsr bcopy
	lda gc_dat
	sta bp1
	lda gc_dat+1
	sta bp1+1
	lda gc_dp
	clc
	adc #4
	sta bp2
	lda gc_dp+1
	adc #0
	sta bp2+1
	lda gc_hdr
	beq @tell
	jsr bcopy
@tell:	; the owner's descriptor: the new place
	lda gc_hdr+1
	sta bp2
	lda gc_hdr+2
	sta bp2+1
	lda gc_hdr+3
	sta ram_bank
	ldy #1
	lda gc_dp
	clc
	adc #4
	sta (bp2),y
	iny
	lda gc_dp+1
	adc #0
	sta (bp2),y
	iny
	lda gc_dbank
	sta (bp2),y
	lda gc_dp
	clc
	adc gc_size
	sta gc_dp
	lda gc_dp+1
	adc #0
	sta gc_dp+1
@skip:	lda gc_hdr
	clc
	adc #4
	adc gc_sp
	sta gc_sp
	lda gc_sp+1
	adc #0
	sta gc_sp+1
	jmp @l
@done:	lda gc_dv
	sta hv
	lda gc_dp
	sta hp
	lda gc_dp+1
	sta hp+1
	ldx #0
@r:	lda gc_zp,x
	sta $D4,x
	inx
	cpx #44
	bne @r
	MAPP
	inc _gc_count
	bne @x
	inc _gc_count+1
@x:	rts
gc_sv:	.byte 0
gc_dv:	.byte 0
gc_sp:	.word 0
gc_dp:	.word 0
gc_sbank: .byte 0
gc_dbank: .byte 0
gc_hdr:	.res 4
gc_dat:	.word 0
gc_size: .byte 0
gc_zp:	.res 44
_gc_count: .word 0
.export _gc_count

;---------------------------------------------------------------
; strings made
;---------------------------------------------------------------
; acc = a temporary of sbufa's a bytes ("" for 0)
buf_to_temp:
	sta t0
	cmp #0
	bne @1
	jmp acc_empty
@1:	jsr salloc              ; p1, t1
	jsr temp_slot           ; x, a
	sta ac1
	lda t0
	sta ac0
	sta temps,x
	lda p1
	sta temps+1,x
	lda p1+1
	sta temps+2,x
	lda t1
	sta temps+3,x
	jsr owner_temp          ; the entry's owner: the slot
	lda #<sbufa
	sta bp1
	lda #>sbufa
	sta bp1+1
	lda p1
	sta bp2
	lda p1+1
	sta bp2+1
	lda t1
	sta bc_db
	sta bc_sb
	lda t0
	jsr bcopy
	lda #SK_TMP
	sta ac4
	lda #TY_S
	sta aty
	rts

; the entry at p1 (bank t1) is owned by temps + x
owner_temp:
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	txa
	clc
	adc #<temps
	sta p0
	lda #>temps
	adc #0
	sta p0+1
	stz xb
	phx
	jsr set_owner
	plx
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	rts

acc_empty:
	lda #TY_S
	sta aty
	stz ac0
	stz ac1
	stz ac2
	stz ac3
	lda #SK_LIT
	sta ac4
	rts

; acc's string -> sbufa, t0 its length; its temporary given back
str_to_buf:
	jsr need_str
	jsr sres
	lda t0
	beq @f
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	sta bc_db
	lda #<sbufa
	sta bp2
	lda #>sbufa
	sta bp2+1
	lda t0
	jsr bcopy
@f:	lda t0
	pha
	jsr sfree
	pla
	sta t0
	rts

; acc = acc's string from x (0-based) for a bytes (both in range)
substr:	sta ss_n
	stx ss_from
	cmp #0
	bne @1
	jsr sfree
	jmp acc_empty
@1:	lda ac4
	cmp #SK_LIT
	bne @copy
	lda ac1                  ; a literal: the same bytes, nearer
	clc
	adc ss_from
	sta ac1
	bcc @2
	inc ac2
@2:	lda ss_n
	sta ac0
	rts
@copy:	lda ss_n
	sta t0
	jsr salloc
	lda p1
	sta ss_p
	lda p1+1
	sta ss_p+1
	lda t1
	sta ss_b
	jsr sres                ; the source again (the heap may have moved)
	lda p1
	clc
	adc ss_from
	sta bp1
	lda p1+1
	adc #0
	sta bp1+1
	lda t1
	sta bc_sb
	lda ss_p
	sta bp2
	lda ss_p+1
	sta bp2+1
	lda ss_b
	sta bc_db
	lda ss_n
	jsr bcopy
	jsr sfree
	jsr temp_slot
	sta ac1
	lda ss_n
	sta ac0
	sta temps,x
	sta t0
	lda ss_p
	sta temps+1,x
	sta p1
	lda ss_p+1
	sta temps+2,x
	sta p1+1
	lda ss_b
	sta temps+3,x
	sta t1
	jsr owner_temp
	lda #SK_TMP
	sta ac4
	lda #TY_S
	sta aty
	rts
ss_n:	.byte 0
ss_from: .byte 0
ss_p:	.word 0
ss_b:	.byte 0

; acc = b + acc (strings)
sconcat:
	jsr bres                ; t0 = b's length
	lda t0
	sta sc_lb
	jsr sres
	lda t0
	sta sc_la
	clc
	adc sc_lb
	bcc @1
	ERR E_LONG
@1:	sta sc_n
	lda sc_la
	bne @2
	jsr sfree               ; acc "": b
	jmp b_to_a
@2:	lda sc_lb
	bne @3
	jsr bfree
	rts                     ; b "": acc
@3:	lda sc_n
	sta t0
	jsr salloc
	lda p1
	sta sc_p
	lda p1+1
	sta sc_p+1
	lda t1
	sta sc_b
	sta bc_db
	jsr bres
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	lda sc_p
	sta bp2
	lda sc_p+1
	sta bp2+1
	lda sc_lb
	jsr bcopy
	jsr sres
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	lda sc_b
	sta bc_db
	lda sc_p
	clc
	adc sc_lb
	sta bp2
	lda sc_p+1
	adc #0
	sta bp2+1
	lda sc_la
	jsr bcopy
	jsr bfree
	jsr sfree
	jsr temp_slot
	sta ac1
	lda sc_n
	sta ac0
	sta temps,x
	sta t0
	lda sc_p
	sta temps+1,x
	sta p1
	lda sc_p+1
	sta temps+2,x
	sta p1+1
	lda sc_b
	sta temps+3,x
	sta t1
	jsr owner_temp
	lda #SK_TMP
	sta ac4
	lda #TY_S
	sta aty
	rts
sc_la:	.byte 0
sc_lb:	.byte 0
sc_n:	.byte 0
sc_p:	.word 0
sc_b:	.byte 0

; sres for b
bres:	ldx #5
@s:	lda aty,x
	pha
	lda bty,x
	sta aty,x
	dex
	bpl @s
	jsr sres
	ldx #0
@r:	pla
	sta aty,x
	inx
	cpx #6
	bne @r
	rts

; a = b's string against acc's: -1, 0, 1 (bytes); both given back
scompare:
	jsr bres
	lda t0
	sta sc_lb
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	sta bc_db
	lda #<sbufb
	sta bp2
	lda #>sbufb
	sta bp2+1
	lda t0
	jsr bcopy
	jsr str_to_buf          ; acc -> sbufa, t0
	jsr bfree
	ldy #0
@l:	cpy sc_lb
	beq @bend
	cpy t0
	beq @gt                 ; a ended first: b is greater
	lda sbufb,y
	cmp sbufa,y
	bcc @lt
	bne @gt
	iny
	bra @l
@bend:	cpy t0
	beq @eq
@lt:	lda #$FF
	rts
@gt:	lda #1
	rts
@eq:	lda #0
	rts

; acc's string, if a variable's, copied into a temporary (or a literal's
; descriptor); x kept
to_temp:
	lda ac4
	cmp #SK_VAR
	beq @1
	rts
@1:	phx
	jsr sres
	lda t0
	beq @lit
	ldx t1
	lda bkind,x
	cmp #2
	bne @lit
	jsr salloc
	lda p1
	sta ss_p
	lda p1+1
	sta ss_p+1
	lda t1
	sta ss_b
	jsr sres
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	lda ss_p
	sta bp2
	lda ss_p+1
	sta bp2+1
	lda ss_b
	sta bc_db
	lda t0
	sta ss_n
	jsr bcopy
	jsr temp_slot
	sta ac1
	lda ss_n
	sta ac0
	sta temps,x
	lda ss_p
	sta temps+1,x
	sta p1
	lda ss_p+1
	sta temps+2,x
	sta p1+1
	lda ss_b
	sta temps+3,x
	sta t1
	jsr owner_temp
	lda #SK_TMP
	sta ac4
	plx
	rts
@lit:	lda t0
	sta ac0
	lda p1
	sta ac1
	lda p1+1
	sta ac2
	lda t1
	sta ac3
	lda #SK_LIT
	sta ac4
	plx
	rts

; before a FUNCTION runs: the strings on the value stack that are the
; caller's variables become copies (strings are values, as the reference has them)
materialize:
	ldx vbase
@l:	cpx vsp
	bcs @r
	lda vstk,x
	cmp #TY_S
	bne @n
	lda vstk+5,x
	cmp #SK_VAR
	bne @n
	lda aty
	pha
	lda ac0
	pha
	lda ac1
	pha
	lda ac2
	pha
	lda ac3
	pha
	lda ac4
	pha
	ldy #0
@c:	lda vstk,x
	sta aty,y
	inx
	iny
	cpy #6
	bne @c
	txa
	sec
	sbc #6
	tax
	jsr to_temp
	ldy #0
@w:	lda aty,y
	sta vstk,x
	inx
	iny
	cpy #6
	bne @w
	txa
	sec
	sbc #6
	tax
	pla
	sta ac4
	pla
	sta ac3
	pla
	sta ac2
	pla
	sta ac1
	pla
	sta ac0
	pla
	sta aty
@n:	txa
	clc
	adc #6
	tax
	bra @l
@r:	rts

;---------------------------------------------------------------
; assignment
;---------------------------------------------------------------
; acc into the cell p0 (bank xb) of type byte t0
store:	lda t0
	and #CT_TYPE
	cmp #TY_S
	beq @s
	cmp #TY_I
	beq @i
	jsr need_num
	jsr toflt
	lda xb
	beq @f
	sta ram_bank
@f:	ldy #4
@c:	lda ac0,y
	sta (p0),y
	dey
	bpl @c
	MAPP
	rts
@i:	jsr need_num
	jsr toint
	lda xb
	beq @j
	sta ram_bank
@j:	lda ac0
	sta (p0)
	ldy #1
	lda ac1
	sta (p0),y
	MAPP
	rts
@s:	jsr need_str
	jmp sassign

; acc's string into the cell p0 (bank xb)
sassign:
	lda ac4
	cmp #SK_VAR
	bne @old
	lda ac1                  ; a$ = a$: nothing
	cmp p0
	bne @old
	lda ac2
	cmp p0+1
	bne @old
	lda ac3
	cmp xb
	bne @old
	rts
@old:	; the cell's old string: dead
	lda p0
	sta p1
	lda p0+1
	sta p1+1
	lda xb
	jsr cell_dead
	lda ac4
	cmp #SK_TMP
	beq @tmp
	cmp #SK_VAR
	beq @var
@put:	; a literal's descriptor (or ""): as it is
	lda xb
	beq @p
	sta ram_bank
@p:	ldy #0
	lda ac0
	sta (p0),y
	iny
	lda ac1
	sta (p0),y
	iny
	lda ac2
	sta (p0),y
	iny
	lda ac3
	sta (p0),y
	MAPP
	rts
@tmp:	lda ac1
	asl a
	asl a
	tax
	lda temps,x
	sta ac0
	lda temps+1,x
	sta ac1
	sta p1
	lda temps+2,x
	sta ac2
	sta p1+1
	lda temps+3,x
	sta ac3
	sta t1
	stz temps,x
	stz temps+1,x
	stz temps+2,x
	stz temps+3,x
	jsr set_owner
	jsr temp_top
	bra @put
@var:	jsr sres
	lda t0
	beq @lit
	ldx t1
	lda bkind,x
	cmp #2
	beq @copy
@lit:	lda t0
	sta ac0
	lda p1
	sta ac1
	lda p1+1
	sta ac2
	lda t1
	sta ac3
	bra @put
@copy:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	jsr salloc
	lda p1
	sta ss_p
	lda p1+1
	sta ss_p+1
	lda t1
	sta ss_b
	jsr sres
	lda p1
	sta bp1
	lda p1+1
	sta bp1+1
	lda t1
	sta bc_sb
	lda ss_p
	sta bp2
	sta p1
	lda ss_p+1
	sta bp2+1
	sta p1+1
	lda ss_b
	sta bc_db
	sta t1
	lda t0
	sta ac0
	jsr bcopy
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	jsr set_owner
	lda ss_p
	sta ac1
	lda ss_p+1
	sta ac2
	lda ss_b
	sta ac3
	jmp @put

; the top temporaries let go when free
temp_top:
@top:	lda ttop
	cmp tbase
	beq @r
	bcc @r
	dec a
	asl a
	asl a
	tax
	lda temps+3,x
	bne @r
	dec ttop
	bra @top
@r:	rts

; CONST name = value [, ...]
st_const:
@l:	lda (ip)
	cmp #T_VAR
	beq @1
	ERR E_SYNTAX
@1:	jsr cellref
	jsr push_target
	lda #'='
	jsr expect
	jsr eval
	jsr pull_target
	jsr store
	jsr accept_comma
	bcs @l
	rts

; the int in the cell p0 (bank xb) -> n1
cell_get_int:
	lda xb
	beq @1
	sta ram_bank
@1:	lda (p0)
	sta n1
	ldy #1
	lda (p0),y
	sta n1+1
	MAPP
	rts

; the float in the cell p0 (bank xb) -> fpa
cell_to_fpa:
	lda xb
	beq @1
	sta ram_bank
@1:	ldy #4
@c:	lda (p0),y
	sta fpa,y
	dey
	bpl @c
	MAPP
	rts

;---------------------------------------------------------------
; arrays: the cell's bytes 0-2 the header's place in the array space
; (linear), 5 its dimensions (0: not made yet); the header: dimensions,
; the element's size, the largest index of each (words); the elements
; after it (2, 8, 4 bytes: integers, floats, strings' descriptors)
;---------------------------------------------------------------
; ip at "(": the element of the array whose cell is p0 (xb) -> p0, xb,
; t0 its type
element:
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	jsr expect_lp
	jsr eval
	jsr toint
	lda (ip)
	cmp #')'
	jeq @one
	lda #1
	sta el_n
	bra @m1
@s:	inc el_n
	lda el_n
	pha
	jsr eval
	jsr toint
	pla
	sta el_n
@m1:	jsr vpush
	jsr accept_comma
	bcs @s
	jsr expect_rp
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	jsr array_info          ; ar_nd, ar_lin, t0 (type)
@made0:	lda ar_nd
	bne @made
	lda el_n                ; used before DIM: 0 .. 10 each
	cmp #4
	bcc @auto
	ERR E_SUBS
@auto:	sta ar_nd
	ldx #0
@a:	lda #10
	sta ar_dims,x
	stz ar_dims+1,x
	inx
	inx
	cpx #6
	bne @a
	jsr dim_alloc
	jsr array_info
@made:	lda el_n
	cmp ar_nd
	beq @hd
	ERR E_SUBS
@hd:	jsr array_header        ; ar_es, ar_dims
	; the index: ((s1) * (d2 + 1) + s2) * (d3 + 1) + s3
	lda el_n
	asl a
	adc el_n
	asl a
	sta t2
	lda vsp
	sec
	sbc t2
	sta vsp
	tax                     ; the first subscript
	stz el_i
	stz el_i+1
	ldy #0
@ix:	; s < 0 or s > d: out of range
	lda vstk+2,x
	jmi @bad
	lda ar_dims,y
	cmp vstk+1,x
	lda ar_dims+1,y
	sbc vstk+2,x
	jcc @bad
	; i = i * (d + 1) + s
	stz n0
	stz n0+1
	lda el_i
	ora el_i+1
	beq @i0                 ; (0 so far: the first subscript)
	phx
	phy
	lda el_i
	sta n0
	lda el_i+1
	sta n0+1
	lda ar_dims,y
	clc
	adc #1
	sta n1
	lda ar_dims+1,y
	adc #0
	sta n1+1
	jsr umul16              ; n0 = n0 * n1
	ply
	plx
@i0:	lda n0
	clc
	adc vstk+1,x
	sta el_i
	lda n0+1
	adc vstk+2,x
	sta el_i+1
	txa
	clc
	adc #6
	tax
	iny
	iny
	dec el_n
	bne @ix
	; the place: lin + 8 + i * es
	lda el_i
	sta n0
	lda el_i+1
	sta n0+1
@pl:	stz t2
	ldx ar_es
@sh:	cpx #1
	beq @add
	asl n0
	rol n0+1
	rol t2
	txa
	lsr a
	tax
	bra @sh
@add:	lda ar_lin
	clc
	adc #8
	tax
	lda ar_lin+1
	adc #0
	tay
	lda ar_lin+2
	adc #0
	sta t3
	txa
	clc
	adc n0
	sta p0
	tya
	adc n0+1
	tay
	lda t3
	adc t2
	sta t3                  ; t3:y:p0 = linear
	jsr lin_to_ptr          ; p0, xb
	lda ar_ty
	sta t0
	rts
@bad:	ERR E_SUBS
@one:	; (V107) one subscript, in acc: not through the value stack
	INCIP
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	jsr array_info
	lda ar_nd
	cmp #1
	bne @gen1
	jsr array_header
	lda ac1                 ; s < 0 or s > d: out of range
	bmi @bad
	lda ar_dims
	cmp ac0
	lda ar_dims+1
	sbc ac1
	bcc @bad
	lda ac0
	sta n0
	lda ac1
	sta n0+1
	bra @pl
@gen1:	jsr vpush               ; (not made yet, or more dimensions)
	lda #1
	sta el_n
	jmp @made0
el_n:	.byte 0
el_i:	.word 0

; t3:y:p0 (a linear address in the array space) -> p0 (at $A000+), xb
lin_to_ptr:
	tya
	pha
	and #$1F
	ora #$A0
	sta p0+1
	pla
	lsr a                   ; >> 13: (y >> 5) | (t3 << 3)
	lsr a
	lsr a
	lsr a
	lsr a
	sta t2
	lda t3
	asl a
	asl a
	asl a
	ora t2
	tax
	lda abanks,x
	sta xb
	rts

; the array cell p0 (xb) -> ar_nd, ar_lin, ar_ty (and t0)
array_info:
	lda xb
	beq @1
	sta ram_bank
@1:	ldy #5
	lda (p0),y
	sta ar_nd
	ldy #0
	lda (p0),y
	sta ar_lin
	iny
	lda (p0),y
	sta ar_lin+1
	iny
	lda (p0),y
	sta ar_lin+2
	ldy #7
	lda (p0),y
	and #CT_TYPE
	sta ar_ty
	sta t0
	MAPP
	rts

; the header at ar_lin -> ar_es, ar_dims
array_header:
	lda hd_ok               ; (V107) the last header read: arrays never
	beq @rd                 ; move or go before the program's reset
	lda ar_lin
	cmp hd_lin
	bne @rd
	lda ar_lin+1
	cmp hd_lin+1
	bne @rd
	lda ar_lin+2
	cmp hd_lin+2
	beq @r
@rd:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda ar_lin
	sta p0
	ldy ar_lin+1
	lda ar_lin+2
	sta t3
	jsr lin_to_ptr
	lda xb
	sta ram_bank
	ldy #1
	lda (p0),y
	sta ar_es
	ldx #0
	iny
@d:	lda (p0),y
	sta ar_dims,x
	inx
	iny
	cpy #8
	bne @d
	MAPP
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	ldx #2
@k:	lda ar_lin,x
	sta hd_lin,x
	dex
	bpl @k
	stx hd_ok               ; ($FF)
@r:	rts
hd_ok:	.byte 0
hd_lin:	.res 3
ar_nd:	.byte 0
ar_lin:	.res 3
ar_ty:	.byte 0
ar_es:	.byte 0
ar_dims: .res 6
ar_tot:	.word 0
ar_bytes: .res 3

; n0 = n0 * n1 (the low 16 bits)
umul16:	stz t0
	stz t1
@l:	lsr n1+1
	ror n1
	bcc @n
	lda t0
	clc
	adc n0
	sta t0
	lda t1
	adc n0+1
	sta t1
@n:	asl n0
	rol n0+1
	lda n1
	ora n1+1
	bne @l
	lda t0
	sta n0
	lda t1
	sta n0+1
	rts

; a new array for the cell p0 (xb): ar_nd dimensions ar_dims, type ar_ty
dim_alloc:
	stz hd_ok               ; (ar_dims, ar_es: the new array's now)
	; a negative size: Illegal quantity; more than 65535 elements: Out of memory
	ldx #0
	ldy ar_nd
@n:	lda ar_dims+1,x
	bpl @n1
	ERR E_ILLQ
@n1:	inx
	inx
	dey
	bne @n
	lda #1
	sta ar_tot
	stz ar_tot+1
	ldx #0
	ldy ar_nd
@m:	phx
	phy
	lda ar_tot
	sta n0
	lda ar_tot+1
	sta n0+1
	lda ar_dims,x
	clc
	adc #1
	sta n1
	lda ar_dims+1,x
	adc #0
	sta n1+1
	; overflow past 16 bits: the high part of the product must be 0
	jsr umul32h             ; n0 = low, carry set if it did not fit
	bcs @mem
	lda n0
	sta ar_tot
	lda n0+1
	sta ar_tot+1
	ply
	plx
	inx
	inx
	dey
	bne @m
	; the bytes: 8 + total * es, a multiple of 8
	lda ar_ty
	tax
	lda esizes,x
	sta ar_es
	lda ar_tot
	sta ar_bytes
	lda ar_tot+1
	sta ar_bytes+1
	stz ar_bytes+2
	ldx ar_es
@sh:	cpx #1
	beq @sd
	asl ar_bytes
	rol ar_bytes+1
	rol ar_bytes+2
	txa
	lsr a
	tax
	bra @sh
@sd:	lda ar_bytes
	clc
	adc #8 + 7
	and #$F8
	sta ar_bytes
	lda ar_bytes+1
	adc #0
	sta ar_bytes+1
	lda ar_bytes+2
	adc #0
	sta ar_bytes+2
	bra @room
@mem:	ERR E_MEM
@room:	; banks for atop + bytes
	lda atop
	clc
	adc ar_bytes
	sta n0
	lda atop+1
	adc ar_bytes+1
	sta n0+1
	lda atop+2
	adc ar_bytes+2
	sta n1                  ; the end (linear)
	; banks needed: (end + 8191) >> 13
	lda n0
	clc
	adc #$FF
	lda n0+1
	adc #$1F
	sta t2
	lda n1
	adc #0
	sta t3
	lda t2
	lsr t3
	ror a
	lsr t3
	ror a
	lsr t3
	ror a
	lsr t3
	ror a
	lsr t3
	ror a
	sta t2                  ; banks needed
@grow:	lda nab
	cmp t2
	bcs @have
	cmp #24
	bcs @mem
	lda _nbanks
	cmp _limitb
	bcs @mem
	jsr new_bank
	beq @mem
	ldx nab
	sta abanks,x
	inc nab
	bra @grow
@have:	; zero it, bank by bank
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda atop
	sta ar_z
	lda atop+1
	sta ar_z+1
	lda atop+2
	sta ar_z+2
	lda ar_bytes
	sta ar_zn
	lda ar_bytes+1
	sta ar_zn+1
	lda ar_bytes+2
	sta ar_zn+2
@z:	lda ar_zn
	ora ar_zn+1
	ora ar_zn+2
	beq @zd
	lda ar_z
	sta p0
	ldy ar_z+1
	lda ar_z+2
	sta t3
	jsr lin_to_ptr
	lda xb
	sta ram_bank
	lda #0
	sta (p0)
	MAPP
	lda ar_z
	clc
	adc #1
	sta ar_z
	bcc @z1
	inc ar_z+1
	bne @z1
	inc ar_z+2
@z1:	lda ar_zn
	bne @z2
	lda ar_zn+1
	bne @z3
	dec ar_zn+2
@z3:	dec ar_zn+1
@z2:	dec ar_zn
	bra @z
@zd:	; the header
	lda atop
	sta p0
	ldy atop+1
	lda atop+2
	sta t3
	jsr lin_to_ptr
	lda xb
	sta ram_bank
	lda ar_nd
	sta (p0)
	ldy #1
	lda ar_es
	sta (p0),y
	ldx #0
	iny
@h:	lda ar_dims,x
	sta (p0),y
	inx
	iny
	cpy #8
	bne @h
	MAPP
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	; the cell
	lda xb
	beq @c
	sta ram_bank
@c:	ldy #0
	lda atop
	sta (p0),y
	iny
	lda atop+1
	sta (p0),y
	iny
	lda atop+2
	sta (p0),y
	ldy #5
	lda ar_nd
	sta (p0),y
	MAPP
	lda atop
	clc
	adc ar_bytes
	sta atop
	lda atop+1
	adc ar_bytes+1
	sta atop+1
	lda atop+2
	adc ar_bytes+2
	sta atop+2
	rts
ar_z:	.res 3
ar_zn:	.res 3
esizes:	.byte 8, 2, 4

; n0 * n1: n0 = the low 16 bits, carry set if the product is 65536 or more
umul32h:
	stz t0
	stz t1
	stz t2
	stz t3
	ldx #16
@l:	asl t0
	rol t1
	rol t2
	rol t3
	asl n1
	rol n1+1
	bcc @n
	lda t0
	clc
	adc n0
	sta t0
	lda t1
	adc n0+1
	sta t1
	lda t2
	adc #0
	sta t2
	lda t3
	adc #0
	sta t3
@n:	dex
	bne @l
	lda t0
	sta n0
	lda t1
	sta n0+1
	lda t2
	ora t3
	cmp #1
	rts

; DIM a(d [, d [, d]]) [, ...] / REDIM
st_dim:	stz dm_re
	bra dim_go
st_redim:
	lda #1
	sta dm_re
dim_go:
@l:	lda (ip)
	cmp #T_VAR
	beq @1
	ERR E_SYNTAX
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
	jsr expect_lp
	stz el_n
@s:	inc el_n
	lda el_n
	pha
	jsr eval
	jsr toint
	jsr vpush
	pla
	sta el_n
	jsr accept_comma
	bcs @s
	jsr expect_rp
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	lda el_n
	cmp #4
	bcc @3
	ERR E_SUBS
@3:	jsr array_info
	lda ar_nd
	beq @new
	lda dm_re
	bne @re
	ERR E_REDIM
@re:	; the old strings dead
	lda ar_ty
	cmp #TY_S
	bne @new
	jsr array_strings_dead
@new:	; the sizes from the value stack
	stz hd_ok
	lda el_n
	sta ar_nd
	asl a
	adc el_n
	asl a
	sta t2
	lda vsp
	sec
	sbc t2
	sta vsp
	tax
	ldy #0
@d:	lda vstk+1,x
	sta ar_dims,y
	lda vstk+2,x
	sta ar_dims+1,y
	txa
	clc
	adc #6
	tax
	iny
	iny
	cpy #6
	bcs @dd
	dec el_n
	bne @d
@dd:	jsr dim_alloc
	jsr accept_comma
	bcc @r
	jmp @l
@r:	rts
dm_re:	.byte 0

; every string of the array (cell p0, xb; ar_lin, ar_nd) dead
array_strings_dead:
	jsr array_header
	; elements: the product of (d + 1)
	lda #1
	sta ar_tot
	stz ar_tot+1
	ldx #0
	ldy ar_nd
@m:	phx
	phy
	lda ar_tot
	sta n0
	lda ar_tot+1
	sta n0+1
	lda ar_dims,x
	clc
	adc #1
	sta n1
	lda ar_dims+1,x
	adc #0
	sta n1+1
	jsr umul16
	lda n0
	sta ar_tot
	lda n0+1
	sta ar_tot+1
	ply
	plx
	inx
	inx
	dey
	bne @m
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda ar_lin
	clc
	adc #8
	sta ar_z
	lda ar_lin+1
	adc #0
	sta ar_z+1
	lda ar_lin+2
	adc #0
	sta ar_z+2
@e:	lda ar_tot
	ora ar_tot+1
	beq @d
	lda ar_z
	sta p0
	ldy ar_z+1
	lda ar_z+2
	sta t3
	jsr lin_to_ptr
	lda p0
	sta p1
	lda p0+1
	sta p1+1
	lda xb
	jsr cell_dead
	lda ar_z
	clc
	adc #4
	sta ar_z
	bcc @1
	inc ar_z+1
	bne @1
	inc ar_z+2
@1:	lda ar_tot
	bne @2
	dec ar_tot+1
@2:	dec ar_tot
	bra @e
@d:	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	rts

; UBOUND: the array cell p0 (xb), ac0 the dimension -> acc
array_ubound:
	lda ac0
	pha
	lda ac1
	pha
	jsr array_info
	pla
	bne @bad
	pla
	beq @bad1
	cmp ar_nd
	beq @ok
	bcs @bad1
@ok:	pha
	lda ar_nd
	beq @bad2
	jsr array_header
	pla
	dec a
	asl a
	tax
	lda ar_dims,x
	sta ac0
	lda ar_dims+1,x
	sta ac1
	lda #TY_I
	sta aty
	rts
@bad:	pla
@bad1:	ERR E_SUBS
@bad2:	ERR E_SUBS

; FRE(x): the free bytes of the data banks, a float
fre_bytes:
	lda _limitb
	sec
	sbc _nbanks
	bcs @1
	lda #0
@1:	asl a                   ; * 8192 / 256 = * 32: banks * 32 pages
	asl a
	asl a
	asl a
	asl a
	sta ac1
	stz ac0
	lda #TY_I
	sta aty
	lda ac1
	bpl @2
	lda #$7F
	sta ac1
	lda #$FF
	sta ac0
@2:	jmp toflt
