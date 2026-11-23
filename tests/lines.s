; gate gfx1: WDrawLine (DECISIONS V159), run as TEST.PRG
;
; Built twice: as it is the lines go through the kernel's WDrawLine, with
; -D REF through RefLine below, WDrawLine before V159 (the midpoint rule,
; each point through WDrawPoint, which is the old line's Plot) as it was.
; Both runs draw the same random lines in the three modes (640 x 480, 640
; x 240, 320 x 240), each mode's screens first filled with noise (the two
; screens different): ends on the screen, off it, far off it (16 bits); the
; modes ink, erase, recover and any byte; dispBufferOn any of the four
; screen choices; the clip off or on (a random rectangle, sometimes past
; the screen, sometimes with 11-bit margins); and log after each line r3,
; r4, r11, r12, every 16 lines a sum of both screens. The gate compares
; the two consoles and the two VRAM dumps: they must be the same.
;
; With -D TIME: the timings instead (TIME <name> <cycles, hex>), 640 x
; 480, interrupts off, 20 lines each: a flat line at 45 degrees (400
; points), a shallow one (640 points), a steep one (480 points), each on
; both screens, the foreground, the back screen and a recover.
; Console: L <case> <r3> <r4> <r11> <r12>, S <case> <sum>, LINES DONE.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

NCASE = 700                     ; lines a mode

.segment "CODE"

Start:
	lda #10                 ; (a line of its own)
	sta EMU_STDOUT
.ifdef TIME
	jmp Timings
.endif
	ldx #0
@mode:	stx mi
	lda Modes,x
	jsr SetVideoMode
	jsr Noise
	stz ncase
	stz ncase+1
@case:	jsr Pick
.ifdef REF
	lda mode
	jsr RefLine
.else
	lda mode
	jsr WDrawLine
.endif
	stz clipOn
	; L case r3 r4 r11 r12
	lda #'L'
	jsr Chr
	jsr Case
	ldx #0
@r:	lda r3+1,x
	jsr LogHex
	lda r3,x
	jsr LogHex
	jsr Space
	inx
	inx
	cpx #4
	bne @r1
	ldx #r11 - r3
@r1:	cpx #r11 - r3 + 4
	bne @r
	lda #10
	sta EMU_STDOUT
	lda ncase
	and #15
	bne @n
	jsr LogSum
@n:	inc ncase
	bne @n1
	inc ncase+1
@n1:	lda ncase
	cmp #<NCASE
	bne @again
	lda ncase+1
	cmp #>NCASE
	beq @end
@again:	jmp @case
@end:	jsr LogSum
	ldx mi
	inx
	cpx #3
	bne @mode
	LoadW r15, MsgDone
	jsr Log15
	lda #10
	sta EMU_STDOUT
Quit:	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Modes:	.byte MODE_640x480, MODE_640x240, MODE_320x240

; "S case sum"
LogSum:	lda #'S'
	jsr Chr
	jsr Case
	jsr SumScreens
	lda s2
	jsr LogHex
	lda s1
	jsr LogHex
	lda #10
	sta EMU_STDOUT
	rts
Case:	jsr Space
	lda mi
	jsr LogHex
	lda ncase+1
	jsr LogHex
	lda ncase
	jsr LogHex
	jmp Space

;---------------------------------------------------------------
; a random line: r3, r11, r4, r12, mode, dispBufferOn, the clip
;---------------------------------------------------------------
Pick:	ldx #0
@p:	phx
	jsr Coord               ; x: 0 .. width - 1 mostly
	plx
	lda rv
	sta r3,x
	lda rv+1
	sta r3+1,x
	phx
	jsr CoordY
	plx
	lda rv
	sta r11,x
	lda rv+1
	sta r11+1,x
	inx
	inx
	cpx #4
	bne @p
	jsr Rnd                 ; 1/8: the second end near the first
	and #7
	bne @m
	jsr Rnd
	and #15
	sec
	sbc #8
	sta dt
	ldx #0
	ldy #0
	jsr Near
	ldy #r11 - r3
	jsr Near
@m:	jsr Rnd                 ; the mode: ink, erase, recover, any byte
	and #3
	tax
	lda MTab,x
	cpx #3
	bne @m1
	jsr Rnd
@m1:	sta mode
	jsr Rnd                 ; the screens (and noise in the other bits)
	sta dispBufferOn
	jsr Rnd                 ; the clip: 1/3
	cmp #$55
	bcc @cl
	rts
