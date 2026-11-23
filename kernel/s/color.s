; Veranda bank S: the colour map (ColorRect; docs/DECISIONS.md V30, V33)
;
; A paper colour for every card (8 x 8 pixels of the bitmap) from a tile
; layer *under* the bitmap. VERA draws layer 0, then layer 1 over it; a
; layer's colour 0 is transparent. With the map on, the bitmap moves to
; layer 1 (paper pixels are 0: transparent), and layer 0 is a 1 bpp tile
; map whose tiles are all tile 0 (eight 0 bytes: every pixel is the
; tile's background colour, the high nibble of its attribute byte); a
; background of 0 is transparent too, so such a card shows palette entry
; 0, the paper of SetColors. The ink stays one colour (palette entry 1):
; a bitmap layer has one palette offset for all its pixels.
;
; VRAM (PLAN 5.1, $1AC00-$1EFFF): the map at $1AC00, 128 x 64 entries of
; 2 bytes (16 KB; VERA's map widths are 32-256: 80 cards need 128; 60
; rows need 64); tile 0 at $1E800 (a tile base is a multiple of 2 KB),
; which is the map's row 60: off the screen, and 0 since the map is
; cleared when it is turned on (with the 1 KB after it: every tile is
; empty, see "Covered cards"). Both layers have the same scale, so a
; card is 8 x 8 bitmap pixels in every video mode.

.include "kernel.inc"

.export k_ColorRect, k_GetCardColor, ColorOff, ColorCover, kColorOn, kCov
.export ColorOn, ColorHide, cX, cW, cY, cN, cA, ClipS
.import TileOn, TileRect, TileCover, TileGet, IsTile
.import GoC, E_CanvCtl, E_CanvCover, E_CanvOff

MAP     = VRAM_FREE             ; $1AC00
TILE0   = $1E800
MAPW    = 128

; Covered cards (menus, dialog boxes: ColorCover; DECISIONS V33): a
; covered card's attribute is 0 (the normal paper) and its tile index
; holds what it had: the paper colour in the high nibble, the number of
; covers in the low one (1-15). Every tile VERA can fetch, 0-255 at
; $1E800-$1EFFF (the map's rows 60-63, off the screen, and the 1 KB
; after it), is eight 0 bytes, so any tile index shows the background.

.segment "BSS"

kColorOn: .res 1                ; $80: the map is shown
kCov:	.res 1                  ; covers in place (0: ColorRect's quick way)
cX:	.res 1                  ; the area (cards), clipped
cW:	.res 1
cY:	.res 1
cN:	.res 1
cA:	.res 1
cT:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; ColorRect: r3L x, r3H width, r11L y, r11H height (cards, clipped to
; the screen), a = the paper colour (palette entry 0-15; 0 the normal
; paper); the first call shows the map (every card 0); a = $FF hides it.
; A covered card (under a menu) gets the colour when it is uncovered.
; a = $FE (COLOR_BUF, V78: a picture's cards): each card its own colour,
; from r0 (below $A000): a byte a card (its low nibble), r3H a row, the
; rows one after the other (the area as given: clipping skips bytes); not
; in tile mode. a = $FD (COLOR_TILES, V101): the map on in tile mode
; (kernel/s/tiles.s), cleared. a = $FC (COLOR_CANVAS, V166): bank C's
; canvas (kernel/c/canvas.s), x what.
;---------------------------------------------------------------
k_ColorRect:
	cmp #$FF
	bne @0
	jmp ColorOff
@0:	cmp #$FE
	bne @t
	jmp ColorBuf
@t:	cmp #$FD
	bne @cv
	jmp TileOn
@cv:	cmp #$FC                ; (V166) COLOR_CANVAS: bank C
	bne @1
	ldy #<E_CanvCtl
	jmp GoC
@1:	ldx VERA_L0_TILEBASE    ; (V166: no colour map under the canvas:
	cpx #CANVAS_TB          ; its room is the save-under stack's then)
	bne @1a
	rts
@1a:	asl
	asl
	asl
	asl
	sta cA
	bit kColorOn
	bmi @2
	jsr ColorOn
@2:	MoveB r3L, cX
	MoveB r3H, cW
	MoveB r11L, cY
	MoveB r11H, cN
	jsr Clip
	bcs @r
	jsr IsTile
	bne @nt
	jmp TileRect
@nt:	lda kCov
	bne @slow
@row:	stz VERA_CTRL           ; the attribute bytes: MAP + y * 256 + x * 2 + 1
	lda cX
	asl
	ina
	sta VERA_ADDR_L
	lda cY
	clc
	adc #>MAP
	sta VERA_ADDR_M
	lda #^MAP | $20         ; (the map does not cross $1FFFF); increment 2
	sta VERA_ADDR_H
	lda cA
	ldx cW
@c:	sta VERA_DATA0
	dex
	bne @c
	inc cY
	dec cN
	bne @row
@r:	rts
@slow:	jsr Ports               ; a covered card keeps the colour in its tile
	ldx cW
@s:	lda VERA_DATA1          ; the tile
	beq @s0
	and #$0F
	ora cA
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	bra @s1
@s0:	sta VERA_DATA0
	lda VERA_DATA1
	lda cA
	sta VERA_DATA0
@s1:	dex
	bne @s
	stz VERA_CTRL
	inc cY
	dec cN
	bne @slow
	rts

; ColorRect $FE: the colours from r0, a byte a card
ColorBuf:
	jsr IsTile              ; (not in tile mode)
	beq @r
	bit kColorOn
	bmi @1
	jsr ColorOn
@1:	MoveB r3L, cX
	MoveB r3H, cW
	MoveB r11L, cY
	MoveB r11H, cN
	MoveW r0, kPtr2
	jsr Clip
	bcs @r
@row:	jsr Ports               ; (a covered card keeps the colour in its tile)
	ldy #0
@c:	lda (kPtr2),y
	asl
	asl
	asl
	asl
	sta cA
	lda VERA_DATA1          ; the tile
	beq @u
	and #$0F
	ora cA
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	bra @n
@u:	sta VERA_DATA0
	lda VERA_DATA1
	lda cA
	sta VERA_DATA0
@n:	iny
	cpy cW
	bne @c
	stz VERA_CTRL
	lda kPtr2               ; the next row of the buffer
	clc
	adc r3H
	sta kPtr2
	bcc @2
	inc kPtr2+1
@2:	inc cY
	dec cN
	bne @row
@r:	rts

;---------------------------------------------------------------
; ColorCover (bank U: menus, dialog boxes): kTmp x, kTmp+1 width,
; kTmp+2 y, kTmp+3 height (cards; kept); a = 0: the cards' colours put aside
; and the cards 0 (the normal paper); a = 1: back (a card covered twice
; comes back when both are gone). -> a = $FF if it covered (the map is
; shown), else 0 (then uncover nothing)
;---------------------------------------------------------------
ColorCover:
	bit kColorOn
	bmi @on
@no:	lda #0
	rts
@on:	ldy #<E_CanvCover       ; (V166: the canvas's program, c set)
	jsr GoC
	bcc @om
	lda #$FF
	rts
@om:	sta cA
	tax
	bne @u
	inc kCov
	bra @g
@u:	lda kCov
	beq @no
	dec kCov
@g:	MoveB kTmp, cX
	MoveB kTmp+1, cW
	MoveB kTmp+2, cY
	MoveB kTmp+3, cN
	jsr Clip
	bcs @yes
	jsr IsTile
	bne @row
	jsr TileCover
	bra @yes
@row:	jsr Ports
	ldx cW
	lda cA
	bne @ur
@c:	lda VERA_DATA1          ; the tile: 0, or covered already
	bne @c1
	lda VERA_DATA1          ; the attribute: the colour, cover 1
	ora #1
	sta VERA_DATA0
	stz VERA_DATA0
	dex
	bne @c
	bra @nr
@c1:	ina                     ; one cover more
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @c
	bra @nr
@ur:	lda VERA_DATA1          ; the tile
	beq @z
	dea
	bit #$0F
	beq @last
	sta VERA_DATA0          ; covered still
	lda VERA_DATA1
	sta VERA_DATA0
	bra @nx
@last:	stz VERA_DATA0          ; the last cover: the colour back
	bit VERA_DATA1
	sta VERA_DATA0
	bra @nx
@z:	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
@nx:	dex
	bne @ur
@nr:	stz VERA_CTRL
	inc cY
	dec cN
	bne @row
@yes:	lda #$FF
	rts

; cX, cW, cY, cN clipped to the screen; c set: nothing left
ClipS:
Clip:	lda screenWidth         ; cards across
	ldx screenWidth+1
	jsr Cards
	sec
	sbc cX
	bcc @no
	beq @no
	cmp cW
	bcs @1
	sta cW                  ; (the cards left)
@1:	lda screenHeight        ; card rows
	ldx screenHeight+1
	jsr Cards
	sec
	sbc cY
	bcc @no
	beq @no
	cmp cN
	bcs @2
	sta cN
@2:	lda cW
	beq @no
	lda cN
	beq @no
	clc
	rts
@no:	sec
	rts

; port 1 (reads) and port 0 (writes) at the entry of card cX, row cY
; (increment 1: tile, attribute); VERA_CTRL left at 0
Ports:	ldy #1
@p:	sty VERA_CTRL
	lda cX
	asl
	sta VERA_ADDR_L
	lda cY
	clc
	adc #>MAP
	sta VERA_ADDR_M
	lda #^MAP | VERA_INC1
	sta VERA_ADDR_H
	dey
	bpl @p
	rts

;---------------------------------------------------------------
; GetCardColor: r3L x, r11L y (cards) -> a = the card's paper colour
; (0 when the map is hidden; no clipping: x < 128, y < 64); a covered
; card's own colour
;---------------------------------------------------------------
k_GetCardColor:
	lda #0
	bit kColorOn
	bpl @r
	jsr IsTile
	bne @0
	jmp TileGet
@0:	stz VERA_CTRL
	lda r3L
	asl
	sta VERA_ADDR_L
	lda r11L
	clc
	adc #>MAP
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^MAP | VERA_INC1
	lda VERA_DATA0          ; the tile: covered, its colour kept there
	bne @1
	lda VERA_DATA0
@1:	lsr
	lsr
	lsr
	lsr
@r:	rts

; a (low), x (high) / 8 -> a
Cards:	stx cT
	ldx #3
@1:	lsr cT
	ror
	dex
	bne @1
	rts

; the map cleared (every card 0), the bitmap on layer 1, the map on layer 0
ColorOn:
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <MAP
	LoadB VERA_ADDR_M, >MAP
	LoadB VERA_ADDR_H, ^MAP | VERA_INC1
	ldx #(TILE0 + 256 * 8 - MAP) / 256 ; 68 pages: the map and every tile
	stz kCov
	ldy #0
@z:	stz VERA_DATA0
	iny
	bne @z
	dex
	bne @z
	php
	sei
	ldx #6                  ; layer 0's registers to layer 1
@l:	lda VERA_L0_CONFIG,x
	sta VERA_L1_CONFIG,x
	dex
	bpl @l
	LoadB VERA_L0_CONFIG, %01100000 ; map 64 high, 128 wide, 1 bpp tiles, 16 colours
	LoadB VERA_L0_MAPBASE, MAP >> 9
	LoadB VERA_L0_TILEBASE, (TILE0 >> 11) << 2 ; 8 x 8 tiles
	stz VERA_L0_HSCROLL_L
	stz VERA_L0_HSCROLL_H
	stz VERA_L0_VSCROLL_L
	stz VERA_L0_VSCROLL_H
	lda VERA_DC_VIDEO
	ora #%00110000          ; both layers
	sta VERA_DC_VIDEO
	plp
	LoadB kColorOn, $80
	rts

; the map hidden: the bitmap on layer 0 again, layer 1 off; leaving tile
; mode (V101) the program's palette rows 2-15 back (entries 32-255: the
; shell kept them at VRAM_TILEPAL when it turned tile mode on), so a
; program started, one put aside going on, BASIC and the shell's own
; plain desktop find them as they were. ColorHide (DaRun): not them (a
; desk accessory over the shell; the shell's picture comes back after it)
ColorOff:
	bit kColorOn
	bpl ColorHide
	phy                     ; (V166: palette entries 16-255 back)
	ldy #<E_CanvOff
	jsr GoC
	ply
	jsr IsTile
	bne ColorHide
	lda #1                  ; port 1 reads VRAM_TILEPAL, port 0 writes
	sta VERA_CTRL           ; entries 32-255
	stz VERA_ADDR_L
	LoadB VERA_ADDR_M, >(VRAM_TILEPAL & $FFFF)
	LoadB VERA_ADDR_H, ^VRAM_TILEPAL | VERA_INC1
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldx #224
@p:	lda VERA_DATA1
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @p
ColorHide:
	bit kColorOn
	bpl @r
	php
	sei
	stz VERA_CTRL
	lda VERA_DC_VIDEO
	and #%11011111
	sta VERA_DC_VIDEO
	ldx #6
@l:	lda VERA_L1_CONFIG,x
	sta VERA_L0_CONFIG,x
	dex
	bpl @l
	plp
	stz kColorOn
@r:	rts
