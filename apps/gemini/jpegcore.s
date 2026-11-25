; Veranda Gemini: the JPEG decoder's core (overlay 7; DECISIONS V192):
; the entropy-coded data, the blocks, the IDCT, the planes in VRAM, the
; colours and the rows to the tiles, in assembly (jpghdr.c, overlay 6,
; reads the header and builds the tables into jsx; tests/jpeg_ref.py is
; the same steps in Python). jstep: an MCU or a row at a time, until
; png_frames frames have gone (pic.c's main-loop slice).
;
; bits      MSB first from main RAM's ln (jpghdr.c's jfill refills it: 256
;           bytes, the last ones of a short read moved to its end), 0xFF
;           0x00 a 0xFF, a marker the data's end (zeros after it)
; Huffman   canonical: the code a bit at a time against the first code
;           past each length (lim; 8 bits for lengths 1-8, all-ones codes
;           being reserved), the symbol from vals; the routines patched
;           with their table's address (hdc, hac)
; a block   DC (its predictor), AC by run and size into coef (natural
;           order), dequantised by the AAN-scaled table (one product's
;           low 16 bits; a value of +-1 the table's entry itself)
; IDCT      libjpeg's AAN ("ifast") in 16-bit integers: columns, then
;           rows; a column or row with no AC its DC; a block with no AC
;           one value; the products floor(x * c / 256), the odd part's
;           z12 * c1 + z10 * c2 as one sum. With VERA FX (firmware 0.3.1
;           or later, jfx bit 7): the 16 x 16 multiplier, its 32-bit
;           sum written to VRAM ($12BFC) through port 0 and its middle
;           two bytes read back through port 1, the interrupt off while
;           the cache is on (as kernel/g/xfx.s); without: shifts and
;           adds, the same numbers
; planes    the MCU row's samples in VRAM's back screen from $09600: Y
;           (ystride a row), then Cb and Cr interleaved (cstride); a
;           picture shown at 1/8 or less keeps one sample a block (DC)
; rows      a shown row's Y and CbCr through ports 0 and 1, YCbCr to RGB
;           by tables (libjpeg's constants; tables beat the multiplier
;           here), then png.c's way: a box filter across (a pixel alone
;           or two without the sums), the 4 x 4 ordered dither into 16
;           colours (as compares with each threshold's levels), outrow
;           to the tiles (tile row oy & 7) once for each output row it is
;
; MIT licence (see LICENSE).

.setcpu "65C02"
.macpack longbranch

.export _jinit, _jstep, _jsx, _joy, _jfx, _jnofx, _jmark, _jidx
.import _jfill, _perr, _ln
.import _pw, _ph, _pow_, _poh, _ptw, _jw, _jh
.ifndef JPEG_BENCH
.import _ser_frames, _png_frames, _u_ret, _oy_done
.export _jpg_step_v
.endif
.ifdef JPEG_PROF
.export _prof
.endif

VAL   = $9F20
VAM   = $9F21
VAH   = $9F22
VD0   = $9F23
VD1   = $9F24
VCTRL = $9F25
FXCTL = $9F29                   ; DCSEL 2
FXMUL = $9F2C                   ; DCSEL 2
CACHE = $9F29                   ; DCSEL 6: the cache's four bytes (reading
                                ; $9F29 clears the sum, $9F2A adds the product)
SCR   = $2BFC                   ; the product's place in VRAM ($12BFC)

PE_DATA = 3
NBLK    = 6                     ; the blocks of an MCU at most

