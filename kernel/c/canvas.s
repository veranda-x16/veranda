; Veranda bank C: the canvas (DECISIONS V166)
;
; A program's picture of one byte a pixel, any of the 256 palette entries,
; under the kernel's 1 bpp screen, in the 320 x 240 mode only: layer 0 an
; 8 bpp bitmap at VRAM_CANVAS ($02800-$153FF: over the back screen and the
; save-under stack's usual room, which a canvas program does not use),
; the 1 bpp screen moved to layer 1 over it (as the colour map moves it,
; kernel/s/color.s); its 0 pixels are transparent, so the picture shows
; wherever the screen is 0. The test for the mode: L0_TILEBASE ==
; CANVAS_TB ($14), as IsTile tests tile mode's.
;
; ColorRect COLOR_CANVAS ($FC), x = what:
;   CANV_ON (0): the canvas on (c clear, x = 0), cleared (palette entry
;     0 everywhere): palette entries 16-255 kept at VRAM_CANVPAL, the
;     save-under stack moved to VRAM_CANVUNDER (bank U's uFree, uCanv:
;     the colour map's room, unused now), the colour map "on" for bank S
;     (kColorOn: ColorCover asks this bank, ColorOff ends the mode, the
;     switcher's Tidy leaves that room alone). r0 = the program's cover
;     routine (0: none), r1 = 4 bytes of the program's (main RAM) where it
;     finds the cards: x, width, y, height. Not in the 640 modes, nor over
;     the colour map or tile mode: x = UNSUPPORTED (c set).
;   CANV_TIDY (1): the picture's VRAM and the stack's free part zeroed
;     (a program put aside packs small: its asideVector; it draws the
;     picture again when it comes back)
; CanvOff (bank S's ColorOff: SetVideoMode, ColorRect $FF, a program's
;   end): palette entries 16-255 back from VRAM_CANVPAL, the stack back
;   at VRAM_SAVEUNDER; bank S then puts the screen back on layer 0
; CanvCover (bank S's ColorCover: menus, dialog boxes; kTmp x, width, y,
;   height in cards, a = 0 cover, 1 uncover): in canvas mode the program's
;   routine with the cards clipped to the screen and a as given (it zeroes
;   the picture under a cover and draws it again when uncovered; it counts
;   the covers itself), c set; else c clear, a kept
;
; r0-r3 are kept (bank S calls these inside SetVideoMode and the menus).

.include "kernel.inc"
.include "kvars.inc"

.export CanvCtl, CanvOff, CanvCover
.import kBankBase, k_BankCopy, AppJsr, kAppVec

CANV_ON   = 0
CANV_TIDY = 1
PAL16     = VRAM_PALETTE + 32   ; entry 16
PICEND    = VRAM_CANVAS + 320 * 240

.segment "BSS"

cvVec:	.res 2                  ; the program's cover routine
cvBuf:	.res 2                  ; its 4 bytes
uImg:	.res 4                  ; bank U's uFree (3), uCanv
sImg:	.res 2                  ; bank S's kColorOn, kCov
rKeep:	.res 8                  ; r0-r3

.segment "CODE"

;---------------------------------------------------------------
CanvCtl:
	cpx #CANV_TIDY
	bne @on
	jmp Tidy
@on:	lda VERA_L0_TILEBASE
	cmp #CANVAS_TB
	bne @off
	jmp @vec                ; (on already: the routine only)
@off:
	lda graphMode
	cmp #MODE_320x240
	bne @no
	lda VERA_DC_VIDEO
	and #%00100000          ; layer 1 on: the colour map or tiles
	beq @1
@no:	ldx #UNSUPPORTED
	sec
	rts
@1:	jsr KeepR
	; palette entries 16-255 to VRAM_CANVPAL (port 1 reads, port 0 writes)
	lda #1
	sta VERA_CTRL
	LoadB VERA_ADDR_L, <PAL16
	LoadB VERA_ADDR_M, >PAL16
	LoadB VERA_ADDR_H, ^PAL16 | VERA_INC1
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_CANVPAL
	LoadB VERA_ADDR_M, >VRAM_CANVPAL
	LoadB VERA_ADDR_H, ^VRAM_CANVPAL | VERA_INC1
	ldx #240
@p:	lda VERA_DATA1
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @p
	; the picture cleared
	LoadB VERA_ADDR_L, <VRAM_CANVAS
	LoadB VERA_ADDR_M, >VRAM_CANVAS
	LoadB VERA_ADDR_H, ^VRAM_CANVAS | VERA_INC1
	lda #<(PICEND - VRAM_CANVAS)
	ldx #>(PICEND - VRAM_CANVAS)
	ldy #^(PICEND - VRAM_CANVAS)
	jsr Zeros
	; the stack moved (empty: no menu or box is open at a program's start)
	stz uImg
	LoadB uImg+1, >VRAM_CANVUNDER
	LoadB uImg+2, ^VRAM_CANVUNDER
	LoadB uImg+3, $80
	jsr PutU
	LoadB sImg, $80         ; bank S: the map "shown", no covers
	stz sImg+1
	jsr PutS
	; the layers: the screen to layer 1, the picture on layer 0
	php
	sei
	ldx #6
@l:	lda VERA_L0_CONFIG,x
	sta VERA_L1_CONFIG,x
	dex
	bpl @l
	LoadB VERA_L0_CONFIG, CANVAS_CFG
	LoadB VERA_L0_TILEBASE, CANVAS_TB
	stz VERA_L0_HSCROLL_H   ; (palette offset 0)
	lda VERA_DC_VIDEO
	ora #%00110000
	sta VERA_DC_VIDEO
	plp
	jsr BackR
@vec:	MoveW r0, cvVec
	MoveW r1, cvBuf
	ldx #0
	clc
	rts

;---------------------------------------------------------------
CanvOff:
	pha
	lda VERA_L0_TILEBASE
	cmp #CANVAS_TB
	bne @r
	phx
	phy
	jsr KeepR
	lda #1                  ; port 1 reads VRAM_CANVPAL, port 0 writes
	sta VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_CANVPAL
	LoadB VERA_ADDR_M, >VRAM_CANVPAL
	LoadB VERA_ADDR_H, ^VRAM_CANVPAL | VERA_INC1
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <PAL16
	LoadB VERA_ADDR_M, >PAL16
	LoadB VERA_ADDR_H, ^PAL16 | VERA_INC1
	ldx #240
@p:	lda VERA_DATA1
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @p
	stz uImg                ; the stack at its usual place (empty: a mode
	LoadB uImg+1, >VRAM_SAVEUNDER ; change, a program's end)
	LoadB uImg+2, ^VRAM_SAVEUNDER
	stz uImg+3
	jsr PutU
	stz cvVec
	stz cvVec+1
	jsr BackR
	ply
	plx
@r:	pla
	rts

;---------------------------------------------------------------
CanvCover:
	pha
	lda VERA_L0_TILEBASE
	cmp #CANVAS_TB
	bne @no
	lda cvVec
	ora cvVec+1
	bne @go
	pla                     ; (no routine: covered, nothing to do)
	sec
	rts
@no:	pla
	clc
	rts
@go:	lda kPtr                ; kPtr: the program's 4 bytes
	pha
	lda kPtr+1
	pha
	MoveW cvBuf, kPtr
	lda kTmp                ; x, clipped to the screen's 40 cards
	cmp #40
	bcs @none
	ldy #0
	sta (kPtr),y
	lda #40
	sec
	sbc kTmp
	cmp kTmp+1
	bcc @w
	lda kTmp+1
@w:	iny
	sta (kPtr),y
	lda kTmp+2              ; y, clipped to its 30
	cmp #30
	bcs @none
	iny
	sta (kPtr),y
	lda #30
	sec
	sbc kTmp+2
	cmp kTmp+3
	bcc @h
	lda kTmp+3
@h:	iny
	sta (kPtr),y
	pla
	sta kPtr+1
	pla
	sta kPtr
	MoveW cvVec, kAppVec
	pla
	pha
	jsr AppJsr
	pla
	sec
	rts
@none:	pla
	sta kPtr+1
	pla
	sta kPtr
	pla
	sec
	rts

;---------------------------------------------------------------
; CANV_TIDY: the picture zeroed, and the stack from bank U's uFree up
Tidy:	lda VERA_L0_TILEBASE
	cmp #CANVAS_TB
	bne @r
	jsr KeepR
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_CANVAS
	LoadB VERA_ADDR_M, >VRAM_CANVAS
	LoadB VERA_ADDR_H, ^VRAM_CANVAS | VERA_INC1
	lda #<(PICEND - VRAM_CANVAS)
	ldx #>(PICEND - VRAM_CANVAS)
	ldy #^(PICEND - VRAM_CANVAS)
	jsr Zeros
	LoadW r0, U_UnderFree   ; uFree from bank U
	LoadW r1, uImg
	LoadW r2, 3
	lda kBankBase
	clc
	adc #BANK_U
	sta r3L
	adc #BANK_C - BANK_U
	sta r3H
	jsr k_BankCopy
	lda uImg+2              ; in the canvas's stack: up to $1F000
	cmp #^VRAM_CANVUNDER
	bne @b
	lda uImg+1
	cmp #>VRAM_CANVUNDER
	bcc @b
	MoveB uImg, VERA_ADDR_L
	MoveB uImg+1, VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_CANVUNDER | VERA_INC1
	lda #0                  ; $1F000 - uFree
	sec
	sbc uImg
	pha
	lda #>$F000
	sbc uImg+1
	tax
	pla
	ldy #0
	jsr Zeros
@b:	jsr BackR
@r:	ldx #0
	clc
	rts

; a, x, y: bytes (24 bits) of 0 to VERA_DATA0 (the odd bytes, then
; pages of 256, eight a turn)
Zeros:	stx r0L                 ; r0: the pages
	sty r0H
	tax
	beq @pg
@b:	stz VERA_DATA0
	dex
	bne @b
@pg:	lda r0L
	ora r0H
	beq @r
	ldx #32
@p:	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	dex
	bne @p
	lda r0L
	bne @1
	dec r0H
@1:	dec r0L
	bra @pg
@r:	rts

; uImg to bank U's uFree, uCanv; sImg to bank S's kColorOn, kCov
PutU:	LoadW r0, uImg
	LoadW r1, U_UnderFree
	LoadW r2, 4
	lda #BANK_U
	bra Put
PutS:	LoadW r0, sImg
	LoadW r1, S_kColorOn
	LoadW r2, 2
	lda #BANK_S
Put:	clc
	adc kBankBase
	sta r3H
	lda kBankBase
	clc
	adc #BANK_C
	sta r3L
	jmp k_BankCopy

KeepR:	ldx #7
@k:	lda r0,x
	sta rKeep,x
	dex
	bpl @k
	rts
BackR:	ldx #7
@b:	lda rKeep,x
	sta r0,x
	dex
	bpl @b
	rts

.assert S_kCov = S_kColorOn + 1, error, "canvas.s: kColorOn, kCov together"
