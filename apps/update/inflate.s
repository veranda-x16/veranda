; Veranda Update: inflate (RFC 1951), for the files that come deflated in
; a release's pack (overlay 4; DECISIONS V210). After Veranda Gemini's
; inflate (apps/gemini/pngcore.s, itself after Commander Calc's
; inflate.c, Marcin Spoczynski, MIT): its canonical tables (the count of
; codes of each length, the symbols in order), its window of 32 KB in
; VRAM's back screen ($09600-$115FF: Veranda Update draws to the
; foreground only, its menus and boxes save what they cover in the
; save-under room above) through VERA's two data ports, its code lengths
; at $12900 (320 bytes). New here:
;   - the input comes from the network, a packet at a time, into a ring
;     in this overlay's bank ($BC00-$BFFF, 1 KB), and a step is taken
;     only when the ring holds all it may read (8 bytes for a code and its
;     extra bits, 640 for a block's header and its tables) unless the
;     stream's last bytes are in: the decoder stops between steps and
;     goes on with the next packet. A broken stream that reads past what
;     came is an error (a few zero bytes after the stream's end are let
;     through: the lookups below read ahead);
;   - the codes are found with lookup tables, as zlib does: the next 9
;     bits index a table of the literal/length codes ($B400: their
;     symbols' low bytes, $B600: their lengths, bit 7 the symbol's ninth
;     bit), the next 8 one of the distances' ($B800, $BA00); a longer code
;     (length 0 there) is found bit by bit in the canonical tables. The
;     bits wait in a 16-bit buffer (bb, bn of them), refilled a byte at a
;     time. Gemini's bit-by-bit search took some 1,300 cycles a literal:
;     4 KB a second, slower than the modem; this one under 200 (literals
;     one after another in a loop of their own while the ring holds 256
;     bytes or more);
;   - a match is copied in runs of up to 255 bytes (VERA's port 1 to port
;     0 and iobuf, some 20 cycles a byte; a distance of 1 one byte again);
;   - the bytes come out into iobuf, up to 512 a call.
;
;   z_start(zsize)   a new stream of zsize bytes (unsigned long)
;   z_feed(buf, n)   n bytes (n <= 256, buf below $A000) into the ring
;                    (it has room: a step leaves less than 640 in it)
;   z_run()          as much as it can into iobuf (zcount bytes): 0 more
;                    bytes wanted, 1 iobuf full (call again), 2 the
;                    stream's end, 3 not deflate
;
; Called with this overlay mapped at $A000 (main.c's wrappers); VERA's
; ports set at each call (whatever drew between two calls) and ADDRSEL 0
; at the end.
;
; MIT licence (see LICENSE).

.setcpu "65C02"
.macpack longbranch

.export _z_start, _z_feed, _z_run, _zcount
.import _iobuf, popax
.importzp ptr1, sreg

VAL   = $9F20
VAM   = $9F21
VAH   = $9F22
VD0   = $9F23
VD1   = $9F24
VCTRL = $9F25

LTS     = $B400                 ; the literal/length lookup: symbols' low bytes (512)
LTL     = $B600                 ;   lengths | the ninth bit << 7 (512); 0: longer than 9
DTS     = $B800                 ; the distances' lookup: symbols (256)
DTL     = $BA00                 ;   lengths (256); 0: longer than 8 (two pages above, as LTL)
RING    = $BC00                 ; the input (1 KB)
RINGEND = $C000
NEED_CODE = 8
NEED_HEAD = 640
PAST_MAX  = 4                   ; zero bytes read past the stream's end, at most

ST_HEADER = 0
ST_STORED = 1
ST_CODES  = 2
ST_DONE   = 3

Z_MORE = 0
Z_FULL = 1
Z_END  = 2
Z_BAD  = 3

.segment "ZEROPAGE": zeropage
bb:	.res 2          ; the bits waiting, the next the lowest
bn:	.res 1          ;   their count (0-16)
zv:	.res 2          ; getbits, decode: the value
zm:	.res 2
zt:	.res 2
zptr:	.res 2          ; a canonical table: the counts (16 words), then the symbols
zq:	.res 2          ; a pointer
zr:	.res 2          ; the ring's next byte to read
zo:	.res 2          ; iobuf's next byte

.segment "OVL4BSS"
_zcount: .res 2
zcode:	.res 2
zfirst:	.res 2
zindex:	.res 2
zerr:	.res 1
zpast:	.res 1
zw:	.res 2          ; the ring's next byte to write
avail:	.res 2          ; bytes in the ring
zleft:	.res 4          ; the stream's bytes not fed yet
state:	.res 1
last:	.res 1
wrapped: .res 1
left:	.res 2
copy_len: .res 2
copy_dist: .res 2
wpos:	.res 2
zsrc:	.res 2
zrun:	.res 2          ; a distance of 1's byte; 1 then
lcount:	.res 32         ; (the literal/length table: counts, then 288 symbols)
lsym:	.res 576
dcount:	.res 32         ; (the distance table: counts, then 30 symbols)
dsym:	.res 60
offs:	.res 32         ; (build's; then the fast table's next codes)
clcl:	.res 19
cn:	.res 2          ; build: the symbols
cs:	.res 2
cprev:	.res 1
crep:	.res 1
ncodes:	.res 2          ; dynamic: nlen + ndist
nw:	.res 2          ; dynamic: the lengths written
nlen:	.res 2
fbits:	.res 1          ; fast: the lookup's bits (9 or 8)
fpage:	.res 1          ;   its lengths' page
flen:	.res 1
fsym:	.res 2
fstep:	.res 2
bsend:

.segment "OVL4RO"
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
bmask:	.byte $00, $01, $03, $07, $0F, $1F, $3F, $7F, $FF

.segment "OVERLAY4"

;---------------------------------------------------------------- the calls
; z_start(zsize): a/x/sreg
_z_start:
	sta zleft
	stx zleft+1
	lda sreg
	sta zleft+2
	lda sreg+1
	sta zleft+3
	stz bb
	stz bb+1
	stz bn
	stz state
	stz wpos
	stz wpos+1
	stz wrapped
	stz copy_len
	stz copy_len+1
	stz zerr
	stz zpast
	stz avail
	stz avail+1
	lda #<RING
	sta zr
	sta zw
	lda #>RING
	sta zr+1
	sta zw+1
	rts

; z_feed(buf, n): n in a/x (0-256), buf on the C stack
_z_feed:
	sta zt
	stx zt+1
	jsr popax
	sta ptr1
	stx ptr1+1
	lda zt
	ora zt+1
	beq @r
	lda state               ; (after the stream's end: more is not deflate)
	cmp #ST_DONE
	bne @1
	lda #1
	sta zerr
@r:	rts
@1:	sec                     ; zleft -= n (more than is left: not deflate)
	lda zleft
	sbc zt
	sta zleft
	lda zleft+1
	sbc zt+1
	sta zleft+1
	lda zleft+2
	sbc #0
	sta zleft+2
	lda zleft+3
	sbc #0
	sta zleft+3
	bcs @2
	lda #1
	sta zerr
@2:	clc                     ; avail += n
	lda avail
	adc zt
	sta avail
	lda avail+1
	adc zt+1
	sta avail+1
	lda zw
	sta zq
	lda zw+1
	sta zq+1
@c:	lda (ptr1)
	sta (zq)
	inc ptr1
	bne @c1
	inc ptr1+1
@c1:	inc zq
	bne @c2
	inc zq+1
	lda zq+1
	cmp #>RINGEND
	bne @c2
	lda #>RING
	sta zq+1
@c2:	lda zt
	bne @c3
	dec zt+1
@c3:	dec zt
	lda zt
	ora zt+1
	bne @c
	lda zq
	sta zw
	lda zq+1
	sta zw+1
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

; port 0 / 1 at the code lengths' a/x (low, high)
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

;---------------------------------------------------------------- the input
; the ring's next byte -> a; none: after the stream's end a zero (a few),
; else zerr; x and y kept
getbyte:
	lda avail
	bne @1
	lda avail+1
	beq @none
	dec avail+1
@1:	dec avail
	lda (zr)
	inc zr
	bne @r
	inc zr+1
	pha
	lda zr+1
	cmp #>RINGEND
	bne @2
	lda #>RING
	sta zr+1
@2:	pla
@r:	rts
@none:	lda zleft
	ora zleft+1
	ora zleft+2
	ora zleft+3
	bne @bad
	inc zpast
	lda zpast
	cmp #PAST_MAX + 1
	bcs @bad
	lda #0
	rts
@bad:	lda #1
	sta zerr
	lda #0
	rts

; the buffer to 9 bits or more; y kept
refill:	lda bn
	cmp #9
	bcs @r
	jsr getbyte
	ldx bn
	beq @b0
	cpx #8
	beq @b8
	stz zm                  ; (the byte << bn into zm/a)
@sh:	asl a
	rol zm
	dex
	bne @sh
	ora bb
	sta bb
	lda zm
	ora bb+1
	sta bb+1
	bra @add
@b8:	sta bb+1                ; (bits 8-15 are 0 when bn is 8)
	bra @add
@b0:	sta bb
@add:	lda bn
	clc
	adc #8
	sta bn
	bra refill
@r:	rts

; x bits (0-16; bn of them there) taken out of the buffer; y kept
drop:	cpx #8
	bcc @b
	lda bb+1
	sta bb
	stz bb+1
	lda bn
	sec
	sbc #8
	sta bn
	txa
	sbc #8
	tax
@b:	txa
	beq @r
	eor #$FF                ; bn -= x
	sec
	adc bn
	sta bn
@l:	lsr bb+1
	ror bb
	dex
	bne @l
@r:	rts

; a bit -> carry (the slow search's); y kept
getbit:	lda bn
	bne @1
	jsr refill
@1:	dec bn
	lsr bb+1
	ror bb
	rts

; x bits (0-13), the first the lowest -> zv; y kept
getbits:
	stz zv+1
	cpx #9
	bcs @two
	phx
	jsr refill
	plx
	lda bb
	and bmask,x
	sta zv
	jmp drop
@two:	txa                     ; (9-13: 8, then the rest)
	sec
	sbc #8
	pha
	jsr refill
	lda bb
	sta zv
	ldx #8
	jsr drop
	jsr refill
	plx
	lda bb
	and bmask,x
	sta zv+1
	jmp drop

; to a byte's start (a stored block)
align:	lda bn
	and #7
	tax
	jmp drop

; the next whole byte -> a (after align: from the buffer first)
getbyte_al:
	lda bn
	beq @ring
	lda bb
	pha
	ldx #8
	jsr drop
	pla
	rts
@ring:	jmp getbyte

;---------------------------------------------------------------- Huffman
; a symbol of the canonical table at zptr, bit by bit -> zv; carry set:
; not a code
decode:	stz zcode
	stz zcode+1
	stz zfirst
	stz zfirst+1
	stz zindex
	stz zindex+1
	ldy #2                  ; (count[1])
@l:	jsr getbit
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
	lda #1
	sta zerr
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

; the canonical table at zptr from the code lengths at cs (in VRAM), cn of them
build:	lda cs
	ldx cs+1
	jsr setcl1
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
	lda fbits
	bne fast
	rts

dec_zt:	lda zt
	bne @1
	dec zt+1
@1:	dec zt
	lda zt
	ora zt+1
	rts

; the lookup table of the canonical one at zptr (its counts) and the code
; lengths at cs, cn of them: fbits bits (lit_table's 9, dist_table's 8;
; 0 for the code lengths' code: none), its lengths at page fpage (the
; symbols' two pages below); a code of fbits or fewer fills every entry
; whose low bits are its code reversed, a longer one none (0: the slow
; search)
fast:	stz zq                  ; the lengths' pages cleared
	ldx fpage
	stx zq+1
	lda #0
	tay
@cl:	sta (zq),y
	iny
	bne @cl
	ldx fbits
	cpx #9
	bne @nc                 ; next_code[len] (offs): code = (code + count[len - 1]) << 1
	inc zq+1
@c2:	sta (zq),y
	iny
	bne @c2
@nc:	stz zt
	stz zt+1
	stz offs
	stz offs+1
	ldx #2
	ldy #0                  ; ((zptr),y: count[len - 1], y = 2 * (len - 1))
@n:	clc
	lda zt
	adc (zptr),y
	sta zt
	iny
	lda zt+1
	adc (zptr),y
	sta zt+1
	iny
	asl zt
	rol zt+1
	lda zt
	sta offs,x
	lda zt+1
	sta offs+1,x
	inx
	inx
	cpx #32
	bne @n
	lda cs                  ; each symbol's length, in order
	ldx cs+1
	jsr setcl1
	stz fsym
	stz fsym+1
@s:	lda VD1
	jeq @ns
	sta flen
	asl a                   ; zt = next_code[len]++
	tax
	lda offs,x
	sta zt
	lda offs+1,x
	sta zt+1
	inc offs,x
	bne @s0
	inc offs+1,x
@s0:	lda flen
	cmp fbits
	beq @s1
	jcs @ns                 ; (longer than the lookup: the slow search)
@s1:	stz zm                  ; zm/zm+1 = the code reversed (flen bits)
	stz zm+1
	ldx flen
@rv:	lsr zt+1
	ror zt
	rol zm
	rol zm+1
	dex
	bne @rv
	lda #1                  ; fstep = 1 << flen
	sta fstep
	stz fstep+1
	ldx flen
@st:	asl fstep
	rol fstep+1
	dex
	bne @st
@f:	lda zm                  ; entry zm: the length (bit 7: the symbol's bit 8), the symbol
	sta zq
	clc
	lda zm+1
	adc fpage
	sta zq+1
	lda fsym+1
	ror a                   ; (bit 0 to the carry)
	lda flen
	bcc @f1
	ora #$80
@f1:	sta (zq)
	lda zq+1
	sec
	sbc #2
	sta zq+1
	lda fsym
	sta (zq)
	clc                     ; zm += fstep, while below 1 << fbits
	lda zm
	adc fstep
	sta zm
	lda zm+1
	adc fstep+1
	sta zm+1
	ldx fbits
	cpx #9
	beq @f9
	cmp #0                  ; (8 bits: below 256)
	beq @f
	bra @ns
@f9:	cmp #2                  ; (9 bits: below 512)
	bcc @f
@ns:	inc fsym
	bne @n1
	inc fsym+1
@n1:	lda fsym
	cmp cn
	jne @s
	lda fsym+1
	cmp cn+1
	jne @s
	rts

lit_table:
	lda #9
	sta fbits
	lda #>LTL
	sta fpage
	lda #<lcount
	ldx #>lcount
	bra tab
dist_table:
	lda #8
	sta fbits
	lda #>DTL
	sta fpage
	lda #<dcount
	ldx #>dcount
tab:	sta zptr
	stx zptr+1
	rts

; a/x into cn; the lengths from cs
build_at:
	sta cn
	stx cn+1
	jmp build

; x copies of a into the code lengths (port 0)
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
	lda #<288               ; (the distances' lengths after the literals')
	ldx #>288
	jsr setcl0
	lda #5
	ldx #30
	jsr fill
	lda #<288
	sta cs
	lda #>288
	sta cs+1
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
	jsr dist_table          ; (their table borrows the distances', with no lookup)
	stz fbits
	stz cs
	stz cs+1
	lda #19
	ldx #0
	jsr build_at
	lda #0                  ; the lengths, coded
	tax
	jsr setcl0
	stz nw
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
	jmp build_at
@bad:	lda #1
	sta zerr
@r:	rts

; nw += x
adv:	txa
	clc
	adc nw
	sta nw
	bcc @r
	inc nw+1
@r:	rts

;---------------------------------------------------------------- inflate
ZEND = _iobuf + 512             ; (iobuf's end)

; a byte into the window (port 0) and iobuf (zo); x and y kept
put:	sta VD0
	sta (zo)
	inc zo
	bne @1
	inc zo+1
@1:	inc wpos
	bne @r
	inc wpos+1
	bpl @r                  ; (below $8000)
	stz wpos+1
	lda #1
	sta wrapped
	phx
	phy
	jsr setw0
	ply
	plx
@r:	rts

; c set: the ring holds fewer bytes than a/x, what the next step may
; read, and the stream's last bytes are not all in yet
short:	sta zm
	stx zm+1
	lda zleft
	ora zleft+1
	ora zleft+2
	ora zleft+3
	beq @ok                 ; (all in: every step may go)
	lda avail
	cmp zm
	lda avail+1
	sbc zm+1
	bcs @ok
	sec
	rts
@ok:	clc
	rts

; iobuf's room -> zt; z set: none
room:	sec
	lda #<ZEND
	sbc zo
	sta zt
	lda #>ZEND
	sbc zo+1
	sta zt+1
	ora zt
	rts

; z_run: up to 512 bytes into iobuf -> a: Z_MORE, Z_FULL, Z_END, Z_BAD
_z_run:
	lda #<_iobuf
	sta zo
	lda #>_iobuf
	sta zo+1
	jsr setw0
@loop:	lda zerr
	jne @bad
	jsr room
	jeq @full
	lda copy_len
	ora copy_len+1
	beq @state
	jsr copy
	bra @loop
@state:	lda state
	cmp #ST_DONE
	jeq @end
	cmp #ST_HEADER
	bne @need8
	lda #<NEED_HEAD         ; a block's header: its tables
	ldx #>NEED_HEAD
	jsr short
	jcs @more
	bra @hd
@need8:	lda state
	cmp #ST_STORED
	jne @codes
	lda #NEED_CODE
	ldx #0
	jsr short
	jcs @more
	jmp @stored
@hd:	ldx #1                  ; a block's header
	jsr getbits
	lda zv
	sta last
	ldx #2
	jsr getbits
	lda zv
	bne @t1
	jsr align               ; stored: to a byte's start
	jsr getbyte_al
	sta left
	jsr getbyte_al
	sta left+1
	jsr getbyte_al
	eor #$FF
	cmp left
	bne @bad
	jsr getbyte_al
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
@bad:	lda #1
	sta zerr
	lda #Z_BAD
	bra @out
@full:	lda #Z_FULL
	bra @out
@more:	lda #Z_MORE
	bra @out
@end:	lda #Z_END
@out:	tay
	sec
	lda zo
	sbc #<_iobuf
	sta _zcount
	lda zo+1
	sbc #>_iobuf
	sta _zcount+1
	stz VCTRL
	tya
	ldx #0
	rts
@stored:
	lda left
	ora left+1
	bne @sb
@bend:	lda #ST_HEADER          ; the block's end
	ldx last
	beq @e
	lda #ST_DONE
@e:	sta state
	jmp @loop
@sb:	jsr getbyte_al
	jsr put
	lda left
	bne @sd
	dec left+1
@sd:	dec left
	jmp @loop
	; the codes: literals one after another here, while iobuf has room
	; and the ring holds 256 bytes or more (else the slow checks: short)
@codes:	lda avail+1
	bne @c1
	lda zerr
	jne @bad
	lda #NEED_CODE
	ldx #0
	jsr short
	jcs @more
@c1:	jsr refill              ; the literal/length code: the next 9 bits
	ldy bb
	lda bb+1
	lsr a
	bcs @hi
	lda LTL,y
	beq @slow
	ldx LTS,y
	bra @got
@hi:	lda LTL+256,y
	beq @slow
	ldx LTS+256,y
@got:	stx zv
	tay                     ; (the length and the ninth bit)
	and #$0F
	tax
	jsr drop
	tya
	bmi @sym9
	lda zv                  ; a literal
	jsr put
	lda zo+1                ; iobuf full?
	cmp #>ZEND
	bcc @codes
	bne @fl
	lda zo
	cmp #<ZEND
	bcc @codes
@fl:	jmp @full
@sym9:	lda #1                  ; 256 and on
	sta zv+1
	bra @len
@slow:	jsr lit_table
	jsr decode
	jcs @lp
	lda zv+1
	bne @len
	lda zv
	jsr put
@lp:	jmp @loop
@len:	lda zv                  ; 256 the end, 257-285 a length
	jeq @bend
	sec
	sbc #1
	cmp #29
	jcs @bad
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
	jsr refill              ; the distance's code: the next 8 bits
	ldy bb
	lda DTL,y
	beq @dslow
	ldx DTS,y
	stx zv
	stz zv+1
	tax
	jsr drop
	bra @dist
@dslow:	jsr dist_table
	jsr decode
	jcs @lp
@dist:	lda zv+1
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
	jne @lp
	lda wpos
	cmp copy_dist
	lda wpos+1
	sbc copy_dist+1
	jcs @lp
	stz copy_len
	stz copy_len+1
	jmp @bad

; a match: as much of copy_len as iobuf takes, in runs of up to 255 bytes
; that cross neither end of the window (port 0 at wpos)
copy:	sec                     ; zsrc = (wpos - dist) & $7FFF
	lda wpos
	sbc copy_dist
	sta zsrc
	lda wpos+1
	sbc copy_dist+1
	and #$7F
	sta zsrc+1
	jsr setw1
	stz zrun+1              ; (0: a match; 1: a distance of 1, the byte again)
	lda copy_dist+1
	bne @run
	lda copy_dist
	cmp #1
	bne @run
	lda VD1                 ; (port 1's next would be the byte not yet written)
	sta zrun
	inc zrun+1
@run:	jsr room                ; x = the run: min(255, copy_len, room, the ends)
	jeq @x
	lda zt+1
	bne @r1
	lda zt
	bra @r2
@r1:	lda #255
@r2:	ldx copy_len+1
	bne @r3
	cmp copy_len
	bcc @r3
	lda copy_len
@r3:	ldx wpos+1              ; (the window's end: $8000 - wpos when under 256)
	cpx #$7F
	bne @r4
	ldx wpos
	beq @r4
	pha
	txa
	eor #$FF
	inc a
	sta zm
	pla
	cmp zm
	bcc @r4
	lda zm
@r4:	ldx zsrc+1
	cpx #$7F
	bne @r5
	ldx zsrc
	beq @r5
	pha
	txa
	eor #$FF
	inc a
	sta zm
	pla
	cmp zm
	bcc @r5
	lda zm
@r5:	sta zm                  ; (1-255)
	tax
	ldy #0
	lda zrun+1
	bne @fill
@cp:	lda VD1
	sta VD0
	sta (zo),y
	iny
	dex
	bne @cp
	bra @adv
@fill:	lda zrun
@f1:	sta VD0
	sta (zo),y
	iny
	dex
	bne @f1
@adv:	clc                     ; zo, wpos, zsrc += the run; copy_len -= it
	lda zo
	adc zm
	sta zo
	bcc @a1
	inc zo+1
@a1:	clc
	lda wpos
	adc zm
	sta wpos
	bcc @a2
	inc wpos+1
	bpl @a2
	stz wpos+1
	lda #1
	sta wrapped
	jsr setw0
@a2:	clc
	lda zsrc
	adc zm
	sta zsrc
	bcc @a3
	inc zsrc+1
	bpl @a3
	stz zsrc+1
	lda zrun+1              ; (a distance of 1 reads port 1 no more)
	bne @a3
	jsr setw1
@a3:	sec
	lda copy_len
	sbc zm
	sta copy_len
	lda copy_len+1
	sbc #0
	sta copy_len+1
	ora copy_len
	jne @run
@x:	rts

.assert bsend <= LTS, error, "inflate.s: the overlay runs into its tables"