@cl:
	jsr Rnd
	ora #1
	sta clipOn
	jsr Coord
	MoveW rv, leftMargin
	jsr Coord
	MoveW rv, rightMargin
	jsr CoordY
	MoveW rv, windowTopW
	jsr CoordY
	MoveW rv, windowBottomW
	jsr Rnd                 ; (1/2: left <= right, top <= bottom)
	bmi @k
	CmpW rightMargin, leftMargin
	bcs @k1
	ldx leftMargin
	ldy leftMargin+1
	MoveW rightMargin, leftMargin
	stx rightMargin
	sty rightMargin+1
@k1:	CmpW windowBottomW, windowTopW
	bcs @k
	ldx windowTopW
	ldy windowTopW+1
	MoveW windowBottomW, windowTopW
	stx windowBottomW
	sty windowBottomW+1
@k:	jsr Rnd                 ; 1/16: margins with bits above 11
	and #15
	bne @nc
	jsr Rnd
	and #$F8
	ora leftMargin+1
	sta leftMargin+1
	jsr Rnd
	and #$F8
	ora rightMargin+1
	sta rightMargin+1
@nc:	rts
MTab:	.byte DRAW_INK, DRAW_ERASE, DRAW_RECOVER, 0

; the second end (r4 + x / r12 + y) = the first + dt
Near:	lda dt
	pha
	clc
	adc r3,y
	sta r4,y
	pla
	and #$80
	beq @1
	lda #$FF
@1:	adc r3+1,y
	sta r4+1,y
	rts

; rv: a coordinate on the axis of size sz (Coord: x, CoordY: y): 3/4 on
; the screen, 3/16 within 40 of it, 1/64 anywhere
Coord:	MoveW screenWidth, sz
	bra Co
CoordY:	MoveW screenHeight, sz
Co:	jsr Rnd
	and #63
	beq @any
	cmp #12
	bcc @near
@on:	jsr Rnd                 ; 0 .. sz - 1
	sta rv
	jsr Rnd
	and #3
	sta rv+1
	CmpW rv, sz
	bcs @on
	rts
@near:	jsr Rnd                 ; -40 .. -1 or sz .. sz + 39
	and #63
	cmp #40
	bcs @near
	sta rv
	stz rv+1
	jsr Rnd
	bmi @neg
	lda rv
	clc
	adc sz
	sta rv
	lda sz+1
	adc #0
	sta rv+1
	rts
@neg:	lda #0
	sec
	sbc rv
	sta rv
	lda #0
	sbc #0
	sta rv+1
	rts
@any:	jsr Rnd
	sta rv
	jsr Rnd
	sta rv+1
	rts

;---------------------------------------------------------------
; both screens: noise (the two different)
;---------------------------------------------------------------
Noise:	LoadW nseed, $4C1D
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	LoadB VERA_ADDR_H, VERA_INC1
	lda #1
	sta VERA_CTRL
	stz VERA_ADDR_L
	LoadB VERA_ADDR_M, >VRAM_BG
	LoadB VERA_ADDR_H, VERA_INC1
	stz VERA_CTRL
	jsr Bytes
@n:	jsr NRnd
	sta VERA_DATA0
	jsr NRnd
	sta VERA_DATA1
	jsr Count
	bne @n
	rts

; kn = the bytes of a screen (width / 8 * height)
Bytes:	MoveW screenWidth, kn
	lsr kn+1
	ror kn
	lsr kn+1
	ror kn
	lsr kn+1
	ror kn
	MoveW screenHeight, sz
	MoveW kn, rv
	stz kn
	stz kn+1
@m:	lda kn
	clc
	adc rv
	sta kn
	lda kn+1
	adc rv+1
	sta kn+1
	lda sz
	bne @1
	dec sz+1
@1:	dec sz
	lda sz
	ora sz+1
	bne @m
	rts

; kn - 1, z set at 0
Count:	lda kn
	bne @1
	dec kn+1
@1:	dec kn
	lda kn
	ora kn+1
	rts

; s1, s2: a sum of both screens' bytes
SumScreens:
	stz s1
	stz s2
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	LoadB VERA_ADDR_H, VERA_INC1
	lda #1
	sta VERA_CTRL
	stz VERA_ADDR_L
	LoadB VERA_ADDR_M, >VRAM_BG
	LoadB VERA_ADDR_H, VERA_INC1
	stz VERA_CTRL
	jsr Bytes
