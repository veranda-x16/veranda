; Veranda bank P: the CCITT Group 4 coder (ITU-T T.6) of the PDF writer
; (docs/DECISIONS.md V38)
;
; A row is coded against the row before it (the reference line; white
; before a page's first row) by its changing elements, as T.6 and
; libtiff's Fax3Encode2DRow do: pass mode, vertical mode (a1 within 3
; pixels of b1) or horizontal mode (two runs, the T.4 run-length codes of
; tools/mkfax.py).
;
; Each row's changing elements are listed first (MakeList: a byte scan,
; whole white or black bytes skipped), as the distances from one to the
; next, a byte each (255: 254 further, no change there); the list is the
; next row's reference line. A row with more changes than a list holds
; (LCAP bytes: any screen row fits, 640 changes) is coded in horizontal
; mode only (its runs found in the bitmap: FindDiff), and so is the row
; after it (no reference list). A row equal to the one before it is one
; V0 a change and one more (EncSame).
;
; Rows are bytes, bit 7 the left pixel, 1 = black (ink). The bits go out
; through PutByte, MSB first.

.include "kernel.inc"

.export EncInit, EncRow, EncWhite, EncSame, EncEnd, rowPtr
.import PutByte, pw, rowBytes, rowA

LCAP    = 680                   ; bytes a list

; the coder's state in the zero page (r0-r15: free while a row is coded;
; r5-r8 are pointers)
pa0     = r0                    ; a0
ca1     = r1                    ; a1, a2 (the coding line), b1, b2
ca2     = r2
rb1     = r3
rb2     = r4
rk0     = r9                    ; the reference line's first change after a0
rk1     = r10                   ; and the two after it
rk2     = r11
bbase   = r12                   ; MakeList: the byte's first pixel
last    = r13                   ; the last change written
mtmp    = r14
lEnd    = r15                   ; the list's room

.segment "BSS"

listA:	.res LCAP
listB:	.res LCAP
rowPtr:	.res 2                  ; the row (main RAM or rowA)
lCur:	.res 2                  ; this row's list, the reference line's
lRef:	.res 2
nCur:	.res 2                  ; their changes
nRef:	.res 2
vCur:	.res 1                  ; $80: the list is whole
vRef:	.res 1
rPar:	.res 1                  ; rk0's index: 0 even (a change to black)
col:	.res 1                  ; a0's colour: 0 white, $FF black
pix:	.res 1                  ; the pixel before the byte ($00 or $FF)
tbits:	.res 1
mtmp2:	.res 1
lastB:	.res 2                  ; the row's last byte's first pixel
lastM:	.res 1                  ; and the changes inside the width there
fdX:	.res 2                  ; FindDiff's position (in and out)
fdC:	.res 1                  ; its colour: 0 white, $FF black
fdB:	.res 1
cHi:	.res 1                  ; a code, left-aligned
cLo:	.res 1
bAcc:	.res 1                  ; the bits of the byte being made
bLeft:	.res 1                  ; bits still free in it
spn:	.res 2                  ; a run's length
spCol:	.res 1                  ; its colour
kk:	.res 1
tmp:	.res 2

.segment "CODE"

; a page's start: the reference line white (an empty list), no bits yet
EncInit:
	LoadB bLeft, 8
	LoadW lCur, listA
	LoadW lRef, listB
	stz listB               ; (an empty list)
	stz nRef
	stz nRef+1
	LoadB vRef, $80
	lda rowBytes            ; the last byte: (rowBytes - 1) * 8
	sec
	sbc #1
	sta lastB
	lda rowBytes+1
	sbc #0
	asl lastB
	rol
	asl lastB
	rol
	asl lastB
	rol
	sta lastB+1
	lda pw                  ; changes up to the width: bits 0 .. (pw & 7) - 1
	and #7
	tax
	lda WMask,x
	sta lastM
	rts

; the page's end: EOFB (two EOLs), then the last byte filled with 0
EncEnd:	jsr Eol
	jsr Eol
@1:	lda bLeft
	cmp #8
	beq @r
	stz cHi
	ldx #1
	jsr PutBits
	bra @1
@r:	rts
Eol:	stz cHi                 ; 0000 0000 0001
	LoadB cLo, $10
	ldx #12
	jmp PutBits

;---------------------------------------------------------------
; EncSame: the row before again (still at rowPtr): nRef + 1 V0s
;---------------------------------------------------------------
EncSame:
	bit vRef
	bpl EncRow
	MoveW nRef, tmp
	IncW tmp
