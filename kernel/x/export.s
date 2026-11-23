; Veranda bank X: ExportRect, "printing" as a file: a screen area written
; to a file as a BMP picture (docs/DECISIONS.md V28, V32)
;
; The file: the 14-byte file header, the 40-byte BITMAPINFOHEADER, the
; palette, then the rows bottom-up, each padded to 4 bytes.
; - 1 bpp (a bit 7 clear): two palette entries (0 the paper, 1 the ink:
;   VERA's entries 0 and 1); bit 7 the leftmost pixel, 1 = ink
;   (Veranda's own bit order and meaning, so a row is the screen's bytes
;   shifted by the left edge's bit). Rows are read with ReadRow into
;   kRowBuf, shifted there and written with FWrite.
; - 4 bpp (a bit 7 set, the colour map shown): VERA's entries 0-15; an
;   ink pixel is 1, a paper pixel its card's colour (the map's attribute,
;   0 the normal paper); the high nibble the left pixel. The row's bits
;   are copied out of kRowBuf, and kRowBuf takes the output 80 bytes at a
;   time.
; - 8 bpp (V101: a bit 7 set on the tile desktop, kernel/s/tiles.s): all
;   256 entries; an ink pixel 1, a paper pixel its tile's pixel as VERA
;   shows it (palette row << 4 | the pixel; 0 the paper): bank W's
;   TileCard reads a card's row of pixels.

.include "kernel.inc"

.export k_ExportRect
.import kRowBuf
.global S_k_FOpen, S_k_FWrite, S_k_FClose, S_k_ReadRow, S_TileCard

HDR1    = 62                    ; 54 + 2 palette entries
HDR4    = 118                   ; 54 + 16
HDR8    = 1078                  ; 54 + 256 x 4 (V101)
MAP     = $1AC00                ; the colour map (kernel/s/color.s)

.segment "BSS"

exName:	.res 2
exL:	.res 2
exY:	.res 2                  ; the row being written (bottom up)
exT:	.res 2
exW:	.res 2                  ; width in pixels
exH:	.res 2                  ; height
exCard:	.res 1                  ; the left card
exCards: .res 1                 ; cards read a row
exShift: .res 1                 ; left & 7
exN:	.res 1                  ; bytes a row (1 bpp, unpadded)
exP:	.res 2                  ; bytes a row in the file (padded to 4)
exMask:	.res 1                  ; the last byte's pixels
exH2:	.res 1                  ; the handle
exDB:	.res 1                  ; the caller's dispBufferOn
exSel:	.res 1                  ; dispBufferOn for ReadRow
exSize:	.res 3                  ; the picture's bytes
exCol:	.res 1                  ; $80: 4 bpp
; 4 bpp
exBits:	.res 80                 ; the row's pixels, 1 bpp
exAttr:	.res 80                 ; the cards' colours on this row
exI:	.res 2                  ; pixels left
exO:	.res 1                  ; bytes in kRowBuf
exOut:	.res 2                  ; bytes of the row written
exAcc:	.res 1                  ; a byte being made
exHalf:	.res 1                  ; $80: its high nibble is there
exC:	.res 1                  ; the current card
exSub:	.res 1                  ; the pixel in it
exBit:	.res 1                  ; the bit in exBits
exBy:	.res 1                  ; the byte in exBits
; 8 bpp (V101)
exPal:	.res 1                  ; the next palette entry written
exCR:	.res 1                  ; the card row
exTC:	.res 1                  ; the card exTRow holds ($FF none)
exTOff:	.res 1                  ; its palette row << 4
exTRow:	.res 4                  ; its pixels on this row (TileCard)

.segment "CODE"

;---------------------------------------------------------------
; ExportRect: r0 name, r3 left, r11 top, r4 right, r12 bottom (clipped
; to the screen); a bit 0: the back screen, bit 7: 4 bpp with the colour
; map (if it is shown; 8 bpp on the tile desktop, V101); x = error
; (INCOMPATIBLE: nothing left)
;---------------------------------------------------------------
k_ExportRect:
	ldx #ST_WR_FORE
	lsr
	bcc @1
	ldx #ST_WR_BACK         ; (bit 6 alone: ReadRow reads the back screen)
@1:	stx exSel
	asl
	and #$80
	beq @0
	lda VERA_DC_VIDEO       ; (DCSEL 0) the map is shown: layer 1 on
	and #$20
	beq @0
	ldx #$80
	lda VERA_L0_TILEBASE    ; (V101) the tile desktop: 8 bpp ($C0)
	cmp #TILE_TB
	bne @x
	ldx #$C0
@x:	txa
@0:	sta exCol
	MoveW r0, exName
	; clip right and bottom to the screen
	CmpW r4, screenWidth
	bcc @2
	lda screenWidth
	sbc #1
	sta r4L
	lda screenWidth+1
	sbc #0
	sta r4H
@2:	CmpW r12, screenHeight
	bcc @3
	lda screenHeight
	sbc #1
	sta r12L
	lda screenHeight+1
	sbc #0
	sta r12H
@3:	CmpW r4, r3             ; right >= left, bottom >= top
	bcc @bad
	CmpW r12, r11
	bcs @4
@bad:	ldx #INCOMPATIBLE
	rts
@4:	MoveW r3, exL
	MoveW r11, exT
	MoveW r12, exY
	lda r4L                 ; width = right - left + 1
	sec
	sbc r3L
	sta exW
	lda r4H
	sbc r3H
	sta exW+1
	IncW exW
	lda r12L                ; height
	sec
	sbc r11L
	sta exH
	lda r12H
	sbc r11H
	sta exH+1
	IncW exH
	; cards: left >> 3 .. right >> 3; the shift; bytes a row
	lda r3L
	and #7
	sta exShift
	MoveW r3, kTmp
	jsr Shr3
	sta exCard
	MoveW r4, kTmp
	jsr Shr3
	sec
	sbc exCard
	ina
	sta exCards
	MoveW exW, kTmp
	lda kTmp                ; (width + 7) >> 3
	clc
	adc #7
	sta kTmp
	bcc @5
	inc kTmp+1
@5:	jsr Shr3
	sta exN
	lda exW
	and #7
	tax
	lda LastMask,x
	sta exMask
	; the file's row: 1 bpp exN bytes, 4 bpp (width + 1) / 2, padded to 4
	stz exP+1
	lda exN
	bit exCol
	bpl @6
	MoveW exW, exP
	bvs @8b                 ; (8 bpp: the width)
	IncW exP
	lsr exP+1
	ror exP
@8b:	lda exP
@6:	clc
	adc #3
	sta exP
	bcc @7
	inc exP+1
@7:	lda exP
	and #$FC
	sta exP
	; the picture's size: exP * height
	stz exSize
	stz exSize+1
	stz exSize+2
	MoveW exH, kTmp
@m:	lda exSize
	clc
	adc exP
	sta exSize
	lda exSize+1
	adc exP+1
	sta exSize+1
	bcc @m1
	inc exSize+2
@m1:	lda kTmp
	bne @m2
	dec kTmp+1
@m2:	dec kTmp
	lda kTmp
	ora kTmp+1
	bne @m
	; the header (54 bytes and the 1 bpp palette)
	ldx #HDR1 - 1
@h:	lda Header,x
	sta kRowBuf,x
	dex
	bpl @h
	lda exSize              ; the rows' size
	sta kRowBuf + 34
	lda exSize+1
	sta kRowBuf + 35
	lda exSize+2
	sta kRowBuf + 36
	ldy #HDR1               ; + the headers: the file's size
	ldx #0
	bit exCol
	bpl @8
	ldy #HDR4
	LoadB kRowBuf + 28, 4   ; bits a pixel
	LoadB kRowBuf + 46, 16  ; colours
	sta kRowBuf + 50
	bvc @8a
	ldy #<HDR8              ; 8 bpp: 256 colours
	ldx #>HDR8
	stx kRowBuf + 11
	LoadB kRowBuf + 47, 1    ; (256 colours)
	LoadB kRowBuf + 28, 8
	stz kRowBuf + 46
	stz kRowBuf + 50
@8a:	sty kRowBuf + 10        ; where the rows start
@8:	tya
	clc
	adc exSize
	sta kRowBuf + 2
	txa
	adc exSize+1
	sta kRowBuf + 3
	lda exSize+2
	adc #0
	sta kRowBuf + 4
	MoveW exW, kRowBuf + 18
	MoveW exH, kRowBuf + 22
	; the file
	MoveW exName, r0
	lda #'w'
	FARCALL k_FOpen
	cpx #0
	beq @9
	rts
@9:	sta exH2
	stz exPal
	bit exCol
	bmi @hc
	lda #54                 ; 1 bpp: entries 0 and 1 after the header
	ldx #2
	jsr Palette
	lda #HDR1
	jsr Write
	beq @rows
@cl:	jmp @close
@hc:	lda #54
	jsr Write
	bne @cl
@pc:	lda #0                  ; 4 bpp: entries 0-15, written alone; 8 bpp:
				; 0-255, 16 at a time
	ldx #16
	jsr Palette
	lda #64
	jsr Write
	bne @close
	bit exCol
	bvc @rows
	lda exPal
	bne @pc
@rows:	MoveB dispBufferOn, exDB
@row:	MoveB exSel, dispBufferOn
	LoadW r0, kRowBuf
	MoveB exCard, r3L
	MoveB exCards, r3H
	MoveW exY, r11
	FARCALL k_ReadRow
	MoveB exDB, dispBufferOn
	jsr Shift
	bit exCol
	bmi @r4
	lda exP
	jsr Write
	bne @close
	bra @next
@r4:	jsr Row4
	bne @close
@next:	CmpW exY, exT
	beq @close              ; (x = 0)
	lda exY
	bne @10
	dec exY+1
@10:	dec exY
	bra @row
@close:	phx
	lda exH2
	FARCALL k_FClose
	plx
	rts

; kTmp >> 3 -> a (the result fits a byte)
Shr3:	lda kTmp
	lsr kTmp+1
	ror
	lsr kTmp+1
	ror
	lsr kTmp+1
	ror
	rts

; a bytes of kRowBuf to the file; x = error, z set if none
Write:	sta r1L
	stz r1H
	LoadW r0, kRowBuf
	lda exH2
	FARCALL k_FWrite
	cpx #0
	rts

; the row in kRowBuf: shifted left by exShift (the bytes after the cards
; read are 0), the last byte masked, padded with 0 to exP bytes (1 bpp)
Shift:	ldx #0
@b:	lda #0                  ; the next byte (0 past the cards read)
	inx
	cpx exCards
	bcs @n
	lda kRowBuf,x
@n:	dex
	sta kTmp
	lda kRowBuf,x
	ldy exShift
	beq @s2
@s:	asl kTmp
	rol
	dey
	bne @s
@s2:	sta kRowBuf,x
	inx
	cpx exN
	bne @b
	lda kRowBuf - 1,x
	and exMask
	sta kRowBuf - 1,x
	bit exCol
	bmi @r
@p:	cpx exP
	beq @r
	stz kRowBuf,x
	inx
	bra @p
@r:	rts

; 4 bpp: the row (exN bytes of bits in kRowBuf) with the colours of the
; cards of row exY >> 3, to the file; x = error, z set if none. 8 bpp
; (V101, the tile desktop): a paper pixel its tile's pixel (palette row
; << 4 | it; 0 the paper), each card's from bank W's TileCard
Row4:	ldx exN
@c:	dex
	lda kRowBuf,x
	sta exBits,x
	cpx #0
	bne @c
	; the colours: the map's attribute bytes of this card row
	lda exY                 ; card row = y >> 3
	sta kTmp
	lda exY+1
	lsr
	ror kTmp
	lsr
	ror kTmp
	lsr
	ror kTmp
	MoveB kTmp, exCR
	LoadB exTC, $FF
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(MAP + 1)
	lda kTmp
	clc
	adc #>MAP
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^MAP | $20   ; increment 2
	ldx #0
