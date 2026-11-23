; gate gfx1 (phase 1): drawing at 640x480, run as TEST.PRG
;
; 1. timings (emulator cycle counter, 8 MHz): full-screen fill (and 4-635
;    in a grey: row by row; the whole screen in the grey), full-screen
;    copy, 256 calls into a kernel bank against 256 resident calls
; 2. the scene (both screens unless said): the same shape at y 20 and at
;    y 320 (rows past 255); RecoverRectangle and ImprintRectangle; CopyRect
;    of the shape; ScrollRect up by 5; TestPoint results
; 3. VRAM dump and exit; tests/check_gfx1.py checks the dump
;
; Console: TIME <name> <cycles, hex> lines, TP <bits>, GFX1 DONE.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:
	; ---- timings: the foreground only
	LoadB dispBufferOn, ST_WR_FORE
	lda #1
	jsr SetPattern
	jsr ClockStart
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	ldx #<NFill
	ldy #>NFill
	jsr ClockReport
	lda #2                  ; rows of 78 bytes, a grey (not one stream)
	jsr SetPattern
	jsr ClockStart
	LoadW r3, 4
	LoadW r11, 0
	LoadW r4, 635
	LoadW r12, 479
	jsr WRectangle
	ldx #<NFill2
	ldy #>NFill2
	jsr ClockReport
	jsr ClockStart          ; the whole screen in the grey
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	ldx #<NFill3
	ldy #>NFill3
	jsr ClockReport
	lda #1
	jsr SetPattern
	jsr ClockStart
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle          ; (ink again, as before)
	jsr ClockStart
	LoadB r3L, 0            ; full screen, one row down
	LoadB r3H, 80
	LoadW r11, 0
	LoadW r12, 479
	LoadB r4L, 0
	LoadW r13, 1
	jsr CopyRect
	ldx #<NCopy
	ldy #>NCopy
	jsr ClockReport
	jsr ClockStart
	ldx #0
@b:	phx
	lda #0
	jsr SetPattern          ; in bank G
	plx
	dex
	bne @b
	ldx #<NBank
	ldy #>NBank
	jsr ClockReport
	jsr ClockStart
	ldx #0
@r:	phx
	jsr GetVersion          ; resident
	plx
	dex
	bne @r
	ldx #<NRes
	ldy #>NRes
	jsr ClockReport

	; text: 10 lines of 100 characters, the system font, foreground only
	jsr UseSystemFont
	LoadW yt, 20
	.byte $CB                ; WAI: start just after an interrupt: the count of
				; interrupts in the run does not depend on what came before
	jsr ClockStart
	LoadB kn, 10
