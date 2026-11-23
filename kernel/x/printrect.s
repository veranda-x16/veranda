; Veranda bank X: PrintRect, a screen area printed as a page of its own of
; the open PDF document (bank P, kernel/p/colour.s; docs/DECISIONS.md V38)
;
; The area is scaled to the page at printer resolution: "fit" (a bit 1)
; the largest size that fits inside a quarter-inch margin, else GEOS's 80
; screen pixels an inch (clipped at the margin); centred across, at the
; top margin. Dot i of a row shows source pixel i * w / Wd (rounded down),
; row j source row j * h / Hd. Each source row is read (ReadRow), widened
; here (the first dot of source pixel p is D(p) = ceil(p * Wd / w),
; counted along the row) and handed to bank P once for all the page rows
; it covers (PrRows). With a bit 7 the ink is printed in its colour
; (palette entry 1) and, if the colour map is shown, the paper colours
; (bank P writes them as a second image: a byte a card, placed over the
; same cards here and clipped to the area).

.include "kernel.inc"

.export k_PrintRect
.import kRowBuf
.global S_PrInfo, S_PrPage, S_PrRows, S_k_PrintPage, S_k_ReadRow

.segment "BSS"

rFlags:	.res 1
rSel:	.res 1                  ; dispBufferOn for ReadRow
rDB:	.res 1                  ; the caller's
rCol:	.res 1                  ; PrPage's a
rDpi:	.res 1
rLeft:	.res 2
rTop:	.res 2
rW:	.res 2                  ; the area (pixels)
rH:	.res 2
rShift:	.res 1
rBytes:	.res 2                  ; the page: bytes a row, rows, dots, margin
pRows:	.res 2
pDots:	.res 2
pMarg:	.res 2
pW:	.res 2                  ; the printable size
pH:	.res 2
; PrPage's r0-r9 (kernel/p/colour.s)
x0:	.res 2
yb:	.res 2
wd:	.res 2
hd:	.res 2
cw:	.res 2
ch:	.res 2
cx:	.res 2
cy:	.res 2
rCard:	.res 1
rCards:	.res 1
rCRow:	.res 1
rCRows:	.res 1
PARAMS = x0
; the steps of D (Wd / w and its remainder, the same for 8 pixels) and of
; the rows (Hd / h)
stQ1:	.res 2
stR1:	.res 2
stQH:	.res 2
stRH:	.res 2
sy:	.res 2                  ; the source row
eq:	.res 2                  ; E(sy) = eq + (er > 0): its first page row
er:	.res 2
e0:	.res 2
; widening a row
sp:	.res 2                  ; source pixels done
dq:	.res 2                  ; D(p) = dq + (dr > 0)
dr:	.res 2
pix:	.res 1                  ; the pixel before the byte ($00 or $FF)
inRun:	.res 1
any:	.res 1                  ; $80: the row has ink
run0:	.res 2
dd:	.res 2
lastB:	.res 1                  ; the row's last byte in kRowBuf
lastM:	.res 1                  ; its pixels of the area
wrow:	.res 320                ; the widened row
; the first dot of each source pixel: x0 + D(p) for the pixel at bit
; q = shift + p of kRowBuf (q = 8 i + k: at DTab + 162 k + 2 i)
DTab:	.res 8 * 162
; arithmetic
mA:	.res 2
mB:	.res 2
dN:	.res 3                  ; dividend, then the quotient
dR:	.res 3
dD:	.res 2
tt:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; PrintRect: r3 left, r11 top, r4 right, r12 bottom (clipped to the
; screen), a flags: bit 0 the back screen, bit 1 fit to the page, bit 7
; colour -> x error (INCOMPATIBLE: no document, or nothing left)
;---------------------------------------------------------------
k_PrintRect:
	sta rFlags
	ldx #ST_WR_FORE
	lsr
	bcc @1
	ldx #ST_WR_BACK
