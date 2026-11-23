; Veranda shell: the colour chrome on the tile desktop (overlay 11, with
; wall.c; DECISIONS V102).
;
; On the full-colour desktop (a wallpaper of version 3 in the kernel's tile
; mode, V101) a card of the colour map can show any 8 x 8 picture in one
; palette row under the ink. The shell keeps a pool of tiles of its own,
; tiles 608-991 (VRAM $17C00-$1ABFF: sprite slots 2-7, which nothing uses
; while the shell runs; a desk accessory's pictures there are put aside
; with VRAM and come back), and writes their map entries where ColorRect
; would write a solid colour:
;   - its six tiles (folder, up, document, card, printer, trash) as colour
;     icons (tools/mkgui.py: gui.inc, guiart.s; 4 x 4 cards in palette row
;     13), in the windows, on the desktop and in the dock;
;   - every other tile's corners rounded (each colour's four corners: the
;     colour inside the frame, the paper outside; made with the pool);
;   - the front window's title band a gradient of the accent (two tiles in
;     row 13) and its corners rounded (radius 6; their ink: gui_ink);
;   - where a corner lies on the picture (a window's, a desk icon's, the
;     dock's) its card is composed: the picture's tile with the corner over
;     it, in the picture's palette row, whose entries 11-15 are the
;     chrome's shades (gui_pal); on anything else the corner stays square,
;     as before.
; Palette row 13: 1-10 the icons' colours, 11-15 the shades (11 the accent
; lighter, 12 the accent, 13 darker, 14 chrome, 15 white); the same 11-15
; in the picture's rows 2-12. The composed tiles have fixed places (a
; window's corners, a desk icon's, the dock's): nothing is allocated or
; freed. guiOn (main.c) is 0 without a picture of version 3 (the pattern,
; the plain colour, 640 x 240, Classic): the look of before.
;
; void gui_init(void)       the pool's corners (wall.c, after the art:
;                           guiart.s's gui_artA, gui_artB)
; void gui_pal(void)        row 13, the shades in rows 2-12
; void gui_icon(cx, cy, w, t, d)  window w's tile t (2: the desk's) at
;                           cards cx, cy (4 x 4; its colour tile_colour's):
;                           a colour icon, or its corners rounded; d a
;                           desktop icon (0-2: its corners on the picture),
;                           else $FF; without guiOn look_rect's colour
; void gui_win(w)           window w's title band and corners (after its
;                           solid colours: chrome_colours)
; void gui_ink(w, which)    its corners' ink (1 the top two, 2 the bottom
;                           two): round on the picture, else square
; void gui_plate(x0, x1, y0, y1)  the dock's plate's corners
; void gui_box(band)        a message box's chrome (V103: its user routine)
; void gui_unbox(void)      the cards it changed put back, after the box
.include "veranda.inc"
.include "x16hw.inc"
.include "gui.inc"

.export _gui_init, _gui_pal, _gui_icon, _gui_win, _gui_ink, _gui_plate, _gui_box, _gui_unbox
.import _colClip, _colX0, _colX1, _colY0, _colY1, _look_rect, _guiOn
.import _wallBank, _wall_word, _wins, _front, _ndesk, _deskX, _dy, _theme
.import _ovl_go, _ovl_bk, _ovl_fn, _bTile, _tile_colour
.importzp c_sp, ptr1, ptr2, tmp1, tmp2, tmp3, tmp4
.import incsp4, pusha, pushax

MAP     = VRAM_FREE
POOL    = 608                   ; the pool's first tile (VRAM $17C00)
CORN    = POOL + GUI_NART       ; colour c's corner q: CORN + 4c + q (row 0)
DYN     = CORN + 64             ; composed: window w's corner q DYN + 4w + q,
DDESK   = DYN + 8               ; desk icon i's DDESK + 4i + q,
DDOCK   = DYN + 20              ; the dock's DDOCK + q,
DBOX    = DYN + 24              ; the message box's DBOX + q
GROW    = 13                    ; the shell's palette row
.assert DBOX + 4 <= 992, error, "gui.s: the pool is tiles 608-991"
BOXX0   = 28                    ; the kernel's default box at 640 x 480 (kernel/u/dlg.s:
BOXX1   = 51                    ; 224-415 by 192-287, its shadow 8 down and right;
BOXY0   = 24                    ; covered: cards 28-52, rows 24-36)
BOXY1   = 35
BANDH   = 3                     ; its title band: card rows 24-26
NSAVE   = BANDH * (BOXX1 - BOXX0 + 1) + 2
WINSZ   = 225                   ; sizeof (struct win) (shell.h; wall.c checks it)
WOPEN   = 0                     ; its fields: open, x, w (cards), y, h (words, pixels)
WX      = 1
WW      = 2
WY      = 3
WH      = 5
TPAPER  = 0                     ; theme.h: palette entries
TINK    = 1
TCHROME = 2

