; Veranda bank G: drawing (the wide calls; the classic ones in phase 2)
;
; Coordinates: x in r3 (and r4), y in r11 (and r12), 16 bits each. Unlike
; GEOS, everything is clipped to the screen, so a bad call cannot write
; outside the bitmaps.

.include "kernel.inc"
.include "line.inc"

.import fb_span, fb_span_off, fb_calc_off, fb_seek, fbTmp
.import fbRow, fbCol, fbCnt, fbKeepL, fbKeepR, fbOp, fbPat, fbSel, fbOff
.importzp FBOP_FILL, FBOP_INV, FBOP_RECOVER, FBOP_IMPRINT
.import kStride, kFx, fb_block, fbBlkN
.import ClipRows

.export k_SetPattern, k_WHorizontalLine, k_WInvertLine, k_WRecoverLine
.export k_WRectangle, k_WFrameRectangle, k_WInvertRectangle, k_WRecoverRectangle
.export k_WImprintRectangle, k_WDrawPoint, k_WTestPoint, k_WDrawLine
.export Patterns, KeepLeft, KeepRight, BitMask, RectRows, yy, yb

.segment "BSS"

xr:	.res 2                  ; the right x, clipped
yb:	.res 2                  ; the bottom y, clipped
yy:	.res 2                  ; the current row
lnMode:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; SetPattern: a = 0-33
;---------------------------------------------------------------
k_SetPattern:
	cmp #NPATTERNS
	bcc @1
	lda #0
@1:	asl
	asl
	asl
	clc
	adc #<Patterns
	sta curPattern
	lda #>Patterns
	adc #0
	sta curPattern+1
	rts

;---------------------------------------------------------------
; spans: r3 .. r4 on row fbRow -> fbCol, fbCnt, the keep masks
; (r4 clipped to the screen; fbCnt = 0 if nothing is left)
;---------------------------------------------------------------
XSpan:
	MoveW r4, xr
	lda screenWidth         ; xr = min(r4, width - 1)
	sec
	sbc #1
	tax
	lda screenWidth+1
	sbc #0
	cmp xr+1
	bne @c
	cpx xr
@c:	bcs @1
	stx xr
	sta xr+1
@1:	CmpW xr, r3             ; xr < r3: nothing
	bcs @2
	stz fbCnt
	rts
@2:	lda r3L
	and #7
	tax
	lda KeepLeft,x
	sta fbKeepL
	lda xr
	and #7
	tax
	lda KeepRight,x
	sta fbKeepR
	lda r3H                 ; x / 8 from 10 bits
	ldy r3L
	jsr Col8
	sta fbCol
	lda xr+1
	ldy xr
	jsr Col8
	sec
	sbc fbCol
	inc a
	sta fbCnt
	rts

; a = the high, y = the low byte of x: a = x / 8 from 11 bits
Col8:	asl
	asl
	asl
	asl
	asl
	sta fbTmp
	tya
	lsr
	lsr
	lsr
	ora fbTmp
	rts

; rows r11 .. r12 (r12 clipped): yy = r11, yb = the last; c set if none
YRange:
	MoveW r12, yb
	lda screenHeight
	sec
	sbc #1
	tax
	lda screenHeight+1
	sbc #0
	cmp yb+1
	bne @c
	cpx yb
@c:	bcs @1
	stx yb
	sta yb+1
@1:	MoveW r11, yy
	CmpW yb, yy             ; c clear if yb < yy: nothing
	rol
	eor #1
	ror                     ; c set if nothing
	rts

; yy < height? c clear if on the screen
OnScreen:
	CmpW yy, screenHeight
	rts

; the row loop: fbOp, and for fills the pattern per row
RectRows:
	jsr XSpan
	lda fbCnt
	beq @r
	jsr YRange
	bcs @r
	MoveB dispBufferOn, fbSel
	lda clipOn              ; the clip (V81): a row at a time through it
	beq @nc
	jmp ClipRows
@nc:	jsr Block
	bcs @r
	MoveW yy, fbRow
	jsr fb_calc_off         ; the first row's offset; the next ones