@n:	lda VERA_DATA0
	jsr Add
	lda VERA_DATA1
	jsr Add
	jsr Count
	bne @n
	rts
Add:	clc
	adc s1
	sta s1
	clc
	adc s2
	sta s2
	rts

;---------------------------------------------------------------
; the timings
;---------------------------------------------------------------
.ifdef TIME
Timings:
	lda #MODE_640x480
	jsr SetVideoMode
	ldx #0
@t:	stx tn
	lda TSel,x
	sta dispBufferOn
	lda TMode,x
	sta mode
	sei
	sta EMU_CLOCK
	LoadB kc, 20
@l:	ldx tn
	lda TLine,x
	tay
	ldx #0
@c:	lda LDesc,y
	sta r3,x
	iny
	inx
	cpx #4
	bne @c1
	ldx #r11 - r3
@c1:	cpx #r11 - r3 + 4
	bne @c
	lda mode
	jsr WDrawLine
	dec kc
	bne @l
	jsr Latch
	cli
	LoadW r15, MsgTime
	jsr Log15
	lda tn
	asl
	tax
	lda TName,x
	sta r15L
	lda TName+1,x
	sta r15H
	jsr Log15
	jsr Space
	ldx #3
@h:	lda clk,x
	jsr LogHex
	dex
	bpl @h
	lda #10
	sta EMU_STDOUT
	ldx tn
	inx
	cpx #NT
	bne @t
	LoadW r15, MsgDone
	jsr Log15
	lda #10
	sta EMU_STDOUT
	jmp Quit

Latch:	lda EMU_CLOCK
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	rts

NT = 12
; each: the line (LDesc offset), dispBufferOn, the mode
TLine:	.byte 0, 0, 0, 0, 8, 8, 8, 8, 16, 16, 16, 16
TSel:	.byte $C0, $80, $40, $80, $C0, $80, $40, $80, $C0, $80, $40, $80
TMode:	.byte 1, 1, 1, DRAW_RECOVER, 1, 1, 1, DRAW_RECOVER, 1, 1, 1, DRAW_RECOVER
; r3 r4 r11 r12
LDesc:	.word 10, 409, 10, 409          ; flat, 45 degrees: 400 points
	.word 0, 639, 100, 140          ; shallow: 640
	.word 300, 340, 0, 479          ; steep: 480
TName:	.word N0, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11
N0:	.byte "d45_both", 0
N1:	.byte "d45_fore", 0
N2:	.byte "d45_back", 0
N3:	.byte "d45_recover", 0
N4:	.byte "flat_both", 0
N5:	.byte "flat_fore", 0
N6:	.byte "flat_back", 0
N7:	.byte "flat_recover", 0
N8:	.byte "steep_both", 0
N9:	.byte "steep_fore", 0
N10:	.byte "steep_back", 0
N11:	.byte "steep_recover", 0
MsgTime: .byte "TIME ", 0
.endif

;---------------------------------------------------------------
; RefLine: WDrawLine before V159, as it was (Plot: WDrawPoint)
;---------------------------------------------------------------
.ifdef REF
.include "lines_ref.s"
.endif

;---------------------------------------------------------------
; the generators and the console
;---------------------------------------------------------------
Rnd:	lda rs
	asl
	rol rs+1
	bcc @1
	eor #$2D
@1:	sta rs
	eor rs+1
	rts
NRnd:	lda nseed
	asl
	rol nseed+1
	bcc @1
	eor #$39
@1:	sta nseed
	adc nseed+1
	rts

Log15:	ldy #0
@1:	lda (r15),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts
Chr:	sta EMU_STDOUT
	rts
Space:	lda #' '
	sta EMU_STDOUT
	rts
LogHex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	sta EMU_STDOUT
	rts

.segment "RODATA"

MsgDone: .byte "LINES DONE", 0

.segment "DATA"

rs:	.word $5EED

.segment "BSS"

mi:	.res 1
ncase:	.res 2
mode:	.res 1
rv:	.res 2
sz:	.res 2
dt:	.res 1
nseed:	.res 2
kn:	.res 2
s1:	.res 1
s2:	.res 1
tn:	.res 1
kc:	.res 1
clk:	.res 4
; RefLine's
lnMode:	.res 1
lnDx:	.res 2
lnDy:	.res 2
lnErr:	.res 2
lnInc1:	.res 2
lnInc2:	.res 2
lnSy:	.res 1
rTmp:	.res 2