@1:	lda bLeft               ; whole bytes of them
	cmp #8
	bne @b
	lda tmp+1
	bne @8
	lda tmp
	cmp #8
	bcc @b
@8:	lda #$FF
	jsr PutByte
	lda tmp
	sec
	sbc #8
	sta tmp
	bcs @1
	dec tmp+1
	bra @1
@b:	lda tmp
	ora tmp+1
	beq @r
	LoadB cHi, $80
	ldx #1
	jsr PutBits
	lda tmp
	bne @2
	dec tmp+1
@2:	dec tmp
	bra @1
@r:	rts

;---------------------------------------------------------------
; EncRow: the row at rowPtr; EncWhite: a white row
;---------------------------------------------------------------
EncWhite:
	stz nCur
	stz nCur+1
	LoadB vCur, $80
	MoveW lCur, r5          ; an empty list
	lda #0
	sta (r5)
	bra Code
EncRow:	jsr MakeList
Code:	bit vCur
	bmi @1
	jsr HBits               ; too many changes: horizontal mode, the bitmap
	bra Swap
@1:	bit vRef
	bmi @2
	jsr HList               ; no reference list: horizontal mode
	bra Swap
@2:	jsr Code2D
Swap:	ldx #1                  ; this row's list becomes the reference
@s:	lda lCur,x
	ldy lRef,x
	sta lRef,x
	tya
	sta lCur,x
	lda nCur,x
	sta nRef,x
	dex
	bpl @s
	MoveB vCur, vRef
	rts

;---------------------------------------------------------------
; MakeList: the changes of the row at rowPtr -> lCur, nCur, vCur. The
; list: the first change + 1, then the distances from one change to the
; next (1-254; 255: 254 further, no change there), 0 at its end.
;---------------------------------------------------------------
MakeList:
	MoveW rowPtr, r8
	MoveW lCur, r5
	lda r5L                 ; room for a byte's changes up to lEnd
	clc
	adc #<(LCAP - 24)
	sta lEnd
	lda r5H
	adc #>(LCAP - 24)
	sta lEnd+1
	stz nCur
	stz nCur+1
	LoadW last, $FFFF
	stz bbase
	stz bbase+1
	stz pix
	LoadB vCur, $80
	ldx rowBytes+1          ; pages left (the last one up to rowBytes)
	inx
	ldy #0
@b:	cpx #1
	bne @n
	cpy rowBytes
	bne @fb221
	jmp @end
@fb221:
@n:	lda (r8),y
	cmp pix                 ; no change in the byte
	bne @fb224
	jmp @nx
@fb224:
	sta tbits
	lda r5L                 ; full?
	cmp lEnd
	lda r5H
	sbc lEnd+1
	bcc @fb230
	jmp @full
@fb230:
	lda tbits               ; the changes: bits unlike their left neighbour
	lsr
	bit pix
	bpl @w
	ora #$80
@w:	eor tbits
	pha
	lda tbits               ; the next byte's left neighbour
	ror
	lda #0
	sbc #0                  ; (c set: 0, c clear: $FF)
	eor #$FF
	sta pix
	CmpW bbase, lastB       ; the last byte: none at the width or after
	pla
	bcc @k0
	and lastM
@k0:	phx
	ldx #0
@k:	asl
	bcc @k2
	pha                     ; a change at bbase + x
	phy
	txa
	clc
	adc bbase
	sta mtmp
	lda bbase+1
	adc #0
	sta mtmp+1
	sec                     ; the distance from the last
	lda mtmp
	sbc last
	tay
	lda mtmp+1
	sbc last+1
	bne @far
	cpy #255
	bcs @far
@put:	tya
	sta (r5)
	inc r5L
	bne @p1
	inc r5H
@p1:	MoveW mtmp, last
	IncW nCur
	ply
	pla
@k2:	inx
	cmp #0
	bne @k
	plx
@nx:	lda bbase               ; the next byte
	clc
	adc #8
	sta bbase
	bcc @nx2
	inc bbase+1
@nx2:	iny
	beq @fb290
	jmp @b
@fb290:
	inc r8H
	dex
	beq @fb293
	jmp @b
@fb293:
@end:	lda #0                  ; the list's end
	sta (r5)
	rts
@full:	stz vCur
	rts
@far:	sta mtmp2               ; 255: 254 further (the rest 1-254)
@f:	lda #255
	sta (r5)
	IncW r5
	tya
	sec
	sbc #254
	tay
	lda mtmp2
	sbc #0
	sta mtmp2
	bne @f
	cpy #255
	bcs @f
	bra @put

