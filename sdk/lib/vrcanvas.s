; Veranda SDK: the canvas (vrcanvas.h; DECISIONS V166)
;
; The kernel's canvas mode (ColorRect COLOR_CANVAS) for a program: the
; cover routine the kernel calls for menus and dialog boxes (a = 0 cover,
; 1 uncover; the cards in area), which counts each card's covers, zeroes
; the picture's bytes under a cover and calls the program's repaint
; routine for the cards whose last cover went; asideVector's routine
; (the picture's VRAM zeroed: CANV_TIDY; noted for vr_canvas_back).
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.importzp ptr1, ptr2, tmp1, tmp2, tmp3, tmp4
.import popa, popax
.export _vr_canvas_on, _vr_canvas_off, _vr_canvas_back, _vr_canvas_covered, _vr_canvas_palette
.export _vr_canvas_area, _vr_canvas_covers

CANV_ON   = 0
CANV_TIDY = 1
TB        = (VR_CANVAS_ADDR >> 11) << 2
VR_CANVAS_ADDR = $02800

.segment "DATA"

back:	.byte 0                 ; 1: asideVector was called
old:	.word 0                 ; the asideVector found
rep:	.word 0                 ; the program's repaint routine

.segment "BSS"

kbuf:	.res 4                  ; the kernel's cards: x, width, y, height
_vr_canvas_area: .res 4
_vr_canvas_covers: .res 1       ; the menus and boxes over the picture now
cnt:	.res 40 * 30            ; each card's covers
op:	.res 1
cy:	.res 1                  ; the row
cx:	.res 1
run:	.res 1                  ; a run's first card ($FF: none)

.segment "CODE"

;---------------------------------------------------------------
; vr_canvas_on(repaint): 0, or the kernel's error
;---------------------------------------------------------------
_vr_canvas_on:
	sta rep
	stx rep+1
	stz _vr_canvas_covers
	LoadW ptr1, cnt         ; no covers
	ldx #>(40 * 30 + 255)
	ldy #0
	tya
@z:	sta (ptr1),y
	iny
	bne @z
	inc ptr1+1
	dex
	bne @z
	LoadW r0, Cover
	LoadW r1, kbuf
	lda #COLOR_CANVAS
	ldx #CANV_ON
	jsr ColorRect
	txa
	bne @r
	lda asideVector         ; the switcher noted (the vector found called
	ldx asideVector+1       ; after)
	cmp #<Aside
	bne @v
	cpx #>Aside
	beq @n
@v:	sta old
	stx old+1
	LoadW asideVector, Aside
@n:	stz back
	lda #0
@r:	ldx #0
	rts

;---------------------------------------------------------------
_vr_canvas_off:
	lda VERA_L0_TILEBASE
	cmp #TB
	bne @a
	lda #$FF
	jsr ColorRect
@a:	lda asideVector
	cmp #<Aside
	bne @r
	lda asideVector+1
	cmp #>Aside
	bne @r
	MoveW old, asideVector
@r:	rts

;---------------------------------------------------------------
_vr_canvas_back:
	lda back
	beq @r
	stz back
	lda #1
@r:	ldx #0
	rts

; asideVector: the picture's VRAM zeroed (the kernel's CANV_TIDY)
Aside:	lda #1
	sta back
	lda #COLOR_CANVAS
	ldx #CANV_TIDY
	jsr ColorRect
	lda old
	ora old+1
	beq @r
	jmp (old)
@r:	rts

;---------------------------------------------------------------
; vr_canvas_covered(x, y)
;---------------------------------------------------------------
_vr_canvas_covered:
	sta tmp1                ; y
	jsr popa
	sta tmp2                ; x
	lda tmp1
	jsr RowP                ; ptr1 = cnt + 40 y
	ldy tmp2
	lda (ptr1),y
	ldx #0
	rts

; ptr1 = cnt + 40 a
RowP:	sta ptr1
	stz ptr1+1
	asl ptr1                ; 8 y
	asl ptr1
	asl ptr1
	rol ptr1+1
	lda ptr1                ; + 32 y = 8 y + 4 * 8 y
	ldx ptr1+1
	asl ptr1
	rol ptr1+1
	asl ptr1
	rol ptr1+1
	clc
	adc ptr1
	sta ptr1
	txa
	adc ptr1+1
	sta ptr1+1
	lda ptr1
	clc
	adc #<cnt
	sta ptr1
	lda ptr1+1
	adc #>cnt
	sta ptr1+1
	rts

