; tests/lines.s -D REF: kernel/g/draw.s's WDrawLine before V159 (main 2d67490),
; as it was, its labels renamed; Plot is WDrawPoint (RefPlot)

RefLine:
	sta lnMode
	; dx = |r4 - r3|, dy = |r12 - r11|
	lda r4
	sec
	sbc r3
	sta lnDx
	lda r4+1
	sbc r3+1
	sta lnDx+1
	bpl @1
	jsr RefNegDx
@1:	lda r12
	sec
	sbc r11
	sta lnDy
	lda r12+1
	sbc r11+1
	sta lnDy+1
	bpl @2
	jsr RefNegDy
@2:	CmpW lnDx, lnDy
	bcs @flat
	jmp RefSteep
@flat:	; from the left end
	CmpW r4, r3
	bcs @3
	jsr RefSwap
@3:	LoadB lnSy, 1           ; y step: +1 if the right end is lower
	CmpW r12, r11
	bcs @4
	LoadB lnSy, $FF
@4:	jsr RefTerms               ; lnInc1 = 2*dy, lnErr = 2*dy - dx, lnInc2 = 2*(dy - dx)
@fl:	jsr RefPlot
	CmpW r3, r4
	bcs @r
	IncW r3
	lda lnErr+1
	bmi @neg
	jsr RefStepY
	AddW lnInc2, lnErr
	bra @fl
@neg:	AddW lnInc1, lnErr
	bra @fl
@r:	rts

RefSteep:	; from the top end
	CmpW r12, r11
	bcs @1
	jsr RefSwap
@1:	LoadB lnSy, 1           ; x step: +1 if the lower end is right
	CmpW r4, r3
	bcs @2
	LoadB lnSy, $FF
@2:	MoveW lnDx, rTmp        ; the terms with the axes exchanged
	MoveW lnDy, lnDx
	MoveW rTmp, lnDy
	jsr RefTerms
@st:	jsr RefPlot
	CmpW r11, r12
	bcs @r
	IncW r11
	lda lnErr+1
	bmi @neg
	jsr RefStepX
	AddW lnInc2, lnErr
	bra @st
@neg:	AddW lnInc1, lnErr
	bra @st
@r:	rts

; lnInc1 = 2*dy, lnErr = 2*dy - dx, lnInc2 = 2*(dy - dx) (dy the minor axis)
RefTerms:	lda lnDy
	asl
	sta lnInc1
	lda lnDy+1
	rol
	sta lnInc1+1
	lda lnInc1
	sec
	sbc lnDx
	sta lnErr
	lda lnInc1+1
	sbc lnDx+1
	sta lnErr+1
	lda lnDy
	sec
	sbc lnDx
	sta lnInc2
	lda lnDy+1
	sbc lnDx+1
	sta lnInc2+1
	asl lnInc2
	rol lnInc2+1
	rts

; exchange the two points
RefSwap:	ldx #1
@sw:	lda r3,x
	pha
	lda r4,x
	sta r3,x
	pla
	sta r4,x
	lda r11,x
	pha
	lda r12,x
	sta r11,x
	pla
	sta r12,x
	dex
	bpl @sw
	rts

RefNegDx:	lda #0
	sec
	sbc lnDx
	sta lnDx
	lda #0
	sbc lnDx+1
	sta lnDx+1
	rts
RefNegDy:	lda #0
	sec
	sbc lnDy
	sta lnDy
	lda #0
	sbc lnDy+1
	sta lnDy+1
	rts

RefStepX:	lda lnSy
	bmi @l
	IncW r3
	rts
@l:	lda r3
	bne @1
	dec r3+1
@1:	dec r3
	rts

RefStepY:	lda lnSy
	bmi @up
	IncW r11
	rts
@up:	lda r11
	bne @1
	dec r11+1
@1:	dec r11
	rts

; the old Plot: WDrawPoint in the mode
RefPlot:	lda lnMode
	jmp WDrawPoint