@row:	lda yy                  ; + the stride (V80)
	and #7
	tay
	lda (curPattern),y
	sta fbPat
	jsr fb_span_off         ; (it keeps fbOff, fbCnt, fbCol, masks)
	CmpW yy, yb
	beq @r
	IncW yy
	lda fbOff
	clc
	adc kStride
	sta fbOff
	bcc @row
	inc fbOff+1
	bra @row
@r:	rts

; a fill of whole rows: one stream of FX cache writes a screen
; (fb_block); c set if done
Block:	bit kFx
	bpl @no
	lda fbOp                ; (FBOP_FILL is 0)
	ora fbCol
	ora fbKeepL
	ora fbKeepR
	bne @no
	lda fbCnt
	cmp kStride
	bne @no
	MoveW yy, fbRow
	lda yb
	sec
	sbc yy
	sta fbBlkN
	lda yb+1
	sbc yy+1
	sta fbBlkN+1
	IncW fbBlkN
	jsr fb_block
	sec
	rts
@no:	clc
	rts

;---------------------------------------------------------------
; WRectangle and friends: r3 left, r11 top, r4 right, r12 bottom
;---------------------------------------------------------------
k_WRectangle:
	LoadB fbOp, FBOP_FILL
	bra Narrow

k_WInvertRectangle:
	LoadB fbOp, FBOP_INV
	; a fill or an invert under NARROW pixels wide: bank T draws it a
	; byte column at a time (kernel/t/cols.s; DECISIONS V80), the pattern
	; on the stack