;---------------------------------------------------------------
; the lists' readers: a1 = a2, a2 = the next change (pw after the last);
; the reference line: rk0 = rk1, rk1 = rk2, rk2 = the next, its parity
; changed
;---------------------------------------------------------------
AdvCur:	lda ca2
	sta ca1
	lda ca2+1
	sta ca1+1
@r:	lda (r5)
	beq @end
	inc r5L
	bne @1
	inc r5H
@1:	cmp #255
	beq @esc
	clc
	adc ca2
	sta ca2
	bcc @x
	inc ca2+1
@x:	rts
@esc:	lda #254
	clc
	adc ca2
	sta ca2
	bcc @r
	inc ca2+1
	bra @r
@end:	MoveW pw, ca2
	rts

AdvRef:	lda rPar
	eor #1
	sta rPar
	MoveW rk1, rk0
	MoveW rk2, rk1
@r:	lda (r6)
	beq @end
	inc r6L
	bne @1
	inc r6H
@1:	cmp #255
	beq @esc
	clc
	adc rk2
	sta rk2
	bcc @x
	inc rk2+1
@x:	rts
@esc:	lda #254
	clc
	adc rk2
	sta rk2
	bcc @r
	inc rk2+1
	bra @r
@end:	MoveW pw, rk2
	rts

; the readers at the lists' starts: a1, a2; b1 .. ; a0 = 0, white
Start:	MoveW lCur, r5
	LoadW ca2, $FFFF        ; (the first entry: the change + 1)
	jsr AdvCur
	jsr AdvCur
	stz pa0
	stz pa0+1
	stz col
	MoveW lRef, r6
	LoadW rk2, $FFFF
	jsr AdvRef
	jsr AdvRef
	jsr AdvRef
	stz rPar
	rts

;---------------------------------------------------------------
; Code2D: the row from both lists
;---------------------------------------------------------------
Code2D:	jsr Start
	bra @sel                ; (b1 may be at 0)
@loop:	CmpW pa0, rk0           ; the first change after a0 ...
	bcc @sel
	jsr AdvRef
	bra @loop
@sel:	lda col                 ; ... b1 the first of them to the colour
	and #1                  ; opposite a0's (an even one, to black,
	eor rPar                ; after white), b2 the next
	beq @k0
	MoveW rk1, rb1
	MoveW rk2, rb2
	bra @go
@k0:	MoveW rk0, rb1
	MoveW rk1, rb2
@go:	CmpW rb2, ca1           ; b2 < a1: pass
	bcs @vh
	LoadB cHi, $10          ; 0001
	ldx #4
	jsr PutBits
	MoveW rb2, pa0
	bra @loop
@vh:	sec                     ; d = b1 - a1
	lda rb1
	sbc ca1
	tay
	lda rb1+1
	sbc ca1+1
	beq @pos
	cmp #$FF
	bne @horiz
	cpy #$FD                ; -3 .. -1
	bcc @horiz
	bra @vert
@pos:	cpy #4                  ; 0 .. 3
	bcs @horiz
@vert:	tya                     ; vertical: the code for d + 3
	clc
	adc #3
	and #7
	tax
	lda VHi,x
	sta cHi
	lda VLen,x
	tax
	jsr PutBits
	MoveW ca1, pa0
	lda col
	eor #$FF
	sta col
	jsr AdvCur
	bra @next
@horiz:	jsr Horiz
	jsr AdvCur
	jsr AdvCur
@next:	CmpW pa0, pw
	bcs @done
	jmp @loop
@done:	rts

; horizontal mode: a1 - a0 in a0's colour, a2 - a1 in the other; a0 = a2
Horiz:	LoadB cHi, $20          ; 001
	ldx #3
	jsr PutBits
	MoveB col, spCol
	sec
	lda ca1
	sbc pa0
	sta spn
	lda ca1+1
	sbc pa0+1
	sta spn+1
	jsr PutSpan
	lda spCol
	eor #$FF
	sta spCol
	sec
	lda ca2
	sbc ca1
	sta spn
	lda ca2+1
	sbc ca1+1
	sta spn+1
	jsr PutSpan
	MoveW ca2, pa0
	rts

; the row in horizontal mode only, from its list
HList:	jsr Start
@1:	jsr Horiz
	jsr AdvCur
	jsr AdvCur
	CmpW pa0, pw
	bcc @1
	rts

; the row in horizontal mode only, its runs from the bitmap (copied to
; rowA, with a stop byte after it)
HBits:	lda rowPtr+1
	cmp #>rowA
	bne @cp
	lda rowPtr
	cmp #<rowA
	beq @c1