@a:	lda VERA_DATA0
	lsr
	lsr
	lsr
	lsr
	sta exAttr,x
	inx
	cpx #80
	bne @a
	; the pixels
	MoveW exW, exI
	stz exO
	stz exOut
	stz exOut+1
	stz exHalf
	MoveB exCard, exC
	MoveB exShift, exSub
	stz exBy
	LoadB exBit, $80
@px:	ldy exBy
	lda exBits,y
	and exBit
	beq @paper
	lda #1                  ; ink
	bra @nib
@paper:	bit exCol
	bvs @p8
	ldx exC
	lda exAttr,x
	bra @nib
@p8:	lda exC                 ; 8 bpp: the card's row of pixels (TileCard)
	cmp exTC
	beq @p9
	sta exTC
	tax
	lda exY
	and #7
	tay
	lda exCR
	FARCALL TileCard
	sta exTOff
	ldx #3
@pk:	lda kTmp,x
	sta exTRow,x
	dex
	bpl @pk
@p9:	lda exSub
	lsr
	tax
	lda exTRow,x
	bcs @lo
	lsr
	lsr
	lsr
	lsr
@lo:	and #$0F
	beq @nib                ; (0: the paper)
	ora exTOff
@nib:	bit exCol
	bvc @n4
	jsr Byte
	bra @nb