.segment "OVL11BSS"
gLo:	.res 1                  ; a map entry (gLo, gHi in this order: bget fills them)
gHi:	.res 1
gX:	.res 1                  ; its card
gY:	.res 1
gSlot:	.res 2                  ; a pool tile
gArt:	.res 2                  ; 32 bytes of art
gMask:	.res 2                  ; its 8 mask bytes
sbuf:	.res 32                 ; the tile under it
abuf:	.res 32                 ; a solid colour's art
gW:	.res 1                  ; what lies over the card ($FF: the dock)
cx:	.res 1
cy:	.res 1
gT:	.res 1
gC:	.res 1
gD:	.res 1
gK:	.res 1                  ; the icon's kind, $FF none
gI:	.res 1
gJ:	.res 1
gQ:	.res 1
gF:	.res 1                  ; window: in front
x0:	.res 1
x1:	.res 1
y0:	.res 1
y1:	.res 1
gWh:	.res 1                  ; gui_ink's which
it:	.res 2                  ; the corner's row (pixels)
shd:	.res 10                 ; the five shades
gSel:	.res 1                  ; Onto's art: a pool tile, or $80 + c solid c
gS:	.res 1                  ; Onto's composed tile (gSlot - DYN)
gB:	.res 1                  ; gui_win: the corners alone
gE:	.res 1                  ; gui_win: the gradient's last column + 1
kX:	.res 24                 ; each composed tile's card, art and palette
kY:	.res 24                 ; row (its picture's) as made: the same again
kA:	.res 24                 ; is not composed again ($FF: none)
kR:	.res 24
bSave:	.res 2 * NSAVE          ; the box's cards' entries before it (tile, attribute)
bN:	.res 1                  ; bSave's next
bOn:	.res 1                  ; the box: $40 drawing it, 1 up, $80 putting back, 0 none

.segment "OVERLAY11"

;---------------------------------------------------------------- the map

; port 0 at byte a of map row gY, VERA_ADDR_H y
At:	stz VERA_CTRL
	sta VERA_ADDR_L
	lda gY
	clc
	adc #>(MAP & $FFFF)
	sta VERA_ADDR_M
	sty VERA_ADDR_H
	rts

; map entry gLo, gHi at gX, gY: only in the colour clip; a card a menu or a
; dialog box covers keeps the row it shows, its own goes into its shadow
; byte (kernel/s/tiles.s's rules, as wall_map's)
Put:	jsr InClip
	bcs @r
	stz VERA_CTRL           ; covers in place?
	lda #<VRAM_TILECOV
	sta VERA_ADDR_L
	lda #>VRAM_TILECOV
	sta VERA_ADDR_M
	lda #^VRAM_TILECOV
	sta VERA_ADDR_H
	lda VERA_DATA0
	beq @open
	lda gX                  ; its attribute: covered?
	asl
	ina
	ldy #^MAP
	jsr At
	lda VERA_DATA0
	cmp #$E0
	bcc @open
	and #$F0                ; covered: the row it shows kept
	sta tmp1
	lda gHi
	and #$0F
	ora tmp1
	sta VERA_DATA0
	dec VERA_ADDR_L         ; the tile's low byte
	lda gLo
	sta VERA_DATA0
	lda gX                  ; its own row into the shadow byte
	clc
	adc #TILE_SHADOW
	jsr At                  ; (y: ^MAP still)
	lda VERA_DATA0
	and #$0F
	sta tmp1
	lda gHi
	and #$F0
	ora tmp1
	sta VERA_DATA0
@r:	rts
@open:	lda gX
	asl
	ldy #^MAP | VERA_INC1
	jsr At
	lda gLo
	sta VERA_DATA0
	lda gHi
	sta VERA_DATA0
	rts

; carry clear: gX, gY in the colour clip (or it is off)
InClip:	lda _colClip
	beq @y
	lda gX
	cmp _colX0
	bcc @n
	lda _colX1
	cmp gX
	bcc @n
	lda gY
	cmp _colY0
	bcc @n
	lda _colY1
	cmp gY
	bcc @n
@y:	clc
	rts
@n:	sec
	rts

; art tile a at gX, gY: a pool tile in row 13, or $80 + c solid c
Art:	tax
	bmi @s
	clc
	adc #<POOL
	sta gLo
	lda #GROW << 4 | >POOL
	adc #0
	bra @w
@s:	and #15
	sta gLo
	lda #GROW << 4
@w:	sta gHi
	jmp Put

; pool tile ax at gX, gY in palette row 0
Pool0:	sta gLo
	stx gHi
	jmp Put

;---------------------------------------------------------------- tiles

; port 0 at tile a (low), x (high) of VRAM_TILES, increment 1
Tile:	stz VERA_CTRL
	sta tmp1
	asl
	asl
	asl
	asl
	asl
	sta VERA_ADDR_L
	txa
	and #3
	asl
	asl
	asl
	asl
	asl
	sta tmp2
	lda tmp1
	lsr
	lsr
	lsr
	ora tmp2
	clc
	adc #>(VRAM_TILES & $FFFF)
	sta VERA_ADDR_M
	lda #^VRAM_TILES | VERA_INC1
	sta VERA_ADDR_H
	rts

; pool tile gSlot = sbuf where gMask's bit is 0, gArt where it is 1 (a
; mask byte a row, bit 7 the left pixel)
Combine:
	lda gSlot
	ldx gSlot+1
	jsr Tile
	lda gArt
	sta ptr1
	lda gArt+1
	sta ptr1+1
	lda gMask
	sta ptr2
	lda gMask+1
	sta ptr2+1
	ldy #0                  ; the byte
