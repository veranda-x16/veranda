; Veranda bank G: the FX fills (linked after the text code, so that the
; text's tables do not move)

.include "kernel.inc"

.import fb_calc_off, fb_seek, fbRow, fbCol, fbSel, fbBlkN, fbB, fbTmp, fbE0, fbE1, kStride

BUF_FG  = 0                     ; as kernel/g/fb.s
BUF_BG  = 1
MAX_BYTES = 80
.export fb_fxfill, fb_block

.segment "CODE"

;---------------------------------------------------------------
; FX fills (docs/PLAN.md 5.4, DECISIONS V29): VERA's 32-bit cache writes,
; when kFx bit 7 says the VERA has them (firmware 0.3.1 or later, read at
; start-up from DCSEL 63; a kernel built with NOFX never uses them). One
; write to DATA0 stores the cache's four bytes at the address rounded
; down to 4 (the written value is the byte mask: 0 all four); the
; address steps by 4. Interrupts are off while the cache is on, so the
; interrupt (and the ROM's handler, which writes VRAM) never sees FX on.
;---------------------------------------------------------------

; FX on: the cache = a four times, cache writes, port 0 steps by 4
; (interrupts must be off); x kept, y changed
FxOn:	ldy #2 << 1             ; DCSEL 2: FX_CTRL
	sty VERA_CTRL
	ldy #$40                ; cache write enable
	sty VERA_FX_CTRL
	ldy #6 << 1             ; DCSEL 6: the cache
	sty VERA_CTRL
	sta VERA_FX_CACHE
	sta VERA_FX_CACHE+1
	sta VERA_FX_CACHE+2
	sta VERA_FX_CACHE+3
	stz VERA_CTRL
	lda VERA_ADDR_H
	and #1
	ora #$30                ; increment 4
	sta VERA_ADDR_H
	rts

; FX off, port 0 steps by 1 again
FxOff:	lda #2 << 1
	sta VERA_CTRL
	stz VERA_FX_CTRL
	stz VERA_CTRL
	lda VERA_ADDR_H
	and #1
	ora #VERA_INC1
	sta VERA_ADDR_H
	rts

; a to port 0, x times (x >= FX_MIN): the bytes up to a multiple of 4,
; then groups of four, then the rest
fb_fxfill:
	sta fbB
@h:	lda VERA_ADDR_L
	and #3
	beq @a
	lda fbB
	sta VERA_DATA0
	dex
	bra @h
@a:	txa
	and #3
	sta fbTmp               ; the rest
	txa
	lsr
	lsr
	tax                     ; groups (at least 7)
	lda fbB
	php
	sei
	jsr FxOn
	jsr fb_groups
	jsr FxOff
	plp
	lda fbB
	ldx fbTmp
	beq @r
@t:	sta VERA_DATA0
	dex
	bne @t
@r:	rts

; x (0-20) cache writes to port 0, unrolled
fb_groups:
	txa
	asl
	tax
	jmp (GroupTab,x)
.repeat MAX_BYTES / 4
	stz VERA_DATA0
.endrepeat
GroupEnd:
	rts
GroupTab:
.repeat MAX_BYTES / 4 + 1, i
	.word GroupEnd - 3 * i
.endrepeat

;---------------------------------------------------------------
; fb_block: rows fbRow .. + fbBlkN - 1, whole rows, row r in the byte
; (curPattern),(r & 7), on the screens fbSel selects: one stream of cache
; writes a screen (whole rows follow each other; a row starts at a
; multiple of 4: 80 and 40 are, and so are both screens' bases); the
; cache gets each row's byte (DCSEL 6 stays selected: DATA0 does not
; depend on it). FX only (the caller checks kFx).
;---------------------------------------------------------------
fb_block:
	stz fbCol
	jsr fb_calc_off
	bit fbSel
	bpl @1
	lda #BUF_FG
	jsr @scr
@1:	bit fbSel
	bvc @2
	lda #BUF_BG
	jsr @scr
@2:	rts
@scr:	ldy #0
	ldx #0
	jsr fb_seek
	MoveW fbBlkN, fbE0      ; (fbE0, fbE1: the rows left)
	lda kStride
	lsr
	lsr
	sta fbTmp               ; groups a row
	lda fbRow
	and #7
	sta fbB                 ; the pattern's row
	php
	sei
	jsr FxOn
	ldx #6 << 1
	stx VERA_CTRL
@row:	ldy fbB
	lda (curPattern),y
	sta VERA_FX_CACHE
	sta VERA_FX_CACHE+1
	sta VERA_FX_CACHE+2
	sta VERA_FX_CACHE+3
	iny
	tya
	and #7
	sta fbB
	ldx fbTmp
	jsr fb_groups
	lda fbE0
	bne @3
	dec fbE1
@3:	dec fbE0
	lda fbE0
	ora fbE1
	beq @end
	lda fbE0                ; every 32 rows a window for the interrupt
	and #31                 ; (FX off: it never sees it on; V68): at
	bne @row                ; most 5,400 cycles off, not 80,000 a screen
	jsr FxOff
	plp
	php
	sei
	jsr FxOn                ; (the port's address kept; the row sets the
	ldx #6 << 1             ; cache)
	stx VERA_CTRL
	bra @row
@end:	jsr FxOff
	plp
	rts