@n4:	jsr Nibble
@nb:
	bne @rr
	lsr exBit               ; the next pixel
	bcc @p1
	ror exBit
	inc exBy
@p1:	inc exSub
	lda exSub
	cmp #8
	bne @p2
	stz exSub
	inc exC
@p2:	lda exI
	bne @p3
	dec exI+1
@p3:	dec exI
	lda exI
	ora exI+1
	beq @pz
	jmp @px
@pz:	; the last half byte, then 0 to exP bytes
	bit exHalf
	bpl @pad
	lda #0
	jsr Nibble
	bne @rr
@pad:	CmpW exOut, exP
	beq @fl
	lda #0
	jsr Byte
	bne @rr
	bra @pad
@fl:	lda exO                 ; what is left in kRowBuf
	beq @ok
	jmp Write
@ok:	ldx #0
@rr:	rts

; a nibble (a) to the output; z clear: an error (x)
Nibble:	bit exHalf
	bmi @lo
	asl
	asl
	asl
	asl
	sta exAcc
	LoadB exHalf, $80
	ldx #0
	rts
@lo:	ora exAcc
	stz exHalf
; a byte (a) to the output, kRowBuf written when full
Byte:	ldx exO
	sta kRowBuf,x
	IncW exOut
	inx
	stx exO
	cpx #80
	bne @r
	stz exO
	lda #80
	jmp Write
