; Veranda bank G: the clip rectangle (DECISIONS V81)
;
; With clipOn not 0, bank G's drawing touches only the pixels in
; leftMargin .. rightMargin by windowTopW .. windowBottomW: every span goes
; through fb_clip (fb_span's entry), which leaves out a row outside the
; rows, cuts the span to the columns (the cut edges' bytes keep the
; pixels outside, as a span's own edges do; a buffer's bytes move with
; the first column) and puts fbCol, fbCnt, the keep masks and fbBufPtr
; back for the caller's next row. A rectangle goes a row at a time
; through it (ClipRows: no FX block, no bank T columns); a frame's sides
; are bank T's vertical lines, which clip themselves (kernel/t/cols.s). The shell's scene is drawn so, a dirty rectangle at a
; time. With clipOn 0 nothing here runs.
;
; In the LATE segment: the text's loops keep their places (V62).

.include "kernel.inc"

.import fb_calc_off, fb_span, fb_span_off, fbRow, fbCol, fbCnt, fbKeepL, fbKeepR, fbOp, fbPat
.import KeepLeft, KeepRight, yy, yb

.export fb_clip, ClipRows

.segment "BSS"

clL:	.res 1                  ; the clip's first and last columns (2 apart:
	.res 1                  ; leftMargin and rightMargin are)
clR:	.res 1
clLast:	.res 1                  ; the span's last column

.segment "LATE"

;---------------------------------------------------------------
; fb_clip: fb_span with the clip on (fbRow, fbCol, fbCnt, the masks)
;---------------------------------------------------------------
fb_clip:
	lda fbCnt
	beq @r0
	CmpW fbRow, windowTopW
	bcc @r0
	CmpW windowBottomW, fbRow
	bcs @in
@r0:	rts
@in:	ldx #2                  ; the columns: margin / 8 (x 2: right, 0: left)
@m:	lda leftMargin+1,x
	asl
	asl
	asl
	asl
	asl
	sta clL,x
	lda leftMargin,x
	lsr
	lsr
	lsr
	ora clL,x
	sta clL,x
	dex
	dex
	bpl @m
	lda fbCol               ; strictly inside the clip's columns: as it is
	cmp clL
	beq @k
	bcc @k
	clc
	adc fbCnt
	cmp clR                 ; (fbCol + fbCnt <= clR: its last byte < clR)
	beq @a
	bcs @k
@a:	jsr fb_calc_off
	jmp fb_span_off
@k:	ldx #3                  ; the span kept: fbCol, fbCnt, fbKeepL, fbKeepR
@s:	lda fbCol,x
	pha
	dex
	bpl @s
	lda fbBufPtr
	pha
	lda fbBufPtr+1
	pha
	lda fbCol
	clc
	adc fbCnt
	dea
	sta clLast
	cmp clL                 ; wholly left or right of the clip: nothing
	bcc @out
	lda clR
	cmp fbCol
	bcc @out
	; the left edge
	lda leftMargin
	and #7
	tax
	lda KeepLeft,x
	ldx fbCol
	cpx clL
	bcc @cut
	bne @right              ; (starts right of it: as it is)
	ora fbKeepL             ; starts in its byte: both masks
	sta fbKeepL
	bra @right
@cut:	sta fbKeepL             ; starts left of it: from its byte on
	lda clL
	sec
	sbc fbCol
	tax
	clc
	adc fbBufPtr
	sta fbBufPtr
	bcc @c1
	inc fbBufPtr+1
@c1:	stx fbCol               ; (the cut: fbCnt - x)
	lda fbCnt
	sec
	sbc fbCol
	sta fbCnt
	lda clL
	sta fbCol
@right:	lda rightMargin
	and #7
	tax
	lda KeepRight,x
	ldx clLast
	cpx clR
	bcc @go                 ; (ends left of it: as it is)
	beq @eq
	sta fbKeepR             ; ends right of it: up to its byte
	lda clR
	sec
	sbc fbCol
	ina
	sta fbCnt
	bra @go
@eq:	ora fbKeepR
	sta fbKeepR
@go:	jsr fb_calc_off
	jsr fb_span_off
@out:	pla
	sta fbBufPtr+1
	pla
	sta fbBufPtr
	ldx #0
@rs:	pla
	sta fbCol,x
	inx
	cpx #4
	bne @rs
	rts

;---------------------------------------------------------------
; ClipRows: a rectangle's rows yy .. yb (RectRows: fbOp, fbSel, the
; span set) a row at a time through fb_clip
;---------------------------------------------------------------
ClipRows:
@row:	MoveW yy, fbRow
	lda yy
	and #7
	tay
	lda (curPattern),y
	sta fbPat
	jsr fb_span
	CmpW yy, yb
	beq @r
	IncW yy
	bra @row
@r:	rts