@row:	tya
	lsr
	lsr
	sta tmp4
	phy
	ldy tmp4
	lda (ptr2),y            ; the row's mask
	sta tmp3
	ply
	ldx #4
	cmp #$FF
	beq @art
	cmp #0
	beq @pic
@b:	lda #0                  ; its two bits: the nibbles taken from gArt
	asl tmp3
	rol
	asl tmp3
	rol
	phx
	tax
	lda Nib,x
	sta tmp4
	plx
	lda sbuf,y              ; sbuf ^ ((sbuf ^ art) & nibbles)
	eor (ptr1),y
	and tmp4
	eor sbuf,y
	sta VERA_DATA0
	iny
	dex
	bne @b
@nr:	cpy #32
	bne @row
	rts
@art:	lda (ptr1),y            ; the row all art
	sta VERA_DATA0
	iny
	dex
	bne @art
	bra @nr
@pic:	lda sbuf,y              ; the row all under it
	sta VERA_DATA0
	iny
	dex
	bne @pic
	bra @nr

; abuf all colour a; gArt = abuf
Solid:	asl
	asl
	asl
	asl
	sta tmp1
	lsr
	lsr
	lsr
	lsr
	ora tmp1
	ldx #31
@f:	sta abuf,x
	dex
	bpl @f
	lda #<abuf
	sta gArt
	lda #>abuf
	sta gArt+1
	rts

; gMask = guiMask + 8a
Mask:	asl
	asl
	asl
	clc
	adc #<guiMask
	sta gMask
	lda #>guiMask
	adc #0
	sta gMask+1
	rts

; gArt = guiArt's tile a (in the pool: read back from VRAM into abuf)
ArtOf:	clc
	adc #<POOL
	pha
	lda #>POOL
	adc #0
	tax
	pla
	jsr Tile
	ldx #0
@r:	lda VERA_DATA0
	sta abuf,x
	inx
	cpx #32
	bne @r
	lda #<abuf
	sta gArt
	lda #>abuf
	sta gArt+1
	rts

; card gX, gY of the picture with art gSel over it where mask a is 1, into
; pool tile gSlot (DYN on), its map entry: only in the colour clip; not
; composed again while its card and art are the ones it was made for
Onto:	jsr Mask
	jsr InClip
	bcc @in
	rts
@in:	lda gSlot               ; the cache
	sec
	sbc #<DYN
	sta gS
	tax
	lda gX
	cmp kX,x
	bne @new
	lda gY
	cmp kY,x
	bne @new
	lda gSel
	cmp kA,x
	bne @new
	lda kR,x
	sta gHi
	jmp OntoPut
@new:	lda gX
	sta kX,x
	lda gY
	sta kY,x
	lda gSel
	sta kA,x
	bmi @sol                ; the art
	jsr ArtOf
	bra @pe
@sol:	and #15
	jsr Solid
@pe:	lda gY                  ; the picture's entry from its banks (51 rows
	ldx _wallBank           ; of 160 bytes in the third, the rest in the
	inx                     ; fourth)
	inx
	cmp #51
	bcc @1
	sbc #51
	inx
@1:	sta tmp3                ; the row in the bank
	phx
	stz tmp4                ; row * 32
	ldx #5
@m:	asl tmp3
	rol tmp4
	dex
	bne @m
	lda tmp3
	sta ptr1
	lda tmp4
	sta ptr1+1
	asl tmp3                ; * 128
	rol tmp4
	asl tmp3
	rol tmp4
	lda gX                  ; + * 32 + gX * 2
	asl
	clc
	adc ptr1
	sta ptr1
	bcc @5
	inc ptr1+1
@5:	lda tmp3                ; ($A000 on)
	clc
	adc ptr1
	sta ptr1
	lda tmp4
	adc ptr1+1
	adc #$A0
	sta ptr1+1
	pla
	jsr _wall_word          ; (resident: it maps the bank)
	sta gLo
	stx gHi
Comp:	; the tile of entry gLo, gHi as it shows (its flips undone) into sbuf
	lda gLo
	ldx gHi
	jsr Tile
	ldy #0                  ; the flips as an index's XOR: v $1C, h 3
	lda gHi
	and #8
	beq @2
	ldy #$1C
@2:	lda gHi
	and #4
	sta tmp3
	beq @3
	tya
	ora #3
	tay
@3:	sty tmp4
	ldx #0
@rd:	lda VERA_DATA0
	ldy tmp3                ; h: the nibbles swapped
	beq @4
	asl
	adc #$80
	rol
	asl
	adc #$80
	rol
@4:	pha
	txa
	eor tmp4
	tay
	pla
	sta sbuf,y
	inx
	cpx #32
	bne @rd
	jsr Combine
	lda gHi                 ; the entry: the slot in the picture's row
	and #$F0
	bit bOn                 ; (the box: no cache, the entry as it is)
	bvc @kr
	ora gSlot+1
	sta gHi
	lda gSlot
	sta gLo
	rts
@kr:	ldx gS
	sta kR,x
OntoPut:	ora gSlot+1
	sta gHi
	lda gSlot
	sta gLo
	jmp Put

; gSlot = a + x * 256
Slot:	sta gSlot
	stx gSlot+1
	rts

