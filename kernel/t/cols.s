; Veranda bank T: narrow rectangles and vertical lines a byte column at a
; time (DECISIONS V80)
;
; Bank G's span engine (kernel/g/fb.s) costs some 400 cycles a row
; whatever the span's width, so a frame's vertical edges, a drag's
; outline or a window's shadow cost 30-90 ms. Here VERA's two ports step
; by the screen's stride (80, or 40 at 320 wide): one byte column, all
; its rows, at 12-16 cycles a row (an unrolled block of 8 rows). The
; result is the span engine's byte for byte: per byte, keep = the left
; edge's mask in the first column, the right edge's in the last (both in
; a single column),
;     fill:   new = (source AND keep) OR (pattern row AND NOT keep)
;     invert: new = source XOR NOT keep
; and the source, as there (GEOS's rule): for a fill the back screen if
; it is written, else the foreground (the foreground written first); for
; an invert the foreground if it is written, else the back screen (the
; back screen written first, so both read the foreground unchanged).
;
; FbCols:          a = 0 fill, 1 invert; r3 .. r4 by r11 .. r12 (clipped
;                  to the screen), the screens dispBufferOn selects; the
;                  fill's pattern: 8 bytes (row y AND 7) the caller pushed
;                  before the FARCALL, row 0 pushed last (bank G's
;                  Narrow, kernel/g/draw.s, takes them off again)
; k_WVerticalLine: the API call (moved here from bank G); as before, r3 =
;                  r4 afterwards

.include "kernel.inc"

.import kStride
.export FbCols, k_WVerticalLine, KeepLeft

.segment "BSS"

cOp:	.res 1                  ; 0 fill, 1 invert
cMode:	.res 1
cPat:	.res 8                  ; the pattern, row y AND 7
cRot:	.res 8                  ; the pattern as the block's rows take it
cT:	.res 8                  ; cRot AND NOT keep (fill)
cA:	.res 1                  ; keep (fill)
cC:	.res 1                  ; NOT keep (invert)
cKeepL:	.res 1
cKeepR:	.res 1
cCol:	.res 1
cCnt:	.res 1                  ; columns
cI:	.res 1
cXr:	.res 2                  ; the right x, clipped
cYb:	.res 2                  ; the bottom row, clipped
cN:	.res 2                  ; rows
cAdr:	.res 2                  ; the column's top: row * stride + column
cInc:	.res 1                  ; ADDR_H's increment: the stride
cSrc:	.res 1                  ; 0 the foreground, 1 the back screen
cE:	.res 1                  ; the block's first row (0-7)
cG:	.res 1                  ; blocks
cVec:	.res 2                  ; where the first block starts
cTmp:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; FbCols (see the top): the pattern from the caller's stack
;---------------------------------------------------------------
FbCols:
	sta cOp
	tsx
	ldy #0
@p:	lda $0100 + FAR_STACK,x
	sta cPat,y
	inx
	iny
	cpy #8
	bne @p
	jmp Cols

;---------------------------------------------------------------
; WVerticalLine: a = pattern byte (bit y AND 7, bit 7 first), r4 = x,
; r11 .. r12
;---------------------------------------------------------------
k_WVerticalLine:
	sta cMode
	lda clipOn              ; the clip rectangle (V81): x in it, its rows
	beq VLine
	jmp VClip
VLine:	ldx #7
@p:	lda cMode
	and BitMask,x
	beq @0
	lda #$FF
@0:	sta cPat,x
	dex
	bpl @p
	stz cOp
	MoveW r4, r3            ; the column as a one pixel span (r3 kept so)
	; fall into Cols

;---------------------------------------------------------------
; the columns of r3 .. r4 by r11 .. r12; cOp, cPat
;---------------------------------------------------------------
; (VClip, below: WVerticalLine with the clip on)
Cols:
	; cXr = min(r4, width - 1); none if cXr < r3
	lda screenWidth
	sec
	sbc #1
	sta cXr
	lda screenWidth+1
	sbc #0
	sta cXr+1
	CmpW r4, cXr
	bcs @1
	MoveW r4, cXr
@1:	CmpW cXr, r3
	bcs @2
@none:	rts
@2:	; cYb = min(r12, height - 1); none if cYb < r11
	lda screenHeight
	sec
	sbc #1
	sta cYb
	lda screenHeight+1
	sbc #0
	sta cYb+1
	CmpW r12, cYb
	bcs @3
	MoveW r12, cYb
@3:	CmpW cYb, r11
	bcc @none
	lda cYb                 ; rows
	sec
	sbc r11
	sta cN
	lda cYb+1
	sbc r11+1
	sta cN+1
	IncW cN
	; the edges' masks, the first column and the count
	lda r3L
	and #7
	tax
	lda KeepLeft,x
	sta cKeepL
	lda cXr
	and #7
	tax
	lda KeepRight,x
	sta cKeepR
	lda r3H
	sta cTmp
	lda r3L
	ldx #3
@4:	lsr cTmp
	ror
	dex
	bne @4
	sta cCol
	lda cXr+1
	sta cTmp
	lda cXr
	ldx #3
@5:	lsr cTmp
	ror
	dex
	bne @5
	sec
	sbc cCol
	sta cCnt
	inc cCnt
	; cAdr = r11 * stride + column (row * 64 + row * 16; half at 40)
	lda r11L
	sta cAdr
	lda r11H
	asl cAdr
	rol
	asl cAdr
	rol
	asl cAdr
	rol
	asl cAdr
	rol
	sta cAdr+1              ; row * 16
	ldx cAdr
	stx cTmp
	asl cTmp
	rol
	asl cTmp
	rol
	tax                     ; row * 64: x, cTmp
	lda cTmp
	clc
	adc cAdr
	sta cAdr
	txa
	adc cAdr+1
	ldx #$C0                ; increment 80
	ldy kStride
	cpy #80
	beq @6
	lsr
	ror cAdr
	ldx #$B0                ; increment 40
@6:	sta cAdr+1
	stx cInc
	lda cAdr
	clc
	adc cCol
	sta cAdr
	bcc @7
	inc cAdr+1
@7:	; blocks of 8 rows: the first entered at row cE = -n AND 7
	lda #0
	sec
	sbc cN
	and #7
	sta cE
	lda cN
	clc
	adc #7
	sta cTmp
	lda cN+1
	adc #0
	lsr
	ror cTmp
	lsr
	ror cTmp
	lsr
	ror cTmp
	lda cTmp
	sta cG
	; the block's row k takes pattern row (r11 - cE + k) AND 7
	lda r11L
	sec
	sbc cE
	tax
	ldy #0
@8:	txa
	and #7
	tax
	lda cPat,x
	sta cRot,y
	inx
	iny
	cpy #8
	bne @8
	; the entry: the block + cE rows; the source
	ldx #<FillBlk
	ldy #>FillBlk
	lda #FROW
	sta cTmp
	lda #0                  ; fill: the back screen if written
	bit dispBufferOn
	bvc @9
	lda #1
@9:	sta cSrc
	lda cOp
	beq @10
	ldx #<InvBlk
	ldy #>InvBlk
	lda #IROW
	sta cTmp
	lda #1                  ; invert: the foreground if written
	bit dispBufferOn
	bpl @s1
	lda #0
@s1:	sta cSrc
@10:	stx cVec
	sty cVec+1
	ldx cE
	beq @12
@11:	lda cVec
	clc
	adc cTmp
	sta cVec
	bcc @11a
	inc cVec+1
@11a:	dex
	bne @11
@12:	; the columns
	stz cI
@col:	ldx cI                  ; keep: the left edge's in the first, the
	lda #0                  ; right edge's in the last
	cpx #0
	bne @k1
	lda cKeepL
@k1:	inx
	cpx cCnt
	bne @k2
	ora cKeepR
@k2:	ldx cOp
	bne @inv
	sta cA
	eor #$FF
	sta cTmp
	ldx #7
@t:	lda cRot,x
	and cTmp
	sta cT,x
	dex
	bpl @t
	bit dispBufferOn        ; the foreground first
	bpl @f1
	lda #0
	jsr Pass
@f1:	bit dispBufferOn
	bvc @next
	lda #1
	jsr Pass
	bra @next
@inv:	eor #$FF
	sta cC
	bit dispBufferOn        ; the back screen first
	bvc @i1
	lda #1
	jsr Pass
@i1:	bit dispBufferOn
	bpl @next
	lda #0
	jsr Pass
@next:	IncW cAdr
	inc cI
	lda cI
	cmp cCnt
	bne @col
	rts

; WVerticalLine with the clip on (V81): nothing unless leftMargin <= x <=
; rightMargin; the rows windowTopW .. windowBottomW of it (the pattern by
; the row, so the same pixels as unclipped); r11, r12 kept
VClip:	CmpW r4, leftMargin
	bcc @r
	CmpW rightMargin, r4
	bcc @r
	PushW r11
	PushW r12
	CmpW r11, windowTopW
	bcs @1
	MoveW windowTopW, r11
@1:	CmpW windowBottomW, r12
	bcs @2
	MoveW windowBottomW, r12
@2:	CmpW r12, r11
	bcc @e
	jsr VLine
@e:	PopW r12
	PopW r11
@r:	rts

; one column on buffer a: port 1 reads cSrc, port 0 writes a, both
; stepping by the stride
Pass:	ldx #0
	jsr Seek
	lda cSrc
	ldx #1
	jsr Seek
	ldx cG
	jmp (cVec)

; data port x at buffer a (0, 1), cAdr; the stride's increment
Seek:	stx VERA_CTRL
	tay
	lda cAdr
	sta VERA_ADDR_L
	lda cAdr+1
	clc
	adc BufMid,y
	sta VERA_ADDR_M
	lda cInc
	adc #0                  ; address bit 16 (the back screen crosses $10000)
	sta VERA_ADDR_H
	stz VERA_CTRL
	rts

; 8 rows a block, x blocks; entered at row cE
FillBlk:
.repeat 8, k
	lda VERA_DATA1
	and cA
	ora cT + k
	sta VERA_DATA0
.endrepeat
	dex
	bne FillBlk
	rts
FROW = (* - FillBlk - 4) / 8

InvBlk:
.repeat 8
	lda VERA_DATA1
	eor cC
	sta VERA_DATA0
.endrepeat
	dex
	bne InvBlk
	rts
IROW = (* - InvBlk - 4) / 8

.segment "RODATA"

BufMid:		.byte >VRAM_FG, >VRAM_BG ; (both start on a page; neither starts above $FFFF)
BitMask:	.byte $80, $40, $20, $10, $08, $04, $02, $01
KeepLeft:	.byte $00, $80, $C0, $E0, $F0, $F8, $FC, $FE
KeepRight:	.byte $7F, $3F, $1F, $0F, $07, $03, $01, $00
