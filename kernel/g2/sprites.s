; Veranda bank G2: sprites
;
; GEOS sprites n = 0-7 are VERA sprites 0-7. A GEOS picture (24x21, 1 bpp,
; 63 bytes) becomes a 32x32 4 bpp sprite in its 2 KB slot at VRAM_SPRITES
; + n * 2048; ink pixels are colour 1 of palette offset 1 (entry 17).
; Sprite 0 is the pointer: Veranda's own 16x16 shapes (SetPointer,
; kernel/g2/feedback.s: the arrow, the I-beam, the crosshair, the busy
; pointer) after the first 512 bytes of its slot, or a picture a program
; draws (PTR_OWN); the interrupt moves it to the mouse every frame.

.include "kernel.inc"

.export k_DrawSprite, k_PosSprite, k_WPosSprite, k_EnablSprite, k_DisablSprite, PointerInit
.import PtrShowInit, PtrPics, PtrPal, kPtrShown
.include "pointers.inc"

SPR_PAL = 1                     ; palette offset: entries 16-31
SPR_INK = 1                     ; the colour of ink pixels in that offset

.segment "CODE"

; the attribute byte i of sprite r3L (port 0, increment 1)
Attr:	stz VERA_CTRL
	lda r3L
	asl
	asl
	asl
	sta kTmp
	txa
	clc
	adc kTmp
	adc #<VRAM_SPRATTR
	sta VERA_ADDR_L
	lda #>VRAM_SPRATTR
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	rts

; port 0 at the slot of sprite r3L
Slot:	stz VERA_CTRL
	lda r3L
	asl
	asl
	asl                     ; n * 8 = high byte of n * 2048
	clc
	adc #>(VRAM_SPRITES & $FFFF)
	sta VERA_ADDR_M
	stz VERA_ADDR_L
	lda #^VRAM_SPRITES | VERA_INC1
	adc #0
	sta VERA_ADDR_H
	rts

; r3L sprite, r4 picture (GEOS, 63 bytes)
k_DrawSprite:
	jsr Slot
	ldy #0                  ; picture index
	ldx #0                  ; rows
@row:	cpx #21
	bcs @blank
	phx
	lda #3                  ; three bytes
	sta kTmp+1
@byte:	lda (r4),y
	iny
	sta kTmp
	ldx #4                  ; four pixel pairs a byte
@pair:	lda #0
	asl kTmp
	bcc @p1
	ora #SPR_INK << 4
@p1:	asl kTmp
	bcc @p2
	ora #SPR_INK
@p2:	sta VERA_DATA0
	dex
	bne @pair
	dec kTmp+1
	bne @byte
	ldx #4                  ; pixels 24-31: none
@z:	stz VERA_DATA0
	dex
	bne @z
	plx
	inx
	bra @row
@blank:	cpx #32
	bcs @attr
	ldy #16
@b1:	stz VERA_DATA0
	dey
	bne @b1
	inx
	bra @blank
@attr:	ldx #0                  ; the picture's address, 4 bpp
	jsr Attr
	lda r3L
	asl
	asl
	asl
	asl
	asl
	asl                     ; n * $40: (slot >> 5) low byte
	clc
	adc #<(VRAM_SPRITES >> 5)
	sta VERA_DATA0
	php                     ; (its carry into the high byte: V68)
	lda r3L
	lsr
	lsr                     ; n * $40 >> 8
	plp
	adc #>(VRAM_SPRITES >> 5)
	sta VERA_DATA0
	ldx #7                  ; 32x32, palette offset
	jsr Attr
	lda #%10100000 | SPR_PAL
	sta VERA_DATA0
	lda r3L                 ; sprite 0: the program's own pointer (SetPointer's
	bne @r                  ; PTR_OWN, kernel/g2/feedback.s)
	lda #PTR_OWN
	sta pointerShape
	sta kPtrShown
@r:	rts

; r3L sprite, r4 x, r5L y (classic)
k_PosSprite:
	PushW r11
	lda r5L
	sta r11L
	stz r11H
	jsr k_WPosSprite
	PopW r11
	rts

; r3L sprite, r4 x, r11 y
k_WPosSprite:
	ldx #2
	jsr Attr
	lda r4L
	sta VERA_DATA0
	lda r4H
	sta VERA_DATA0
	lda r11L
	sta VERA_DATA0
	lda r11H
	sta VERA_DATA0
	rts

k_EnablSprite:
	ldx #6
	jsr Attr
	lda #%00001100          ; in front of the layers
	sta VERA_DATA0
	rts

k_DisablSprite:
	ldx #6
	jsr Attr
	stz VERA_DATA0
	rts

; sprite 0: Veranda's pointer shapes into its slot from PTR_SLOT_OFFSET
; (kernel/g2/feedback.s), the arrow shown; palette entries 17-20 (black,
; white, two greys); sprites 1-7 off
PointerInit:
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_SPRITES + PTR_SLOT_OFFSET)
	LoadB VERA_ADDR_M, >(VRAM_SPRITES + PTR_SLOT_OFFSET)
	LoadB VERA_ADDR_H, ^(VRAM_SPRITES + PTR_SLOT_OFFSET) | VERA_INC1
	LoadW kPtr, PtrPics
	ldx #>(PTR_SHAPES * 128)
	ldy #0
@1:	lda (kPtr),y
	sta VERA_DATA0
	iny
	bne @1
	inc kPtr+1
	dex
	bne @1
@2:	lda (kPtr),y            ; the last part page
	sta VERA_DATA0
	iny
	cpy #<(PTR_SHAPES * 128)
	bne @2
	jsr PtrShowInit
	lda #PTR_ARROW
	jsr ShowArrow
	LoadB r3L, 1
@off:	jsr k_DisablSprite
	inc r3L
	lda r3L
	cmp #8
	bne @off
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 2 * 17)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 2 * 17)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldx #0
@p:	lda PtrPal,x
	sta VERA_DATA0
	inx
	cpx #8
	bne @p
	rts

; sprite 0 shows the arrow (16x16 at the slot's PTR_SLOT_OFFSET)
ShowArrow:
	stz r3L
	ldx #0
	jsr Attr
	lda #<((VRAM_SPRITES + PTR_SLOT_OFFSET) >> 5)
	sta VERA_DATA0
	lda #>((VRAM_SPRITES + PTR_SLOT_OFFSET) >> 5)
	sta VERA_DATA0
	ldx #7
	jsr Attr
	lda #%01010000 | SPR_PAL ; 16x16
	sta VERA_DATA0
	rts
