; Veranda Gemini: the PNG decoder's core (overlay 5; DECISIONS V125):
; inflate and the rows, in assembly (png.c's C versions, compiled only for
; the host's test, are the same steps; cc65's code for them did not fit
; the overlay).
;
; inflate: RFC 1951 after Commander Calc's inflate.c (Marcin Spoczynski,
; MIT; its canonical Huffman decoder: a code's bits one at a time against
; the count of codes of each length), the window's 32 KB in VRAM at
; $09600 (the back screen: tile mode does not use it): a literal goes out
; through port 0, a match comes back through port 1 (a distance of 1
; read once: port 1's prefetch would miss the byte port 0 just wrote).
; The code lengths in VRAM at $12900 (320 bytes), read back in order.
; Up to 128 bytes a call into obuf.
;
; unfilter: obuf's bytes through the five filters, the row in VRAM at
; $11600 (4,864 bytes) rewritten in place (the row above read through
; port 1, this one written through port 0; the last bpp bytes of each in
; la, lc); a shown row's bytes become pixels (1-16 bits, every colour
; type, alpha over white), summed across (a box filter: pow_ out of pw),
; dithered (4 x 4 ordered) into outrow's 4 bpp; at the row's end outrow
; goes to the tiles (tile row oy & 7), once for each output row it is.
;
; MIT licence (see LICENSE).

.setcpu "65C02"
.macpack longbranch

.export _inflate, _unfilter, _core_init, _iy, _oy, _obuf
.import _inb, _perr, _ln, _ip, _il, _clen
.import _pw, _ph, _pow_, _poh, _pmode, _ptw, _rowb, _bpp, _pch, _psb, _pdepth, _pctype, _pr, _pg, _pb
.ifdef GEMINI_TEST
.import _png_test_row, _png_sums
.export _rowsum
.endif

VAL   = $9F20
VAM   = $9F21
VAH   = $9F22
VD0   = $9F23
VD1   = $9F24
VCTRL = $9F25

PE_DATA = 3
PM_GRAY = 0
PM_COLOUR = 1
PM_DIRECT = 2

ST_HEADER = 0
ST_STORED = 1
ST_CODES  = 2
ST_DONE   = 3

.segment "ZEROPAGE": zeropage        ; (cc65's zero page: $D4-$FF did not survive the card's reads)
zbits:	.res 1          ; the bits left of the byte, a 1 above them
zv:	.res 2          ; getbits, decode: the value
zm:	.res 2          ; getbits: the bit's mask
zt:	.res 2
zptr:	.res 2          ; a table: the counts (16 words), then the symbols
zq:	.res 2          ; a pointer

.segment "OVL5BSS"
zcode:	.res 2
zfirst:	.res 2
zindex:	.res 2
zn:	.res 1          ; obuf's bytes
zi:	.res 1          ; obuf's next
zx:	.res 1          ; the byte
za:	.res 1          ; the filters' a, b, c
zb:	.res 1
zc:	.res 1
zs:	.res 1          ; (emit, out_row)
zbyte:	.res 1          ; a byte of 1, 2 or 4-bit samples
.segment "OVL5BSS"
_obuf:	.res 128
state:	.res 1
last:	.res 1
wrapped: .res 1
left:	.res 2
copy_len: .res 2
copy_dist: .res 2
wpos:	.res 2
zsrc:	.res 2
zrun:	.res 1
lcount:	.res 32         ; (the literal/length table: counts, then 288 symbols)
lsym:	.res 576
dcount:	.res 32         ; (the distance table: counts, then 30 symbols)
dsym:	.res 60
offs:	.res 32
clcl:	.res 19
cn:	.res 2          ; build: the symbols
cs:	.res 2
cprev:	.res 1
crep:	.res 1
ncodes:	.res 2          ; dynamic: nlen + ndist
nw:	.res 2          ; dynamic: the lengths written
nlen:	.res 2
; the rows
rpos:	.res 2
ftype:	.res 1
la:	.res 8
lc:	.res 8
ki:	.res 1
_iy:	.res 2
_oy:	.res 2
accy:	.res 2
accx:	.res 2
ox:	.res 2
show:	.res 1
smp:	.res 2
li:	.res 1
hilo:	.res 1
px:	.res 4
cr:	.res 1
cg:	.res 1
cb:	.res 1
ci:	.res 1
sr:	.res 2
sg:	.res 2
sbl:	.res 2
nsum:	.res 1
outrow:	.res 312
.ifdef GEMINI_TEST
_rowsum: .res 2
.endif