;---------------------------------------------------------------- the picture?

; carry clear if card gX, gY shows the picture under gW (a window; $FF the
; dock): not on a window below it (with its shadow), not by the desktop's
; icons
OnPic:	ldx #0
@o:	cpx gW
	beq @n
	lda gW
	cmp #$FF
	beq @c
	cmp _front              ; (a window behind has none below it)
	bne @n
@c:	jsr WinPtr
	ldy #WOPEN
	lda (ptr1),y
	beq @n
	ldy #WX                 ; x <= gX <= x + w
	lda (ptr1),y
	sta tmp1
	lda gX
	cmp tmp1
	bcc @n
	ldy #WW
	lda (ptr1),y
	clc
	adc tmp1
	cmp gX
	bcc @n
	ldy #WY                 ; y / 8 <= gY <= (y + h) / 8
	jsr Card
	sta tmp1
	lda gY
	cmp tmp1
	bcc @n
	ldy #WH
	jsr Card
	clc
	adc tmp1
	cmp gY
	bcs @no
@n:	inx
	cpx #NWIN
	bne @o
	ldx #0                  ; the desktop's icons: cards deskX - 1 .. + 10,
@d:	cpx _ndesk              ; their rows .. + 5
	beq @yes
	lda gX
	ina
	cmp _deskX
	bcc @dn
	lda _deskX
	clc
	adc #10
	cmp gX
	bcc @dn
	txa
	asl
	tay
	lda _dy,y
	sta tmp2
	lda _dy+1,y
	lsr
	ror tmp2
	lsr
	ror tmp2
	lsr
	ror tmp2
	lda gY
	cmp tmp2
	bcc @dn
	lda tmp2
	adc #4                  ; (carry set: + 5)
	cmp gY
	bcs @no
@dn:	inx
	bra @d
@yes:	clc
	rts
@no:	sec
	rts

NWIN = 2

; ptr1 = &wins[x]
WinPtr:	lda #<_wins
	sta ptr1
	lda #>_wins
	sta ptr1+1
	txa
	beq @r
	lda ptr1
	clc
	adc #<WINSZ
	sta ptr1
	bcc @r
	inc ptr1+1
@r:	rts

; a = the word at (ptr1),y / 8
Card:	lda (ptr1),y
	sta tmp2
	iny
	lda (ptr1),y
	lsr
	ror tmp2
	lsr
	ror tmp2
	lsr
	ror tmp2
	lda tmp2
	rts

;---------------------------------------------------------------- the calls

_gui_init:
	stz bOn                 ; (no box; the BSS is not cleared)
	ldx #31                 ; sbuf 0, the cache empty
@z:	stz sbuf,x
	lda #$FF
	cpx #24
	bcs @z1
	sta kA,x
@z1:	dex
	bpl @z
	stz gC
@c:	lda gC
	jsr Solid
	stz gQ
@q:	lda gQ
	jsr Mask
	lda gC                  ; CORN + 4c + q
	asl
	asl
	ora gQ
	clc
	adc #<CORN
	sta gSlot
	lda #>CORN
	adc #0
	sta gSlot+1
	jsr Combine
	inc gQ
	lda gQ
	cmp #4
	bne @q
	inc gC
	lda gC
	cmp #16
	bne @c
	rts

; void gui_icon(cx, cy, w, t, d): its colour tile_colour(w, t)'s
_gui_icon:
	sta gD
	ldy #0
	lda (c_sp),y
	sta gT
	lda #$FF                ; the shell's six: their art (no colour needed)
	sta gK
	lda gT
	bpl @k
	and #$1F
	sec
	sbc #GUI_KIND0
	cmp #6
	bcs @k
	asl
	asl
	asl
	asl
	sta gK                  ; (16 cards each)
	lda _guiOn
	bne @kc
@k:	ldy #1
	lda (c_sp),y            ; tile_colour(w, t) (overlay 10)
	jsr pusha
	lda _bTile
	sta _ovl_bk
	lda #<_tile_colour
	sta _ovl_fn
	lda #>_tile_colour
	sta _ovl_fn+1
	lda gT
	jsr _ovl_go
	sta gC
@kc:	ldy #2
	lda (c_sp),y
	sta cy
	iny
	lda (c_sp),y
	sta cx
	lda _guiOn
	bne @on
	lda #4                  ; look_rect(cx, 4, cy, 4, c): its arguments in
	ldy #0                  ; place (the stack: h 0, y 1, w 2, x 3)
	sta (c_sp),y
	ldy #2
	sta (c_sp),y
	dey
	lda cy
	sta (c_sp),y
	lda gC
	jmp _look_rect
@on:	jsr incsp4
	stz gJ
@j:	stz gI
@i:	lda cx
	clc
	adc gI
	sta gX
	lda cy
	clc
	adc gJ
	sta gY
	ldx #$FF                ; the corner: 0-3, $FF none
	lda gI
	beq @x
	cmp #3
	bne @nq
@x:	lda gJ
	beq @y
	cmp #3
	bne @nq
@y:	lda gI
	lsr                     ; (3: 1)
	and #1
	sta gQ
	lda gJ
	and #2
	ora gQ
	tax