;---------------------------------------------------------------
; the kernel's cover routine: a = 0 cover, 1 uncover; kbuf the cards
; (clipped). r0-r15 kept (the kernel's menu code holds them).
;---------------------------------------------------------------
Cover:	sta op
	tax                     ; the covers in place
	bne @dn
	inc _vr_canvas_covers
	bra @k
@dn:	lda _vr_canvas_covers
	beq @k
	dec _vr_canvas_covers
@k:	lda kbuf+1
	beq @r
	lda kbuf+3
	beq @r
	lda kbuf+2
	sta cy
@row:	lda cy
	jsr RowP
	lda op
	bne @un
	ldy kbuf                ; a cover: each card's count up, its bytes 0
	ldx kbuf+1
@c:	lda (ptr1),y
	ina
	beq @c1                 ; (255 at most)
	sta (ptr1),y
@c1:	iny
	dex
	bne @c
	jsr Zero
	bra @nx
@un:	LoadB run, $FF          ; uncovered: the counts down; the runs of
	lda kbuf                ; cards at 0 now drawn again
	sta cx
	ldx kbuf+1
@u:	ldy cx
	lda (ptr1),y
	beq @u0                 ; (not covered: nothing)
	dea
	sta (ptr1),y
	bne @u0
	lda run                 ; a card back: in a run
	bpl @u1
	sty run
	bra @u1
@u0:	jsr Flush               ; (the run ends before this card)
@u1:	inc cx
	dex
	bne @u
	jsr Flush
@nx:	inc cy
	lda kbuf+2
	clc
	adc kbuf+3
	cmp cy
	bne @row
@r:	rts

; the run from `run` to cx - 1 in row cy to the program's repaint
Flush:	lda run
	bmi @r
	sta _vr_canvas_area
	lda cx
	sec
	sbc run
	sta _vr_canvas_area+1
	lda cy
	sta _vr_canvas_area+2
	lda #1
	sta _vr_canvas_area+3
	LoadB run, $FF
	lda rep
	ora rep+1
	beq @r
	phx
	lda ptr1                ; (the C routine uses cc65's zero page)
	pha
	lda ptr1+1
	pha
	ldx #31                 ; and may use r0-r15: kept
@k:	lda r0,x
	pha
	dex
	bpl @k
	jsr @go
	ldx #0
@b:	pla
	sta r0,x
	inx
	cpx #32
	bne @b
	pla
	sta ptr1+1
	pla
	sta ptr1
	plx
@r:	rts
@go:	jmp (rep)

; the picture's rows of card row cy, cards kbuf .. + width, zeroed
Zero:	phx
	lda cy                  ; the first pixel row: 8 cy
	asl
	asl
	asl
	sta tmp3
	LoadB tmp4, 8
@line:	; VR_CANVAS + 320 r + 8 x = $2800 + 256 r + 64 r + 8 x
	stz ptr2+1
	lda tmp3
	sta ptr2
	asl ptr2                ; 64 r
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	lda kbuf                ; + 8 x
	stz tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	clc
	adc ptr2
	sta VERA_ADDR_L
	lda ptr2+1
	adc tmp1
	sta tmp1
	lda tmp3                ; + 256 r + $2800
	clc
	adc #>VR_CANVAS_ADDR
	stz tmp2
	bcc @h
	inc tmp2
@h:	clc
	adc tmp1
	bcc @h1
	inc tmp2
@h1:	stz VERA_CTRL
	sta VERA_ADDR_M
	lda tmp2
	ora #VERA_INC1
	sta VERA_ADDR_H
	lda kbuf+1              ; 8 bytes a card
	tax
@b:	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	dex
	bne @b
	inc tmp3
	dec tmp4
	bne @line
	plx
	rts

;---------------------------------------------------------------
; vr_canvas_palette(pal, first, n): entries 17-20 skipped
;---------------------------------------------------------------
_vr_canvas_palette:
	sta tmp1                ; n
	jsr popa
	sta tmp2                ; first
	jsr popax
	sta ptr1
	stx ptr1+1
	lda tmp1
	beq @r
@e:	lda tmp2
	cmp #17
	bcc @w
	cmp #21
	bcc @s
@w:	stz VERA_CTRL           ; VRAM_PALETTE + 2 entry
	asl
	sta VERA_ADDR_L
	lda #>(VRAM_PALETTE & $FFFF)
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldy #0
	lda (ptr1),y
	sta VERA_DATA0
	iny
	lda (ptr1),y
	sta VERA_DATA0
@s:	lda ptr1
	clc
	adc #2
	sta ptr1
	bcc @1
	inc ptr1+1
@1:	inc tmp2
	dec tmp1
	bne @e
@r:	rts
