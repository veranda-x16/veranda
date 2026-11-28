; textkit (Veranda Edit, VeraBASIC): the window's rows moved (DECISIONS
; V215). view.c's scroll_rows: the text area's card rows moved by d rows
; on the foreground through VERA's two data ports (port 1 reads the old
; row, port 0 writes the new one), and with tk_vcol (TK_PAPER builds) the
; colour map's paper bytes of the same cards; the rows uncovered are left
; as they were (view.c draws them: a row is drawn whole).
;
; A row moves only as far as there may be ink: tk_iw[r], the cards from
; column 0 row r's drawing may have inked (view.c sets it when it draws a
; row; all when the window is drawn), the larger of the two rows' (at
; most tk_vlim); tk_iw moves with its rows. With VERA FX (firmware 0.3.1
; or later, read once: DCSEL 63) a pixel row goes through the 32-bit
; cache, 4 reads of DATA1 and one write of DATA0 a group of 4 bytes (the
; last group's write masked to the row), with interrupts off for that
; pixel row alone (at most about 500 cycles, as the kernel's CopyRect);
; without FX byte by byte. Rows start at column 0: a multiple of 4.
;
; TK_BANK (an assembler define): the code in segment "B<n>CODE" (a bank
; of the program's: view.c calls it through TK_VMOVE()), else "CODE". Its
; variables in "BSS" (main RAM: view.c's bank and the program's hook set
; tk_iw).
;
; MIT licence (see LICENSE).

	.setcpu "65C02"
	.include "x16hw.inc"
	.export _tk_vmove, _tk_vmove_x, _tk_vd, _tk_iw, _tk_vlim, _tk_vcol
	.importzp ptr1, ptr2, tmp1, tmp2, tmp3, tmp4

ROWS	= 54
TROW	= 4
CMAP	= VRAM_FREE + TROW * 256 + 1  ; the colour map's row TROW, card 0's paper

.segment "BSS"

_tk_iw:	.res ROWS               ; each row's ink: cards from column 0
_tk_vlim: .res 1                ; the cards a row has (X0 + COLS)
_tk_vcol: .res 1                ; 1: the colour map's paper too
_tk_vd:	.res 1                  ; tk_vmove_x's d
fx:	.res 1                  ; 0 not looked at yet, $80 FX, 1 none
src:	.res 1                  ; the card rows: from, to
dst:	.res 1
step:	.res 1                  ; 1 or -1
left:	.res 1                  ; the rows still to move
grp:	.res 1                  ; FX: the groups of 4 before the last
mask:	.res 1                  ; the last group's write mask

.ifdef TK_BANK
.segment .sprintf("B%dCODE", TK_BANK)
.else
.segment "CODE"
.endif

; void __fastcall__ tk_vmove(signed char d): d > 0 down (the text to later
; rows: from the last row back), d < 0 up; 0 < |d| < ROWS. tk_vmove_x:
; d from tk_vd (a call through another bank's trampoline)
_tk_vmove_x:
	lda _tk_vd
_tk_vmove:
	tax
	lda fx
	bne @f
	jsr FxCheck
@f:	ldy #1                  ; up: from row |d| to row 0, on
	txa
	bpl @dn
	eor #$FF
	ina
	sta src
	stz dst
	bra @n
@dn:	ldy #$FF
	eor #$FF
	sec
	adc #ROWS - 1           ; ROWS - 1 - d: the last row moved
	sta src
	txa
	clc
	adc src
	sta dst
	txa
@n:	sty step
	eor #$FF                ; ROWS - |d| rows
	sec
	adc #ROWS
	sta left
@row:	ldx src
	ldy dst
	lda _tk_iw,x            ; the width: the wider of the two
	cmp _tk_iw,y
	bcs @w
	lda _tk_iw,y
@w:	cmp _tk_vlim
	bcc @w1
	lda _tk_vlim
@w1:	sta tmp4
	lda _tk_iw,x            ; the ink moves with its row
	sta _tk_iw,y
	lda tmp4
	beq @nx
	jsr Card
.ifdef TK_PAPER
	lda _tk_vcol
	beq @nx
	jsr Paper
.endif
@nx:	lda src
	clc
	adc step
	sta src
	lda dst
	clc
	adc step
	sta dst
	dec left
	bne @row
	rts

; card row src's 8 pixel rows to dst's, tmp4 bytes each
Card:	lda src
	jsr RowAddr
	stx ptr1
	sty ptr1+1
	lda dst
	jsr RowAddr
	stx ptr2
	sty ptr2+1
	lda #8
	sta tmp3
	lda tmp4                ; (FX) the groups, the last one's mask
	dec a
	lsr
	lsr
	sta grp
	lda tmp4
	and #3
	tax
	lda TailMask,x
	sta mask
	lda #2 << 1 | 1         ; DCSEL 2, port 1: the source, by 1
	sta VERA_CTRL
	lda #VERA_INC1
	sta VERA_ADDR_H
	lda #2 << 1             ; port 0: the target, by 1 (by 4: FX)
	sta VERA_CTRL
	lda #VERA_INC1
	bit fx
	bpl @h
	lda #$30
@h:	sta VERA_ADDR_H         ; (the increments stay: a row sets the rest)
@p:	lda #2 << 1 | 1
	sta VERA_CTRL
	lda ptr1
	sta VERA_ADDR_L
	lda ptr1+1
	sta VERA_ADDR_M
	lda #2 << 1
	sta VERA_CTRL
	lda ptr2
	sta VERA_ADDR_L
	lda ptr2+1
	sta VERA_ADDR_M
	bit fx
	bmi @fx
	lda tmp4                ; byte by byte, two at a time
	lsr
	tax
	bcc @b0
	lda VERA_DATA1
	sta VERA_DATA0
@b0:	txa
	beq @e
@b:	lda VERA_DATA1
	sta VERA_DATA0
	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @b
	bra @e
@fx:	lda grp                 ; the groups two at a time
	lsr
	tax
	php
	sei
	lda #$60                ; cache writes, cache fills from the reads
	sta VERA_FX_CTRL
	stz VERA_FX_MULT        ; (the cache's first byte)
	bcc @ev
	lda VERA_DATA1          ; (an odd one)
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	stz VERA_DATA0
@ev:	txa
	beq @l
@g:
.repeat 2
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	stz VERA_DATA0          ; (0: all four bytes)
.endrepeat
	dex
	bne @g
@l:	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	lda mask
	sta VERA_DATA0
	stz VERA_FX_CTRL
	plp
@e:	lda ptr1                ; the next pixel row: 80 bytes on
	clc
	adc #80
	sta ptr1
	bcc @1
	inc ptr1+1
@1:	lda ptr2
	clc
	adc #80
	sta ptr2
	bcc @2
	inc ptr2+1
@2:	dec tmp3
	beq @x
	jmp @p
@x:	stz VERA_CTRL
	rts

.ifdef TK_PAPER
; card row src's paper bytes (tmp4 of them) to dst's: the colour map's
; attribute bytes, a card's every second byte
Paper:	lda #1
	sta VERA_CTRL
	lda src
	jsr @seek
	stz VERA_CTRL
	lda dst
	jsr @seek
	ldx tmp4
@c:	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @c
	rts
@seek:	clc
	adc #>CMAP
	sta VERA_ADDR_M
	lda #<CMAP
	sta VERA_ADDR_L
	lda #^CMAP | VERA_INC2
	sta VERA_ADDR_H
	rts
.endif

; a = a text row: y.x = its first pixel row's address on the foreground
; ((TY + 8a) * 80 = TY * 80 + a * 5 * 128)
RowAddr:
	sta tmp1
	stz tmp2
	asl
	rol tmp2
	asl
	rol tmp2                ; a * 4
	clc
	adc tmp1
	bcc @1
	inc tmp2                ; tmp2.a = a * 5
@1:	lsr tmp2                ; * 128: (a * 5) << 8 >> 1
	ror
	tay
	lda #0
	ror
	tax
	tya
	clc
	adc #>(TROW * 8 * 80)
	tay
	rts

; fx: $80 if VERA has the cache's writes (firmware 0.3.1 or later), else 1
FxCheck:
	lda #1
	sta fx
	lda #63 << 1
	sta VERA_CTRL
	lda VERA_VERSION
	cmp #'V'
	bne @no
	lda VERA_VERSION+1      ; major
	bne @yes
	lda VERA_VERSION+2      ; minor
	cmp #3
	bcc @no
	bne @yes
	lda VERA_VERSION+3      ; patch
	beq @no
@yes:	lda #2 << 1             ; FX off, the multiplier off
	sta VERA_CTRL
	stz VERA_FX_CTRL
	stz VERA_FX_MULT
	lda #$80
	sta fx
@no:	stz VERA_CTRL
	rts

TailMask: .byte $00, $FC, $F0, $C0      ; the last group: bytes kept (2 bits a byte)