@nq:	stx gQ
	lda gK
	bmi @plain
	lda gJ                  ; guiIcon[k + 4j + i]
	asl
	asl
	ora gI
	ora gK
	tax
	lda guiIcon,x
	ldx gQ
	bmi @art
	ldx gD
	cpx #3
	bcs @art
	sta gSel                ; a desktop icon's corner: on the picture
	lda gD
	asl
	asl
	ora gQ
	clc
	adc #<DDESK
	ldx #>DDESK
	bcc @s
	inx
@s:	jsr Slot
	lda gQ
	jsr Onto
	bra @next
@art:	jsr Art
	bra @next
@plain:	ldx gQ                  ; another tile: its colour, rounded corners
	bmi @sol
	lda gC
	asl
	asl
	ora gQ
	clc
	adc #<CORN
	ldx #>CORN
	bcc @p
	inx
@p:	jsr Pool0
	bra @next
@sol:	lda gC
	ldx #0
	jsr Pool0
@next:	inc gI
	lda gI
	cmp #4
	beq @nj
	jmp @i
@nj:	inc gJ
	lda gJ
	cmp #4
	beq @r
	jmp @j
@r:	rts

; the window's place: x0, x1, y0, y1 (cards), gF (in front), gW = a
Place:	sta gW
	tax
	jsr WinPtr
	ldy #WX
	lda (ptr1),y
	sta x0
	ldy #WW
	clc
	adc (ptr1),y
	dea
	sta x1
	ldy #WY
	jsr Card
	sta y0
	ldy #WH
	jsr Card
	clc
	adc y0
	dea
	sta y1
	stz gF
	lda gW
	cmp _front
	bne @r
	inc gF
@r:	rts

; gX, gY = corner gQ of x0, x1, y0, y1
Corner:	ldx x0
	lda gQ
	lsr
	bcc @1
	ldx x1
@1:	stx gX
	ldx y0
	lsr
	bcc @2
	ldx y1
@2:	stx gY
	rts

; void gui_win(w): + $80 the corners alone (after a move: its title band
; moved with it)
_gui_win:
	tax
	and #$80
	sta gB
	txa
	and #$7F
	jsr Place
	lda gF                  ; in front: the title band's gradient
	beq @c
	lda gB
	bne @c
	lda x1                  ; its columns: x0 + 1 .. x1 - 1, in the clip
	sta gE
	lda x0
	sta gI
	lda _colClip
	beq @y
	lda _colX1
	cmp x1
	bcs @e
	ina
	sta gE
@e:	lda _colX0
	beq @y
	dea
	cmp gI
	bcc @y
	sta gI
@y:	lda y0
	sta gY
@row:	lda _colClip            ; (a row outside the clip: none)
	beq @ro
	lda gY
	cmp _colY0
	bcc @nr
	lda _colY1
	cmp gY
	bcc @nr
@ro:	ldx gI
@col:	inx
	cpx gE
	bcs @nr
	stx gX
	lda gY
	sec
	sbc y0
	clc
	adc #GUI_GRAD
	jsr Art
	ldx gX
	bra @col
@nr:	inc gY
	lda gY
	sec
	sbc y0
	cmp #2
	bne @row
@c:	stz gQ
@q:	jsr Corner
	jsr OnPic
	bcc @pic
	lda gF                  ; not on the picture: square (the front's top
	beq @n                  ; two on the gradient)
	lda gQ
	cmp #2
	bcs @n
	lda #GUI_GRAD
	jsr Art
	bra @n
@pic:	lda #$80 | 14         ; chrome; in front the gradient's top tile
	ldx gF
	beq @ch
	ldx gQ
	cpx #2
	bcs @ch
	lda #GUI_GRAD
@ch:	sta gSel
	lda gW                  ; DYN + 4w + q
	asl
	asl
	ora gQ
	clc
	adc #<DYN
	ldx #>DYN
	bcc @s
	inx
@s:	jsr Slot
	lda gQ
	ora #4
	jsr Onto
@n:	inc gQ
	lda gQ
	cmp #4
	bne @q
	rts

; void gui_plate(x0, x1, y0, y1)
_gui_plate:
	sta y1
	ldy #0
	lda (c_sp),y
	sta y0
	iny
	lda (c_sp),y
	sta x1
	iny
	lda (c_sp),y
	sta x0
	jsr incsp3
	lda _guiOn
	beq @r
	lda #$FF
	sta gW
	lda #$80                ; the paper
	sta gSel
	stz gQ
@q:	jsr Corner
	jsr OnPic
	bcs @n
	lda gQ
	clc
	adc #<DDOCK
	ldx #>DDOCK
	bcc @s
	inx
@s:	jsr Slot
	lda gQ
	ora #4
	jsr Onto
@n:	inc gQ
	lda gQ
	cmp #4
	bne @q
@r:	rts

incsp3:	lda c_sp
	clc
	adc #3
	sta c_sp
	bcc @r
	inc c_sp+1
@r:	rts

;---------------------------------------------------------------- the message box