@r:	ldx #0
	rts

; x palette entries from entry exPal on (VERA: GGGGBBBB, 0000RRRR) -> B,
; G, R, 0 at kRowBuf + a ...; exPal + x
Palette:
	stx kTmp+2
	tax
	stz VERA_CTRL
	lda exPal               ; from entry exPal on (V101)
	asl
	sta VERA_ADDR_L
	lda #>VRAM_PALETTE
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	lda exPal
	clc
	adc kTmp+2
	sta exPal
@1:	lda VERA_DATA0          ; GB
	pha
	and #$0F
	jsr Exp
	sta kRowBuf,x           ; B
	pla
	lsr
	lsr
	lsr
	lsr
	jsr Exp
	sta kRowBuf + 1,x       ; G
	lda VERA_DATA0
	and #$0F
	jsr Exp
	sta kRowBuf + 2,x       ; R
	stz kRowBuf + 3,x
	inx
	inx
	inx
	inx
	dec kTmp+2
	bne @1
	rts
; a nibble n -> n * 17 (0-255)
Exp:	sta kTmp
	asl
	asl
	asl
	asl
	ora kTmp
	rts

.segment "RODATA"

LastMask: .byte $FF, $80, $C0, $E0, $F0, $F8, $FC, $FE

Header:	.byte "BM"
	.dword 0                ; the file's size (set)
	.dword 0
	.dword HDR1             ; where the rows start (4 bpp: HDR4)
	.dword 40               ; BITMAPINFOHEADER
	.dword 0                ; width (set)
	.dword 0                ; height (set; > 0: bottom-up)
	.word 1                 ; planes
	.word 1                 ; bits a pixel (4 bpp: 4)
	.dword 0                ; no compression
	.dword 0                ; the rows' size (set)
	.dword 2835, 2835       ; 72 dpi
	.dword 2, 2             ; colours (4 bpp: 16)
	.dword 0, 0             ; the palette (set)
.assert * - Header = HDR1, error, "export.s: the header"