.segment "OVL5RO"
lbase_l: .byte <3, <4, <5, <6, <7, <8, <9, <10, <11, <13, <15, <17, <19, <23, <27, <31, <35, <43
	.byte <51, <59, <67, <83, <99, <115, <131, <163, <195, <227, <258
lbase_h: .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
lextra:	.byte 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
dbase_l: .byte <1, <2, <3, <4, <5, <7, <9, <13, <17, <25, <33, <49, <65, <97, <129, <193, <257, <385
	.byte <513, <769, <1025, <1537, <2049, <3073, <4097, <6145, <8193, <12289, <16385, <24577
dbase_h: .byte >1, >2, >3, >4, >5, >7, >9, >13, >17, >25, >33, >49, >65, >97, >129, >193, >257, >385
	.byte >513, >769, >1025, >1537, >2049, >3073, >4097, >6145, >8193, >12289, >16385, >24577
dextra:	.byte 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
order:	.byte 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
; the ordered dither's thresholds (png.c's thr)
thr:	.byte 7, 135, 39, 167, 199, 71, 231, 103, 55, 183, 23, 151, 247, 119, 215, 87
gmul:	.byte 0, 255, 85, 0, 17       ; a 1, 2 or 4-bit grey's step

.segment "OVERLAY5"

;---------------------------------------------------------------- the start
_core_init:
	lda #1
	sta zbits
	stz state
	stz wpos
	stz wpos+1
	stz wrapped
	stz copy_len
	stz copy_len+1
	stz rpos
	stz rpos+1
	stz _iy
	stz _iy+1
	stz _oy
	stz _oy+1
	stz accy
	stz accy+1
	rts

;---------------------------------------------------------------- VERA's ports
; port 0 at the window's wpos
setw0:	stz VCTRL
	lda wpos
	sta VAL
	lda wpos+1
	clc
	adc #$96
	sta VAM
	lda #$10
	adc #0
	sta VAH
	rts

; port 1 at the window's zsrc
setw1:	lda #1
	sta VCTRL
	lda zsrc
	sta VAL
	lda zsrc+1
	clc
	adc #$96
	sta VAM
	lda #$10
	adc #0
	sta VAH
	rts

; port 0 at the code lengths' a/x (low, high)
setcl0:	stz VCTRL
	bra setcl
setcl1:	ldy #1
	sty VCTRL
setcl:	sta VAL
	txa
	clc
	adc #$29
	sta VAM
	lda #$11
	sta VAH
	rts

; ports 0 and 1 at the row's byte rpos - 1 (0 at a row's start)
setrow:	lda rpos
	ldx rpos+1
	bne @1
	cmp #0
	beq @2
@1:	sec
	sbc #1
	bcs @2
	dex
@2:	ldy #1
@p:	sty VCTRL
	sta VAL
	pha
	txa
	clc
	adc #$16
	sta VAM
	lda #$11
	sta VAH
	pla
	dey
	bpl @p
	rts

;---------------------------------------------------------------- the input
; the next byte of IDAT's data -> a (png.c's inb when the buffer or the
; chunk ends)
getbyte:
	lda _clen
	ora _clen+1
	ora _clen+2
	ora _clen+3
	beq @slow
	lda _ip+1
	bne @slow
	lda _ip
	cmp _il
	bne @fast
	lda _il+1
	beq @slow
@fast:	lda _clen               ; (clen - 1)
	bne @d0
	lda _clen+1
	bne @d1
	lda _clen+2
	bne @d2
	dec _clen+3
@d2:	dec _clen+2
@d1:	dec _clen+1
@d0:	dec _clen
	ldy _ip
	inc _ip
	bne @r
	inc _ip+1
@r:	lda _ln,y
	rts
@slow:	jmp _inb

; a bit -> carry
getbit:	lsr zbits
	bne @r
	jsr getbyte
	sec
	ror a
	sta zbits
@r:	rts

; x bits (0-13), the first the lowest -> zv
getbits:
	stz zv
	stz zv+1
	lda #1
	sta zm
	stz zm+1
	cpx #0
	beq @r
@b:	phx                     ; (png.c's inb, at a buffer's end, takes x)
	jsr getbit
	plx
	bcc @0
	lda zv
	ora zm
	sta zv
	lda zv+1
	ora zm+1
	sta zv+1
@0:	asl zm
	rol zm+1
	dex
	bne @b