; void gui_box(band): the shell's message boxes (main.c: DB_USR_ROUT, so
; in the kernel's DoDlgBox after the box is drawn; the default place at
; 640 x 480, its cards covered): its corners rounded (composed on what the
; card shows under the cover; the bottom right one on the shadow: ink);
; band: its first three card rows a title band (the gradient), a line
; under it; the shadow's two ends show what is under them, not the paper.
; The entries it changes are kept (bSave) for gui_unbox, after the box: the
; kernel gives back the covered cards' rows, not their tiles.
_gui_box:
	sta gB
	stz bN
	stz bOn
	lda _guiOn
	bne @on
	rts
@on:	lda #$40
	sta bOn
	jsr Cards
	lda #1
	sta bOn
	lda #52                 ; the shadow's ends
	sta gX
	lda #BOXY0
	sta gY
	jsr Uncov
	lda #BOXX0
	sta gX
	lda #BOXY1 + 1
	sta gY
	jsr Uncov
	lda #3                  ; the ink: corners round, the bottom right on the shadow
	sta gWh
	lda #BOXX0
	sta x0
	lda #BOXX1
	sta x1
	lda #BOXY0
	sta y0
	lda #BOXY1
	sta y1
	stz gQ
@q:	jsr Corner
	ldx gQ
	lda BoxInk,x
	sta gF
	jsr InkCorner
	inc gQ
	lda gQ
	cmp #4
	bne @q
	lda gB                  ; the band's line
	beq @r
	lda #<(BOXX0 * 8 + 1)
	sta r3L
	lda #>(BOXX0 * 8 + 1)
	sta r3H
	lda #<(BOXX1 * 8 + 6)
	sta r4L
	lda #>(BOXX1 * 8 + 6)
	sta r4H
	lda #<((BOXY0 + BANDH) * 8 - 1)
	sta r11L
	lda #>((BOXY0 + BANDH) * 8 - 1)
	sta r11H
	lda #$FF
	jmp WHorizontalLine
@r:	rts

; void gui_unbox(void): the cards gui_box changed as they were (after the
; box: their rows are back)
_gui_unbox:
	lda _guiOn
	beq @r
	lda bOn
	beq @r
	lda #$80
	sta bOn
	stz bN
	jsr Cards
	stz bOn
@r:	rts

; the box's cards: drawn (bOn 1) or put back (bOn $80), in the same order
Cards:	lda gB
	beq @c
	lda #BOXY0
	sta gY
@row:	ldx #BOXX0 - 1
@col:	inx
	cpx #BOXX1 + 1
	beq @nr
	stx gX
	lda gY                  ; (the first row's ends: the corners, below)
	cmp #BOXY0
	bne @k
	cpx #BOXX0
	beq @n
	cpx #BOXX1
	beq @n
@k:	jsr Keep
	bcs @n
	lda gY
	sec
	sbc #BOXY0
	cmp #2
	lda #$80 | 13           ; (its third row the darkest shade)
	bcs @a
	lda gY
	sec
	sbc #BOXY0
	clc
	adc #GUI_GRAD
@a:	jsr ArtE
	jsr PutRaw
@n:	ldx gX
	bra @col
@nr:	inc gY
	lda gY
	cmp #BOXY0 + BANDH
	bne @row
@c:	lda #BOXX0
	sta x0
	lda #BOXX1
	sta x1
	lda #BOXY0
	sta y0
	lda #BOXY1
	sta y1
	stz gQ
@q:	jsr Corner
	lda gQ
	cmp #3
	beq @nq                 ; (the bottom right: on the shadow, ink)
	jsr Keep
	bcs @nq
	jsr Real                ; what the card shows under the cover
	lda gHi
	cmp #2 << 4
	bcc @sq
	cmp #(GROW + 1) << 4
	bcs @sq
	lda gQ                  ; composed: the gradient's top tile or the paper
	ora #4
	jsr Mask
	lda gB
	beq @pap
	lda gQ
	cmp #2
	bcs @pap
	lda #GUI_GRAD
	jsr ArtOf
	bra @cs
@pap:	lda #0
	jsr Solid
@cs:	lda gQ
	clc
	adc #<DBOX
	sta gSlot
	lda #>DBOX
	adc #0
	sta gSlot+1
	jsr Comp
	jsr PutRaw
	bra @nq
@sq:	lda gB                  ; not composable: square; the band's top
	beq @nq                 ; corners its gradient
	lda gQ
	cmp #2
	bcs @nq
	lda #GUI_GRAD
	jsr ArtE
	jsr PutRaw
@nq:	inc gQ
	lda gQ
	cmp #4
	bne @q
	rts

; card gX, gY's entry kept in bSave (bOn 1), or put back from it (bOn $80:
; its tile, flips and tile bits; the row the kernel gave back): carry set
; when put back (nothing more to do)
Keep:	lda gX
	asl
	ldy #^MAP | VERA_INC1
	jsr At
	lda bN
	asl
	tax
	inc bN
	bit bOn
	bmi @back
	lda VERA_DATA0
	sta bSave,x
	lda VERA_DATA0
	sta bSave+1,x
	clc
	rts
@back:	lda bSave,x
	sta VERA_DATA0
	lda VERA_ADDR_L         ; (increment 1: the attribute next)
	pha
	lda VERA_DATA0
	and #$F0
	sta tmp1
	pla
	sta VERA_ADDR_L
	lda bSave+1,x
	and #$0F
	ora tmp1
	sta VERA_DATA0
	sec
	rts

