; Veranda bank G2: PutCards, text in fixed 8 x 8 character cells
; (docs/DECISIONS.md V36)
;
; r0 the characters (below $A000; r3H of them, or fewer up to a 0), r1 the
; font (below $A000: 8 bytes a glyph, glyph c at r1 + 8 * c, rows top
; first, bit 7 the left pixel), r3L the column (cards), r11 the top row
; (pixels, any row), a flags: bit 0 reverse, bit 1 bold (v OR v >> 1).
; Each glyph is opaque in its card. The screens dispBufferOn selects;
; rows outside the clip window (windowTopW, windowBottomW) are left alone;
; columns are clipped to the screen.
;
; One seek a character: VERA's address steps by the screen's stride (80
; or 40 bytes), so the glyph's 8 bytes go down the card in one stream
; (port 0 the first screen, port 1 the back screen when both are drawn).
; A whole card without bold is unrolled.

.include "kernel.inc"

.import kStride
.export k_PutCards, RowOff, pcAddr, pcTmp

.segment "BSS"

pcFlags: .res 1
pcN:	.res 1                  ; characters
pcRow0:	.res 1                  ; the first and last glyph row drawn
pcRow1:	.res 1
pcAddr:	.res 3                  ; the first screen's address (17 bits)
pcAddr2: .res 3                 ; the back screen's
pcTmp:	.res 2

.segment "CODE"

k_PutCards:
	sta pcFlags
	; the screens: none, nothing to do
	lda dispBufferOn
	and #%11000000
	bne @0
@r:	rts
@0:	; the columns
	lda r3L
	cmp kStride
	bcs @r
	lda kStride
	sec
	sbc r3L
	cmp r3H
	bcc @1
	lda r3H
@1:	sta pcN
	; up to a 0
	ldy #0
@z:	cpy pcN
	beq @z1
	lda (r0),y
	beq @z1
	iny
	bra @z
@z1:	sty pcN
	tya
	beq @r
	; the rows: glyph row r is screen row r11 + r, kept if it is in the
	; window and on the screen
	lda #8
	sta pcRow0
	stz pcRow1
	ldx #0
@rw:	txa
	clc
	adc r11L
	sta pcTmp
	lda r11H
	adc #0
	sta pcTmp+1
	CmpW pcTmp, windowTopW
	bcc @rn
	CmpW windowBottomW, pcTmp
	bcc @rn
	CmpW pcTmp, screenHeight
	bcs @rn
	lda pcRow0
	cmp #8
	bcc @r1
	stx pcRow0
@r1:	stx pcRow1
@rn:	inx
	cpx #8
	bne @rw
	lda pcRow0
	cmp #8
	bcc @go
	rts                     ; no row
@go:	; the address of (r3L, r11 + pcRow0) on the first screen
	clc
	adc r11L
	sta pcTmp
	lda r11H
	adc #0
	sta pcTmp+1
	jsr RowOff              ; pcAddr = pcTmp * stride + r3L
	; port 0: the foreground if it is drawn, else the back screen; port 1:
	; the back screen when both are
	lda #$8D                ; the second store: sta VERA_DATA1 ...
	bit dispBufferOn
	bpl @bgonly
	bvs @both
	lda #$2C                ; ... or bit (one screen)
	bra @p
@bgonly: jsr AddBg
	lda #$2C
@p:	jsr Patch
	bra @a
@both:	jsr Patch
	MoveW pcAddr, pcAddr2
	lda pcAddr+2
	sta pcAddr2+2
	jsr AddBg
	; swap: pcAddr the foreground, pcAddr2 the back screen
	ldx #2
@sw:	lda pcAddr,x
	ldy pcAddr2,x
	sta pcAddr2,x
	tya
	sta pcAddr,x
	dex
	bpl @sw
@a:	; reverse and bold
	lda pcFlags
	lsr
	lda #0
	bcc @a1
	lda #$FF
@a1:.repeat 8, I
	sta .ident(.sprintf("Eor%d", I))+1
.endrepeat
	sta EorS+1
	; the step: the stride
	ldx #$C0                ; 80
	lda kStride
	cmp #80
	beq @st
	ldx #$B0                ; 40
@st:	stx pcTmp
	lda pcRow1
	ina
	sta RowEnd+1
	; whole cards without bold: the unrolled loop
	lda pcFlags
	and #2
	bne @sl
	lda pcRow0
	ora pcRow1
	cmp #7
	bne @sl
	lda pcRow0
	beq @fast
@sl:	jmp PcSlow
@fast:	ldy #0
	lda pcAddr+2
	ora pcTmp
	sta pcTmp+1             ; ADDR_H with the step