@r:	rts

;---------------------------------------------------------------- Huffman
; a symbol of the table at zptr -> zv; carry set: not a code
decode:	stz zcode
	stz zcode+1
	stz zfirst
	stz zfirst+1
	stz zindex
	stz zindex+1
	ldy #2                  ; (count[1])
@l:	phy
	jsr getbit
	ply
	lda #0
	rol a
	ora zcode
	sta zcode
	sec                     ; zt = code - first
	sbc zfirst
	sta zt
	lda zcode+1
	sbc zfirst+1
	sta zt+1
	iny                     ; zt < count[len]?
	cmp (zptr),y
	php                     ; (dey would change Z)
	dey
	plp
	bcc @hit
	bne @miss
	lda zt
	cmp (zptr),y
	bcc @hit
@miss:	clc                     ; index += n
	lda zindex
	adc (zptr),y
	sta zindex
	iny
	lda zindex+1
	adc (zptr),y
	sta zindex+1
	dey
	clc                     ; first = (first + n) << 1
	lda zfirst
	adc (zptr),y
	sta zfirst
	iny
	lda zfirst+1
	adc (zptr),y
	sta zfirst+1
	asl zfirst
	rol zfirst+1
	asl zcode               ; code <<= 1
	rol zcode+1
	iny
	cpy #32
	bne @l
	lda #PE_DATA
	sta _perr
	sec
	rts
@hit:	clc                     ; symbol[index + zt]
	lda zindex
	adc zt
	sta zt
	lda zindex+1
	adc zt+1
	asl zt
	rol a
	sta zt+1
	clc
	lda zt
	adc zptr
	sta zq
	lda zt+1
	adc zptr+1
	sta zq+1
	ldy #32
	lda (zq),y
	sta zv
	iny
	lda (zq),y
	sta zv+1
	clc
	rts

; the table at zptr from the code lengths at a/x (in VRAM), cn of them
build:	jsr setcl1
	ldy #31                 ; the counts 0
	lda #0
@z:	sta (zptr),y
	dey
	bpl @z
	lda cn
	sta zt
	lda cn+1
	sta zt+1
@c:	lda VD1                 ; count[len]++
	asl a
	tay
	lda (zptr),y
	inc a
	sta (zptr),y
	bne @c1
	iny
	lda (zptr),y
	inc a
	sta (zptr),y
@c1:	jsr dec_zt
	bne @c
	lda #0                  ; count[0] = 0
	sta (zptr)
	ldy #1
	sta (zptr),y
	stz offs+2              ; offs[1] = 0; offs[len + 1] = offs[len] + count[len]
	stz offs+3
	ldx #2
@o:	txa
	tay
	clc
	lda offs,x
	adc (zptr),y
	sta offs+2,x
	iny
	lda offs+1,x
	adc (zptr),y
	sta offs+3,x
	inx
	inx
	cpx #30
	bne @o
	lda cs                  ; the symbols: symbol[offs[len]++] = s
	ldx cs+1
	jsr setcl1
	stz zt
	stz zt+1
@s:	lda VD1
	beq @n
	asl a
	tax
	lda offs,x              ; zq = zptr + 32 + 2 * offs[len]
	asl a
	sta zq
	lda offs+1,x
	rol a
	sta zq+1
	inc offs,x
	bne @s1
	inc offs+1,x
@s1:	clc
	lda zq
	adc zptr
	sta zq
	lda zq+1
	adc zptr+1
	sta zq+1
	ldy #32
	lda zt
	sta (zq),y
	iny
	lda zt+1
	sta (zq),y
@n:	inc zt
	bne @n1
	inc zt+1
@n1:	lda zt
	cmp cn
	bne @s
	lda zt+1
	cmp cn+1
	bne @s
	rts

dec_zt:	lda zt
	bne @1
	dec zt+1
@1:	dec zt
	lda zt
	ora zt+1
	rts

; (build's arguments: the table, the lengths' first, their count)
lit_table:
	lda #<lcount
	ldx #>lcount
	bra tab
dist_table:
	lda #<dcount
	ldx #>dcount
tab:	sta zptr
	stx zptr+1
	rts

; a/x into cn; the lengths from cs
build_at:
	sta cn
	stx cn+1
	lda cs
	ldx cs+1
	jmp build

; n copies of a into the code lengths (port 0)
fill:	sta VD0
	dex
	bne fill
	rts

