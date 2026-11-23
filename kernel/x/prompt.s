; Veranda bank X: the text prompt (GetString's cursor)
;
; Sprite 1: a line one pixel wide and height + 1 rows tall (as GEOS 64), in
; an 8x64 sprite (4 bpp, ink colour 1 of palette offset 1: entry 17), its
; top left at (stringX, stringYW). alphaFlag: bit 7 blinking, bit 6 shown,
; bits 0-5 frames left in this phase (60 on, 60 off; every PromptOn and
; PromptOff starts a phase).

.include "kernel.inc"

.export k_InitTextPrompt, k_PromptOn, k_PromptOff, PromptBlink

SLOT    = VRAM_SPRITES + 2048
ATTR    = VRAM_SPRATTR + 8
PHASE   = 60

.segment "CODE"

; port 0 at sprite 1's attribute byte x
Attr:	stz VERA_CTRL
	txa
	clc
	adc #<ATTR
	sta VERA_ADDR_L
	lda #>ATTR
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^ATTR | VERA_INC1
	rts

; a = the height in pixels
k_InitTextPrompt:
	cmp #63
	bcc @1
	lda #62
@1:	sta kTmp                ; rows 0 .. height
	LoadB alphaFlag, %10000011
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <SLOT
	LoadB VERA_ADDR_M, >SLOT
	LoadB VERA_ADDR_H, ^SLOT | VERA_INC1
	ldy #0                  ; 64 rows of 4 bytes
@row:	lda #0
	cpy kTmp
	beq @on
	bcs @px
@on:	lda #$10                ; the leftmost pixel, colour 1
@px:	sta VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	iny
	cpy #64
	bne @row
	ldx #0                  ; its address, 4 bpp
	jsr Attr
	LoadB VERA_DATA0, <(SLOT >> 5)
	LoadB VERA_DATA0, >(SLOT >> 5)
	ldx #6
	jsr Attr
	stz VERA_DATA0          ; off
	LoadB VERA_DATA0, %11000000 | 1   ; 64 high, 8 wide, palette offset 1
	rts

k_PromptOn:
	lda alphaFlag
	ora #$40
	jsr Phase
	ldx #2
	jsr Attr
	lda stringX
	sta VERA_DATA0
	lda stringX+1
	sta VERA_DATA0
	lda stringYW
	sta VERA_DATA0
	lda stringYW+1
	sta VERA_DATA0
	lda #%00001100          ; in front
	sta VERA_DATA0
	rts

k_PromptOff:
	lda alphaFlag
	and #<~$40
	jsr Phase
	ldx #6
	jsr Attr
	stz VERA_DATA0
	rts

; alphaFlag = a's bits 7 and 6, a new phase
Phase:	and #$C0
	ora #PHASE
	sta alphaFlag
	rts

; the interrupt
PromptBlink:
	bit alphaFlag
	bpl @r
	dec alphaFlag
	lda alphaFlag
	and #$3F
	bne @r
	bit alphaFlag
	bvs @off
	bra k_PromptOn
@off:	jmp k_PromptOff
@r:	rts