@tl:	LoadW r0, Line100
	LoadW r11, 0
	MoveW yt, r12
	jsr WPutString
	AddVW 10, yt
	dec kn
	bne @tl
	ldx #<NText
	ldy #>NText
	jsr ClockReport
	; PutCards (API 2): a full screen, 60 lines of 80 characters
	LoadW yt, 0
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 60
@cl:	LoadW r0, Line100
	LoadW r1, CFont
	LoadB r3L, 0
	LoadB r3H, 80
	MoveW yt, r11
	lda #0
	jsr PutCards
	AddVW 8, yt
	dec kn
	bne @cl
	ldx #<NCards
	ldy #>NCards
	jsr ClockReport

	; window operations (DECISIONS V80), a 384 x 312 window at x 101-484,
	; y 80-391: the drag's outline step (its erase and draw: four
	; InvertRectangle each, the foreground only, as the shell's xorFrame);
	; a frame, a vertical line and the window's shadow (6 pixels wide) on
	; both screens; the window moved (CopyRect, 48 cards of 312 rows, both
	; screens); a menu's area (160 x 160) recovered from the back screen
	lda #MODE_640x480
	jsr SetVideoMode
	LoadB dispBufferOn, ST_WR_FORE
	jsr ClockStart
	jsr XorFrame
	jsr XorFrame
	ldx #<NOutline
	ldy #>NOutline
	jsr ClockReport
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	jsr ClockStart
	LoadW r3, 101
	LoadW r4, 484
	LoadW r11, 80
	LoadW r12, 391
	lda #$FF
	jsr WFrameRectangle
	ldx #<NFrame
	ldy #>NFrame
	jsr ClockReport
	jsr ClockStart
	LoadW r4, 300
	LoadW r11, 80
	LoadW r12, 391
	lda #$FF
	jsr WVerticalLine
	ldx #<NVLine
	ldy #>NVLine
	jsr ClockReport
	lda #2
	jsr SetPattern
	jsr ClockStart
	LoadW r3, 485
	LoadW r4, 490
	LoadW r11, 86
	LoadW r12, 397
	jsr WRectangle
	ldx #<NShadow
	ldy #>NShadow
	jsr ClockReport
	jsr ClockStart
	LoadB r3L, 12
	LoadB r3H, 48
	LoadW r11, 80
	LoadW r12, 312
	LoadB r4L, 22
	LoadW r13, 160
	jsr CopyRect
	ldx #<NMove
	ldy #>NMove
	jsr ClockReport
	LoadB dispBufferOn, ST_WR_FORE
	jsr ClockStart
	LoadW r3, 200
	LoadW r4, 359
	LoadW r11, 20
	LoadW r12, 179
	jsr WRecoverRectangle
	ldx #<NRecover
	ldy #>NRecover
	jsr ClockReport

	; window operations, second batch (DECISIONS V81): 10 lines of 100
	; characters in the UI font (bank T's rows, the system font's loop), the
	; same in bold; 100 UseFont (the UI font) and UseSystemFont pairs; 100
	; tiles (4 cards by 32 rows, both screens) as raw rows (WBitmapUp's
	; height bit 15) and compacted (two literal runs); 100 strings of 11
	; characters in the UI font with the clip on, in a clip that holds
	; them, and in one right of them (skipped)
	LoadB dispBufferOn, ST_WR_FORE
	lda #FONT_UI
	jsr UseFont
	jsr UiLines
	ldx #<NUi
	ldy #>NUi
	jsr ClockReport
	LoadB currentMode, SET_BOLD
	jsr UiLines
	stz currentMode
	ldx #<NUiB
	ldy #>NUiB
	jsr ClockReport
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 100
@uf:	lda #FONT_UI
	jsr UseFont
	jsr UseSystemFont
	dec kn
	bne @uf
	ldx #<NUse
	ldy #>NUse
	jsr ClockReport
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 100
@rt:	LoadW r0, TileRaw
	LoadB r1L, 10
	LoadB r2L, 4
	LoadW r11, 200
	LoadW r12, $8000 | 32
	jsr WBitmapUp
	dec kn
	bne @rt
	ldx #<NRaw
	ldy #>NRaw
	jsr ClockReport
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 100
@ct:	LoadW r0, TileUp
	LoadB r1L, 10
	LoadB r2L, 4
	LoadW r11, 200
	LoadW r12, 32
	jsr WBitmapUp
	dec kn
	bne @ct
	ldx #<NUp
	ldy #>NUp
	jsr ClockReport
	LoadB dispBufferOn, ST_WR_BACK
	lda #FONT_UI
	jsr UseFont
	LoadW leftMargin, 0
	LoadW rightMargin, 639
	jsr ClipStrings
	ldx #<NClipIn
	ldy #>NClipIn
	jsr ClockReport
	LoadW leftMargin, 400
	jsr ClipStrings
	ldx #<NClipOut
	ldy #>NClipOut
	jsr ClockReport
	LoadW leftMargin, 0
	jsr UseSystemFont

	; ---- the scene
	lda #MODE_640x480       ; clears both screens
	jsr SetVideoMode
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadW y0, 20
	jsr Shape
	LoadW y0, 320
	jsr Shape
	; RecoverRectangle: ink on the foreground only, then recovered from the
	; (empty) back screen
	LoadB dispBufferOn, ST_WR_FORE
	lda #1
	jsr SetPattern
	LoadW r3, 16
	LoadW r4, 80
	LoadW r11, 200
	LoadW r12, 230
	jsr WRectangle
	jsr WRecoverRectangle
	; ImprintRectangle: ink on the foreground only, then copied back
	LoadW r3, 300
	LoadW r4, 340
	LoadW r11, 200
	LoadW r12, 220
	jsr WRectangle
	jsr WImprintRectangle
	; CopyRect: cards 2-26 of rows 20-80 to card 40, row 140 (both screens)
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadB r3L, 2
	LoadB r3H, 25
	LoadW r11, 20
	LoadW r12, 61
	LoadB r4L, 40
	LoadW r13, 140
	jsr CopyRect
	; ScrollRect: a line on row 410, cards 60-79, rows 400-479 up by 5
	LoadW r3, 480
	LoadW r4, 639
	LoadW r11, 410
	lda #$FF
	jsr WHorizontalLine
	LoadB r3L, 60
	LoadB r3H, 20
	LoadW r11, 400
	LoadW r12, 479
	LoadW r13, -5
	lda #0
	jsr ScrollRect
	; system font text (its fast path), checked against tools/mkfont.py
	jsr UseSystemFont
	LoadW r0, SysText
	LoadW r11, 100
	LoadW r12, 450
	jsr WPutString
	; PutCards (API 2), checked by tests/check_gfx1.py: (a) both screens,
	; an unaligned row; (b) reverse and bold, the foreground; (c) the clip
	; window's rows 262-265 only; (d) clipped at the right edge; (e) up to a 0
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadW r0, CardA
	LoadW r1, CFont
	LoadB r3L, 1
	LoadB r3H, 8
	LoadW r11, 241
	lda #0
	jsr PutCards
	LoadB dispBufferOn, ST_WR_FORE
	LoadW r0, CardB
	LoadW r1, CFont
	LoadB r3L, 20
	LoadB r3H, 4
	LoadW r11, 250
	lda #3
	jsr PutCards
	MoveW windowTopW, kr    ; (the window's variables: WSetWindow is not there yet)
	MoveW windowBottomW, y0
	LoadW windowTopW, 262
	LoadW windowBottomW, 265
	LoadW r0, CardB
	LoadW r1, CFont
	LoadB r3L, 30
	LoadB r3H, 4
	LoadW r11, 260
	lda #0
	jsr PutCards
	MoveW kr, windowTopW
	MoveW y0, windowBottomW
	LoadW r0, CardA
	LoadW r1, CFont
	LoadB r3L, 76
	LoadB r3H, 8
	LoadW r11, 280
	lda #0
	jsr PutCards
	LoadW r0, CardE
	LoadW r1, CFont
	LoadB r3L, 40
	LoadB r3H, 20
	LoadW r11, 290
	lda #1
	jsr PutCards
	; TestPoint: (16,20) is ink (pattern 2 row 4 = $AA), (17,20) paper,
	; (639,0) paper, (220,320) ink (the line's first point)
	LoadW r0, MsgTP
	jsr LogText
	ldx #0
@tp:	lda TPx,x
	sta r3L
	lda TPxH,x
	sta r3H
	lda TPy,x
	sta r11L
	lda TPyH,x
	sta r11H
	phx
	jsr WTestPoint
	plx
	ora #'0'
	sta EMU_STDOUT
	inx
	cpx #4
	bne @tp
	lda #10
	sta EMU_STDOUT
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; the shape, with its top at y0
Shape:
	lda #2
	jsr SetPattern
	LoadW r3, 16
	LoadW r4, 199
	MoveW y0, r11
	lda y0
	clc
	adc #59
	sta r12
	lda y0+1
	adc #0
	sta r12+1
	jsr WRectangle
	LoadW r3, 8             ; frame around it
	LoadW r4, 207
	MoveW r12, kr
	lda y0
	sec
	sbc #4
	sta r11
	lda y0+1
	sbc #0
	sta r11+1
	AddVW 4, r12
	lda #$FF
	jsr WFrameRectangle
	LoadW r3, 220           ; an X of two lines
	MoveW y0, r11
	LoadW r4, 400
	MoveW y0, r12
	AddVW 60, r12
	lda #DRAW_INK
	jsr WDrawLine
	LoadW r3, 400
	MoveW y0, r11
	LoadW r4, 220
	MoveW y0, r12
	AddVW 60, r12
	lda #DRAW_INK
	jsr WDrawLine
	LoadW r4, 410           ; a dotted vertical line
	MoveW y0, r11
	MoveW y0, r12
	AddVW 60, r12
	lda #$AA
	jsr WVerticalLine
	LoadW r3, 420           ; a horizontal line with a pattern byte
	LoadW r4, 600
	MoveW y0, r11
	AddVW 30, r11
	lda #$F0
	jsr WHorizontalLine
	LoadW r3, 100           ; an inverted band
	LoadW r4, 300
	MoveW y0, r11
	AddVW 10, r11
	MoveW y0, r12
	AddVW 40, r12
	jsr WInvertRectangle
	LoadB kn, 0             ; points: x 610 + i, y0 + 2i
@p:	lda kn
	clc
	adc #<610
	sta r3
	lda #>610
	adc #0
	sta r3+1
	lda kn
	asl
	clc
	adc y0
	sta r11
	lda y0+1
	adc #0
	sta r11+1
	lda #DRAW_INK
	jsr WDrawPoint
	inc kn
	lda kn
	cmp #10
	bne @p
	rts

; the shell's drag outline (shell/mouse.c xorFrame): x 101-484, y 80-391
XorFrame:
	LoadW r3, 101
	LoadW r4, 484
	LoadW r11, 80
	LoadW r12, 80
	jsr WInvertRectangle
	LoadW r11, 391
	LoadW r12, 391
	jsr WInvertRectangle
	LoadW r4, 101
	LoadW r11, 81
	LoadW r12, 390
	jsr WInvertRectangle
	LoadW r3, 484
	LoadW r4, 484
	jsr WInvertRectangle
	rts

; 10 lines of 100 characters at y 20-146, the font and mode as set (timed)
UiLines:
	LoadW yt, 20
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 10
@l:	LoadW r0, Line100
	LoadW r11, 0
	MoveW yt, r12
	jsr WPutString
	AddVW 14, yt
	dec kn
	bne @l
	rts

; 100 strings of 11 characters at x 10, y 300 with the clip on (the clip:
; leftMargin as set .. 639, rows 0-479), timed
ClipStrings:
	LoadB clipOn, $80
	.byte $CB                ; WAI
	jsr ClockStart
	LoadB kn, 100
@s:	LoadW r0, Short
	LoadW r11, 10
	LoadW r12, 300
	jsr WPutString
	dec kn
	bne @s
	stz clipOn
	rts

ClockStart:
	sta EMU_CLOCK
	rts

; x/y = name: "TIME <name> <32-bit hex>"
ClockReport:
	lda EMU_CLOCK           ; latch
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	stx r0L
	sty r0H
	ldy #0
@1:	lda TimePfx,y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	ldy #0
@3:	lda (r0),y
	beq @4
	sta EMU_STDOUT
	iny
	bne @3
@4:	lda #' '
	sta EMU_STDOUT
	ldx #3
@5:	lda clk,x
	jsr Hex
	dex
	bpl @5
	lda #10
	sta EMU_STDOUT
	rts

Hex:	pha
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

TimePfx:	.byte "TIME ", 0
NFill:		.byte "fill", 0
NFill2:		.byte "fill2", 0
NFill3:		.byte "fill3", 0
NCopy:		.byte "copy", 0
NBank:		.byte "bank256", 0
NRes:		.byte "res256", 0
NText:		.byte "text1000", 0
NCards:		.byte "cards4800", 0
NOutline:	.byte "outline", 0
NFrame:		.byte "frame", 0
NVLine:		.byte "vline", 0
NShadow:	.byte "shadow", 0
NMove:		.byte "move", 0
NRecover:	.byte "recover", 0
NUi:		.byte "ui1000", 0
NUiB:		.byte "uibold1000", 0
NUse:		.byte "usefont100", 0
NRaw:		.byte "rawtile100", 0
NUp:		.byte "tile100", 0
NClipIn:	.byte "clipin1100", 0
NClipOut:	.byte "clipout1100", 0
Short:		.byte "Note 01.txt", 0
TileRaw:
.repeat 128, I
		.byte <(I * 37 + 11)
.endrepeat
TileUp:		.byte $80 + 64
.repeat 64, I
		.byte <(I * 37 + 11)
.endrepeat
		.byte $80 + 64
.repeat 64, I
		.byte <((I + 64) * 37 + 11)
.endrepeat
CardA:		.byte "AZaz09{}"
CardB:		.byte "Bold"
CardE:		.byte "Zero", 0, "xxxxxxxxxxxxxxx"
; a test font: glyph c's row r is (8c + r) * 37 XOR c (tests/check_gfx1.py)
CFont:
.repeat 1024, I
	.byte <((I * 37) ^ (I / 8))
.endrepeat
SysText:	.byte "Veranda 0.1: Hello, X16! {gjpqy}", 0
Line100:	.byte "The quick brown fox jumps over the lazy dog. 0123456789 "
		.byte "Pack my box with five dozen liquor jugs!!", 0
MsgTP:		.byte "TP", 0
MsgDone:	.byte "GFX1 DONE", 0
TPx:		.byte <16, <17, <639, <220
TPxH:		.byte >16, >17, >639, >220
TPy:		.byte <20, <20, <0, <320
TPyH:		.byte >20, >20, >0, >320

.segment "BSS"

y0:	.res 2
yt:	.res 2
kr:	.res 2
kn:	.res 1
clk:	.res 4