fixed:	lda #0
	tax
	jsr setcl0
	lda #8
	ldx #144
	jsr fill
	lda #9
	ldx #112
	jsr fill
	lda #7
	ldx #24
	jsr fill
	lda #8
	ldx #8
	jsr fill
	stz cs
	stz cs+1
	jsr lit_table
	lda #<288
	ldx #>288
	jsr build_at
	lda #0
	tax
	jsr setcl0
	lda #5
	ldx #30
	jsr fill
	jsr dist_table
	lda #30
	ldx #0
	jmp build_at

dynamic:
	ldx #5                  ; nlen = 257 + 5 bits
	jsr getbits
	clc
	lda zv
	adc #<257
	sta nlen
	lda #>257
	adc #0
	sta nlen+1
	ldx #5                  ; + ndist (1 + 5 bits)
	jsr getbits
	sec                     ; (zv + 1 + nlen)
	lda zv
	adc nlen
	sta ncodes
	lda nlen+1
	adc #0
	sta ncodes+1
	lda nlen+1              ; nlen > 286 or ndist > 30: not deflate
	beq @ok1
	lda nlen
	cmp #<287
	jcs @bad
@ok1:	lda zv
	cmp #30
	jcs @bad
	ldx #4                  ; ncode = 4 + 4 bits
	jsr getbits
	lda zv
	clc
	adc #4
	sta zt
	ldx #18                 ; the code length code's lengths, in order
@z:	stz clcl,x
	dex
	bpl @z
	ldx #0
@cl:	phx
	ldx #3
	jsr getbits
	plx
	ldy order,x
	lda zv
	sta clcl,y
	inx
	cpx zt
	bne @cl
	lda #0
	tax
	jsr setcl0
	ldx #0