; gLo, gHi = what card gX, gY shows under its cover (its tile; its own row,
; in the shadow byte)
Real:	lda gX
	asl
	ldy #^MAP | VERA_INC1
	jsr At
	lda VERA_DATA0
	sta gLo
	lda VERA_DATA0
	sta gHi
	jsr Shd
	and #$0F
	beq @r
	lda VERA_DATA0
	and #$F0
	sta tmp1
	lda gHi
	and #$0F
	ora tmp1
	sta gHi
@r:	rts

; port 0 on card gX's shadow byte (increment 0), a = it
Shd:	lda gX
	clc
	adc #TILE_SHADOW
	ldy #^MAP
	jsr At
	lda VERA_DATA0
	rts

; a covered card gX, gY shows what is under it (its own row): the kernel
; gives the same row back when it uncovers it
Uncov:	jsr Shd
	tax
	and #$0F
	beq @r
	txa
	and #$F0
	sta tmp1
	lda gX
	asl
	ina
	jsr At
	lda VERA_DATA0
	and #$0F
	ora tmp1
	sta VERA_DATA0
@r:	rts

; gLo, gHi = art tile a's entry (a pool tile in row 13, or $80 + c solid c)
ArtE:	tax
	bmi @s
	clc
	adc #<POOL
	sta gLo
	lda #GROW << 4 | >POOL
	adc #0
	sta gHi
	rts
@s:	and #15
	sta gLo
	lda #GROW << 4
	sta gHi
	rts

; entry gLo, gHi at gX, gY as it is (a covered card shows it; the kernel
; keeps the cover)
PutRaw:	lda gX
	asl
	ldy #^MAP | VERA_INC1
	jsr At
	lda gLo
	sta VERA_DATA0
	lda gHi
	sta VERA_DATA0
	rts

;---------------------------------------------------------------- the ink

