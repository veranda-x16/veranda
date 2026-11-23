; Paint's fill: the scanline flood fill's core (overlay 4, with tools.c;
; DECISIONS V147). The area's paper around a seed is set on the back
; screen, straight through VERA's data port, a byte at a time; tools.c's
; fill_at sets it up and then paints the pattern where the back screen
; has more ink than the foreground. (In C each short span of a patterned
; area cost thousands of cycles: a fill around patterns took 16 s.)
;
; fill_scan(): the seed in fx_k (its byte in the row, 0-73), fx_j (its
; bit, 0 the left pixel), fy (the area's row, 0-463). Uses:
;   _twork      the seeds' stack: 4 bytes each (byte, bit, row), 600
;   _band+256   each area row's back-screen address, low bytes (464)
;   _band+720   their high bytes (rows 324 on start in VRAM bank 1)
;   _packed     each row's first byte set (464; 255 none); +464 its last
;
; MIT licence (see LICENSE).

.importzp ptr1, ptr2, ptr3, tmp1, tmp2, tmp3, tmp4
.import _twork, _band, _packed
.export _fill_scan, _fx_k, _fx_j, _fy

VERA_ADDR_L = $9F20
VERA_ADDR_M = $9F21
VERA_ADDR_H = $9F22
VERA_DATA0  = $9F23
VERA_CTRL   = $9F25

ROWL    = _band + 256
ROWH    = _band + 720
LO      = _packed
HI      = _packed + 464
STKEND  = _twork + 4 * 600
LASTK   = 73                    ; the row's last byte (x 584-591)
AH      = 463                   ; the area's last row

sp      = ptr1                  ; the seeds' stack pointer
tp      = ptr2                  ; a table entry
rl      = tmp1                  ; the row's address (low, high, bank)
rh      = tmp2
rb      = tmp3
cb      = tmp4

.segment "OVL4BSS"

_fx_k:	.res 1
_fx_j:	.res 1
_fy:	.res 2
py:	.res 2                  ; the row being filled
ny:	.res 2                  ; a row next to it
k0:	.res 1
j0:	.res 1
b0:	.res 1
lk:	.res 1                  ; the span: from byte lk, bit lj ...
lj:	.res 1
rk:	.res 1                  ; ... to byte rk, bit rj
rj:	.res 1
k:	.res 1
pv:	.res 1                  ; the last pixel of the byte before (paper: 1)
st:	.res 1

.segment "OVL4RO"

bits:	.byte $80, $40, $20, $10, $08, $04, $02, $01
from:	.byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01     ; bits j .. 7
upto:	.byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF     ; bits 0 .. j

.segment "OVERLAY4"

;---------------------------------------------------------------
; the row in a/x (low, high): rl, rh, rb its back-screen address
;---------------------------------------------------------------
Row:	pha
	clc
	adc #<ROWL
	sta tp
	txa
	adc #>ROWL
	sta tp+1
	lda (tp)
	sta rl
	pla
	pha
	clc
	adc #<ROWH
	sta tp
	txa
	adc #>ROWH
	sta tp+1
	lda (tp)
	sta rh
	pla
	stz rb                  ; rows 324 on start in bank 1 (row 323
	cpx #2                  ; crosses it: At carries)
	bcs @1
	cpx #1
	bcc @r
	cmp #<324
	bcc @r
@1:	inc rb
@r:	rts

; port 0 at byte a of the row (stepping 1)
At:	stz VERA_CTRL
	clc
	adc rl
	sta VERA_ADDR_L
	lda rh
	adc #0
	sta VERA_ADDR_M
	lda rb
	adc #0
	ora #$10
	sta VERA_ADDR_H
	rts

; a = byte a of the row
Get:	jsr At
	lda VERA_DATA0
	rts

; the table entry for row py at LO (tp: x = 0) or HI (x = 1)
Ent:	lda py
	clc
	adc tlo,x
	sta tp
	lda py+1
	adc thi,x
	sta tp+1
	rts
tlo:	.byte <LO, <HI
thi:	.byte >LO, >HI

; a seed: byte k, bit in x, row ny (dropped when the stack is full)
Push:	lda sp+1
	cmp #>STKEND
	bcc @ok
	lda sp
	cmp #<STKEND
	bcs @r
@ok:	lda k
	sta (sp)
	ldy #1
	txa
	sta (sp),y
	iny
	lda ny
	sta (sp),y
	iny
	lda ny+1
	sta (sp),y
	lda sp
	clc
	adc #4
	sta sp
	bcc @r
	inc sp+1
@r:	rts

;---------------------------------------------------------------
; the runs of paper in row ny between the span's ends: a seed each
;---------------------------------------------------------------
Seeds:	lda ny
	ldx ny+1
	jsr Row
	lda lk
	sta k
	jsr At
	stz pv
@b:	lda VERA_DATA0
	eor #$FF                ; (paper: 1)
	ldx k
	cpx lk
	bne @1
	ldy lj
	and from,y
@1:	cpx rk
	bne @2
	ldy rj
	and upto,y
@2:	sta cb
	lsr                     ; a run starts where the pixel on the left
	ldy pv                  ; is not paper
	beq @3
	ora #$80
@3:	eor #$FF
	and cb
	sta st
	lda cb
	and #1
	sta pv
	lda st
	beq @n
	ldx #0                  ; each run's first pixel
@4:	asl
	bcc @5
	pha
	phx
	jsr Push
	plx                     ; (Push does not touch VERA)
	pla
@5:	inx
	cmp #0
	bne @4
@n:	lda k
	cmp rk
	beq @r
	inc k
	bra @b
@r:	rts

;---------------------------------------------------------------
; fill_scan
;---------------------------------------------------------------
_fill_scan:
	lda #<_twork
	sta sp
	lda #>_twork
	sta sp+1
	lda _fx_k
	sta k
	lda _fy
	sta ny
	lda _fy+1
	sta ny+1
	ldx _fx_j
	jsr Push
Pop:	lda sp+1                ; the stack empty: done
	cmp #>_twork
	bne @p
	lda sp
	cmp #<_twork
	bne @p
	rts
@p:	lda sp
	sec
	sbc #4
	sta sp
	bcs @p1
	dec sp+1
@p1:	lda (sp)
	sta k0
	ldy #1
	lda (sp),y
	sta j0
	iny
	lda (sp),y
	sta py
	iny
	lda (sp),y
	sta py+1
	lda py
	ldx py+1
	jsr Row
	lda k0
	jsr Get
	sta b0
	ldx j0
	and bits,x
	bne Pop                 ; set already
	; the left end: the nearest ink on the left, a byte at a time
	ldy j0
	ldx k0
	lda from,y
	eor #$FF
	and b0                  ; (z: none in this byte)
@l:	bne @lf
	cpx #0
	beq @l0
	dex
	stx k
	txa
	jsr Get
	ldx k
	cmp #0
	bra @l
@l0:	stz lk                  ; none: the row's start
	stz lj
	bra @right
@lf:	ldy #8                  ; its rightmost ink pixel (y) ...
@l1:	dey
	lsr
	bcc @l1
	iny                     ; ... the span from the next one
	cpy #8
	bne @l2
	inx
	ldy #0
@l2:	stx lk
	sty lj
@right:	ldy j0
	ldx k0
	lda upto,y
	eor #$FF
	and b0
@r:	bne @rf
	cpx #LASTK
	beq @r0
	inx
	stx k
	txa
	jsr Get
	ldx k
	cmp #0
	bra @r
@r0:	lda #LASTK              ; none: the row's end
	sta rk
	lda #7
	sta rj
	bra @set
@rf:	ldy #$FF                ; its leftmost ink pixel - 1
@r1:	iny
	asl
	bcc @r1
	dey
	bpl @r2
	dex
	ldy #7
@r2:	stx rk
	sty rj
	; the span set (on the back screen)
@set:	lda lk
	cmp rk
	bne @s2
	ldy lj                  ; in one byte
	lda from,y
	ldy rj
	and upto,y
	sta cb
	lda lk
	jsr Get
	ora cb
	pha
	lda lk
	jsr At
	pla
	sta VERA_DATA0
	bra @lohi
@s2:	lda lk                  ; the first byte, the ones between, the last
	jsr Get
	ldy lj
	ora from,y
	pha
	lda lk
	jsr At
	pla
	sta VERA_DATA0
	lda rk
	sec
	sbc lk
	tax
	dex
	beq @s3
	lda #$FF
@s4:	sta VERA_DATA0
	dex
	bne @s4
@s3:	lda rk
	jsr Get
	ldy rj
	ora upto,y
	pha
	lda rk
	jsr At
	pla
	sta VERA_DATA0
@lohi:	ldx #0                  ; the row's first and last bytes set
	jsr Ent
	lda lk
	cmp (tp)
	bcs @h
	sta (tp)
@h:	ldx #1
	jsr Ent
	lda (tp)
	cmp rk
	bcs @up
	lda rk
	sta (tp)
	; the rows above and below
@up:	lda py
	ora py+1
	beq @down
	lda py
	sec
	sbc #1
	sta ny
	lda py+1
	sbc #0
	sta ny+1
	jsr Seeds
@down:	lda py+1
	cmp #>AH
	bne @d1
	lda py
	cmp #<AH
@d1:	bcs @next
	lda py
	clc
	adc #1
	sta ny
	lda py+1
	adc #0
	sta ny+1
	jsr Seeds
@next:	jmp Pop
