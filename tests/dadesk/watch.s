; gate da: the test program's watch on PSG voice 15 (the beep), from
; intFirstVector (it runs in every interrupt, dialog boxes included:
; DoDlgBox clears intTopVector for its time). VERA's control and port 0's
; address are kept. Each change: its 4 registers and the frame, into a
; ring of 32 that dadesk.c logs from its main loop.
.export _watch_irq, _wring, _whead, _wtail

.segment "BSS"
_wring:	.res 32 * 5
_whead:	.res 1
_wtail:	.res 1
psg:	.res 4
frm:	.res 1
chg:	.res 1

.segment "CODE"
_watch_irq:
	lda $9F25
	pha
	stz $9F25
	lda $9F20
	pha
	lda $9F21
	pha
	lda $9F22
	pha
	lda #$FC
	sta $9F20
	lda #$F9
	sta $9F21
	lda #$11
	sta $9F22
	inc frm
	ldx #0
@l:	lda $9F23
	cmp psg,x
	beq @s
	sta psg,x
	inc chg
@s:	inx
	cpx #4
	bne @l
	lda chg
	beq @o
	stz chg
	lda _whead              ; room in the ring?
	inc
	and #31
	cmp _wtail
	beq @o
	lda _whead
	asl
	asl
	adc _whead              ; x 5
	tax
	ldy #0
@c:	lda psg,y
	sta _wring,x
	inx
	iny
	cpy #4
	bne @c
	lda frm
	sta _wring,x
	lda _whead
	inc
	and #31
	sta _whead
@o:	pla
	sta $9F22
	pla
	sta $9F21
	pla
	sta $9F20
	pla
	sta $9F25
	clc
	rts

; (V91) a counter of interrupts from intTopVector, kept twice: in zero page
; and in RAM. While the program is put aside for an accessory, the kernel
; restores zero page from its copy and RAM from the packed pages: both
; must come back equal (the routine stopped before either was taken), and
; count on after.
.export _count_irq, _count_get, _count_zero, _cget

.zeropage
_zcnt:	.res 2

.segment "BSS"
_rcnt:	.res 2
_cget:	.res 4

.segment "CODE"
_count_irq:
	inc _zcnt
	bne @1
	inc _zcnt+1
@1:	inc _rcnt
	bne @2
	inc _rcnt+1
@2:	rts

; both 0 (zero page is not cleared at the start)
_count_zero:
	stz _zcnt
	stz _zcnt+1
	stz _rcnt
	stz _rcnt+1
	rts

; the two counters at one moment into _cget (zero page's, RAM's)
_count_get:
	php
	sei
	lda _zcnt
	sta _cget
	lda _zcnt+1
	sta _cget+1
	lda _rcnt
	sta _cget+2
	lda _rcnt+1
	sta _cget+3
	plp
	rts
