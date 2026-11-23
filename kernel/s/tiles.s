; Veranda bank S: the colour map in tile mode (the shell's full-colour
; desktop picture; docs/DECISIONS.md V101)
;
; ColorRect COLOR_TILES ($FD) turns the colour map on as 4 bpp tiles of 8 x
; 8 pixels: layer 0's map at $1AC00 as before (128 x 64 entries, cleared:
; every card tile 0, palette row 0), its tiles at VRAM_TILES ($13000-
; $16BFF: 480 tiles, the save-under stack's room; bank U's UnderPush
; refuses while it is on, so menus and dialog boxes recover from the back
; screen, GEOS's way). The program (the shell) puts the tiles and palette
; rows there itself. Tile mode is "layer 0's tile base is VRAM_TILES"
; (L0_TILEBASE = TILE_TB): every bank can test it, nothing resident; the
; map hidden (ColorOff), SetVideoMode and a program's start end it.
;
; A map entry: the tile's low byte; palette row << 4 | vflip << 3 | hflip
; << 2 | the tile's bits 8-9. A tile pixel 0 is transparent (palette entry
; 0, the paper, shows); tiles 0-15 are solid (tile c: every pixel c), so
; ColorRect's colour c is tile c in palette row 0 (Veranda's 16 colours).
;
; Covered cards (menus, dialog boxes: ColorCover, V33): the entry keeps its
; tile and flips; its palette row becomes TILE_COVROW (15: every entry the
; paper) and its own row and the count of covers go to the map's off-screen
; byte TILE_SHADOW + x of its row (bytes 160-239 of the 256: columns 80-
; 119, never shown); the last cover gone, the row comes back. A covered
; card's highlight (LookHi: a menu's item) is row TILE_HIROW (14), whose
; 16 entries are made the highlight colour. ColorRect on a covered card
; writes its tile and its own row into the shadow byte (it shows when
; uncovered). The count of covers in place (kCov) is kept at VRAM_TILECOV
; too (the map's row 63, off the screen: 0 when the map is cleared), so
; that the program sees when there are none. ExportRect's pixels: bank W's TileCard (kernel/w/tilecard.s).

.include "kernel.inc"

.export TileOn, TileRect, TileCover, TileGet, TileHi, IsTile
.import kCov, cX, cW, cY, cN, cA, ClipS

MAP     = VRAM_FREE             ; $1AC00

.segment "BSS"

tS:	.res 1                  ; the shadow byte
tT:	.res 1                  ; the tile byte to write
tE:	.res 1                  ; the attribute byte to write
tX:	.res 1                  ; the card in a row
tK:	.res 1                  ; a row's cards left

.segment "CODE"

; z set: tile mode (a destroyed)
IsTile:	lda VERA_L0_TILEBASE
	cmp #TILE_TB
	rts

;---------------------------------------------------------------
; port 0 at byte a of the map's row cY: increment 1 (At) or 0 (At0)
;---------------------------------------------------------------
At0:	ldy #^MAP
	bra At1
At:	ldy #^MAP | VERA_INC1
At1:	stz VERA_CTRL
	sta VERA_ADDR_L
	lda cY
	clc
	adc #>MAP
	sta VERA_ADDR_M
	sty VERA_ADDR_H
	rts

; tS = card tX's shadow byte; port 0 left on it (increment 0)
Shadow:	lda tX
	clc
	adc #TILE_SHADOW
	jsr At0
	lda VERA_DATA0
	sta tS
	rts

; card tX's attribute: port 0 on it (increment 0), a = it
Attr:	lda tX
	asl
	ina
	jsr At0
	lda VERA_DATA0
	rts

;---------------------------------------------------------------
; TileOn (ColorRect COLOR_TILES): the map on (cleared) as 4 bpp tiles
;---------------------------------------------------------------
TileOn:	.import ColorOn, ColorOff
	jsr ColorOff            ; (a map shown: its layers back first)
	jsr ColorOn
	LoadB VERA_L0_CONFIG, TILE_CFG
	LoadB VERA_L0_TILEBASE, TILE_TB
	rts

;---------------------------------------------------------------
; TileRect (ColorRect in tile mode): cX, cW, cY, cN clipped, cA the colour
; << 4: each card tile c, palette row 0 (a covered card: its tile, and row
; 0 kept for when it is uncovered)
;---------------------------------------------------------------
TileRect:
	lda cA
	lsr
	lsr
	lsr
	lsr
	sta tT
	stz tE
	lda kCov
	bne @slow
@row:	lda cX                  ; no covers: both bytes as they come
	asl
	jsr At
	lda tT
	ldx cW
@c:	sta VERA_DATA0
	stz VERA_DATA0
	dex
	bne @c
	inc cY
	dec cN
	bne @row
	rts
@slow:	jsr Each
	bne @slow
	rts

; the cards cX .. cX + cW - 1 of row cY: tT, tE written (a covered one's
; row into its shadow); the next row; z set: none left
Each:	MoveB cX, tX
	MoveB cW, tK
@c:	jsr Shadow
	and #$0F
	beq @open
	lda tS                  ; covered: its own row in the shadow
	and #$0F
	sta tS
	lda tE
	and #$F0
	ora tS
	sta VERA_DATA0
	jsr Attr                ; the shown row kept, the flips and tile's
	and #$F0                ; high bits new
	sta tS
	lda tE
	and #$0F
	ora tS
	sta VERA_DATA0
	lda tX                  ; the tile
	asl
	jsr At0
	lda tT
	sta VERA_DATA0
	bra @n
@open:	lda tX
	asl
	jsr At
	lda tT
	sta VERA_DATA0
	lda tE
	sta VERA_DATA0
@n:	inc tX
	dec tK
	bne @c
	inc cY
	dec cN
	rts

;---------------------------------------------------------------
; TileCover (ColorCover in tile mode): cX, cW, cY, cN clipped; cA = 0
; cover, 1 uncover
;---------------------------------------------------------------
TileCover:
	stz VERA_CTRL           ; the count of covers where the program sees
	LoadB VERA_ADDR_L, <VRAM_TILECOV ; it (VRAM_TILECOV: 0, it may write the
	LoadB VERA_ADDR_M, >VRAM_TILECOV ; map without looking at each card)
	LoadB VERA_ADDR_H, ^VRAM_TILECOV
	MoveB kCov, VERA_DATA0
@row:	MoveB cX, tX
	MoveB cW, tK
@c:	jsr Shadow
	lda cA
	bne @un
	lda tS                  ; cover: the first keeps the row
	and #$0F
	bne @more
	jsr Attr
	pha
	and #$F0
	ora #1
	sta tT
	pla
	and #$0F
	ora #TILE_COVROW << 4
	sta VERA_DATA0
	jsr Shadow
	lda tT
	bra @w
@more:	cmp #$0F
	beq @n                  ; (15 at most)
	lda tS
	ina
	bra @w
@un:	lda tS                  ; uncover: the last gives the row back
	and #$0F
	beq @n
	dec tS
	lda tS
	and #$0F
	bne @w1
	jsr Attr
	and #$0F
	sta tT
	lda tS
	and #$F0
	ora tT
	sta VERA_DATA0
	jsr Shadow
	lda #0
	bra @w
@w1:	lda tS
@w:	sta VERA_DATA0          ; (port 0 on the shadow byte)
@n:	inc tX
	dec tK
	beq @nr
	jmp @c
@nr:	inc cY
	dec cN
	beq @r
	jmp @row
@r:	rts

;---------------------------------------------------------------
; TileGet (GetCardColor in tile mode): r3L x, r11L y -> a = the card's
; colour (0-15) if it is one of Veranda's (palette row 0, a solid tile),
; else 0 (the picture)
;---------------------------------------------------------------
TileGet:
	MoveB r3L, tX
	MoveB r11L, cY
	jsr Shadow
	jsr Attr
	ldx tS                  ; covered: its own row is the shadow's
	beq @1
	txa
@1:	and #$F0
	bne @no
	lda tX
	asl
	jsr At0
	lda VERA_DATA0
	cmp #16
	bcc @r
@no:	lda #0
@r:	rts

;---------------------------------------------------------------
; TileHi (LookHi in tile mode, bank T): kTmp x, width, y, height (cards),
; a the colour: an uncovered card tile c, row 0; a covered one row
; TILE_COVROW (c = 0) or TILE_HIROW, made colour c
;---------------------------------------------------------------
TileHi:	sta tT
	stz VERA_CTRL
	ldx #3
@k:	lda kTmp,x
	sta cX,x
	dex
	bpl @k
	jsr ClipS
	bcs @r
	lda tT
	beq @rows
	asl                     ; row TILE_HIROW: colour c's entry 16 times
	ldx #VERA_INC1 | 1      ; (the palette at $1FA00)
	stx VERA_ADDR_H
	sta VERA_ADDR_L
	LoadB VERA_ADDR_M, $FA
	lda VERA_DATA0
	ldy VERA_DATA0
	ldx #<($FA00 + TILE_HIROW * 32)
	stx VERA_ADDR_L
	ldx #>($FA00 + TILE_HIROW * 32)
	stx VERA_ADDR_M
	ldx #16
@p:	sta VERA_DATA0
	sty VERA_DATA0
	dex
	bne @p
@rows:	stz tE
@row:	MoveB cX, tX
	MoveB cW, tK
@c:	jsr Shadow
	and #$0F
	beq @open
	jsr Attr
	and #$0F
	ldx tT
	beq @pap
	ora #TILE_HIROW << 4
	bra @w
@pap:	ora #TILE_COVROW << 4
@w:	sta VERA_DATA0
	bra @n
@open:	lda tX
	asl
	jsr At
	lda tT
	sta VERA_DATA0
	stz VERA_DATA0
@n:	inc tX
	dec tK
	bne @c
	inc cY
	dec cN
	bne @row
@r:	clc
	rts