.ifdef JPEG_BENCH
.segment "ZEROPAGE": zeropage
.else
.segment "ZEROPAGE2": zeropage  ; ($D4-$FF: passing values only; fill keeps zc, zv over the card's reads)
.endif
zc:	.res 2
zv:	.res 2
zo:	.res 2          ; outrow's byte
x0:	.res 2          ; the IDCT's eight values
x1:	.res 2
x2:	.res 2
x3:	.res 2
x4:	.res 2
x5:	.res 2
x6:	.res 2
x7:	.res 2
t7:	.res 2
o10:	.res 2
o11:	.res 2
o12:	.res 2
zd:	.res 2
cr:	.res 1          ; a pixel; then the shown one
cg:	.res 1
cb:	.res 1
drl:	.res 1          ; the chroma's differences
drh:	.res 1
dgl:	.res 1
dgh:	.res 1
dbl:	.res 1
dbh:	.res 1
zt:	.res 1          ; the dither's threshold
znib:	.res 1          ; a pixel's colour, waiting for its pair
ZPN = 4                 ; (zc, zv: fill)

.segment "BSS"          ; (main RAM: jpghdr.c's too)
_jmark:	.res 1          ; a marker met (no more data)
_jidx:	.res 1          ; ln's next byte
_jfx:	.res 1          ; bit 7: VERA FX's multiplier used
_jnofx:	.res 1          ; (the bench: 1 FX not used)
.ifdef JPEG_BENCH
.segment "BSS"
.else
.segment "OVL7BSS"
.endif
; the picture's set-up (jpeg.h's struct jstate, written by jpghdr.c)
_jsx:
jnblk:	.res 1          ; the blocks of an MCU
jbt:	.res NBLK       ; a block's component (0-2)
jbq:	.res NBLK       ; its quantisation table (0-3)
jbdc:	.res NBLK*2     ; its DC table (the address)
jbac:	.res NBLK*2     ; its AC table
jbd0:	.res NBLK*2     ; its place in an MCU row's first MCU (from $09600)
jbstep:	.res NBLK       ; the step to the next MCU's
jbinc:	.res NBLK       ; VERA's increment ($10 1, $20 2)
jbstr:	.res NBLK*2     ; its plane's stride
jbs:	.res 1          ; samples a block across: 8, or 1 (DC alone)
jhmax:	.res 1          ; Y's samples a chroma sample across (1, 2)
jgray:	.res 1          ; one component
jvmask:	.res 1          ; Y's rows a chroma row - 1
jmcux:	.res 2          ; MCUs a row
jyrows:	.res 1          ; an MCU row's rows
jystr:	.res 2          ; the planes' strides
jcstr:	.res 2
jcbase:	.res 2          ; the CbCr plane (from $09600)
jdri:	.res 2          ; the restart interval (MCUs)
jhtab:	.res 2*67 + 2*307 ; the Huffman tables: DC 0, 1, AC 0, 1; each
                        ; lim[17], limh[17], off[17], vals
jqlo:	.res 256        ; the quantisation tables (zigzag order), AAN-scaled
jqhi:	.res 256
.assert * - _jsx = 1348, error, "jpeg.h's struct jstate"
fxon_:	.res 1          ; (the cache on now: fill turns it off and on again)
fxuse:	.res 1          ; bit 7: the multiplier for this picture (FX, and 8 x 8 blocks)
lastdc:	.res 2          ; the tables patched in
lastac:	.res 2
zbuf:	.res 1          ; the bits left of the byte, a 1 below them
jpred:	.res 6          ; the components' DC predictors (lo, hi)
jbd:	.res NBLK*3     ; a block's place now (lo, mid, bank), from $09600
jya:	.res 3          ; jrow: the Y row's address
jca:	.res 3          ; the CbCr row's
jshow:	.res 1          ; (jrow: the output rows this row is)
phase:	.res 1          ; jstep: 0 the MCUs, 1 the rows
mx:	.res 2
ry:	.res 1
rcount:	.res 2
iy:	.res 2
t0:	.res 2
frames:	.res 1
coefl:	.res 64         ; a block's coefficients (natural order)
coefh:	.res 64
wsl:	.res 64         ; after the columns
wsh:	.res 64
pix:	.res 64         ; its samples
nzl:	.res 64         ; the coefficients written (to clear)
nzn:	.res 1
colac:	.res 1          ; the columns with AC below row 0
colany:	.res 1          ; the columns with any coefficient
anyac:	.res 1
blk:	.res 1          ; the block
qn:	.res 1          ; its quantisation table
comp2:	.res 1          ; its component * 2
zk:	.res 1          ; the coefficient (zigzag)
cntb:	.res 1
ma:	.res 4          ; (the products without FX; the tables)
mb:	.res 3
mc:	.res 2
pcnt:	.res 2          ; jrow: the pixels left
hcnt:	.res 1
accx:	.res 2
sr:	.res 2
sg:	.res 2
sbl:	.res 2
nsum:	.res 1
oxm:	.res 1          ; the threshold: (oy & 3) * 4 + (ox & 3)
oxb:	.res 1          ; (oy & 3) * 4
zend:	.res 2          ; outrow's end
accy:	.res 2
_joy:	.res 2          ; the output rows done
rcrl:	.res 256        ; Cr's red, Cb's blue, Cb's and Cr's green (the low
bcbl:	.res 256        ; bytes: red's and blue's high byte is the index's sign)
gcb:	.res 256
gcr:	.res 256
outrow:	.res 312
zpkeep:	.res ZPN        ; (jfill)
.ifdef JPEG_PROF
_prof:	.res 16         ; cycles: Huffman, IDCT, the planes, the rows
pt0:	.res 4
.endif

.ifdef JPEG_BENCH
.segment "RODATA"
.else
.segment "OVL7RO"
.endif
zz:	.byte 0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14
	.byte 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60
	.byte 61, 54, 47, 55, 62, 63
bit8:	.byte 1, 2, 4, 8, 16, 32, 64, 128
thr:	.byte 7, 135, 39, 167, 199, 71, 231, 103, 55, 183, 23, 151, 247, 119, 215, 87
; (dith) the levels' first values for each threshold t: red and blue
; 255 - t, green's 1, 2 and 3 ceil((255 k - t) / 3) (tools: Python)
rth:	.byte 248, 120, 216, 88, 56, 184, 24, 152, 200, 72, 232, 104, 8, 136, 40, 168
g1t:	.byte 83, 40, 72, 30, 19, 62, 8, 51, 67, 24, 78, 35, 3, 46, 14, 56
g2t:	.byte 168, 125, 157, 115, 104, 147, 93, 136, 152, 109, 163, 120, 88, 131, 99, 141
g3t:	.byte 253, 210, 242, 200, 189, 232, 178, 221, 237, 194, 248, 205, 173, 216, 184, 226
; the colour tables' constants (16.16): 1.402, 1.772, -0.34414, -0.71414
ktab:	.dword 91881, 116130, $FFFFA7E6, $FFFF492E
tlo_l:	.byte <rcrl, <bcbl, <gcb, <gcr
tlo_h:	.byte >rcrl, >bcbl, >gcb, >gcr
mtab:	.word m1f, m2f, m3f, m4f, m1s, m2s, m3s, m4s

.ifdef JPEG_BENCH
.segment "CODE"
.else
.segment "OVERLAY7"
.endif

.ifdef JPEG_PROF
; the cycle counter ($9FB8: the emulator's; the bench only) into pt0
.macro PSTART
	jsr pstart
.endmacro
; the cycles since PSTART added to _prof + n
.macro PSTOP p_n
	ldx #p_n
	jsr pstop
.endmacro
pstart:	lda $9FB8
	sta pt0
	lda $9FB9
	sta pt0+1
	lda $9FBA
	sta pt0+2
	lda $9FBB
	sta pt0+3
	rts
pstop:	lda $9FB8
	sec
	sbc pt0
	sta pt0
	lda $9FB9
	sbc pt0+1
	sta pt0+1
	lda $9FBA
	sbc pt0+2
	sta pt0+2
	lda $9FBB
	sbc pt0+3
	sta pt0+3
	clc
	ldy #0
@a:	lda _prof,x
	adc pt0,y
	sta _prof,x
	inx
	iny
	tya
	eor #4
	bne @a
	rts
.else
.macro PSTART
.endmacro
.macro PSTOP p_n
.endmacro
.endif

;---------------------------------------------------------------- VERA FX
; jfxcheck: jfx bit 7 when DCSEL 63 reads "V" and 0.3.1 or later (tests/
; fxver.s's rule, the kernel's FxCheck)
jfxcheck:
	stz _jfx
	lda #63 << 1
	sta VCTRL
	lda $9F29
	cmp #$56                ; ('V')
	bne @no
	lda $9F2A               ; major
	bne @yes
	lda $9F2B               ; minor
	cmp #3
	bcc @no
	bne @yes
	lda $9F2C               ; patch
	beq @no
@yes:	lda #$80
	sta _jfx
@no:	stz VCTRL
	rts

; the multiplier on: interrupts off, cache writes, the sum cleared; port 0
; at SCR (no step), port 1 at SCR + 1 (step 1); DCSEL 6, ADDRSEL 1 left
fxon:	sei
	lda #2 << 1
	sta VCTRL
	lda #$40                ; cache write enable
	sta FXCTL
	lda #$90                ; clear the sum, the multiplier on
	sta FXMUL
	lda #6 << 1
	sta VCTRL
	lda #<SCR
	sta VAL
	lda #>SCR
	sta VAM
	lda #$01                ; (bank 1, no step)
	sta VAH
	lda #(6 << 1) | 1
	sta VCTRL
	lda #<(SCR + 1)
	sta VAL
	lda #>SCR
	sta VAM
	lda #$11
	sta VAH
	lda #1
	sta fxon_
	rts

fxoff:	lda #2 << 1
	sta VCTRL
	stz FXCTL
	stz FXMUL
	stz VCTRL
	stz fxon_
	cli
	rts

;---------------------------------------------------------------- the bits
; ln's next byte (jfill when it is used up) -> a; x, y kept
fill:	phx
	phy
	pha
	lda fxon_               ; (the card's read with the cache off, the interrupt on)
	pha
	beq @1
	jsr fxoff
@1:	ldx #ZPN - 1            ; (the card's reads may change $D4-$FF)
@k:	lda zc,x
	sta zpkeep,x
	dex
	bpl @k
	jsr _jfill
	ldx #ZPN - 1
@b:	lda zpkeep,x
	sta zc,x
	dex
	bpl @b
	pla
	beq @2
	jsr fxon
@2:	pla
	ply
	plx
	rts

; the data's next byte -> a (0xFF 0x00: 0xFF; a marker: 0, and after it); x kept
nextbyte:
	lda _jmark
	bne @zero
	ldy _jidx
	lda _ln,y
	iny
	sty _jidx
	bne @1
	jsr fill
@1:	cmp #$FF
	beq @ff
	rts
@ff:	ldy _jidx
	lda _ln,y
	iny
	sty _jidx
	bne @2
	jsr fill
@2:	cmp #0
	beq @stuffed
	sta _jmark
@zero:	lda #0
	rts
@stuffed:
	lda #$FF
	rts

; (zbuf empty) the next byte's first bit -> carry; a, x kept
refill:	pha
	phx
	jsr nextbyte
	sec
	rol a
	sta zbuf
	plx
	pla
	rts

; the next bit -> carry
.macro GETBIT
	asl zbuf
	bne :+
	jsr refill
:
.endmacro

; (at a restart interval's end) the bits left dropped, the marker found
; (RST0-7, else damaged), the predictors 0
jrestart:
	lda #$80
	sta zbuf
@f:	lda _jmark
	bne @m
	jsr nextbyte
	bra @f
@m:	and #$F8
	cmp #$D0
	beq @ok
	lda #PE_DATA
	sta _perr
@ok:	stz _jmark
	ldx #5
@z:	stz jpred,x
	dex
	bpl @z
	rts

;---------------------------------------------------------------- Huffman
; a symbol -> a (carry clear); carry set: no such code. The table's
; address patched in (patch)
.macro HDEC lim8, limh, liml, off, vals
.local l8, l16, n16, f16, found
	lda #0
	ldx #1
l8:	GETBIT
	rol a
lim8:	cmp $FFFF,x
	bcc found
	inx
	cpx #9
	bne l8
	sta zc
	stz zc+1
l16:	GETBIT
	rol zc
	rol zc+1
	lda zc+1
limh:	cmp $FFFF,x
	bcc f16
	bne n16
	lda zc
liml:	cmp $FFFF,x
	bcc f16
n16:	inx
	cpx #17
	bne l16
	sec
	rts
f16:	lda zc
found:	clc
off:	adc $FFFF,x
	tay
vals:	lda $FFFF,y
	clc
	rts
.endmacro

hdc:	HDEC dc8, dch, dcl, dco, dcv
hac:	HDEC ac8, ach, acl, aco, acv

; the table at a/x into hdc's operands (y: 0) or hac's (y: 1)
patch:	sta zc
	stx zc+1
	cpy #0
	bne @ac
	sta dc8 + 1
	stx dc8 + 2
	sta dcl + 1
	stx dcl + 2
	jsr @adv
	sta dch + 1
	stx dch + 2
	jsr @adv
	sta dco + 1
	stx dco + 2
	jsr @adv
	sta dcv + 1
	stx dcv + 2
	rts
@ac:	sta ac8 + 1
	stx ac8 + 2
	sta acl + 1
	stx acl + 2
	jsr @adv
	sta ach + 1
	stx ach + 2
	jsr @adv
	sta aco + 1
	stx aco + 2
	jsr @adv
	sta acv + 1
	stx acv + 2
	rts
@adv:	clc                     ; zc += 17 -> a/x
	lda zc
	adc #17
	sta zc
	lda zc+1
	adc #0
	sta zc+1
	tax
	lda zc
	rts

; a (1-15) bits, extended (a first bit 0: negative) -> zv
receive:
	tax
	GETBIT
	bcs @p
	lda #$FF
	sta zv
	sta zv+1
	bra @r
@p:	stz zv
	stz zv+1
@r:	rol zv
	rol zv+1
	dex
	beq @e
@b:	GETBIT
	rol zv
	rol zv+1
	dex
	bne @b
@e:	lda zv+1
	bpl @x
	inc zv                  ; (v - 2^s + 1)
	bne @x
	inc zv+1
@x:	rts

;---------------------------------------------------------------- products
; zv * the table's entry k (zk), its low 16 bits -> zd
dqidx:	lda qn                  ; x = qn * 64 + zk
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	ora zk
	tax
	rts

dequant:
	jsr dqidx
	lda zv+1                ; +-1: the entry itself
	bne @neg
	lda zv
	cmp #1
	bne @mul
	lda jqlo,x
	sta zd
	lda jqhi,x
	sta zd+1
	rts
@neg:	cmp #$FF
	bne @mul
	lda zv
	cmp #$FF
	bne @mul
	sec
	lda #0
	sbc jqlo,x
	sta zd
	lda #0
	sbc jqhi,x
	sta zd+1
	rts
@mul:
dqmul:	bit fxuse
	bpl dqsoft
	lda zv                  ; VERA FX: zv * q, bytes 0 and 1
	sta CACHE
	lda zv+1
	sta CACHE+1
	lda jqlo,x
	sta CACHE+2
	lda jqhi,x
	sta CACHE+3
	stz VD0
	lda #<SCR
	sta VAL
	lda VD1
	sta zd
	lda VD1
	sta zd+1
	lda #<(SCR + 1)
	sta VAL
	rts
dqsoft:	lda jqlo,x             ; q * |zv|: q shifted, |zv|'s bits; negated after
	sta mc
	lda jqhi,x
	sta mc+1
	lda zv
	sta ma
	lda zv+1
	sta ma+1
	sta mb                  ; (the sign)
	bpl @p
	sec
	lda #0
	sbc ma
	sta ma
	lda #0
	sbc ma+1
	sta ma+1
@p:	stz zd
	stz zd+1
	ldy #16
@b:	lsr ma+1
	ror ma
	bcc @n
	clc
	lda zd
	adc mc
	sta zd
	lda zd+1
	adc mc+1
	sta zd+1
@n:	lda ma
	ora ma+1
	beq @d
	asl mc
	rol mc+1
	dey
	bne @b
@d:	bit mb
	bpl @r
	sec
	lda #0
	sbc zd
	sta zd
	lda #0
	sbc zd+1
	sta zd+1
@r:	rts

; FX: one product a * c (a 16-bit value at zero page, c a constant) ->
; floor(a * c / 256) at r
.macro FMUL p_a, p_c, p_r
	lda p_a
	sta CACHE
	lda p_a+1
	sta CACHE+1
	lda #<(p_c)
	sta CACHE+2
	lda #>(p_c)
	sta CACHE+3
	stz VD0
	lda #<(SCR + 1)
	sta VAL
	lda VD1
	sta p_r
	lda VD1
	sta p_r+1
.endmacro
; FX: floor((a * c1 + b * c2) / 256) at r
.macro FMUL2 p_a, p_c1, p_b, p_c2, p_r
	lda p_a
	sta CACHE
	lda p_a+1
	sta CACHE+1
	lda #<(p_c1)
	sta CACHE+2
	lda #>(p_c1)
	sta CACHE+3
	lda CACHE+1             ; (the sum += the product)
	lda p_b
	sta CACHE
	lda p_b+1
	sta CACHE+1
	lda #<(p_c2)
	sta CACHE+2
	lda #>(p_c2)
	sta CACHE+3
	stz VD0
	lda #<(SCR + 1)
	sta VAL
	lda VD1
	sta p_r
	lda VD1
	sta p_r+1
	lda CACHE               ; (the sum cleared)
.endmacro

; without FX: ma (24 bits) += the 16-bit value at (x) * a/y (a constant, lo/hi)
smac:	sta mc
	sty mc+1
	lda 0,x
	sta mb
	lda 1,x
	sta mb+1
	and #$80                ; (sign-extended)
	beq @p
	lda #$FF
@p:	sta mb+2
	lda mc+1                ; a negative constant: the value negated
	bpl @b
	sec
	lda #0
	sbc mc
	sta mc
	lda #0
	sbc mc+1
	sta mc+1
	sec
	lda #0
	sbc mb
	sta mb
	lda #0
	sbc mb+1
	sta mb+1
	lda #0
	sbc mb+2
	sta mb+2
@b:	lsr mc+1
	ror mc
	bcc @n
	clc
	lda ma
	adc mb
	sta ma
	lda ma+1
	adc mb+1
	sta ma+1
	lda ma+2
	adc mb+2
	sta ma+2
@n:	lda mc
	ora mc+1
	beq @d
	asl mb
	rol mb+1
	rol mb+2
	bra @b
@d:	rts

.macro SMUL p_a, p_c, p_r
	stz ma
	stz ma+1
	stz ma+2
	ldx #p_a
	lda #<(p_c)
	ldy #>(p_c)
	jsr smac
	lda ma+1
	sta p_r
	lda ma+2
	sta p_r+1
.endmacro
.macro SMUL2 p_a, p_c1, p_b, p_c2, p_r
	stz ma
	stz ma+1
	stz ma+2
	ldx #p_a
	lda #<(p_c1)
	ldy #>(p_c1)
	jsr smac
	ldx #p_b
	lda #<(p_c2)
	ldy #>(p_c2)
	jsr smac
	lda ma+1
	sta p_r
	lda ma+2
	sta p_r+1
.endmacro

; the IDCT's four products (tests/jpeg_ref.py's mul, mul2), through the
; jumps m1-m4: VERA FX's (m1f ...) or, patched by jinit, the shifts' (m1s)
m1:	jmp m1f                 ; x2 = M(x2, 362)
m2:	jmp m2f                 ; o11 = M(zd, 362)
m3:	jmp m3f                 ; o10 = M2(z12, -196, z10, -473)
m4:	jmp m4f                 ; o12 = M2(z10, -196, z12, 473)
m1f:	FMUL x2, 362, x2
	rts
m2f:	FMUL zd, 362, o11
	rts
m3f:	FMUL2 x7, -196, x3, -473, o10
	rts
m4f:	FMUL2 x3, -196, x7, 473, o12
	rts
m1s:	SMUL x2, 362, x2
	rts
m2s:	SMUL zd, 362, o11
	rts
m3s:	SMUL2 x7, -196, x3, -473, o10
	rts
m4s:	SMUL2 x3, -196, x7, 473, o12
	rts

;---------------------------------------------------------------- the IDCT
; r = a + b, r = a - b (16 bits, zero page)
.macro ADD p_r, p_a, p_b
	clc
	lda p_a
	adc p_b
	sta p_r
	lda p_a+1
	adc p_b+1
	sta p_r+1
.endmacro
.macro SUB p_r, p_a, p_b
	sec
	lda p_a
	sbc p_b
	sta p_r
	lda p_a+1
	sbc p_b+1
	sta p_r+1
.endmacro
; r = a + b and s = a - b at once (either may be a or b)
.macro BFLY p_r, p_s, p_a, p_b
	clc
	lda p_a
	adc p_b
	tax
	lda p_a+1
	adc p_b+1
	tay
	sec
	lda p_a
	sbc p_b
	sta p_s
	lda p_a+1
	sbc p_b+1
	sta p_s+1
	stx p_r
	sty p_r+1
.endmacro
; one 8-point pass on x0-x7 (tests/jpeg_ref.py's idct1); colout, rowout its outputs
idct1:	BFLY x0, x4, x0, x4             ; t10 = x0 + x4, t11 = x0 - x4
	BFLY x6, x2, x2, x6             ; t13 = x2 + x6, x2 - x6
	jsr m1                          ; t12 = M(x2 - x6) - t13
	SUB x2, x2, x6
	BFLY x0, x6, x0, x6             ; e0 = t10 + t13 (x0), e3 = t10 - t13 (x6)
	BFLY x4, x2, x4, x2             ; e1 = t11 + t12 (x4), e2 = t11 - t12 (x2)
	BFLY x5, x3, x5, x3             ; the odd part: z13 (x5), z10 (x3)
	BFLY x1, x7, x1, x7             ; z11 (x1), z12 (x7)
	ADD t7, x1, x5
	SUB zd, x1, x5
	jsr m2
	jsr m3
	jsr m4
	SUB o12, o12, t7                ; t6
	SUB o11, o11, o12               ; t5
	ADD o10, o10, o11               ; t4
	rts                             ; (the outputs: e0-e3 in x0, x4, x2, x6; t4-t7 in o10, o11, o12, t7)

; the outputs of a column (zc) into ws
.macro OCOL p_n, p_a, p_b, p_op
	.if p_op
	clc
	lda p_a
	adc p_b
	sta wsl + 8 * p_n,x
	lda p_a+1
	adc p_b+1
	sta wsh + 8 * p_n,x
	.else
	sec
	lda p_a
	sbc p_b
	sta wsl + 8 * p_n,x
	lda p_a+1
	sbc p_b+1
	sta wsh + 8 * p_n,x
	.endif
.endmacro
colout:	ldx zc
	OCOL 0, x0, t7, 1
	OCOL 7, x0, t7, 0
	OCOL 1, x4, o12, 1
	OCOL 6, x4, o12, 0
	OCOL 2, x2, o11, 1
	OCOL 5, x2, o11, 0
	OCOL 4, x6, o10, 1
	OCOL 3, x6, o10, 0
	rts
; the outputs of a row (zc = 8 r) into pix
.macro OROW p_n, p_a, p_b, p_op
	.if p_op
	ADD zd, p_a, p_b
	.else
	SUB zd, p_a, p_b
	.endif
	jsr desc
	sta pix + p_n,x
.endmacro
rowout:	ldx zc
	OROW 0, x0, t7, 1
	OROW 7, x0, t7, 0
	OROW 1, x4, o12, 1
	OROW 6, x4, o12, 0
	OROW 2, x2, o11, 1
	OROW 5, x2, o11, 0
	OROW 4, x6, o10, 1
	OROW 3, x6, o10, 0
	rts

; zd -> a: ((zd + 16) >> 5) + 128, 0-255
desc:	clc
	lda zd
	adc #16
	sta zd
	lda zd+1
	adc #0
	tay
	clc
	adc #$10                ; (the high byte -16..15: in range)
	cmp #$20
	bcs @out
	asl a
	asl a
	asl a
	sta zd+1
	lda zd
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	ora zd+1
	rts
@out:	tya
	bmi @z
	lda #$FF
	rts
@z:	lda #0
	rts

; the block's samples into pix (8 x 8; jbs 1: pix[0] alone)
idct:	lda jbs
	cmp #8
	beq @full
	lda coefl               ; (1/8: the DC alone)
	sta zd
	lda coefh
	sta zd+1
	jsr desc
	sta pix
	rts
@dc:	lda coefl               ; (no AC: the DC alone)
	sta zd
	lda coefh
	sta zd+1
	jsr desc
	ldx #63
@f:	sta pix,x
	dex
	bpl @f
	rts
@full:	lda anyac
	beq @dc
	ldx #0                  ; the columns
@c:	stx zc
	lda colac
	and bit8,x
	bne @cf
	lda colany              ; no AC below row 0: its DC in every row
	and bit8,x
	beq @cz
	lda coefl,x
	ldy coefh,x
	bra @cs
@cz:	lda #0
	tay
@cs:	.repeat 8, r
	sta wsl + 8 * r,x
	.endrepeat
	tya
	.repeat 8, r
	sta wsh + 8 * r,x
	.endrepeat
	jmp @cn
@cf:	.repeat 8, r            ; the column into x0-x7
	lda coefl + 8 * r,x
	sta x0 + 2 * r
	lda coefh + 8 * r,x
	sta x0 + 2 * r + 1
	.endrepeat
	jsr idct1
	jsr colout
@cn:	ldx zc
	inx
	cpx #8
	jne @c
	lda colany              ; the rows: only column 0 has values?
	and #$FE
	bne @rows
	ldx #0
@r1:	stx zc
	lda wsl,x
	sta zd
	lda wsh,x
	sta zd+1
	jsr desc
	ldx zc
	.repeat 8, c
	sta pix + c,x
	.endrepeat
	txa
	clc
	adc #8
	tax
	cpx #64
	bne @r1
	rts
@rows:	ldx #0
@r:	stx zc
	.repeat 8, c            ; the row into x0-x7
	lda wsl + c,x
	sta x0 + 2 * c
	lda wsh + c,x
	sta x0 + 2 * c + 1
	.endrepeat
	jsr idct1
	jsr rowout
	lda zc
	clc
	adc #8
	tax
	cpx #64
	jne @r
	rts

;---------------------------------------------------------------- a block
; the block blk: its coefficients, pix; carry set: damaged
block:	ldx blk
	lda jbq,x
	sta qn
	lda jbt,x
	asl a
	sta comp2
	txa                     ; the tables (patched in when they change)
	asl a
	tax
	lda jbdc,x
	cmp lastdc
	bne @pd
	lda jbdc+1,x
	cmp lastdc+1
	beq @sd
@pd:	lda jbdc,x
	sta lastdc
	lda jbdc+1,x
	sta lastdc+1
	phx
	tax
	lda lastdc
	ldy #0
	jsr patch
	plx
@sd:	lda jbac,x
	cmp lastac
	bne @pa
	lda jbac+1,x
	cmp lastac+1
	beq @sa
@pa:	lda jbac,x
	sta lastac
	lda jbac+1,x
	sta lastac+1
	tax
	lda lastac
	ldy #1
	jsr patch
@sa:
	stz colac
	lda #1                  ; (column 0: its DC)
	sta colany
	stz anyac
	stz nzn
	jsr hdc                 ; DC: its size
	jcs @bad
	cmp #12
	jcs @bad
	stz zv
	stz zv+1
	cmp #0
	beq @d0
	jsr receive
@d0:	ldx comp2               ; the predictor + the difference
	clc
	lda jpred,x
	adc zv
	sta jpred,x
	sta zv
	lda jpred+1,x
	adc zv+1
	sta jpred+1,x
	sta zv+1
	stz zk
	jsr dqidx               ; (the product always)
	jsr dqmul
	lda zd
	sta coefl
	lda zd+1
	sta coefh
	lda #1                  ; AC
	sta zk
@ac:	jsr hac
	jcs @bad
	tax
	and #15
	bne @v
	cpx #$F0                ; ZRL: 16 zeros
	bne @end                ; (EOB)
	lda zk
	clc
	adc #16
	sta zk
	cmp #64
	bcc @ac
	beq @end
	bra @bad
@v:	pha                     ; the run, then the value
	txa
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc zk
	sta zk
	cmp #64
	bcs @badp
	pla
	jsr receive
	inc anyac
	lda jbs
	cmp #8
	bne @nx                 ; (1/8: the AC not needed)
	jsr dequant
	ldx zk                  ; coef[zz[k]]
	ldy zz,x
	lda zd
	sta coefl,y
	lda zd+1
	sta coefh,y
	ldx nzn
	tya
	sta nzl,x
	inc nzn
	and #7
	tax
	lda bit8,x
	tsb colany
	cpy #8
	bcc @nx
	tsb colac
@nx:	inc zk
	lda zk
	cmp #64
	bcc @ac
@end:	clc
	rts
@badp:	pla
@bad:	sec
	rts

; the coefficients written back to 0
clear:	ldy nzn
	beq @r
@l:	ldx nzl-1,y
	stz coefl,x
	stz coefh,x
	dey
	bne @l
@r:	stz coefl
	stz coefh
	rts

; pix to the block's place (jbd), then the place moved to the next MCU's
store:	ldx blk
	lda jbinc,x
	sta zt
	txa
	asl a
	tax
	lda jbstr,x
	sta zv
	lda jbstr+1,x
	sta zv+1
	lda blk                 ; (x = blk * 3)
	asl a
	adc blk
	tax
	lda jbd,x
	sta zc
	lda jbd+1,x
	sta zc+1
	lda jbd+2,x
	sta znib
	stz VCTRL
	ldy #0                  ; pix's next
@row:	clc                     ; $09600 + the place
	lda zc
	sta VAL
	lda zc+1
	adc #$96
	sta VAM
	lda znib
	adc #0
	ora zt
	sta VAH
	lda jbs
	cmp #8
	bne @one
	.repeat 8
	lda pix,y
	sta VD0
	iny
	.endrepeat
	clc                     ; the next row
	lda zc
	adc zv
	sta zc
	lda zc+1
	adc zv+1
	sta zc+1
	bcc @nc
	inc znib
@nc:	cpy #64
	bne @row
	bra @next
@one:	lda pix
	sta VD0
@next:	lda blk                 ; jbd += jbstep
	asl a
	adc blk
	tax
	ldy blk
	clc
	lda jbd,x
	adc jbstep,y
	sta jbd,x
	bcc @r
	inc jbd+1,x
	bne @r
	inc jbd+2,x
@r:	rts

; jmcu: the MCU's blocks to the planes (perr when damaged)
jmcu:	stz blk
@b:	PSTART
	bit fxuse
	bpl @1
	jsr fxon
@1:	jsr block
	bcc @2
	bit fxuse
	bpl @e
	jsr fxoff
@e:	lda #PE_DATA
	sta _perr
	rts
@2:	PSTOP 0
	PSTART
	jsr idct
	bit fxuse
	bpl @3
	jsr fxoff
@3:	jsr clear
	PSTOP 4
	PSTART
	jsr store
	PSTOP 8
	inc blk
	lda blk
	cmp jnblk
	bne @b
	rts

;---------------------------------------------------------------- the rows
; the shown pixel cr, cg, cb into outrow (png.c's dither: 4 x 4 ordered,
; its thresholds by oxm = (oy & 3) * 4 + (ox & 3), as compares)
dith:	ldx oxm
	lda jgray
	bne @grey
	lda cr                  ; red: r + t >= 255
	cmp rth,x
	rol znib
	lda cg                  ; green: (3 g + t) / 255, 0-3
	cmp g2t,x
	bcs @hi
	rol znib
	cmp g1t,x
	bra @lo
@hi:	rol znib
	cmp g3t,x
@lo:	rol znib
	lda cb                  ; blue
	cmp rth,x
	rol znib
	lda znib
	and #15
	bra @st
@grey:	lda cr                  ; grey: (15 c + t) / 255
	sta zd
	stz zd+1
	asl zd
	rol zd+1
	asl zd
	rol zd+1
	asl zd
	rol zd+1
	asl zd
	rol zd+1
	sec
	lda zd
	sbc cr
	sta zd
	lda zd+1
	sbc #0
	sta zd+1
	lda thr,x
	sta zt
	jsr div255
@st:	tay                     ; the colour (0-15) into outrow's nibble
	txa
	inc a
	and #3
	ora oxb
	sta oxm
	txa
	lsr a
	tya
	bcs @second
	asl a
	asl a
	asl a
	asl a
	sta (zo)
	rts
@second:
	ora (zo)
	sta (zo)
	inc zo
	bne @r
	inc zo+1
@r:	rts

; (zd + t + 1 + ((zd + t) >> 8)) >> 8 -> a, the sum's colour level
div255:	clc
	lda zd
	adc zt
	sta zd
	bcc @1
	inc zd+1
@1:	sec
	lda zd
	adc zd+1
	lda zd+1
	adc #0
	rts

; the input pixel into the sums (the first as it is: the high bytes are 0)
addsum:	lda nsum
	bne @add
	inc nsum
	lda cr
	sta sr
	lda cg
	sta sg
	lda cb
	sta sbl
	rts
@add:	clc
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
	rts

; (PIXEL, accx >= pw: carry set, a = accx's high byte - pw's) the pixel
; with the ones summed before it shown, then again while accx >= pw
emitpx:	sta accx+1
	lda accx
	sbc _pw
	sta accx
	lda nsum
	beq @d                  ; (alone: as it is)
	cmp #1
	bne @3
	sec                     ; (one before it: (a + b + 1) / 2)
	lda cr
	adc sr
	ror a
	sta cr
	sec
	lda cg
	adc sg
	ror a
	sta cg
	sec
	lda cb
	adc sbl
	ror a
	sta cb
	stz nsum
	bra @d
@3:	jsr addsum
	ldx #0
	jsr mean
	sta cr
	ldx #2
	jsr mean
	sta cg
	ldx #4
	jsr mean
	sta cb
	stz nsum
	stz sr
	stz sr+1
	stz sg
	stz sg+1
	stz sbl
	stz sbl+1
@d:	jsr dith
@l:	lda accx
	cmp _pw
	lda accx+1
	sbc _pw+1
	bcc @r
	sta accx+1
	lda accx
	sbc _pw
	sta accx
	jsr dith
	bra @l
@r:	rts

; (sum + nsum / 2) / nsum for the sum at sr + x -> a (nsum >= 2)
mean:	lda nsum
	cmp #2
	bne @g
	lda sr,x                ; (2: (sum + 1) / 2)
	clc
	adc #1
	sta zd
	lda sr+1,x
	adc #0
	lsr a
	lda zd
	ror a
	rts
@g:	lsr a
	clc
	adc sr,x
	sta zd
	lda sr+1,x
	adc #0
	sta zd+1
	lda #0
	ldy #16
@b:	asl zd
	rol zd+1
	rol a
	bcs @s
	cmp nsum
	bcc @n
@s:	sbc nsum
	inc zd
@n:	dey
	bne @b
	lda zd
	rts

; the input pixel cr, cg, cb (png.c's pixel): accx += pow_; shown when
; accx >= pw (with the ones summed before it), else summed
.macro PIXEL
	clc
	lda accx
	adc _pow_
	sta accx
	lda accx+1
	adc _pow_+1
	sta accx+1
	lda accx
	cmp _pw
	lda accx+1
	sbc _pw+1
	bcc :+
	jsr emitpx
	bra :++
:	jsr addsum
:
.endmacro

; y + the difference (drl/drh at x) -> a, 0-255
.macro CLAMP lo, hi
	clc
	adc lo
	tay
	lda hi
	adc #0
	beq :++
	bmi :+
	ldy #$FF
	bra :++
:	ldy #0
:	tya
.endmacro

; jrow: a row of the MCU row (jya, jca) out: shown jshow times (accy);
; the tiles' row; iy + 1
jrow:	PSTART
	stz jshow
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
	sbc _ph
	sta accy
	inc jshow
	bra @s
@c:	lda jshow
	jeq @none
	lda _joy                 ; the thresholds: thr's row oy & 3
	and #3
	asl a
	asl a
	sta oxb
	sta oxm
	stz accx
	stz accx+1
	stz nsum
	stz sr
	stz sr+1
	stz sg
	stz sg+1
	stz sbl
	stz sbl+1
	lda #<outrow
	sta zo
	lda #>outrow
	sta zo+1
	lda _ptw                ; the row's end: outrow + 4 ptw
	asl a
	asl a
	sta zend
	lda #0
	rol a
	sta zend+1
	clc
	lda zend
	adc #<outrow
	sta zend
	lda zend+1
	adc #>outrow
	sta zend+1
	stz VCTRL               ; port 0: the Y row
	lda jya
	sta VAL
	lda jya+1
	sta VAM
	lda jya+2
	ora #$10
	sta VAH
	lda #1
	sta VCTRL               ; port 1: CbCr
	lda jca
	sta VAL
	lda jca+1
	sta VAM
	lda jca+2
	ora #$10
	sta VAH
	stz VCTRL
	lda _pw
	sta pcnt
	lda _pw+1
	sta pcnt+1
	lda jgray
	jne @gray
	lda #1
	sta hcnt
@px:	dec hcnt                ; a chroma sample every jhmax pixels
	bne @same
	lda jhmax
	sta hcnt
	ldy VD1                 ; Cb
	ldx VD1                 ; Cr
	lda rcrl,x
	sta drl
	cpx #$80                ; (the high byte: $FF below 128)
	lda #$FF
	adc #0
	sta drh
	lda bcbl,y
	sta dbl
	cpy #$80
	lda #$FF
	adc #0
	sta dbh
	stz dgh                 ; green: gcb + gcr (8 bits each, signed)
	lda gcb,y
	bpl @g1
	dec dgh
@g1:	clc
	adc gcr,x
	sta dgl
	lda gcr,x
	bpl @g2
	dec dgh
@g2:	lda dgh
	adc #0
	sta dgh
@same:	lda VD0                 ; Y
	tax
	CLAMP drl, drh
	sta cr
	txa
	CLAMP dgl, dgh
	sta cg
	txa
	CLAMP dbl, dbh
	sta cb
	PIXEL
	lda pcnt
	bne @p1
	dec pcnt+1
@p1:	dec pcnt
	lda pcnt
	ora pcnt+1
	jne @px
	jmp @pad
@gray:	lda VD0
	sta cr
	sta cg
	sta cb
	PIXEL
	lda pcnt
	bne @p2
	dec pcnt+1
@p2:	dec pcnt
	lda pcnt
	ora pcnt+1
	bne @gray
@pad:	lda #$FF                ; the tiles' columns past the picture: white
	sta cr
	sta cg
	sta cb
@pw:	lda zo
	cmp zend
	lda zo+1
	sbc zend+1
	bcs @out
	jsr dith
	bra @pw
@out:	jsr out_row
	dec jshow
	bne @out
@none:
	PSTOP 12
	rts

; outrow to the tiles' row oy & 7; oy + 1
out_row:
	lda _joy                 ; n = (oy >> 3) * ptw
	sta zd
	lda _joy+1
	sta zd+1
	lsr zd+1
	ror zd
	lsr zd+1
	ror zd
	lsr zd+1
	ror zd
	stz zv                  ; zv = zd * ptw
	stz zv+1
	ldx _ptw
@m:	clc
	lda zv
	adc zd
	sta zv
	lda zv+1
	adc #0
	sta zv+1
	dex
	bne @m
	lda #<outrow
	sta zo
	lda #>outrow
	sta zo+1
	lda _ptw
	sta cntb
	stz VCTRL
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
	sta zc
	lda zv+1
	adc #0
	sta zc+1
	asl zc                  ; * 32
	rol zc+1
	asl zc
	rol zc+1
	asl zc
	rol zc+1
	asl zc
	rol zc+1
	asl zc
	rol zc+1
	lda _joy                 ; + (oy & 7) * 4
	and #7
	asl a
	asl a
	ora zc
	sta VAL
	lda zc+1
	clc
	adc #$30
	sta VAM
	lda #$11
	sta VAH
	ldy #0
	lda (zo),y
	sta VD0
	iny
	lda (zo),y
	sta VD0
	iny
	lda (zo),y
	sta VD0
	iny
	lda (zo),y
	sta VD0
	clc
	lda zo
	adc #4
	sta zo
	bcc @nq
	inc zo+1
@nq:	inc zv
	bne @nv
	inc zv+1
@nv:	dec cntb
	bne @t
	inc _joy
	bne @r
	inc _joy+1
@r:	rts

;---------------------------------------------------------------- the start
; jinit: the colour tables (floor((k * (i - 128) + 32768) / 65536)), the
; bits, the predictors, accy, the profile
_jinit:	jsr jfxcheck
	lda _jnofx
	beq @fx
	stz _jfx
@fx:	ldy #0                  ; the four tables
@t:	sty cntb
	tya
	asl a
	asl a
	tax
	lda ktab,x              ; k (x0, x1)
	sta x0
	lda ktab+1,x
	sta x0+1
	lda ktab+2,x
	sta x1
	lda ktab+3,x
	sta x1+1
	stz ma                  ; ma..ma+3 = 32768 - 128 k
	lda #$80
	sta ma+1
	stz ma+2
	stz ma+3
	ldx #128
@s:	sec
	lda ma
	sbc x0
	sta ma
	lda ma+1
	sbc x0+1
	sta ma+1
	lda ma+2
	sbc x1
	sta ma+2
	lda ma+3
	sbc x1+1
	sta ma+3
	dex
	bne @s
	ldy cntb                ; the table's addresses (lo, hi)
	lda tlo_l,y
	sta zc
	lda tlo_h,y
	sta zc+1
	ldy #0
@i:	lda ma+2                ; the entry: bits 16-23, 24-31
	sta (zc),y
	clc                     ; + k
	lda ma
	adc x0
	sta ma
	lda ma+1
	adc x0+1
	sta ma+1
	lda ma+2
	adc x1
	sta ma+2
	lda ma+3
	adc x1+1
	sta ma+3
	iny
	bne @i
	ldy cntb
	iny
	cpy #4
	jne @t
	stz lastdc
	stz lastdc+1
	stz lastac
	stz lastac+1
	lda jbs                 ; FX for 8 x 8 blocks
	cmp #8
	lda #0
	bcc @f8
	lda _jfx
@f8:	sta fxuse
	ldx #0                  ; the IDCT's products: FX's or the shifts'
	bit _jfx
	bmi @m
	ldx #8
@m:	ldy #0
@mj:	lda mtab,x
	sta m1+1,y
	lda mtab+1,x
	sta m1+2,y
	inx
	inx
	iny
	iny
	iny
	cpy #12
	bne @mj
	lda #$80
	sta zbuf
	stz _jmark
	ldx #5
@z:	stz jpred,x
	dex
	bpl @z
	stz accy
	stz accy+1
	stz _joy
	stz _joy+1
	stz phase
	stz mx
	stz mx+1
	stz ry
	stz rcount
	stz rcount+1
	stz iy
	stz iy+1
	jsr places
	ldx #63
@c:	stz coefl,x
	stz coefh,x
	dex
	bpl @c
.ifdef JPEG_PROF
	ldx #15
@pz:	stz _prof,x
	dex
	bpl @pz
.endif
	rts

; the blocks' places at an MCU row's start; the rows' addresses at its first
places:	ldx #0
	ldy #0
@b:	lda jbd0,x
	sta jbd,y
	lda jbd0+1,x
	sta jbd+1,y
	lda #0
	sta jbd+2,y
	inx
	inx
	iny
	iny
	iny
	cpx #NBLK*2
	bne @b
	stz jya                 ; ($09600)
	lda #$96
	sta jya+1
	stz jya+2
	clc
	lda jcbase
	sta jca
	lda jcbase+1
	adc #$96
	sta jca+1
	lda #0
	adc #0
	sta jca+2
	rts

; jstep(frames): about frames' worth of decoding: 0 more to come, 1 done,
; PE_* (the bench: all of it)
_jstep:	sta frames
.ifndef JPEG_BENCH
	lda _ser_frames
	sta t0
	lda _ser_frames+1
	sta t0+1
.endif
@l:	lda _perr
	jne @ret
	lda phase
	bne @row
	lda jdri                ; a restart interval's end?
	ora jdri+1
	beq @m
	lda rcount
	cmp jdri
	bne @m
	lda rcount+1
	cmp jdri+1
	bne @m
	stz rcount
	stz rcount+1
	jsr jrestart
@m:	inc rcount
	bne @1
	inc rcount+1
@1:	jsr jmcu
	inc mx
	bne @2
	inc mx+1
@2:	lda mx
	cmp jmcux
	jne @t
	lda mx+1
	cmp jmcux+1
	jne @t
	inc phase               ; the MCU row's rows next
	stz ry
	jmp @t
@row:	jsr jrow
	inc iy
	bne @3
	inc iy+1
@3:	lda iy                  ; iy >= ph: done
	cmp _ph
	lda iy+1
	sbc _ph+1
	bcc @4
	lda _perr
	bne @ret
	lda _jw                 ; (the picture's size again, for the status bar)
	sta _pw
	lda _jw+1
	sta _pw+1
	lda _jh
	sta _ph
	lda _jh+1
	sta _ph+1
	lda #1
@ret:	rts
@4:	inc ry
	lda ry
	cmp jyrows
	bne @5
	stz phase               ; the next MCU row
	stz mx
	stz mx+1
	jsr places
	jmp @t
@5:	clc                     ; the next row: Y's, CbCr's when its row changes
	lda jya
	adc jystr
	sta jya
	lda jya+1
	adc jystr+1
	sta jya+1
	bcc @6
	inc jya+2
@6:	lda ry
	and jvmask
	jne @t
	clc
	lda jca
	adc jcstr
	sta jca
	lda jca+1
	adc jcstr+1
	sta jca+1
	bcc @t
	inc jca+2
@t:
.ifndef JPEG_BENCH
	sec
	lda _ser_frames
	sbc t0
	tax
	lda _ser_frames+1
	sbc t0+1
	bne @no                 ; (a long time)
	cpx frames
	jcc @l
@no:	lda #0
	rts
.else
	jmp @l
.endif

.ifndef JPEG_BENCH
; (pic.c's call, through main.c's ov7) u_ret = jstep(png_frames), oy_done
_jpg_step_v:
	lda _png_frames
	jsr _jstep
	sta _u_ret
	lda _joy
	sta _oy_done
	lda _joy+1
	sta _oy_done+1
	rts
.endif
