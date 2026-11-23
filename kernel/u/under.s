; Veranda bank U: the save-under stack
;
; Menus and dialog boxes keep what they cover here when the application
; draws to the foreground only (dispBufferOn without ST_WR_BACK): the
; covered bytes are copied VRAM to VRAM (port 1 reads, port 0 writes) into
; the stack at VRAM_SAVEUNDER (16 KB) and back when the menu or box closes
; (bank G2's VCopy: VERA FX cache copies when the VERA has them, V80).
; When the back screen is in use GEOS's own way is kept (RecoverRectangle
; from the back screen, or the application's RecoverVector): see Covered.
;
; UnderPush: uX (card), uW (cards), uTop, uBot (rows, 16 bits, inclusive);
;            c set: no room (nothing saved); always in tile mode (V101:
;            the tiles are in the stack's room, $13000-$16BFF)
; UnderPop:  the last area back on the foreground; c set: none
; UnderSpill: (V84) the area, clipped to the screen, copied from the
;            foreground to the same place on the back screen: for a box
;            that does not fit on the stack, when the application draws to
;            the foreground only (the back screen is not its own), so that
;            GEOS's RecoverRectangle gives back exactly what it covered

.include "kernel.inc"

.import kStride

.export UnderPush, UnderPop, UnderDrop, UnderReset, UnderSpill, uX, uW, uTop, uBot
.export UnderFree               ; (the switcher clears what is free: V83)

LEVELS = 8
UNDER_END = VRAM_SPRITES      ; 16 KB

.segment "BSS"

uX:	.res 1
uW:	.res 1
uTop:	.res 2
uBot:	.res 2
uN:	.res 1                  ; areas on the stack
UnderFree:
uFree:	.res 3                  ; the next free VRAM byte (17 bits)
uCanv:	.res 1                  ; (V166) $80: the canvas's, at VRAM_CANVUNDER
				; (bank C sets uFree and this, kernel/c/canvas.s)
sX:	.res LEVELS
sW:	.res LEVELS
sTopL:	.res LEVELS
sTopH:	.res LEVELS
sBotL:	.res LEVELS
sBotH:	.res LEVELS
sAL:	.res LEVELS             ; where its bytes are
sAM:	.res LEVELS
sAH:	.res LEVELS
rows:	.res 2
row:	.res 2
size:	.res 3
scr:	.res 3                  ; a screen address

.segment "CODE"

UnderReset:
	stz uN
	stz uFree               ; (<VRAM_SAVEUNDER: V165, 2 bytes for the canvas)
	LoadB uFree+1, >VRAM_SAVEUNDER
	LoadB uFree+2, ^VRAM_SAVEUNDER
	rts

; forget the last area (its menu was recovered another way)
UnderDrop:
	ldx uN
	beq @r
	dex
	stx uN
	lda sAL,x
	sta uFree
	lda sAM,x
	sta uFree+1
	lda sAH,x
	sta uFree+2
@r:	rts

UnderPush:
	lda VERA_L0_TILEBASE    ; (V101) the tile desktop's tiles are here
	cmp #TILE_TB
	beq @full
	ldx uN
	cpx #LEVELS
	bcs @r                  ; (c set)
	; rows = bot - top + 1; size = rows * w
	lda uBot
	sec
	sbc uTop
	sta rows
	lda uBot+1
	sbc uTop+1
	sta rows+1
	IncW rows
	stz size
	stz size+1
	stz size+2
	ldy uW
	beq @full
@m:	lda size
	clc
	adc rows
	sta size
	lda size+1
	adc rows+1
	sta size+1
	bcc @m1
	inc size+2
@m1:	dey
	bne @m
	; room: uFree + size <= UNDER_END
	lda uFree
	clc
	adc size
	lda uFree+1
	adc size+1
	sta kTmp
	lda uFree+2
	adc size+2
	cmp #^(UNDER_END)
	bcc @ok
	bne @full
	lda kTmp
	eor uCanv               ; (V166: VRAM_CANVUNDER is $8000 on)
	cmp #>(UNDER_END)       ; (up to 255 bytes short of the end: unused)
	bcc @ok
@full:	sec
@r:	rts
@ok:	ldx uN
	lda uX
	sta sX,x
	lda uW
	sta sW,x
	lda uTop
	sta sTopL,x
	lda uTop+1
	sta sTopH,x
	lda uBot
	sta sBotL,x
	lda uBot+1
	sta sBotH,x
	lda uFree
	sta sAL,x
	lda uFree+1
	sta sAM,x
	lda uFree+2
	sta sAH,x
	inc uN
	ldx #0                  ; screen -> stack
	jsr Move
	lda uFree               ; uFree += size
	clc
	adc size
	sta uFree
	lda uFree+1
	adc size+1
	sta uFree+1
	lda uFree+2
	adc size+2
	sta uFree+2
	clc
	rts

UnderPop:
	ldx uN
	bne @1
	sec
	rts
@1:	dex
	stx uN
	lda sX,x
	sta uX
	lda sW,x
	sta uW
	lda sTopL,x
	sta uTop
	lda sTopH,x
	sta uTop+1
	lda sBotL,x
	sta uBot
	lda sBotH,x
	sta uBot+1
	lda sAL,x
	sta uFree
	lda sAM,x
	sta uFree+1
	lda sAH,x
	sta uFree+2             ; (the stack's top: where this area began)
	ldx #1                  ; stack -> screen
	jsr Move
	clc
	rts

UnderSpill:
	bit uCanv               ; (V166: the canvas is over the back screen)
	bmi @r
	lda screenHeight        ; the rows on the screen
	sec
	sbc #1
	sta row
	lda screenHeight+1
	sbc #0
	sta row+1
	CmpW row, uBot
	bcs @1
	MoveW row, uBot
@1:	CmpW row, uTop
	bcc @r                  ; (all below the screen)
	lda kStride             ; the cards on it
	clc
	sbc uX                  ; (stride - uX - 1)
	bcc @r
	cmp uW
	bcs @2
	ina
	sta uW
@2:	ldx #2
	jmp Move
@r:	rts

; the area's rows uTop .. uBot, uW bytes each, VRAM to VRAM (bank G2's
; VCopy, its parameters on the stack): x = 0 the screen (rows a stride
; apart) to the stack at uFree (rows uW apart), 1 back, 2 the screen to
; the back screen (the same place: V84)
Move:	MoveW uTop, row
	phx
	jsr Scr                 ; scr: the area's first byte on the screen
	plx
	lda uBot
	sec
	sbc uTop
	sta rows
	lda uBot+1
	sbc uTop+1
	sta rows+1
	IncW rows
	ldy uW
	lda kStride
	cpx #1
	beq @1
	cpx #0
	bne @s
	phy                     ; the target's stride, the source's
	bra @s1
@s:	pha
@s1:	pha
	bra @2
@1:	pha
	phy
@2:	lda rows+1
	pha
	lda rows
	pha
	phy                     ; bytes a row
	cpx #1
	beq @3
	cpx #0
	beq @0
	jsr @back               ; to the back screen, from the screen
	bra @01
@0:	jsr @free               ; to the stack, from the screen
@01:	jsr @scr
	bra @4
@3:	jsr @scr                ; to the screen, from the stack
	jsr @free
@4:	FARCALL VCopy
	ldx #11
@d:	pla
	dex
	bne @d
	rts
; (pushes under the return: the address's 3 bytes, the high one first)
@free:	ply
	plx
	lda uFree+2
	pha
	lda uFree+1
	pha
	lda uFree
	pha
	bra @ret
@back:	ply
	plx
	lda scr+1
	clc
	adc #>VRAM_BG
	sta kTmp
	lda scr+2
	adc #^VRAM_BG
	pha
	lda kTmp
	pha
	lda scr
	pha
	bra @ret
@scr:	ply
	plx
	lda scr+2
	pha
	lda scr+1
	pha
	lda scr
	pha
@ret:	phx
	phy
	rts

.assert <VRAM_BG = 0, error, "under.s: the back screen on a page"
.assert <VRAM_SAVEUNDER = 0, error, "under.s: UnderReset's stz uFree"

; scr = the foreground address of (uX, row): row * stride + uX
Scr:	lda row
	sta scr
	lda row+1
	sta scr+1
	stz scr+2
	; row * 8 (40 = 8 * 5, 80 = 16 * 5): row * 5 first
	lda scr
	asl
	sta kTmp
	lda scr+1
	rol
	sta kTmp+1
	asl kTmp
	rol kTmp+1              ; row * 4
	lda kTmp
	clc
	adc row
	sta scr
	lda kTmp+1
	adc row+1
	sta scr+1               ; row * 5 (at most 2,400)
	ldx #3                  ; * 8: 40
	lda kStride
	cmp #80
	bne @s
	inx                     ; * 16: 80
@s:	asl scr
	rol scr+1
	rol scr+2
	dex
	bne @s
	lda scr
	clc
	adc uX
	sta scr
	bcc @r
	inc scr+1
	bne @r
	inc scr+2
@r:	rts