; void gui_ink(w, which): the corners' rows 0-3 in the bitmap: on the
; picture the outside cleared and the arc (shell_rframe's radius 6), else
; square; written into VRAM on the screens dispBufferOn selects, in the
; kernel's clip when it is on (the scene) (a 640 x 480 screen: tile mode)
_gui_ink:
	sta gWh
	ldy #0
	lda (c_sp),y
	pha
	jsr incsp1
	ldx _guiOn
	bne @on
	pla
	rts
@on:	pla
	jsr Place
	stz gQ
@q:	lda gQ                  ; this corner wanted?
	and #2
	beq @t
	lda #2
	.byte $2C
@t:	lda #1
	and gWh
	beq @nq
	jsr Corner
	jsr OnPic
	lda #0                  ; the table: square 8, right 16
	rol
	asl
	asl
	asl
	sta gF
	lda gQ
	lsr
	bcc @l
	lda gF
	ora #16
	sta gF
@l:	jsr InkCorner
@nq:	inc gQ
	lda gQ
	cmp #4
	beq @dn
	jmp @q
@dn:	rts

; corner gQ of card gX, gY in the ink: Ink's rows from gF on
InkCorner:
	jsr ClipX
	lda tmp3
	bne @in
	rts
@in:	sta gI                  ; (the clip's pixels of the byte)
	lda gY                  ; the corner's first row
	jsr Pix
	sta it
	stx it+1
	lda gQ
	and #2
	beq @top
	lda it                  ; the bottom's: its card's last
	ora #7
	sta it
@top:	stz gJ
@j:	jsr Row
	lda gQ                  ; the next row: down from the top, up from the bottom
	and #2
	bne @up
	inc it
	bne @nx
	inc it+1
	bra @nx
@up:	lda it
	bne @u1
	dec it+1
@u1:	dec it
@nx:	inc gF
	inc gF
	inc gJ
	lda gJ
	cmp #4
	bne @j
	rts

incsp1:	inc c_sp
	bne @r
	inc c_sp+1
@r:	rts

; ax = a * 8
Pix:	ldx #0
	stx tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	ldx tmp1
	rts

; tmp3 = the pixels of card gX's byte in the kernel's clip ($FF: it is off)
ClipX:	lda #$FF
	sta tmp3
	lda clipOn
	beq @r
	lda gX
	jsr Pix
	sta ptr1
	stx ptr1+1
	sec                     ; leftMargin - x: the pixels left of it out
	lda leftMargin
	sbc ptr1
	tay
	lda leftMargin+1
	sbc ptr1+1
	bmi @hi
	bne @no
	cpy #8
	bcs @no
	lda #$FF
@s1:	dey
	bmi @d1
	lsr
	bra @s1
@d1:	sta tmp3
@hi:	sec                     ; rightMargin - x: the pixels right of it out
	lda rightMargin
	sbc ptr1
	tay
	lda rightMargin+1
	sbc ptr1+1
	bmi @no
	bne @r
	cpy #7
	bcs @r
	lda #$FF
@s2:	cpy #7
	beq @d2
	asl
	iny
	bra @s2
@d2:	and tmp3
	sta tmp3
@r:	rts
@no:	stz tmp3
	rts

; row it of the corner: Ink's pair gF (clear, set) in the clip's pixels gI
Row:	lda clipOn              ; the clip's rows
	beq @in
	lda it
	cmp windowTopW
	lda it+1
	sbc windowTopW+1
	bcc @x
	lda windowBottomW
	cmp it
	lda windowBottomW+1
	sbc it+1
	bcc @x
	bra @in
@x:	rts
@in:	ldx gF
	lda Ink,x               ; clear: (clear | set) & clip
	ora Ink+1,x
	and gI
	eor #$FF
	sta tmp1
	lda Ink+1,x             ; set: set & clip
	and gI
	sta tmp2
	lda it                  ; ptr2 = it * 80 + gX
	sta ptr2
	lda it+1
	sta ptr2+1
	asl ptr2
	rol ptr2+1
	asl ptr2
	rol ptr2+1
	clc
	lda ptr2
	adc it
	sta ptr2
	lda ptr2+1
	adc it+1
	ldx #4
@m:	asl ptr2
	rol
	dex
	bne @m
	sta ptr2+1
	lda ptr2
	clc
	adc gX
	sta ptr2
	bcc @1
	inc ptr2+1
@1:	stz VERA_CTRL
	bit dispBufferOn
	bpl @back
	lda ptr2                ; the foreground ($00000)
	sta VERA_ADDR_L
	lda ptr2+1
	sta VERA_ADDR_M
	stz VERA_ADDR_H
	jsr @rmw
@back:	bit dispBufferOn
	bvc @r
	lda ptr2                ; the back screen ($09600)
	sta VERA_ADDR_L
	lda ptr2+1
	clc
	adc #>VRAM_BG
	sta VERA_ADDR_M
	lda #0
	rol
	sta VERA_ADDR_H
@rmw:	lda VERA_DATA0
	and tmp1
	ora tmp2
	sta VERA_DATA0
@r:	rts

;---------------------------------------------------------------- the palette

; port 0 at palette entry a, increment x
PalAt:	stz VERA_CTRL
	asl
	sta VERA_ADDR_L
	lda #$FA
	adc #0
	sta VERA_ADDR_M
	stx VERA_ADDR_H
	rts

; ax = palette entry a
Get:	pha
	ldx #$01
	jsr PalAt
	ldy VERA_DATA0
	inc VERA_ADDR_L
	ldx VERA_DATA0
	pla
	tya
	rts

_gui_pal:
	lda _theme              ; (theme.accent)
	jsr Get
	sta shd+2               ; 12: the accent
	stx shd+3
	stx tmp2                ; 13: the accent less a quarter: a - (a >> 2 & $333)
	lsr tmp2
	ror
	lsr tmp2
	ror
	and #$33
	sta tmp1
	lda tmp2
	and #$03
	sta tmp2
	lda shd+2
	sec
	sbc tmp1
	sta shd+4
	lda shd+3
	sbc tmp2
	sta shd+5
	lda #TPAPER             ; 11: halfway to the paper: (a >> 1 & $777) + (p >> 1 & $777)
	jsr Get
	stx tmp2
	lsr tmp2
	ror
	and #$77
	sta tmp1
	lda shd+3
	lsr
	lda shd+2
	ror
	and #$77
	clc
	adc tmp1
	sta shd
	lda shd+3
	lsr
	clc
	adc tmp2
	sta shd+1
	lda #TCHROME            ; 14: chrome
	jsr Get
	sta shd+6
	stx shd+7
	ldx #$0F                ; 15: white (dark mode a grey: its ink is light)
	lda #$FF
	ldy _theme+4            ; (theme.dark)
	beq @w
	ldx #$08
	lda #$89
@w:	sta shd+8
	stx shd+9
	lda #2 * 16 + 11        ; rows 2-13, entries 11-15
@row:	pha
	ldx #VERA_INC1 | 1
	jsr PalAt
	ldx #0
@e:	lda shd,x
	sta VERA_DATA0
	inx
	cpx #10
	bne @e
	pla
	clc
	adc #16
	cmp #(GROW + 1) * 16 + 11
	bne @row
	lda #GROW * 16 + 1      ; row 13's 1-10: the icons'
	ldx #VERA_INC1 | 1
	jsr PalAt
	ldx #0                  ; (dark mode: half as bright, for its light ink)
@c:	lda guiCols+1,x
	ldy _theme+4
	beq @l
	lsr
	sta tmp2
	lda guiCols,x
	ror
	and #$77
	sta VERA_DATA0
	lda tmp2
	bra @h
@l:	ldy guiCols,x
	sty VERA_DATA0
@h:	sta VERA_DATA0
	inx
	inx
	cpx #20
	bne @c
	rts

.segment "OVL11RO"
Nib:	.byte $00, $0F, $F0, $FF
BoxInk:	.byte 0, 16, 0, 32               ; the box's corners: round; the bottom right on the shadow
; the corners' rows 0-3 (pairs: the pixels cleared, set; bit 7 the left):
; left round, left square, right round, right square
Ink:	.byte $F0, $00, $E0, $10, $C0, $20, $80, $40
	.byte $00, $F0, $70, $80, $60, $80, $40, $80
	.byte $0F, $00, $07, $08, $03, $04, $01, $02
	.byte $00, $0F, $0E, $01, $06, $01, $02, $01
	.byte $00, $0F, $00, $0F, $00, $07, $00, $03   ; right round on a shadow
GuiTables                       ; (gui.inc: guiIcon, guiMask, guiCols)
