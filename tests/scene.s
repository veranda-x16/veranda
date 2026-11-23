; gate gfx (phase 2): one scene of classic GEOS calls, assembled twice:
; with -D GEOS64 against GEOS 64's addresses (build/gen/geos64.inc) for the
; GEOS 64 KERNAL in the simulator, and against veranda.inc for Veranda in its
; 320x240 mode (tests/gfx2.s). Both must draw the same bytes on both screens
; (tests/check_gfx2.py). Patterns 0-2 only (the same in both); the BSW font
; is a test fixture loaded with LoadCharSet on both sides.

.ifdef GEOS64
.include "geos64.inc"
.else
.include "veranda.inc"
.endif
.include "macros.inc"

; a marker on Veranda's console (gate debugging)
.macro MARK ch
.ifndef GEOS64
	pha
	lda #ch
	sta $9FBB
	lda #10
	sta $9FBB
	pla
.endif
.endmacro

.export GfxScene

.segment "CODE"

GfxScene:
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadB windowTop, 0
	LoadB windowBottom, 199
	LoadW leftMargin, 0
	LoadW rightMargin, 319
	LoadB currentMode, 0
	LoadW r0, BswFont
	jsr LoadCharSet

	MARK 'A'
	; shapes
	lda #2
	jsr SetPattern
	LoadB r2L, 10
	LoadB r2H, 50
	LoadW r3, 10
	LoadW r4, 150
	jsr Rectangle
	LoadB r2L, 8
	LoadB r2H, 52
	LoadW r3, 8
	LoadW r4, 152
	lda #$FF
	jsr FrameRectangle
	LoadB r2L, 20
	LoadB r2H, 40
	LoadW r3, 30
	LoadW r4, 130
	jsr InvertRectangle
	LoadW r3, 160
	LoadW r4, 300
	LoadB r11L, 10
	lda #$CC
	jsr HorizontalLine
	LoadW r3, 160
	LoadW r4, 300
	LoadB r11L, 20
	jsr InvertLine
	LoadB r3L, 12
	LoadB r3H, 60
	LoadW r4, 170
	lda #$F0
	jsr VerticalLine
	LoadW r3, 180           ; ink line
	LoadB r11L, 15
	LoadW r4, 300
	LoadB r11H, 60
	lda #0                  ; N clear
	sec                     ; C set: ink
	jsr DrawLine
	LoadW r3, 180           ; steep ink line
	LoadB r11L, 25
	LoadW r4, 200
	LoadB r11H, 62
	lda #0
	sec
	jsr DrawLine
	LoadW r3, 290           ; paper line across the first
	LoadB r11L, 15
	LoadW r4, 190
	LoadB r11H, 60
	lda #0
	clc
	jsr DrawLine
	LoadB r11L, 30          ; points
	LoadW r3, 305