@1:	stx rSel
	CmpW r4, screenWidth    ; clipped to the screen
	bcc @2
	lda screenWidth
	sbc #1
	sta r4L
	lda screenWidth+1
	sbc #0
	sta r4H
@2:	CmpW r12, screenHeight
	bcc @3
	lda screenHeight
	sbc #1
	sta r12L
	lda screenHeight+1
	sbc #0
	sta r12H
@3:	CmpW r4, r3
	bcc @bad
	CmpW r12, r11
	bcs @4
@bad:	ldx #INCOMPATIBLE
	rts
@4:	MoveW r3, rLeft
	MoveW r11, rTop
	sec
	lda r4L
	sbc r3L
	sta rW
	lda r4H
	sbc r3H
	sta rW+1
	IncW rW
	sec
	lda r12L
	sbc r11L
	sta rH
	lda r12H
	sbc r11H
	sta rH+1
	IncW rH
	FARCALL PrInfo          ; the page
	cpx #0
	beq @5
	rts
@5:	sta rDpi
	ldx #7
@6:	lda r1,x
	sta rBytes,x
	dex
	bpl @6
	MoveW pDots, pW
	SubW pMarg, pW
	SubW pMarg, pW
	MoveW pRows, pH
	SubW pMarg, pH
	SubW pMarg, pH
	lda rFlags
	and #2
	bne @fb157
	jmp @nat
@fb157:
	; fit: the width, or the height if it is the tighter
	MoveW pW, wd
	MoveW rH, mA
	MoveW pW, mB
	MoveW rW, dD
	jsr MulDiv              ; h * PW / w
	MoveW dN, hd
	CmpW pH, hd
	bcc @fb166
	jmp @sc
@fb166:
	MoveW pH, hd
	MoveW rW, mA
	MoveW pH, mB
	MoveW rH, dD
	jsr MulDiv              ; w * PH / h
	MoveW dN, wd
	jmp @sc
@nat:	; 80 pixels an inch: 15 / 8 dots a pixel at 150 dpi, 15 / 4 at 300
	LoadW dD, 15
	MoveW pW, mA            ; the widest area that fits
	jsr Den
	jsr MulDiv
	CmpW rW, dN
	bcc @n1
	MoveW dN, rW
@n1:	MoveW pH, mA
	jsr Den
	jsr MulDiv
	CmpW rH, dN
	bcc @n2
	MoveW dN, rH
@n2:	jsr Den                 ; Wd = w * 15 / den
	MoveW mB, dD
	LoadW mB, 15
	MoveW rW, mA
	jsr MulDiv
	MoveW dN, wd
	MoveW rH, mA
	jsr MulDiv
	MoveW dN, hd
@sc:	; centred across, at the top margin
	sec
	lda pW
	sbc wd
	sta x0
	lda pW+1
	sbc wd+1
	lsr
	sta x0+1
	ror x0
	AddW pMarg, x0
	; the cards: left >> 3 .. (left + w - 1) >> 3, the rows the same
	lda rLeft
	and #7
	sta rShift
	ldx #0
	jsr Cards
	ldx #2
	jsr Cards
	; the colours
	stz rCol
	bit rFlags
	bpl @7
	LoadB rCol, $40         ; the ink
	stz VERA_CTRL
	lda VERA_DC_VIDEO       ; the map shown: layer 1 on
	and #$20
	beq @7
	lda VERA_L0_TILEBASE    ; (V101) not the tile desktop's: the ink alone
	cmp #TILE_TB
	beq @7
	LoadB rCol, $C0
	jsr Place
@7:	MoveW pRows, yb         ; the area's bottom: rows - margin - Hd
	SubW pMarg, yb
	SubW hd, yb
	; the steps of D: Wd / w and 8 Wd / w; of E: Hd / h
	MoveW wd, mA
	LoadW mB, 1
	MoveW rW, dD
	jsr MulDiv
	MoveW dN, stQ1
	MoveW dR, stR1
	MoveW hd, mA
	LoadW mB, 1
	MoveW rH, dD
	jsr MulDiv
	MoveW dN, stQH
	MoveW dR, stRH
	jsr Table
	; the page
	ldx #19