PcF:	lda pcAddr              ; port 0 at column y; the next column after
	sta VERA_ADDR_L
	lda pcAddr+1
	sta VERA_ADDR_M
	lda pcTmp+1
	sta VERA_ADDR_H
	bit dispBufferOn        ; both screens: port 1 too
	bpl @g
	bvc @g
	jsr Seek1
@g:	inc pcAddr
	bne @g1
	inc pcAddr+1
	bne @g1
	inc pcTmp+1             ; (bit 16)
@g1:	lda (r0),y              ; kPtr = r1 + 8 * the character
	tax
	lda Mul8L,x
	clc
	adc r1L
	sta kPtr
	lda Mul8H,x
	adc r1H
	sta kPtr+1
	phy
	ldy #0
.repeat 8, I
	lda (kPtr),y
.ident(.sprintf("Eor%d", I)):
	eor #0
	sta VERA_DATA0
.ident(.sprintf("St%d", I)):
	sta VERA_DATA1          ; (bit VERA_DATA1: one screen)
	iny
.endrepeat
	ply
	iny
	cpy pcN
	beq @fr
	jmp PcF
@fr:	rts
PcSlow:	ldy #0
PcS:	jsr Seek
	jsr Glyph
	phy
	ldy pcRow0
PcS1:	lda (kPtr),y
	sta pcTmp+1
	lda pcFlags
	and #2
	beq PcS2
	lda pcTmp+1
	lsr
	ora pcTmp+1
	bra PcS3
PcS2:	lda pcTmp+1
PcS3:
EorS:	eor #0
	sta VERA_DATA0
Store2b: sta VERA_DATA1
	iny
RowEnd:	cpy #8
	bne PcS1
	ply
	iny
	cpy pcN
	bne PcS
	rts

; the stores to port 1: a = $8D (sta) or $2C (bit)
Patch:
.repeat 8, I
	sta .ident(.sprintf("St%d", I))
.endrepeat
	sta Store2b
	rts

; kPtr = r1 + 8 * character y
Glyph:	lda (r0),y
	stz kPtr+1
	asl
	rol kPtr+1
	asl
	rol kPtr+1
	asl
	rol kPtr+1
	clc
	adc r1L
	sta kPtr
	lda kPtr+1
	adc r1H
	sta kPtr+1
	rts

; both ports at column y of the run (pcAddr + y, pcAddr2 + y), stepping
; by the stride (pcTmp)
Seek:	tya
	clc
	adc pcAddr
	sta VERA_ADDR_L
	lda pcAddr+1
	adc #0
	sta VERA_ADDR_M
	lda pcAddr+2
	adc #0
	ora pcTmp
	sta VERA_ADDR_H
	bit dispBufferOn
	bpl SeekR
	bvc SeekR
Seek1:	lda #1                  ; port 1 alone
	sta VERA_CTRL
	tya
	clc
	adc pcAddr2
	sta VERA_ADDR_L
	lda pcAddr2+1
	adc #0
	sta VERA_ADDR_M
	lda pcAddr2+2
	adc #0
	ora pcTmp
	sta VERA_ADDR_H
	stz VERA_CTRL
SeekR:	rts

; pcAddr += the back screen's start
AddBg:	lda pcAddr+1
	clc
	adc #>VRAM_BG
	sta pcAddr+1
	lda pcAddr+2
	adc #^VRAM_BG
	sta pcAddr+2
	rts

; pcAddr = pcTmp (a row) * kStride + r3L
RowOff:	lda pcTmp               ; row * 16
	sta pcAddr
	lda pcTmp+1
	stz pcAddr+2
	ldx #4
@1:	asl pcAddr
	rol
	rol pcAddr+2
	dex
	bne @1
	sta pcAddr+1            ; pcAddr = row * 16
	lda pcAddr              ; + row * 64
	sta kTmp
	lda pcAddr+1
	sta kTmp+1
	lda pcAddr+2
	sta kTmp+2
	ldx #2
@2:	asl kTmp
	rol kTmp+1
	rol kTmp+2
	dex
	bne @2
	lda pcAddr
	clc
	adc kTmp
	sta pcAddr
	lda pcAddr+1
	adc kTmp+1
	sta pcAddr+1
	lda pcAddr+2
	adc kTmp+2
	sta pcAddr+2
	lda kStride
	cmp #80
	beq @3
	lsr pcAddr+2            ; 40 a row: half
	ror pcAddr+1
	ror pcAddr
@3:	lda pcAddr
	clc
	adc r3L
	sta pcAddr
	bcc @r
	inc pcAddr+1
	bne @r
	inc pcAddr+2
@r:	rts

; 8 * c, low and high bytes
Mul8L:
.repeat 256, I
	.byte <(I * 8)
.endrepeat
Mul8H:
.repeat 256, I
	.byte >(I * 8)
.endrepeat
