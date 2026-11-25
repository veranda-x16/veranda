; Veranda shell: the dragged icon's ghost (overlay 16; DECISIONS V193).
;
; While an icon is dragged (a window's entry, a desktop icon, a dock pin:
; mouse.c) a copy of it follows the pointer as a VERA sprite, in place of
; the outline drawn and drawn again. Its picture is what the screen shows
; there when the drag starts, composed as VERA composes it: the 1 bpp
; bitmap (layer 1 when it is shown and a bitmap, else layer 0), its ink 1
; + 16 * the layer's palette offset; under it layer 0, when on: the
; colour map's 1 bpp cards (each card's background nibble) or the tile
; desktop's 4 bpp tiles (their palette row, flips); anything else none.
; So every look, light or dark, the tile wallpaper and the colour icons
; show in their own colours: an 8 bpp sprite (32 x 32) shows any of the
; 256 entries and needs none of its own. The colour of the picture's first
; pixel (the cell's background) is left out, and every other pixel of the
; rest (a checkerboard): the ghost looks half transparent; the pointer
; (sprite 0, in front of sprite 2) stays over it.
;
; VERA sprite 2 (DrawSprite's slots 2-7 are the shell's tile pool, gui.s),
; its picture in sprite slot 1's unused end ($17800-$17BFF; the text
; prompt has its first 256 bytes, kernel/x/prompt.s). The kernel turns
; sprites 1-7 off when a program starts (AppReset's StateReset) and clears
; slots 1-7 when a program is put aside (bank W).
;
; void ghost_start(void) (mouse.c, when an icon's drag begins) r0, r1 the
;                       press; r2L the drag (0 a window's entry, 4 a
;                       desktop icon, 7 a dock pin: mouse.c's D_* less
;                       D_ICON), r2H the window's view, r3L its selection,
;                       the desktop icon or the pin, r3H the window: the
;                       picture's place (a window's cell: its icon, or a
;                       small icon's or a list's row's start; a desktop
;                       icon's tile; a pin's), then ghost_on
; void ghost_on(void)   r0 x, r1 y: the picture's corner on the screen (on
;                       a card), r2, r3 the pointer's place from it, r4L
;                       its rows of cards (4; 2: a list's row): shown at
;                       the pointer
; void ghost_move(void) to the pointer
; void ghost_off(void)
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.macpack longbranch

.export _ghost_on, _ghost_move, _ghost_off, _ghost_start
.import _ovl_go, _ovl_bk, _ovl_fn, _bView, _bDock, _view_cell, _dock_tile, _vx, _vy, _deskX, _dy, pusha

VRAM_SPRATTR = $1FC00
PIC_M   = $78                   ; the picture: $17800 (mid, bank 1)
ATTR    = VRAM_SPRATTR + 2 * 8  ; sprite 2's attributes

VAL     = $9F20
VAM     = $9F21
VAH     = $9F22
VD0     = $9F23
VCTRL   = $9F25
DCVIDEO = $9F29
L0CFG   = $9F2D
L0MAP   = $9F2E
L0TILE  = $9F2F
L0HSH   = $9F31
L1CFG   = $9F34
L1TILE  = $9F36
L1HSH   = $9F38

.segment "OVL16BSS"
gx:	.res 2          ; the pointer from the picture's corner
gy:	.res 2
ink:	.res 1          ; the bitmap's ink
kind:	.res 1          ; layer 0 under it: 0 none, 1 1 bpp cards, 2 4 bpp tiles
bmm:	.res 1          ; the bitmap's address (mid, bank; lo 0)
bmb:	.res 1
stride:	.res 1          ; its bytes a row (80, 40)
mapm:	.res 1          ; layer 0's map (mid, bank)
mapb:	.res 1
mapsh:	.res 1          ; its rows' bytes: 64 << mapsh
tilm:	.res 1          ; its tiles (mid, bank)
tilb:	.res 1
xc:	.res 1          ; the picture's first card across, down
yc:	.res 1
y0:	.res 2          ; its first row
rows:	.res 1          ; its rows of cards
cr:	.res 1          ; the card: row, column
cc:	.res 1
rw8:	.res 1          ; the row in the card
bits:	.res 1          ; the bitmap's byte
ent:	.res 2          ; the card's map entry
tb:	.res 4          ; the tile's row
key:	.res 1          ; the background's colour
keyset:	.res 1
buf:	.res 64         ; a card's pixels
ax:	.res 2
ay:	.res 2
va0:	.res 3          ; an address (lo, mid, bank)

.segment "OVERLAY16"

; port 0 at va0, increment 1
port:	stz VCTRL
	lda va0
	sta VAL
	lda va0+1
	sta VAM
	lda va0+2
	and #1
	ora #$10
	sta VAH
	rts

; va0 += ax
addax:	clc
	lda va0
	adc ax
	sta va0
	lda va0+1
	adc ax+1
	sta va0+1
	bcc @r
	inc va0+2
@r:	rts

; the layers: the bitmap's place and ink, layer 0's kind and places
layers:	stz VCTRL
	stz kind
	lda DCVIDEO
	and #$20                ; layer 1 on and a bitmap: the bitmap there
	beq @b0
	lda L1CFG
	and #4
	beq @b0
	ldx L1TILE
	ldy L1HSH
	lda DCVIDEO             ; layer 0 under it, when on and tiles
	and #$10
	beq @bm
	lda L0CFG
	and #7
	cmp #2                  ; 4 bpp tiles (the tile desktop)
	beq @k2
	cmp #0                  ; 1 bpp cards (the colour map)
	bne @bm
	lda #1
	bra @k
@k2:	lda #2
@k:	sta kind
	bra @bm
@b0:	ldx L0TILE
	ldy L0HSH
@bm:	tya                     ; the ink: 1 + 16 * the palette offset
	asl a
	asl a
	asl a
	asl a
	ora #1
	sta ink
	txa                     ; bit 0: 640 wide
	lsr a
	lda #40
	bcc @w
	lda #80
@w:	sta stride
	txa                     ; (base >> 2) << 11: << 9
	and #$FC
	asl a
	sta bmm
	lda #0
	rol a
	sta bmb
	lda L0MAP               ; layer 0's map: base << 9
	asl a
	sta mapm
	lda #0
	rol a
	sta mapb
	lda L0CFG               ; its width: 32 << n entries
	lsr a
	lsr a
	lsr a
	lsr a
	and #3
	sta mapsh
	lda L0TILE              ; its tiles
	and #$FC
	asl a
	sta tilm
	lda #0
	rol a
	sta tilb
	rts

; a pixel not of the bitmap at column x (0-7) of the card -> its colour
; (0: none)
paper:	lda kind
	beq @r
	cmp #1
	beq @k1
	lda ent+1               ; 4 bpp: the nibble (flipped across)
	and #4
	beq @h
	txa
	eor #7
	tax
@h:	txa
	lsr a
	tay
	lda tb,y
	bcs @lo
	lsr a
	lsr a
	lsr a
	lsr a
@lo:	and #15
	beq @r
	sta ay
	lda ent+1               ; in its palette row
	and #$F0
	ora ay
@r:	rts
@k1:	lda ent+1               ; 1 bpp: the background nibble
	lsr a
	lsr a
	lsr a
	lsr a
	rts

; the card (cr, cc) into buf: its pixels' colours, the background's and
; every other one 0
card:	lda kind                ; its map entry: map + (yc + cr) << (6 + mapsh) + (xc + cc) * 2
	beq @r0
	lda yc
	clc
	adc cr
	sta ay
	stz ay+1
	ldx mapsh
	inx
	inx
	inx
	inx
	inx
	inx
@s:	asl ay
	rol ay+1
	dex
	bne @s
	lda xc
	clc
	adc cc
	asl a
	sta ax
	lda #0
	rol a
	sta ax+1
	clc
	lda ax
	adc ay
	sta ax
	lda ax+1
	adc ay+1
	sta ax+1
	stz va0
	lda mapm
	sta va0+1
	lda mapb
	sta va0+2
	jsr addax
	jsr port
	lda VD0
	sta ent
	lda VD0
	sta ent+1
@r0:	stz rw8
@row:	lda cr                  ; the bitmap's byte: (y0 + cr * 8 + rw8) * stride + xc + cc
	asl a
	asl a
	asl a
	clc
	adc rw8
	adc y0
	sta ay
	lda y0+1
	adc #0
	sta ay+1
	stz ax                  ; ax = ay * stride
	stz ax+1
	lda stride
@m:	lsr a
	bcc @mn
	tax
	clc
	lda ax
	adc ay
	sta ax
	lda ax+1
	adc ay+1
	sta ax+1
	txa
@mn:	asl ay
	rol ay+1
	cmp #0
	bne @m
	lda xc
	clc
	adc cc
	adc ax
	sta ax
	bcc @m2
	inc ax+1
@m2:	stz va0
	lda bmm
	sta va0+1
	lda bmb
	sta va0+2
	jsr addax
	jsr port
	lda VD0
	sta bits
	lda kind                ; 4 bpp: the tile's row, tile * 32 + row * 4 (flipped down)
	cmp #2
	bne @px
	lda ent+1
	and #3
	sta ax+1
	lda ent
	ldx #5
@x32:	asl a
	rol ax+1
	dex
	bne @x32
	sta ax
	lda rw8
	tax
	lda ent+1
	and #8
	beq @f
	txa
	eor #7
	tax
@f:	txa
	asl a
	asl a
	ora ax
	sta ax
	stz va0
	lda tilm
	sta va0+1
	lda tilb
	sta va0+2
	jsr addax
	jsr port
	ldx #0
@t:	lda VD0
	sta tb,x
	inx
	cpx #4
	bne @t
@px:	lda rw8                  ; the row's 8 pixels into buf
	asl a
	asl a
	asl a
	tay
	ldx #0
@p:	asl bits
	bcc @pp
	lda ink
	bra @pk
@pp:	phy
	phx
	jsr paper
	plx
	ply
@pk:	bit keyset              ; (the first pixel: the background's colour)
	bmi @kk
	sta key
	dec keyset
@kk:	cmp key
	beq @z
	pha                     ; every other pixel (x + y odd) left out
	txa
	eor rw8
	lsr a
	pla
	bcc @st
@z:	lda #0
@st:	sta buf,y
	iny
	inx
	cpx #8
	bne @p
	inc rw8
	lda rw8
	cmp #8
	jne @row
	rts

; buf to the picture's card (cr, cc): $17800 + (cr * 8 + i) * 32 + cc * 8
putcard:
	ldy #0
@r:	tya                     ; (the row i = y / 8)
	lsr a
	lsr a
	lsr a
	sta ax
	lda cr
	asl a
	asl a
	asl a
	ora ax                  ; cr * 8 + i
	stz ax+1
	ldx #5
@s:	asl a
	rol ax+1
	dex
	bne @s
	sta ax
	lda cc
	asl a
	asl a
	asl a
	ora ax
	sta va0
	lda ax+1
	clc
	adc #PIC_M
	sta va0+1
	lda #1
	sta va0+2
	jsr port
	ldx #8
@b:	lda buf,y
	sta VD0
	iny
	dex
	bne @b
	cpy #64
	bne @r
	rts

; port 0 at sprite 2's attribute byte a, increment 1
attr:	stz VCTRL
	clc
	adc #<ATTR
	sta VAL
	lda #>ATTR
	sta VAM
	lda #$11
	sta VAH
	rts

_ghost_on:
	lda r2L
	sta gx
	lda r2H
	sta gx+1
	lda r3L
	sta gy
	lda r3H
	sta gy+1
	lda r4L
	sta rows
	lda r1L
	sta y0
	lda r1H
	sta y0+1
	lsr a                   ; (y < 512)
	lda r1L
	ror a
	lsr a
	lsr a
	sta yc
	lda r0H                 ; (x < 1024: r0H's two bits)
	asl a
	asl a
	asl a
	asl a
	asl a
	sta xc
	lda r0L
	lsr a
	lsr a
	lsr a
	ora xc
	sta xc
	jsr layers
	stz keyset
	stz cr
@r:	stz cc
@c:	jsr card
	jsr putcard
	inc cc
	lda cc
	cmp #4
	bne @c
	inc cr
	lda cr
	cmp rows
	bne @r
	stz va0                  ; the rows below it: none (rows * 8 * 32 = rows << 8 on)
	lda rows
	clc
	adc #PIC_M
	sta va0+1
	lda #1
	sta va0+2
	jsr port
	lda #4
	sec
	sbc rows
	beq @a
	tax
	ldy #0
@zr:	stz VD0
	iny
	bne @zr
	dex
	bne @zr
@a:	lda #0                  ; the picture's address ($17800 >> 5), 8 bpp
	jsr attr
	lda #<($17800 >> 5)
	sta VD0
	lda #>($17800 >> 5) | $80
	sta VD0
	jsr pos
	lda #$0C                ; in front of the layers
	sta VD0
	lda #$A0                ; 32 x 32, palette offset 0
	sta VD0
	rts

_ghost_start:
	lda r0L                 ; (the press, for now)
	sta gx
	lda r0H
	sta gx+1
	lda r1L
	sta gy
	lda r1H
	sta gy+1
	lda #4
	sta rows
	lda r2L
	bne @nw
	lda r2H                 ; a window's: view_cell(window, its selection)
	pha
	lda r3H
	jsr pusha
	lda _bView
	sta _ovl_bk
	lda #<_view_cell
	sta _ovl_fn
	lda #>_view_cell
	sta _ovl_fn+1
	lda r3L
	jsr _ovl_go
	pla                     ; the icons: the icon (2 cards in)
	ldx #16
	cmp #0
	beq @ic
	lsr rows                ; the small icons, the list: a row (16 lines)
	ldx #0
	cmp #1
	beq @ic
	ldx #8                  ; (the list's badge a card in)
@ic:	txa
	clc
	adc _vx
	sta _vx
	bcc @go
	inc _vx+1
	bra @go
@nw:	cmp #4
	bne @dk
	lda _deskX              ; a desktop icon: cards deskX + 2, its dy
	stz _vx+1
	asl a
	rol _vx+1
	asl a
	rol _vx+1
	asl a
	rol _vx+1
	clc
	adc #16
	sta _vx
	bcc @d1
	inc _vx+1
@d1:	lda r3L
	asl a
	tax
	lda _dy,x
	sta _vy
	lda _dy+1,x
	sta _vy+1
	bra @go
@dk:	lda _bDock              ; a pin: dock_tile(it)
	sta _ovl_bk
	lda #<_dock_tile
	sta _ovl_fn
	lda #>_dock_tile
	sta _ovl_fn+1
	lda r3L
	jsr _ovl_go
@go:	lda _vx                 ; (not shown: none)
	and _vx+1
	cmp #$FF
	beq @r
	lda _vx
	sta r0L
	lda _vx+1
	sta r0H
	lda _vy
	sta r1L
	lda _vy+1
	sta r1H
	sec                     ; the pointer from the corner
	lda gx
	sbc _vx
	sta r2L
	lda gx+1
	sbc _vx+1
	sta r2H
	sec
	lda gy
	sbc _vy
	sta r3L
	lda gy+1
	sbc _vy+1
	sta r3H
	lda rows
	sta r4L
	jmp _ghost_on
@r:	rts

; to the pointer: the pointer less gx, gy
_ghost_move:
	lda #2
	jsr attr
pos:	sec
	lda mouseXPos
	sbc gx
	sta VD0
	lda mouseXPos+1
	sbc gx+1
	and #3
	sta VD0
	sec
	lda mouseYPosW
	sbc gy
	sta VD0
	lda mouseYPosW+1
	sbc gy+1
	and #3
	sta VD0
	rts

_ghost_off:
	lda #6
	jsr attr
	stz VD0
	rts