@8:	lda PARAMS,x
	sta r0,x
	dex
	bpl @8
	lda rCol
	FARCALL PrPage
	bcc @9
	rts
@9:	MoveW pMarg, r1         ; the top margin
	LoadW r0, 0
	FARCALL PrRows
	; the rows: source row sy for page rows E(sy) .. E(sy + 1) - 1
	stz sy
	stz sy+1
	stz eq
	stz eq+1
	stz er
	stz er+1
@row:	CmpW sy, rH
	bcc @fb269
	jmp @end
@fb269:
	jsr Edge                ; E(sy) -> e0
	MoveW mA, e0
	lda er                  ; the next
	clc
	adc stRH
	sta er
	lda er+1
	adc stRH+1
	sta er+1
	AddW stQH, eq
	CmpW er, rH
	bcc @10
	SubW rH, er
	IncW eq
@10:	jsr Edge                ; E(sy + 1) - E(sy) rows
	SubW e0, mA
	MoveW mA, r1
	jsr Widen
	LoadW r0, 0
	bit any
	bpl @11
	LoadW r0, wrow
@11:	FARCALL PrRows
	cpx #0
	bne @r
	IncW sy
	jmp @row
@end:	FARCALL k_PrintPage     ; the rest white
@r:	rts

; E(sy) = eq + (er > 0) -> mA
Edge:	MoveW eq, mA
	lda er
	ora er+1
	beq @1
	IncW mA
@1:	rts

; mB = the dots-per-pixel denominator: 8 (150 dpi) or 4 (300)
Den:	LoadW mB, 8
	lda rDpi
	beq @1
	LoadB mB, 4
@1:	rts

; x = 0: the card columns (rLeft, rW -> rCard, rCards); x = 2: the card
; rows (rTop, rH -> rCRow, rCRows)
Cards:	lda rLeft,x
	sta mA
	lda rLeft+1,x
	sta mA+1
	jsr Shr3
	pha
	lda rLeft,x             ; the last: left + w - 1
	clc
	adc rW,x
	sta mA
	lda rLeft+1,x
	adc rW+1,x
	sta mA+1
	lda mA
	bne @1
	dec mA+1
@1:	dec mA
	jsr Shr3
	sta tt
	pla
	cpx #0
	bne @2
	sta rCard
	bra @3
@2:	sta rCRow
@3:	eor #$FF                ; last - first + 1: ~first + last + 1, + 1
	sec
	adc tt
	ina
	cpx #0
	bne @4
	sta rCards
	rts
@4:	sta rCRows
	rts

; mA >> 3 -> a
Shr3:	lda mA
	lsr mA+1
	ror
	lsr mA+1
	ror
	lsr mA+1
	ror
	rts

; the colours' image over the area's cards, in PDF coordinates: x
; x0 - shift * Wd / w, width 8 * cards * Wd / w; from the top margin
; - (top & 7) * Hd / h, height 8 * rows * Hd / h
Place:	lda rShift
	sta mA
	stz mA+1
	MoveW wd, mB
	MoveW rW, dD
	jsr MulDiv
	MoveW x0, cx
	SubW dN, cx
	lda rCards
	jsr Times8
	MoveW wd, mB
	jsr MulDiv
	MoveW dN, cw
	lda rTop
	and #7
	sta mA
	stz mA+1
	MoveW hd, mB
	MoveW rH, dD
	jsr MulDiv
	MoveW pMarg, cy         ; (the top, for now)
	SubW dN, cy
	lda rCRows
	jsr Times8
	MoveW hd, mB
	jsr MulDiv
	MoveW dN, ch
	MoveW pRows, mA         ; the bottom: rows - top - height
	SubW cy, mA
	SubW ch, mA
	MoveW mA, cy
	rts
Times8:	sta mA
	stz mA+1
	asl mA
	rol mA+1
	asl mA
	rol mA+1
	asl mA
	rol mA+1
	rts