Narrow:	lda clipOn              ; (the clip, V81: bank G's rows)
	bne @w
	lda r4
	sec
	sbc r3
	tax
	lda r4+1
	sbc r3+1
	bne @w                  ; (r4 < r3 too: nothing, as there)
	cpx #NARROW
	bcs @w
	ldy #7
@p:	lda (curPattern),y
	pha
	dey
	bpl @p
	lda fbOp                ; (FBOP_FILL 0, FBOP_INV 1)
	FARCALL FbCols
	ldx #8
@d:	pla
	dex
	bne @d
	rts
@w:	jmp RectRows
NARROW = 32
.assert FBOP_FILL = 0 && FBOP_INV = 1, error, "FbCols takes 0 and 1"

k_WRecoverRectangle:
	LoadB fbOp, FBOP_RECOVER
	jmp RectRows

k_WImprintRectangle:
	LoadB fbOp, FBOP_IMPRINT
	jmp RectRows

; a = pattern byte: the four sides
k_WFrameRectangle:
	sta lnMode
	PushW r11
	PushW r12
	MoveW r11, r12          ; top
	lda lnMode
	jsr k_WHorizontalLine
	pla                     ; bottom (r12 as passed)
	sta r11
	pla
	sta r11+1
	PushW r11
	lda lnMode
	jsr k_WHorizontalLine
	PopW r12
	PopW r11
	PushW r4
	MoveW r3, r4
	lda lnMode
	FARCALL k_WVerticalLine  ; (bank T: kernel/t/cols.s; the clip there too, V81)
	PopW r4
	lda lnMode
	FARCALL k_WVerticalLine
	rts

;---------------------------------------------------------------
; one row: r3 .. r4 on r11
;---------------------------------------------------------------
; a = pattern byte
k_WHorizontalLine:
	sta fbPat
	LoadB fbOp, FBOP_FILL
	bra Line1

k_WInvertLine:
	LoadB fbOp, FBOP_INV
	bra Line1

k_WRecoverLine:
	LoadB fbOp, FBOP_RECOVER
Line1:	MoveW r11, yy
	jsr OnScreen
	bcs @r
	jsr XSpan
	MoveW yy, fbRow
	MoveB dispBufferOn, fbSel
	jmp fb_span
@r:	rts

;---------------------------------------------------------------
; points: a = DRAW_ERASE, DRAW_INK or DRAW_RECOVER; r3, r11
;---------------------------------------------------------------
k_WDrawPoint:
	sta lnMode
Plot:	CmpW r3, screenWidth
	bcs @r
	MoveW r11, yy
	jsr OnScreen
	bcs @r
	MoveW r11, fbRow
	jsr XPoint
	MoveB dispBufferOn, fbSel
	lda lnMode
	bmi @rec
	beq @0
	lda #$FF
@0:	sta fbPat
	LoadB fbOp, FBOP_FILL
	jmp fb_span
@rec:	LoadB fbOp, FBOP_RECOVER
	jmp fb_span
@r:	rts

; r3 -> one byte span, keep = the other bits; a = the pixel's mask
XPoint:
	lda r3H
	ldy r3L
	jsr Col8
	sta fbCol
	LoadB fbCnt, 1
	stz fbKeepR
	lda r3L
	and #7
	tax
	lda BitMask,x
	pha
	eor #$FF
	sta fbKeepL
	pla
	rts

; a = 1 and c set if the pixel r3, r11 is set (the back screen if
; dispBufferOn bit 6, else the foreground)
k_WTestPoint:
	CmpW r3, screenWidth
	bcs @no
	MoveW r11, yy
	jsr OnScreen
	bcs @no
	MoveW r11, fbRow
	jsr XPoint
	sta kTmp
	jsr fb_calc_off
	lda #0                  ; foreground
	bit dispBufferOn
	bvc @1
	lda #1
@1:	ldx #0
	ldy #0
	jsr fb_seek
	lda VERA_DATA0
	and kTmp
	beq @no
	lda #1
	sec
	rts
@no:	lda #0
	clc
	rts

;---------------------------------------------------------------
; WDrawLine: a = mode (as WDrawPoint), r3, r11 to r4, r12
; The midpoint rule, as GEOS: along the longer axis from the left (flat)
; or the top (steep) end; error d = 2*minor - major, after each point the
; major coordinate steps; d < 0: d += 2*minor, else the minor coordinate
; steps and d += 2*(minor - major). A steep line is worked out with the
; axes exchanged (r3, r4 and r11, r12: Trans). Afterwards r3, r11 = r4,
; r12 (the ends exchanged if the line went the other way).
; V159: a line with both ends on the screen, and in the clip if it is on,
; goes to bank T's FbLine (kernel/t/line.s), the VERA ports set here;
; any other a point at a time through Plot, as before.
;---------------------------------------------------------------
lnDx    = lnC                   ; |major|
lnDy    = lnM                   ; |minor|

k_WDrawLine:
	sta lnMode
	jsr InClip              ; c set: not wholly on the screen (kept on
	php                     ; the stack)
	ldx #r11 - r3           ; |dy|, then |dx|
	ldy #lnDy
@d:	lda r4,x
	sec
	sbc r3,x
	sta 0,y
	lda r4+1,x
	sbc r3+1,x
	sta 1,y
	bpl @p
	lda #0
	sec
	sbc 0,y
	sta 0,y
	lda #0
	sbc 1,y
	sta 1,y
@p:	txa
	beq @dn
	ldx #0
	ldy #lnDx
	bra @d
@dn:	stz lnSt
	lda lnDx                ; steep (dy > dx): the axes exchanged
	cmp lnDy
	lda lnDx+1
	sbc lnDy+1
	bcs @f
	dec lnSt
	jsr Trans
	ldx #1
@x:	lda lnDx,x
	ldy lnDy,x
	sta lnDy,x
	sty lnDx,x
	dex
	bpl @x
@f:	lda r4                  ; from the end with the lower major coordinate
	cmp r3
	lda r4+1
	sbc r3+1
	bcs @o
	jsr Swap
@o:	lda r12                 ; the minor step: +1 if the other end's is higher
	cmp r11
	lda r12+1
	sbc r11+1
	lda #1
	bcs @s
	lda #$FF
@s:	sta lnSy
	lda lnDy                ; lnI1 = 2 * minor, d = 2 * minor - major,
	asl                     ; lnI2 = 2 * (minor - major)
	sta lnI1
	lda lnDy+1
	rol
	sta lnI1+1
	lda lnI1
	sec
	sbc lnDx
	sta lnE
	lda lnI1+1
	sbc lnDx+1
	sta lnE+1
	lda lnDy
	sec
	sbc lnDx
	sta lnI2
	lda lnDy+1
	sbc lnDx+1
	asl lnI2
	rol
	sta lnI2+1
	plp
	bcc LnFast
; a point at a time, with the axes exchanged for a steep line (Plot
; takes care of the screen's edges and the clip)
Slow:	jsr TransIf
	jsr Plot
	jsr TransIf
	lda r3
	cmp r4
	lda r3+1
	sbc r4+1
	bcs TransIf             ; (the axes back)
	inc r3
	bne @1
	inc r3+1
@1:	lda lnE+1
	bmi @n
	ldx #0                  ; r11 += lnSy
	lda lnSy
	bpl @2
	dex
@2:	clc
	adc r11
	sta r11
	txa
	adc r11+1
	sta r11+1
	lda lnE
	clc
	adc lnI2
	sta lnE
	lda lnE+1
	adc lnI2+1
	bra @e
@n:	lda lnE
	clc
	adc lnI1
	sta lnE
	lda lnE+1
	adc lnI1+1
@e:	sta lnE+1
	bra Slow


; a steep line's axes exchanged (r3, r4 with r11, r12)
TransIf:
	bit lnSt
	bpl Tr9
Trans:	ldx #3
@t:	lda r3,x
	ldy r11,x
	sta r11,x
	sty r3,x
	dex
	bpl @t
Tr9:	rts

; bank T's: the ports set, the axes as they are
LnFast:	jsr TransIf
	lda lnMode              ; the fill's byte, the flags (lnF), port 0's
	bmi @rec                ; screen (fbSel)
	beq @0
	lda #$FF
@0:	sta lnP
	lda dispBufferOn
	and #$C0
	beq LnEnd               ; (neither screen)
	sta fbSel               ; ($80 the foreground, $40 or $C0 the back screen)
	lsr                     ; both: $40, port 1 the foreground, written
	and fbSel
	bra @m
@rec:	lda #$80                ; recover: port 0 the foreground, port 1 the
	sta fbSel               ; back screen, read
@m:	ldy lnSt                ; (lnF takes its place)
	phy
	sta lnF
	jsr XPoint
	sta lnM
	MoveW r11, fbRow
	jsr fb_calc_off
	ldy #0
	lda #1                  ; port 0: the foreground if fbSel bit 7 alone
	bit fbSel
	bvs @1
	dea
@1:	ldx #0
	jsr fb_seek
	lda #$F0                ; increment 0
	trb VERA_ADDR_H
	lda lnF                 ; port 1: the back screen for a recover, else
	asl                     ; the foreground
	lda #0
	rol
	ldx #1
	ldy #0
	jsr fb_seek
	inc VERA_CTRL
	lda #$F0
	trb VERA_ADDR_H
	inc lnC                 ; the points + $101 (FbLine's count)
	inc lnC+1
	ply                     ; y = lnSt
	bpl @3
	lda #$C0                ; steep: a row each access (increment 80,
	ldx kStride             ; or 40)
	cpx #80
	beq @4
	lda #$B0
@4:	tsb VERA_ADDR_H
@3:	stz VERA_CTRL
	lda lnF                 ; a = 1: port 1 used
	beq @5
	lda #1
@5:
	FARCALL FbLine
LnEnd:	ldx #1                  ; r3, r11 = r4, r12
@e:	lda r4,x
	sta r3,x
	lda r12,x
	sta r11,x
	dex
	bpl @e
	rts

; the two points exchanged
Swap:	ldx #1
@s:	lda r3,x
	ldy r4,x
	sta r4,x
	sty r3,x
	lda r11,x
	ldy r12,x
	sta r12,x
	sty r11,x
	dex
	bpl @s
	rts

; c clear if both ends are on the screen and, if it is on, in the clip
; (Plot's clip: leftMargin .. rightMargin taken to 11 bits)
InClip:	ldx #2
@p:	lda r3,x
	cmp screenWidth
	lda r3+1,x
	sbc screenWidth+1
	bcs @no
	lda r11,x
	cmp screenHeight
	lda r11+1,x
	sbc screenHeight+1
	bcs @no
	lda clipOn
	beq @in
	lda leftMargin+1
	and #7
	sta fbTmp
	lda r3,x
	cmp leftMargin
	lda r3+1,x
	sbc fbTmp
	bcc @no
	lda rightMargin+1
	and #7
	sta fbTmp
	lda rightMargin
	cmp r3,x
	lda fbTmp
	sbc r3+1,x
	bcc @no
	lda r11,x
	cmp windowTopW
	lda r11+1,x
	sbc windowTopW+1
	bcc @no
	lda windowBottomW
	cmp r11,x
	lda windowBottomW+1
	sbc r11+1,x
	bcc @no
@in:	dex
	dex
	bpl @p
	clc
	rts
@no:	sec
	rts

.segment "RODATA"

BitMask:	.byte $80, $40, $20, $10, $08, $04, $02, $01
KeepLeft:	.byte $00, $80, $C0, $E0, $F0, $F8, $FC, $FE
KeepRight:	.byte $7F, $3F, $1F, $0F, $07, $03, $01, $00

; Veranda's fill patterns (8 bytes, top row first): 0 paper, 1 ink, then
; greys, lines and textures
NPATTERNS = 34
Patterns:
	.byte $00,$00,$00,$00,$00,$00,$00,$00   ; 0 paper
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF   ; 1 ink
	.byte $AA,$55,$AA,$55,$AA,$55,$AA,$55   ; 2 50 % grey
	.byte $88,$22,$88,$22,$88,$22,$88,$22   ; 3 25 % grey
	.byte $77,$DD,$77,$DD,$77,$DD,$77,$DD   ; 4 75 % grey
	.byte $88,$00,$22,$00,$88,$00,$22,$00   ; 5 12 % grey
	.byte $FF,$00,$FF,$00,$FF,$00,$FF,$00   ; 6 horizontal lines
	.byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA   ; 7 vertical lines
	.byte $FF,$00,$00,$00,$FF,$00,$00,$00   ; 8 wide horizontal lines
	.byte $88,$88,$88,$88,$88,$88,$88,$88   ; 9 wide vertical lines
	.byte $FF,$88,$88,$88,$FF,$88,$88,$88   ; 10 grid
	.byte $FF,$80,$80,$80,$80,$80,$80,$80   ; 11 wide grid
	.byte $01,$02,$04,$08,$10,$20,$40,$80   ; 12 diagonal /
	.byte $80,$40,$20,$10,$08,$04,$02,$01   ; 13 diagonal \
	.byte $11,$22,$44,$88,$11,$22,$44,$88   ; 14 dense /
	.byte $88,$44,$22,$11,$88,$44,$22,$11   ; 15 dense \
	.byte $81,$42,$24,$18,$18,$24,$42,$81   ; 16 crosses
	.byte $18,$18,$18,$FF,$FF,$18,$18,$18   ; 17 plus
	.byte $00,$66,$66,$00,$00,$66,$66,$00   ; 18 dots
	.byte $CC,$CC,$33,$33,$CC,$CC,$33,$33   ; 19 checks
	.byte $F0,$F0,$F0,$F0,$0F,$0F,$0F,$0F   ; 20 big checks
	.byte $FF,$FF,$00,$00,$FF,$FF,$00,$00   ; 21 thick stripes
	.byte $CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC   ; 22 thick columns
	.byte $80,$00,$08,$00,$80,$00,$08,$00   ; 23 sparse dots
	.byte $FF,$81,$81,$81,$81,$81,$81,$FF   ; 24 boxes
	.byte $00,$7E,$42,$42,$42,$42,$7E,$00   ; 25 small boxes
	.byte $10,$38,$7C,$FE,$7C,$38,$10,$00   ; 26 diamonds
	.byte $FF,$7F,$3F,$1F,$0F,$07,$03,$01   ; 27 triangles
	.byte $3C,$42,$81,$81,$81,$81,$42,$3C   ; 28 rings
	.byte $E0,$E0,$E0,$00,$0E,$0E,$0E,$00   ; 29 blocks
	.byte $FF,$80,$BE,$A2,$AA,$BA,$82,$FE   ; 30 maze
	.byte $55,$00,$55,$00,$55,$00,$55,$00   ; 31 light dots
	.byte $DD,$77,$DD,$77,$DD,$77,$DD,$77   ; 32 dark grey
	.byte $AA,$00,$AA,$00,$AA,$00,$AA,$00   ; 33 pin stripes