@cp:	lda clcl,x
	sta VD0
	inx
	cpx #19
	bne @cp
	jsr dist_table          ; (their table borrows the distances')
	stz cs
	stz cs+1
	lda #19
	ldx #0
	jsr build_at
	lda #0                  ; the lengths, coded
	tax
	jsr setcl0
	stz nw                  ; nw: lengths written (zt is decode's)
	stz nw+1
	stz cprev
@len:	lda nw
	cmp ncodes
	lda nw+1
	sbc ncodes+1
	bcs @built
	jsr decode
	jcs @r
	lda zv
	cmp #16
	bcs @rep
	sta cprev
	sta VD0
	ldx #1
	jsr adv
	bra @len
@rep:	bne @r17
	lda nw                  ; 16: the previous one, 3-6 times
	ora nw+1
	jeq @bad
	ldx #2
	jsr getbits
	lda #3
	bra @fill
@r17:	cmp #17
	bne @r18
	ldx #3                  ; 17: zeros, 3-10 times
	jsr getbits
	stz cprev
	lda #3
	bra @fill
@r18:	ldx #7                  ; 18: zeros, 11-138 times
	jsr getbits
	stz cprev
	lda #11
@fill:	clc
	adc zv
	sta crep
	tax
	jsr adv                 ; (past the end: not deflate)
	lda ncodes
	cmp nw
	lda ncodes+1
	sbc nw+1
	bcc @bad
	ldx crep
	lda cprev
	jsr fill
	bra @len
@built:	jsr lit_table
	stz cs
	stz cs+1
	lda nlen
	ldx nlen+1
	jsr build_at
	jsr dist_table
	lda nlen
	sta cs
	lda nlen+1
	sta cs+1
	sec
	lda ncodes
	sbc nlen
	ldx #0
	jsr build_at
	rts
@bad:	lda #PE_DATA
	sta _perr
@r:	rts

; zt += x
adv:	txa
	clc
	adc nw
	sta nw
	bcc @r
	inc nw+1
@r:	rts

;---------------------------------------------------------------- inflate
; a byte into the window (port 0) and obuf
put:	sta VD0
	ldy zn
	sta _obuf,y
	inc zn
	inc wpos
	bne @r
	inc wpos+1
	lda wpos+1
	cmp #$80
	bne @r
	stz wpos+1
	lda #1
	sta wrapped
	jmp setw0
@r:	rts

; up to 128 bytes into obuf -> a/x (0: the end, or perr)
_inflate:
	stz zn
	jsr setw0
@loop:	lda zn
	bpl @1
@out:	lda zn
	ldx #0
	rts
@1:	lda _perr
	bne @out
	lda copy_len
	ora copy_len+1
	beq @state
	jsr copy
	bra @loop
@state:	lda state
	cmp #ST_DONE
	beq @out
	cmp #ST_STORED
	jeq @stored
	cmp #ST_CODES
	jeq @codes
	jsr getbit              ; a block's header
	lda #0
	rol a
	sta last
	ldx #2
	jsr getbits
	lda zv
	bne @t1
	lda #1                  ; stored: to a byte's start
	sta zbits
	jsr getbyte
	sta left
	jsr getbyte
	sta left+1
	jsr getbyte
	eor #$FF
	cmp left
	bne @bad
	jsr getbyte
	eor #$FF
	cmp left+1
	bne @bad
	lda #ST_STORED
	bra @st
@t1:	cmp #1
	bne @t2
	jsr fixed
	bra @cd
@t2:	cmp #2
	bne @bad
	jsr dynamic
@cd:	lda #ST_CODES
@st:	sta state
	jsr setw0
	jmp @loop
@bad:	lda #PE_DATA
	sta _perr
	jmp @out
@stored:
	lda left
	ora left+1
	bne @sb
@end:	lda #ST_HEADER          ; the block's end
	ldx last
	beq @e
	lda #ST_DONE
@e:	sta state
	jmp @loop
@sb:	jsr getbyte
	jsr put
	lda left
	bne @sd
	dec left+1
@sd:	dec left
	jmp @loop
@codes:	jsr lit_table
	jsr decode
	jcs @loop
	lda zv+1
	bne @len
	lda zv
	jsr put
	jmp @loop
@len:	lda zv                  ; 256 the end, 257-285 a length
	beq @end
	sec
	sbc #1
	cmp #29
	bcs @bad
	tax
	lda lbase_l,x
	pha
	lda lbase_h,x
	pha
	lda lextra,x
	tax
	jsr getbits
	pla
	tax
	pla
	clc
	adc zv
	sta copy_len
	txa
	adc zv+1
	sta copy_len+1
	jsr dist_table
	jsr decode
	jcs @loop
	lda zv+1
	jne @bad
	lda zv
	cmp #30
	jcs @bad
	tax
	lda dbase_l,x
	pha
	lda dbase_h,x
	pha
	lda dextra,x
	tax
	jsr getbits
	pla
	tax
	pla
	clc
	adc zv
	sta copy_dist
	txa
	adc zv+1
	sta copy_dist+1
	lda wrapped             ; further back than written: not deflate
	bne @lp
	lda wpos
	cmp copy_dist
	lda wpos+1
	sbc copy_dist+1
	bcc @far
@lp:	jmp @loop
@far:	stz copy_len
	stz copy_len+1
	jmp @bad

; a match: as much of copy_len as obuf takes
copy:	sec                     ; zsrc = (wpos - dist) & $7FFF
	lda wpos
	sbc copy_dist
	sta zsrc
	lda wpos+1
	sbc copy_dist+1
	and #$7F
	sta zsrc+1
	jsr setw1
	lda copy_dist+1
	bne @g
	lda copy_dist
	dec a
	bne @g
	lda VD1                 ; a distance of 1: the byte again
	sta zrun
@r:	lda zn
	bmi @x
	lda zrun
	jsr put
	jsr @dec
	bne @r
@x:	rts
@g:	lda zn
	bmi @x
	lda VD1
	inc zsrc
	bne @g1
	inc zsrc+1
	ldx zsrc+1
	cpx #$80
	bne @g1
	stz zsrc+1
	pha
	jsr setw1
	pla
@g1:	jsr put
	jsr @dec
	bne @g
	rts
@dec:	lda copy_len
	bne @d
	dec copy_len+1
@d:	dec copy_len
	lda copy_len
	ora copy_len+1
	rts

;---------------------------------------------------------------- the rows
; obuf's a bytes: unfiltered, the shown rows' pixels
_unfilter:
	sta zn
	stz zi
	jsr setrow
@b:	ldy zi
	lda _obuf,y
	sta zx
	lda rpos
	ora rpos+1
	bne @data
	lda zx                  ; a row's filter type
	cmp #5
	bcc @f
	lda #PE_DATA
	sta _perr
	rts
@f:	sta ftype
	jsr row_start
	lda #1
	sta rpos
	jmp @next
@data:	ldx ki
	lda la,x
	sta za
	lda lc,x
	sta zc
	lda VD1
	sta zb
	lda ftype
	beq @put
	cmp #2
	beq @up
	bcc @sub
	cmp #3
	beq @avg
	jsr paeth
	bra @add
@sub:	lda za
	bra @add
@up:	lda zb
	bra @add
@avg:	clc
	lda za
	adc zb
	ror a
@add:	clc
	adc zx
	sta zx
@put:	lda zx
	sta VD0
	ldx ki
	sta la,x
	lda zb
	sta lc,x
	inx
	cpx _bpp
	bne @k
	ldx #0
@k:	stx ki
	lda show
.ifdef GEMINI_TEST
	ora _png_sums
.endif
	beq @nx
	lda zx
	jsr sample
@nx:	lda rpos                ; the row's last byte?
	cmp _rowb
	bne @inc
	lda rpos+1
	cmp _rowb+1
	bne @inc
	jsr row_end
	lda _iy
	cmp _ph
	bne @next
	lda _iy+1
	cmp _ph+1
	bne @next
	rts
@inc:	inc rpos
	bne @next
	inc rpos+1
@next:	inc zi
	dec zn
	beq @r
	jmp @b
@r:	rts

; Paeth's predictor of za, zb, zc -> a
paeth:	lda zb                  ; pa = |b - c|
	sec
	sbc zc
	sta zt                  ; (b - c, 9 bits signed in zt, zt+1)
	lda #0
	sbc #0
	sta zt+1
	lda za                  ; pb = |a - c|
	sec
	sbc zc
	sta zq
	lda #0
	sbc #0
	sta zq+1
	clc                     ; pc = |(b - c) + (a - c)| -> zm
	lda zt
	adc zq
	sta zm
	lda zt+1
	adc zq+1
	sta zm+1
	ldx #zt
	jsr abs16
	ldx #zq
	jsr abs16
	ldx #zm
	jsr abs16
	lda zq                  ; pa <= pb?
	cmp zt
	lda zq+1
	sbc zt+1
	bcc @nb                 ; pb < pa
	lda zm                  ; pa <= pc?
	cmp zt
	lda zm+1
	sbc zt+1
	bcc @nb
	lda za
	rts
@nb:	lda zm                  ; pb <= pc?
	cmp zq
	lda zm+1
	sbc zq+1
	bcc @c
	lda zb
	rts
@c:	lda zc
	rts

abs16:	lda 1,x
	bpl @r
	sec
	lda #0
	sbc 0,x
	sta 0,x
	lda #0
	sbc 1,x
	sta 1,x
@r:	rts

; a row's start: shown how many times; the sums and the samples cleared
row_start:
	stz show
	clc
	lda accy
	adc _poh
	sta accy
	lda accy+1
	adc _poh+1
	sta accy+1
@s:	lda accy
	cmp _ph
	lda accy+1
	sbc _ph+1
	bcc @c
	sta accy+1
	lda accy
	sec
	sbc _ph
	sta accy
	inc show
	bra @s
@c:	ldx #16                 ; la, lc, ki
@z:	stz la,x
	dex
	bpl @z
	stz smp
	stz smp+1
	stz accx
	stz accx+1
	stz ox
	stz ox+1
	stz nsum
	stz li
	stz hilo
	jsr zsums
.ifdef GEMINI_TEST
	stz _rowsum
	stz _rowsum+1
.endif
	rts

zsums:	stz sr
	stz sr+1
	stz sg
	stz sg+1
	stz sbl
	stz sbl+1
	rts

; a row's end: the tiles' columns past the picture white; out show times
row_end:
	lda show
	beq @n
@pad:	lda ox                  ; ox < ptw * 8?
	sta zt
	lda ox+1
	sta zt+1
	ldx #3
@sh:	lsr zt+1
	ror zt
	dex
	bne @sh
	lda zt
	cmp _ptw
	bcs @o
	lda #15
	sta ci
	lda #255
	sta cr
	sta cg
	sta cb
	stz nsum
	jsr emit
	bra @pad
@o:	jsr out_row
	dec show
	bne @o
@n:
.ifdef GEMINI_TEST
	jsr _png_test_row
.endif
	inc _iy
	bne @i
	inc _iy+1
@i:	stz rpos
	stz rpos+1
	jmp setrow

; outrow to the tiles' row oy & 7; oy + 1
out_row:
	lda _oy                 ; n = (oy >> 3) * ptw
	sta zt
	lda _oy+1
	sta zt+1
	ldx #3
@sh:	lsr zt+1
	ror zt
	dex
	bne @sh
	lda zt
	ldx _ptw
	jsr mul8                ; -> zv
	lda #<outrow
	sta zq
	lda #>outrow
	sta zq+1
	lda _ptw
	sta zs
@t:	lda zv+1                ; idx = n < 464 ? n + 16 : n + 80
	cmp #>464
	bcc @lo
	bne @hi
	lda zv
	cmp #<464
	bcc @lo
@hi:	lda #80
	bra @ix
@lo:	lda #16
@ix:	clc
	adc zv
	sta zt
	lda zv+1
	adc #0
	sta zt+1
	ldx #5                  ; * 32
@x32:	asl zt
	rol zt+1
	dex
	bne @x32
	stz VCTRL
	lda _oy                 ; + (oy & 7) * 4
	and #7
	asl a
	asl a
	ora zt
	sta VAL
	lda zt+1
	clc
	adc #$30
	sta VAM
	lda #$11
	sta VAH
	ldy #0
@w:	lda (zq),y
	sta VD0
	iny
	cpy #4
	bne @w
	clc
	lda zq
	adc #4
	sta zq
	bcc @nq
	inc zq+1
@nq:	inc zv
	bne @nv
	inc zv+1
@nv:	dec zs
	bne @t
	inc _oy
	bne @r
	inc _oy+1
@r:	rts

; a * x -> zv (8 x 8 bits)
mul8:	sta zm
	stz zm+1
	stz zv
	stz zv+1
	txa
@b:	lsr a
	bcc @n
	pha
	clc
	lda zv
	adc zm
	sta zv
	lda zv+1
	adc zm+1
	sta zv+1
	pla
@n:	asl zm
	rol zm+1
	cmp #0
	bne @b
	rts

; a shown row's byte (a): its samples
sample:	ldx _pdepth
	cpx #8
	bcc @low
	ldx _psb                ; 16 bits: the high byte only
	cpx #2
	bne @k
	ldx hilo
	inc hilo
	cpx #0
	beq @k
	stz hilo
	rts
@k:	ldx li
	sta px,x
	inx
	cpx _pch
	bcs @px
	stx li
	rts
@px:	stz li
	lda _pctype
	beq @gray
	cmp #3
	beq @idx
	cmp #4
	beq @ga
	cmp #2
	beq @rgb
	ldx #2                  ; RGBA: each colour over white
@ov:	phx
	lda px,x
	ldy px+3
	jsr over
	plx
	sta px,x
	dex
	bpl @ov
@rgb:	lda px
	sta cr
	lda px+1
	sta cg
	lda px+2
	sta cb
	jmp pixel
@ga:	lda px
	ldy px+1
	jsr over
	jmp gray
@gray:	lda px
	jmp gray
@idx:	lda px
	jmp index
@low:	sta zbyte                 ; 1, 2 or 4 bits a sample
	lda #8
@l:	pha
	lda smp                 ; (past the row's pixels: padding)
	cmp _pw
	lda smp+1
	sbc _pw+1
	bcs @lx
	inc smp
	bne @s1
	inc smp+1
@s1:	lda #0                  ; the top pdepth bits
	ldx _pdepth
@tb:	asl zbyte
	rol a
	dex
	bne @tb
	ldx _pctype
	bne @li
	ldx _pdepth             ; a grey: times its step
	ldy gmul,x
	tax
	tya
	jsr mul8
	lda zv
	jsr gray
	bra @ln
@li:	jsr index
@ln:	pla
	sec
	sbc _pdepth
	bne @l
	rts
@lx:	pla
	rts

; c (a) with alpha y over white -> a: (255 * 255 - y * (255 - c)) / 255
over:	eor #$FF
	tax
	tya
	jsr mul8
	sec
	lda #<65025
	sbc zv
	sta zt
	lda #>65025
	sbc zv+1
	sta zt+1
div255:	lda zt                  ; zt / 255 = (zt + 1 + (zt >> 8)) >> 8
	sec
	adc zt+1
	lda zt+1
	adc #0
	rts

gray:	sta cr
	sta cg
	sta cb
	bra pixel

index:	sta ci
	tax
	lda _pr,x
	sta cr
	lda _pg,x
	sta cg
	lda _pb,x
	sta cb

; a picture's pixel (cr, cg, cb; ci): summed across, emitted
pixel:
.ifdef GEMINI_TEST
	lda cg                  ; (the test: r + 2g + 3b)
	asl a
	tax
	lda #0
	rol a
	tay
	txa
	clc
	adc cr
	bcc @t1
	iny
@t1:	clc
	adc cb
	bcc @t2
	iny
@t2:	clc
	adc cb
	bcc @t3
	iny
@t3:	clc
	adc cb
	bcc @t4
	iny
@t4:	clc
	adc _rowsum
	sta _rowsum
	tya
	adc _rowsum+1
	sta _rowsum+1
	lda show
	bne @sh
	rts
@sh:
.endif
	lda _pmode
	cmp #PM_DIRECT
	beq @acc
	clc                     ; sr += cr, sg += cg, sbl += cb
	lda cr
	adc sr
	sta sr
	bcc @1
	inc sr+1
@1:	clc
	lda cg
	adc sg
	sta sg
	bcc @2
	inc sg+1
@2:	clc
	lda cb
	adc sbl
	sta sbl
	bcc @3
	inc sbl+1
@3:	inc nsum
@acc:	clc                     ; accx += pow_; while accx >= pw: emit
	lda accx
	adc _pow_
	sta accx
	lda accx+1
	adc _pow_+1
	sta accx+1
@w:	lda accx
	cmp _pw
	lda accx+1
	sbc _pw+1
	bcc @r
	sta accx+1
	lda accx
	sec
	sbc _pw
	sta accx
	jsr emit
	bra @w
@r:	rts

; an output pixel at ox: the sums' means (not DIRECT), dithered, into outrow
emit:	lda nsum
	beq @d
	lda _pmode
	cmp #PM_DIRECT
	beq @z
	ldx #0
	jsr mean
	sta cr
	lda _pmode
	cmp #PM_COLOUR
	bne @z
	ldx #2
	jsr mean
	sta cg
	ldx #4
	jsr mean
	sta cb
@z:	stz nsum
	jsr zsums
@d:	lda _oy                 ; the threshold
	and #3
	asl a
	asl a
	sta zt
	lda ox
	and #3
	ora zt
	tax
	lda thr,x
	sta zc
	lda _pmode
	cmp #PM_DIRECT
	bne @g
	lda ci
	bra @st
@g:	cmp #PM_GRAY
	bne @col
	lda cr                  ; (cr * 15 + t) / 255
	sta zt
	stz zt+1
	ldx #4
@x16:	asl zt
	rol zt+1
	dex
	bne @x16
	sec
	lda zt
	sbc cr
	sta zt
	lda zt+1
	sbc #0
	sta zt+1
	jsr addt
	jsr div255
	bra @st
@col:	lda cr                  ; red: (r + t) / 255 << 3
	jsr one
	asl a
	asl a
	asl a
	sta zb
	lda cb                  ; blue: (b + t) / 255
	jsr one
	ora zb
	sta zb
	lda cg                  ; green: (g * 3 + t) / 255 << 1
	sta zt
	stz zt+1
	asl a
	rol zt+1
	clc
	adc zt
	sta zt
	bcc @g3
	inc zt+1
@g3:	jsr addt
	jsr div255
	asl a
	ora zb
@st:	sta zs                  ; the nibble into outrow[ox >> 1]
	lda ox+1
	lsr a
	sta zq+1
	lda ox
	ror a
	clc
	adc #<outrow
	sta zq
	lda zq+1
	adc #>outrow
	sta zq+1
	lda ox
	lsr a
	lda (zq)
	bcs @odd
	and #$0F
	sta zt
	lda zs
	asl a
	asl a
	asl a
	asl a
	ora zt
	bra @w
@odd:	and #$F0
	ora zs
@w:	sta (zq)
	inc ox
	bne @r
	inc ox+1
@r:	rts

; (a + t) / 255 (a, t bytes)
one:	clc
	adc zc
	sta zt
	lda #0
	adc #0
	sta zt+1
	jmp div255

; zt += t
addt:	clc
	lda zt
	adc zc
	sta zt
	bcc @r
	inc zt+1
@r:	rts

; (sum + nsum / 2) / nsum for the sum at sr + x -> a
mean:	lda nsum
	lsr a
	clc
	adc sr,x
	sta zt
	lda sr+1,x
	adc #0
	sta zt+1
	lda #0                  ; 16 / 8 bits: zt / nsum -> zt (the remainder in a)
	ldy #16
@b:	asl zt
	rol zt+1
	rol a
	bcs @s
	cmp nsum
	bcc @n
@s:	sbc nsum
	inc zt
@n:	dey
	bne @b
	lda zt
	rts