;---------------------------------------------------------------
; the table of first dots: x0 + D(p), p = 0 .. w (D(p) = ceil(p * Wd / w),
; counted: dq + (dr > 0), dq / dr stepping by Wd / w)
;---------------------------------------------------------------
Table:	stz dq
	stz dq+1
	stz dr
	stz dr+1
	MoveW rShift, sp        ; q = shift (sp+1: 0)
	stz sp+1
@p:	lda sp                  ; r7 = DTab + 162 (q & 7) + 2 (q >> 3)
	and #7
	asl
	tax
	lda TabK,x
	sta r7L
	lda TabK+1,x
	sta r7H
	lda sp+1
	sta r8H
	lda sp
	lsr r8H
	ror
	lsr r8H
	ror
	lsr r8H
	ror
	asl
	tay
	lda dq                  ; x0 + dq (+ 1 if dr > 0)
	ldx dr
	bne @1
	ldx dr+1
	beq @2
@1:	sec
	.byte $24               ; (bit zp: skips the clc)
@2:	clc
	adc x0
	sta (r7),y
	iny
	lda dq+1
	adc x0+1
	sta (r7),y
	; the next pixel
	lda dr
	clc
	adc stR1
	sta dr
	lda dr+1
	adc stR1+1
	sta dr+1
	AddW stQ1, dq
	CmpW dr, rW
	bcc @3
	SubW rW, dr
	IncW dq
@3:	IncW sp
	sec                     ; up to q = shift + w
	lda sp
	sbc rShift
	tax
	lda sp+1
	sbc #0
	cmp rW+1
	bne @4
	cpx rW
@4:	bcs @fb478
	jmp @p
@fb478:
	bne @fb479
	jmp @p
@fb479:
	; the row's last byte and its pixels of the area
	lda rShift
	clc
	adc rW
	sta mA
	lda rW+1
	adc #0
	sta mA+1
	lda mA
	bne @5
	dec mA+1
@5:	dec mA                  ; q of the last pixel
	lda mA
	and #7
	tax
	lda LMask,x
	sta lastM
	jsr Shr3
	sta lastB
	rts