@cp:	MoveW rowPtr, r8        ; (main RAM)
	LoadW r7, rowA
	ldy #0
	ldx rowBytes+1
	beq @p2
@p1:	lda (r8),y
	sta (r7),y
	iny
	bne @p1
	inc r8H
	inc r7H
@p2:	cpy rowBytes
	beq @c1
	lda (r8),y
	sta (r7),y
	iny
	bra @p2
@c1:	lda #<rowA              ; the stop byte
	clc
	adc rowBytes
	sta r7L
	lda #>rowA
	adc rowBytes+1
	sta r7H
	lda #$55
	sta (r7)
	LoadW r7, rowA
	stz pa0
	stz pa0+1
	stz col
@run:	MoveW pa0, fdX          ; a1: the first black from a0
	stz fdC
	jsr FindDiff
	MoveW fdX, ca1
	LoadB fdC, $FF          ; a2: the first white from a1
	jsr FindDiff
	MoveW fdX, ca2
	jsr Horiz
	CmpW pa0, pw
	bcc @run
	rts

;---------------------------------------------------------------
; FindDiff: the first position >= fdX on the row at r7 (with a stop byte,
; $55, after it) whose pixel is not fdC -> fdX (the width at most); r8
; changed
;---------------------------------------------------------------
FindDiff:
	CmpW fdX, pw
	bcc @in
	jmp Cap
@in:	lda fdX+1               ; r8 = r7 + fdX / 8, x = fdX & 7
	sta r8H
	lda fdX
	lsr r8H
	ror
	lsr r8H
	ror
	lsr r8H
	ror
	clc
	adc r7L
	sta r8L
	lda r8H
	adc r7H
	sta r8H
	lda fdX
	and #7
	tax
	lda (r8)                ; the first byte from fdX's bit on
	eor fdC
	and RMask,x
	bne Found
	ldy #0
	lda fdC
	bne @bl
@wl:	iny                     ; whole white bytes
	bne @w1
	inc r8H
@w1:	lda (r8),y
	beq @wl
	bra @f
@bl:	iny                     ; whole black bytes
	bne @b1
	inc r8H
@b1:	lda (r8),y
	cmp #$FF
	beq @bl
	eor #$FF
@f:	tax
	tya
	clc
	adc r8L
	sta r8L
	bcc @f1
	inc r8H
@f1:	txa
Found:	ldx #0                  ; the first set bit from the left
@z:	asl
	bcs @z1
	inx
	bra @z
@z1:	stx fdB
	sec                     ; fdX = (r8 - r7) * 8 + the bit
	lda r8L
	sbc r7L
	sta fdX
	lda r8H
	sbc r7H
	asl fdX
	rol
	asl fdX
	rol
	asl fdX
	rol
	sta fdX+1
	lda fdX
	ora fdB
	sta fdX
	CmpW fdX, pw
	bcc FdRet
Cap:	MoveW pw, fdX
FdRet:	rts

;---------------------------------------------------------------
; the codes
;---------------------------------------------------------------
; a run of spn (below 2624) in colour spCol: a make-up code for 64 * k
; if spn >= 64, then the terminating code for the rest
PutSpan:
	lda spn+1
	bne @mk
	lda spn
	cmp #64
	bcc PutRun
@mk:	lda spn+1               ; k = spn >> 6
	sta kk
	lda spn
	asl
	rol kk
	asl
	rol kk
	lda kk
	clc
	adc #63
	jsr PutRun
	lda spn
	and #63
PutRun:	tax                     ; code x of spCol's table
	bit spCol
	bmi @b
	lda FaxWHi,x
	sta cHi
	lda FaxWLo,x
	sta cLo
	lda FaxWLen,x
	bra @p
@b:	lda FaxBHi,x
	sta cHi
	lda FaxBLo,x
	sta cLo
	lda FaxBLen,x
@p:	tax
; x bits of cHi:cLo, from the left
PutBits:
@l:	asl cLo
	rol cHi
	rol bAcc
	dec bLeft
	bne @n
	lda bAcc
	jsr PutByte             ; (keeps x)
	LoadB bLeft, 8
@n:	dex
	bne @l
	rts

.segment "RODATA"

; vertical mode, d = b1 - a1 + 3: VR3 VR2 VR1 V0 VL1 VL2 VL3
VHi:	.byte %00000110, %00001100, %01100000, %10000000, %01000000, %00001000, %00000100
VLen:	.byte 7, 6, 3, 1, 3, 6, 7
RMask:	.byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01
WMask:	.byte $FF, $80, $C0, $E0, $F0, $F8, $FC, $FE

.include "faxcodes.inc"