@pt:	lda #0
	sec
	jsr DrawPoint
	inc r3L
	inc r11L
	lda r11L
	cmp #42
	bne @pt

	MARK 'B'
	; text
	LoadW r0, Text1
	LoadW r11, 10
	LoadB r1H, 72
	jsr PutString
	LoadW r0, Text2
	LoadW r11, 10
	LoadB r1H, 84
	jsr PutString
	LoadW r0, 12345
	LoadW r11, 230
	LoadB r1H, 72
	lda #SET_LEFTJUST | SET_SURPRESS
	jsr PutDecimal
	LoadW r0, 42
	LoadW r11, 230
	LoadB r1H, 84
	lda #SET_RIGHTJUST | SET_SURPRESS | 40
	jsr PutDecimal
	LoadW r11, 280
	LoadB r1H, 96
	lda #'A'
	jsr PutChar
	lda #'b'
	jsr PutChar
	; (V91) an ESC_GRAPHICS ends the string with its GraphicsString's 0:
	; the bytes after it are not drawn (geoWrite's "Previous page" item)
	LoadW r0, Text3
	LoadW r11, 160
	LoadB r1H, 108
	jsr PutString
	jsr i_PutString
	.word 230
	.byte 108
	.byte "i", ESC_GRAPHICS, MOVEPENTO, <240, >240, 101, LINETO, <250, >250, 107, 0
	LoadW r11, 256          ; i_PutString returns past the GraphicsString's 0
	LoadB r1H, 108
	lda #'k'
	jsr PutChar

	MARK 'C'
	; GraphicsString
	LoadW r0, GStr
	jsr GraphicsString

	MARK 'D'
	; bitmaps
	LoadW r0, Bitmap
	LoadB r1L, 25
	LoadB r1H, 140
	LoadB r2L, 8
	LoadB r2H, 16
	jsr BitmapUp
	LoadW r0, Bitmap
	LoadB r1L, 3            ; the middle 5 cards of rows 3-15
	LoadB r1H, 165
	LoadB r2L, 5
	LoadB r2H, 13
	LoadB r11L, 1
	LoadB r11H, 2
	LoadW r12, 3
	jsr BitmapClip

	MARK 'E'
	; recover and imprint: ink on the foreground only, copied to the back
	; screen; paper on the foreground; part of it back from the back screen
	LoadB dispBufferOn, ST_WR_FORE
	lda #1
	jsr SetPattern
	LoadB r2L, 160
	LoadB r2H, 190
	LoadW r3, 200
	LoadW r4, 260
	jsr Rectangle
	jsr ImprintRectangle
	lda #0
	jsr SetPattern
	jsr Rectangle
	LoadB r2L, 170
	LoadB r2H, 180
	LoadW r3, 210
	LoadW r4, 230
	jsr RecoverRectangle
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK

	MARK 'F'
	; the inline calls
	lda #2
	jsr SetPattern
	jsr i_Rectangle
	.byte 110, 125
	.word 270, 300
	jsr i_FrameRectangle
	.byte 108, 127
	.word 268, 302
	.byte $AA
	jsr i_PutString
	.word 160
	.byte 120
	.byte "inline", 0
	jsr i_GraphicsString
	.byte MOVEPENTO
	.word 160
	.byte 128
	.byte LINETO
	.word 250
	.byte 135
	.byte 0
	jsr i_BitmapUp
	.word Bitmap
	.byte 36, 140, 2, 8
	MARK 'G'
	jsr i_RecoverRectangle
	.byte 0, 2
	.word 0, 7
	jsr i_ImprintRectangle
	.byte 0, 2
	.word 0, 7
	rts

.segment "RODATA"

Text1:	.byte "Hello, Veranda! 0123456789", 0
Text2:	.byte BOLDON, "Bold ", PLAINTEXT, ITALICON, "Italic ", PLAINTEXT
	.byte ULINEON, "Under", ULINEOFF, " ", REV_ON, "Rev", REV_OFF
	.byte GOTOX, <200, >200, "x200", 0

Text3:	.byte "Prev", ESC_GRAPHICS, MOVEPENTO, <190, >190, 108, LINETO, <200, >200, 100
	.byte LINETO, <210, >210, 108, 0
	.byte "NOT DRAWN", 0

GStr:	.byte MOVEPENTO
	.word 10
	.byte 100
	.byte LINETO
	.word 100
	.byte 128
	.byte NEWPATTERN, 1
	.byte RECTANGLETO
	.word 130
	.byte 110
	.byte FRAME_RECTO
	.word 150
	.byte 130
	.byte PEN_XY_DELTA
	.word 5, 3
	.byte ESC_PUTSTRING
	.word 20
	.byte 135
	.byte "GS", 0
	.byte 0

; 8 cards by 16 rows, compacted with all three kinds of count
Bitmap:
	.byte 8, $FF                    ; row 0: a repeated byte
	.byte $80 + 8, $81, $42, $24, $18, $18, $24, $42, $81 ; row 1: literal bytes
	.byte $DC + 4, 6, 2, $AA, 2, $55 ; rows 2-4: a 4-byte pattern (itself
					; two repeats of 2), 6 times
	.byte 16, $0F                   ; rows 5-6
	.byte $80 + 16, $01, $02, $04, $08, $10, $20, $40, $80
	.byte $80, $40, $20, $10, $08, $04, $02, $01 ; rows 7-8
	.byte 32, $3C                   ; rows 9-12
	.byte 24, $E7                   ; rows 13-15

BswFont:
	.incbin "bsw9.bin"