;---------------------------------------------------------------
; source row sy widened into wrow: ReadRow, then each black run of
; source pixels p0 .. p1 - 1 (found as in kernel/p/fax.s's MakeList)
; fills dots x0 + D(p0) .. x0 + D(p1) - 1; any: $80 if there is ink
;---------------------------------------------------------------
Widen:	PushW r1
	MoveB dispBufferOn, rDB
	MoveB rSel, dispBufferOn
	LoadW r0, kRowBuf
	MoveB rCard, r3L
	MoveB rCards, r3H
	lda rTop
	clc
	adc sy
	sta r11L
	lda rTop+1
	adc sy+1
	sta r11H
	FARCALL k_ReadRow
	MoveB rDB, dispBufferOn
	ldx rShift              ; only the area's pixels
	lda kRowBuf
	and RMask,x
	sta kRowBuf
	ldx lastB
	lda kRowBuf,x
	and lastM
	sta kRowBuf,x
	LoadW r7, wrow          ; white
	ldy #0
	lda #0
	ldx rBytes+1
	beq @c2
@c1:	sta (r7),y
	iny
	bne @c1
	inc r7H
@c2:	cpy rBytes
	beq @c3
	sta (r7),y
	iny
	bra @c2
@c3:	stz inRun
	stz any
	stz pix
	ldy #0                  ; the bytes
@b:	lda kRowBuf,y
	cmp pix
	beq @nx
	sta sp                  ; the changes: bits unlike their left neighbour
	lsr
	bit pix
	bpl @w
	ora #$80
@w:	eor sp
	sta sp+1
	lda sp                  ; the next byte's left neighbour
	ror
	lda #0
	sbc #0
	eor #$FF
	sta pix
	tya                     ; y * 2: the table's offset
	asl
	sta dd+1
	LoadW r9, TabK
@k:	asl sp+1
	bcc @k2
	phy                     ; a change at q = 8 y + k: its first dot
	ldy #0
	lda (r9),y
	sta r7L
	iny
	lda (r9),y
	sta r7H
	ldy dd+1
	lda (r7),y
	sta dd
	iny
	lda (r7),y
	ply
	bit inRun
	bmi @end
	sta run0+1              ; a run starts
	MoveB dd, run0
	LoadB inRun, $80
	bra @k2
@end:	sta dd+1                ; a run ends
	phy
	jsr EndRun
	ply
	tya
	asl
	sta dd+1
@k2:	lda r9L
	clc
	adc #2
	sta r9L
	bcc @k3
	inc r9H
@k3:	lda sp+1
	bne @k
@nx:	iny
	cpy rCards
	beq @fb605
	jmp @b
@fb605:
	bit inRun               ; the last run ends at x0 + Wd
	bpl @r
	lda x0
	clc
	adc wd
	sta dd
	lda x0+1
	adc wd+1
	sta dd+1
	jsr EndRun
@r:	PopW r1
	rts

; a run ends at dd: dots run0 .. dd - 1 set
EndRun:	stz inRun
	MoveW run0, mA
	MoveW dd, mB
	CmpW mA, mB
	bcc @0
	rts                     ; (empty)
@0:	LoadB any, $80
	lda mB                  ; the last
	bne @1
	dec mB+1
@1:	dec mB
	; r7 = wrow + first >> 3, x its bit; r8 = last >> 3 - first >> 3
	lda mA
	and #7
	tax
	lda mA+1
	sta r7H
	lda mA
	lsr r7H
	ror
	lsr r7H
	ror
	lsr r7H
	ror
	sta r7L
	lda mB+1
	sta r8H
	lda mB
	lsr r8H
	ror
	lsr r8H
	ror
	lsr r8H
	ror
	sec
	sbc r7L
	sta r8L
	lda r8H
	sbc r7H
	sta r8H
	lda r7L
	clc
	adc #<wrow
	sta r7L
	lda r7H
	adc #>wrow
	sta r7H
	lda mB
	and #7
	tay
	lda r8L
	ora r8H
	bne @many
	lda RMask,x             ; one byte
	and LMask,y
	ora (r7)
	sta (r7)
	rts
@many:	lda RMask,x
	ora (r7)
	sta (r7)
@m:	IncW r7
	lda r8L
	bne @m1
	dec r8H
@m1:	dec r8L
	lda r8L
	ora r8H
	beq @lst
	lda #$FF
	sta (r7)
	bra @m
@lst:	lda LMask,y
	ora (r7)
	sta (r7)
	rts

;---------------------------------------------------------------
; dN = mA * mB / dD, dR the remainder (mA changed; products below 2^24)
;---------------------------------------------------------------
MulDiv:	stz dN
	stz dN+1
	stz dN+2
	stz tt                  ; mA, tt: the multiplicand, shifted
	lda mB
	sta dR
	lda mB+1
	sta dR+1
	ldx #16
@m:	lsr dR+1
	ror dR
	bcc @n
	lda dN
	clc
	adc mA
	sta dN
	lda dN+1
	adc mA+1
	sta dN+1
	lda dN+2
	adc tt
	sta dN+2
@n:	asl mA
	rol mA+1
	rol tt
	dex
	bne @m
	stz dR                  ; dN / dD
	stz dR+1
	stz dR+2
	ldx #24
@l:	asl dN
	rol dN+1
	rol dN+2
	rol dR
	rol dR+1
	rol dR+2
	sec
	lda dR
	sbc dD
	tay
	lda dR+1
	sbc dD+1
	sta tt
	lda dR+2
	sbc #0
	bcc @k
	sta dR+2
	MoveB tt, dR+1
	sty dR
	inc dN
@k:	dex
	bne @l
	rts

.segment "RODATA"

TabK:	.repeat 8, K
	.word DTab + 162 * K
	.endrepeat
RMask:	.byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01
LMask:	.byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF
