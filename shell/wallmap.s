; Veranda shell: the desktop's picture to VERA (wall.c; DECISIONS V101),
; in the resident part: it maps the picture's banks, which an overlay (at
; $A000 itself) cannot.
;
; The picture is VERA tiles (the kernel's tile mode, ColorRect
; COLOR_TILES): its tiles in RAM banks _wmBank and _wmBank + 1 (8 KB, then
; the rest), its map in _wmBank + 2 and + 3 (51 rows of 80 entries of 2
; bytes a bank: 8,160 bytes, then 9 rows).
;
; wall_up():  _wmLen bytes of tiles to VRAM_TILES ($13000)
; wall_map(): the map's entries of cards _wmX .. _wmX + _wmW - 1, rows _wmY
;             .. _wmY + _wmH - 1 into the colour map ($1AC00, 256 bytes a
;             row). A card a menu or dialog box covers (its palette row 14
;             or 15: kernel/s/tiles.s) keeps the row it shows; the one it
;             will show again goes into its shadow byte (160 + x). With no
;             covers in place (the kernel's count at VRAM_TILECOV) the
;             entries go as they are.
.include "veranda.inc"
.include "x16hw.inc"

.export _wall_up, _wall_map, _wmBank, _wmLen, _wmX, _wmW, _wmY, _wmH, _wall_word
.importzp ptr1

MAP     = VRAM_FREE
ROWB    = 160                   ; a map row in the banks
PERBANK = 51                    ; rows a bank

.segment "ZEROPAGE"
wPtr:	.res 2

.segment "BSS"
_wmBank: .res 1
_wmLen:	.res 2
_wmX:	.res 1
_wmW:	.res 1
_wmY:	.res 1
_wmH:	.res 1
wB:	.res 1                  ; the bank of the row
wR:	.res 1                  ; the row in it
wK:	.res 1                  ; cards left
wCov:	.res 1                  ; a covered card on this row
wHi:	.res 1
wLeft:	.res 2
wAny:	.res 1                  ; covers in place

.segment "CODE"

_wall_up:
	lda $00
	pha
	stz VERA_CTRL
	stz VERA_ADDR_L
	lda #>(VRAM_TILES & $FFFF)
	sta VERA_ADDR_M
	lda #^VRAM_TILES | VERA_INC1
	sta VERA_ADDR_H
	lda _wmBank
	sta $00
	lda _wmLen
	sta wLeft
	lda _wmLen+1
	sta wLeft+1
	stz wPtr
	lda #$A0
	sta wPtr+1
@pg:	lda wLeft+1             ; whole pages
	beq @tail
	ldy #0
@b:	lda (wPtr),y
	sta VERA_DATA0
	iny
	lda (wPtr),y
	sta VERA_DATA0
	iny
	lda (wPtr),y
	sta VERA_DATA0
	iny
	lda (wPtr),y
	sta VERA_DATA0
	iny
	bne @b
	dec wLeft+1
	inc wPtr+1
	lda wPtr+1
	cmp #$C0
	bne @pg
	lda #$A0                ; the next bank
	sta wPtr+1
	inc $00
	bra @pg
@tail:	ldy #0
	ldx wLeft
	beq @r
@t:	lda (wPtr),y
	sta VERA_DATA0
	iny
	dex
	bne @t
@r:	pla
	sta $00
	rts

_wall_map:
	lda $00
	pha
	lda _wmH
	bne @0
	jmp @end
@0:	lda _wmBank             ; the first row's bank and place
	clc
	adc #2
	sta wB
	lda _wmY
	cmp #PERBANK
	bcc @1
	sbc #PERBANK
	inc wB
@1:	sta wR
	jsr RowPtr
	stz VERA_CTRL           ; covers in place?
	lda #<VRAM_TILECOV
	sta VERA_ADDR_L
	lda #>VRAM_TILECOV
	sta VERA_ADDR_M
	lda #^VRAM_TILECOV
	sta VERA_ADDR_H
	lda VERA_DATA0
	sta wAny
@row:	lda wB
	sta $00
	lda #1                  ; port 1 reads the map, port 0 writes it
	jsr Seek
	lda #0
	jsr Seek
	stz wCov
	ldy #0
	ldx _wmW
	lda wAny
	bne @c
@f:	lda (wPtr),y            ; none: as they are
	sta VERA_DATA0
	iny
	lda (wPtr),y
	sta VERA_DATA0
	iny
	dex
	bne @f
	bra @adv
@c:	lda VERA_DATA1          ; (its tile)
	lda VERA_DATA1          ; its attribute: covered?
	cmp #$E0
	bcs @cov
	lda (wPtr),y
	sta VERA_DATA0
	iny
	lda (wPtr),y
	sta VERA_DATA0
	iny
	dex
	bne @c
	bra @next
@cov:	and #$F0                ; covered: the row it shows kept
	sta wHi
	lda (wPtr),y
	sta VERA_DATA0
	iny
	lda (wPtr),y
	and #$0F
	ora wHi
	sta VERA_DATA0
	iny
	inc wCov
	dex
	bne @c
@next:	lda wCov
	beq @adv
	jsr Shadows
@adv:	inc _wmY
	dec _wmH
	beq @end
	inc wR                  ; the next row of the banks
	lda wR
	cmp #PERBANK
	bne @2
	stz wR
	inc wB
	jsr RowPtr
	bra @3
@2:	lda wPtr
	clc
	adc #ROWB
	sta wPtr
	bcc @3
	inc wPtr+1
@3:	jmp @row
@end:	stz VERA_CTRL
	pla
	sta $00
	rts

; wall_word (gui.s, V102): ax = the word at (ptr1) in bank a (the picture's
; map entry of a card, for the chrome's corner over it)
_wall_word:
	ldx $00
	phx
	sta $00
	ldy #1
	lda (ptr1),y
	tax
	lda (ptr1)
	ply
	sty $00
	rts

; wPtr = $A000 + wR * 160 + _wmX * 2
RowPtr:	lda _wmX
	asl
	sta wPtr
	lda #$A0
	sta wPtr+1
	ldx wR
	beq @r
@m:	lda wPtr
	clc
	adc #ROWB
	sta wPtr
	bcc @1
	inc wPtr+1
@1:	dex
	bne @m
@r:	rts

; port VERA_CTRL = a at card _wmX of map row _wmY, increment 1
Seek:	sta VERA_CTRL
	lda _wmX
	asl
	sta VERA_ADDR_L
	lda _wmY
	clc
	adc #>(MAP & $FFFF)
	sta VERA_ADDR_M
	lda #^MAP | VERA_INC1
	sta VERA_ADDR_H
	rts

; the covered cards of row _wmY: their shadow byte's high nibble the row
; of their new entry (wPtr's attributes)
Shadows:
	ldy #0
	ldx _wmX
@c:	stz VERA_CTRL
	txa
	asl
	ina
	sta VERA_ADDR_L         ; the attribute
	lda _wmY
	clc
	adc #>(MAP & $FFFF)
	sta VERA_ADDR_M
	lda #^MAP               ; (increment 0)
	sta VERA_ADDR_H
	lda VERA_DATA0
	cmp #$E0
	bcc @n
	txa                     ; the shadow byte
	clc
	adc #TILE_SHADOW
	sta VERA_ADDR_L
	lda VERA_DATA0
	and #$0F
	sta wHi
	iny
	lda (wPtr),y
	dey
	and #$F0
	ora wHi
	sta VERA_DATA0
@n:	iny
	iny
	inx
	txa
	sec
	sbc _wmX
	cmp _wmW
	bne @c
	rts
