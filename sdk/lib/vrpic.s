; Veranda SDK: a program's full-colour picture (vrpic.h; DECISIONS V105)
;
; The kernel's tile mode (ColorRect COLOR_TILES, V101: layer 0 in 4 bpp
; tiles at VRAM_TILES under the 1 bpp bitmap), set up for a program as the
; shell sets it up for its desktop picture: the palette rows 2-15 kept at
; VRAM_TILEPAL (the kernel puts them back when tile mode ends: vr_pic_off,
; the next program's start), tiles 0-15 the 16 solid colours (ColorRect's
; colour c, the menu bar's highlight), row 15 the paper (the covered
; cards under menus and dialog boxes), the back screen cleared (menus
; recover from it in tile mode: the save-under stack's room holds the
; tiles), and a routine on asideVector that notes the switcher (Alt +
; Tab): a program put aside comes back with palette rows 2-15 as they
; were before vr_pic_on, so vr_pic_back() tells it to write its own again.
; vr_vram_load: VRAM chunks from a record (mkwall.py --tiles).
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export _vr_pic_on, _vr_pic_off, _vr_pic_back, _vr_vram_load

.segment "DATA"

back:	.byte 0                 ; 1: asideVector was called
old:	.word 0                 ; the asideVector found

.segment "CODE"

;---------------------------------------------------------------
; vr_pic_on: tile mode on (nothing if it is on already)
;---------------------------------------------------------------
_vr_pic_on:
	lda VERA_L0_TILEBASE
	cmp #TILE_TB
	bne @on
	rts
@on:	lda #1                  ; palette entries 32-255 (port 1) to
	sta VERA_CTRL           ; VRAM_TILEPAL (port 0)
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 64)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_TILEPAL
	LoadB VERA_ADDR_M, >VRAM_TILEPAL
	LoadB VERA_ADDR_H, ^VRAM_TILEPAL | VERA_INC1
	ldx #224
@p:	lda VERA_DATA1
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @p
	lda #COLOR_TILES
	jsr ColorRect           ; (the map cleared: every card tile 0, row 0)
	stz VERA_CTRL           ; tiles 0-15: tile c every pixel c
	LoadB VERA_ADDR_L, <VRAM_TILES
	LoadB VERA_ADDR_M, >VRAM_TILES
	LoadB VERA_ADDR_H, ^VRAM_TILES | VERA_INC1
	ldy #0
@t:	tya
	asl
	asl
	asl
	asl
	sty r0L
	ora r0L
	ldx #32
@tb:	sta VERA_DATA0
	dex
	bne @tb
	iny
	cpy #16
	bne @t
	jsr Row15
	lda dispBufferOn        ; the back screen cleared (pattern 0)
	pha
	LoadB dispBufferOn, ST_WR_BACK
	lda #0
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 0
	lda screenWidth
	sec
	sbc #1
	sta r4L
	lda screenWidth+1
	sbc #0
	sta r4H
	lda screenHeight
	sec
	sbc #1
	sta r12L
	lda screenHeight+1
	sbc #0
	sta r12H
	jsr WRectangle
	pla
	sta dispBufferOn
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
	rts

; palette row 15: entry 0 (the paper) 16 times
Row15:	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldy VERA_DATA0
	ldx VERA_DATA0
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 15 * 32)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 15 * 32)
	tya
	ldy #16
@w:	sta VERA_DATA0
	stx VERA_DATA0
	dey
	bne @w
	rts

; asideVector: the program is about to be put aside (or asked to quit)
Aside:	lda #1
	sta back
	lda old
	ora old+1
	beq @r
	jmp (old)
@r:	rts

;---------------------------------------------------------------
; vr_pic_off: tile mode off (the map hidden, palette rows 2-15 as they
; were before vr_pic_on); asideVector as it was
;---------------------------------------------------------------
_vr_pic_off:
	lda VERA_L0_TILEBASE
	cmp #TILE_TB
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
; vr_pic_back: 1 once after asideVector was called (the program was put
; aside and came back, or stayed after the switcher's question): row 15
; written again here, the program's rows 2-13 to be written again
;---------------------------------------------------------------
_vr_pic_back:
	lda back
	beq @r
	stz back
	lda VERA_L0_TILEBASE
	cmp #TILE_TB
	bne @1
	jsr Row15
@1:	lda #1
@r:	ldx #0
	rts

;---------------------------------------------------------------
; vr_vram_load(bank): the VRAM chunks at $A000 of RAM bank a (a record:
; LoadOverlay's r1L): 3 bytes the address (17 bits), 2 the length, the
; bytes; a length 0 ends. r0, r1 changed.
;---------------------------------------------------------------
_vr_vram_load:
	ldx $00
	phx
	sta $00
	LoadW r0, $A000
@chunk:	stz VERA_CTRL
	jsr Byte
	sta VERA_ADDR_L
	jsr Byte
	sta VERA_ADDR_M
	jsr Byte
	and #1
	ora #VERA_INC1
	sta VERA_ADDR_H
	jsr Byte
	sta r1L
	jsr Byte
	sta r1H
	ora r1L
	beq @done
	ldx r1H                 ; whole pages
	beq @part
	ldy #0
@pg:	lda (r0),y
	sta VERA_DATA0
	iny
	bne @pg
	inc r0H
	dex
	bne @pg
@part:	ldx r1L
	beq @chunk
	ldy #0
@b:	lda (r0),y
	sta VERA_DATA0
	iny
	dex
	bne @b
	tya
	clc
	adc r0L
	sta r0L
	bcc @chunk
	inc r0H
	bra @chunk
@done:	pla
	sta $00
	rts

Byte:	lda (r0)
	inc r0L
	bne @r
	inc r0H
@r:	rts
