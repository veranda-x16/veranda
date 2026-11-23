; Veranda bank G: text
;
; Fonts are GEOS fonts (tools/mkfont.py has the format). y is the baseline
; (as in GEOS); a character covers rows y - baselineOffset .. + curHeight - 1
; and is drawn opaque within that box.
;
; Characters are rendered into a strip in RAM (STRIP_W bytes by up to
; STRIP_H rows), bit by bit, with bold, italic and underline applied there;
; the strip goes to the screen one row at a time (fb_span, FBOP_BUF, with
; reverse as the XOR value): one VERA seek per row of a run of characters
; instead of one per row of every character. PutString collects a run until
; the strip is full, the position or the font changes, or reverse changes.
; Outline is drawn plain for now.
;
; Italic (V122) leans a character's rows right, past its advance (which
; italic leaves as it is): the pixels past a run's end (its overhang, up to
; (baselineOffset + 2) / 2) are ORed onto the screen after the run, up to
; rightMargin, and kept in the strip's first bytes for the next run: if it
; goes on from there (the same x, baseline and baselineOffset, also in the
; next WPutString or WPutChar) it is drawn with them, so its opaque boxes
; do not cut them off. The system font's bold and italic come from
; SysRows (SysSlow): its own bitmap is not kept here.

.include "kernel.inc"

.import sysFont, fontBank, fontPage ; (resident: menus and dialogs keep them with the font)
.import kBankBase
.import FontRow
.import gA, Tail1, E_HiLook ; (V141: bank G2's HiLook)
.assert BANK_G2 = 1, error, "HiCall: Tail1 is bank G2's"

.import fb_span, fbRow, fbCol, fbCnt, fbKeepL, fbKeepR, fbOp, fbSel, fbXor
.importzp FBOP_BUF
.import KeepLeft, KeepRight, BitMask, kStride

.export k_LoadCharSet, k_UseSystemFont, k_GetCharWidth, k_GetRealSize
.export k_WPutChar, k_WSmallPutChar, k_WPutString

STRIP_W = 32                    ; bytes: 256 pixels a run
STRIP_H = 32                    ; rows: fonts up to 32 lines (with the underline)

.segment "BSS"

strip:	.res STRIP_W * STRIP_H
stOpen:	.res 1                  ; $80: a run is being collected
stX0:	.res 2                  ; screen x of the strip's first byte (a card)
stLeft:	.res 1                  ; first pixel's bit in the strip (0-7)
stBit:	.res 1                  ; next character's bit position in the strip
stBase:	.res 2                  ; the baseline of the run
stRev:	.res 1                  ; $FF: reversed
chW:	.res 1                  ; the character's width (with styles)
chGW:	.res 1                  ; its glyph's width (from the index table)
chSrc   = kTmp + 2              ; (2) bit position in the font's rows (V141: zero
				; page, where bank G2's HiLook gives it)
lastW:	.res 1
yb:	.res 2                  ; baseline (wide)
row:	.res 1
rowSrc:	.res 2
dbit:	.res 1
dbyte0:	.res 1
sShift:	.res 1
sVec:	.res 2
stUL:	.res 1
c0:	.res 1
c1:	.res 1
c2:	.res 1
cnt:	.res 1
stLean:	.res 1                  ; the run's overhang (V122): pixels (0: none)
oB0:	.res 1                  ; its first byte in the strip
oE:	.res 1                  ; its last
oM0:	.res 1                  ; the pixels in oB0 (from stBit)
oEM:	.res 1                  ; and in oE (before the end)
oSv:	.res 1                  ; the run's first column
pOn:	.res 1                  ; bit 7: strip bytes 0-3 hold the last overhang
pX:	.res 2                  ; where it starts (the last run's end)
pBase:	.res 2                  ; its baseline
pBo:	.res 1                  ; its baselineOffset
; (its index table: IDX_COPY, the last 194 bytes of this bank, written by
; the font service in bank T; tools/kbuild.py checks that bank G ends before)

.segment "CODE"

;---------------------------------------------------------------
; fonts
;---------------------------------------------------------------
k_UseSystemFont:
	LoadW r0, SystemFont
k_LoadCharSet:
	stz fontBank            ; (a font in the program's memory)
	stz sysFont             ; the system font has a fast path (SysRows)
	lda r0L
	cmp #<SystemFont
	bne @g
	lda r0H
	cmp #>SystemFont
	bne @g
.ifndef NOFASTFONT
	dec sysFont
.endif
@g:	ldy #0
	lda (r0),y
	sta baselineOffset
	iny
	lda (r0),y
	sta curSetWidth
	iny
	lda (r0),y
	sta curSetWidth+1
	iny
	lda (r0),y
	sta curHeight
	iny
	lda (r0),y
	clc
	adc r0L
	sta curIndexTable
	iny
	lda (r0),y
	adc r0H
	sta curIndexTable+1
	iny
	lda (r0),y
	clc
	adc r0L
	sta cardDataPntr
	iny
	lda (r0),y
	adc r0H
	sta cardDataPntr+1
	rts

; a = character -> a = its width in the font (0 for codes); $80-$FF:
; GcwHi (V141: the font's $A0-$FF, else '?')
k_GetCharWidth:
	sec
	sbc #32
	bcc Gcw0
	cmp #96
	bcc GcwLo
	jmp GcwHi
GcwLo:	asl
	tay
	iny
	iny
	lda (curIndexTable),y   ; next start - this start
	dey
	dey
	sec
	sbc (curIndexTable),y
	rts
Gcw0:	lda #0
	rts

; a = a glyph's width, x = currentMode -> a = the width with the styles
; (bold + 1, outline + 2)
Styled:	pha
	txa
	and #SET_BOLD
	beq @1
	pla
	inc a
	pha
@1:	txa
	and #SET_OUTLINE
	beq @2
	pla
	inc a
	inc a
	rts
@2:	pla
	rts

; a = character, x = currentMode -> y = width, x = height, a = baseline
k_GetRealSize:
	stx kTmp
	jsr k_GetCharWidth
	tay
	ldx curHeight
	lda kTmp
	and #SET_BOLD
	beq @1
	iny
@1:	lda kTmp
	and #SET_OUTLINE
	beq @2
	iny
	iny
	inx
	inx
	lda baselineOffset
	clc
	adc #2
	rts
@2:	lda baselineOffset
	rts

;---------------------------------------------------------------
; WPutChar: a, r11 x (advances), r12 baseline
;---------------------------------------------------------------
k_WPutChar:
	pha
	MoveW r12, yb
	pla
	jsr PutC
	jmp Flush

; without codes and margins
k_WSmallPutChar:
	pha
	MoveW r12, yb
	pla
	cmp #32
	bcc @r
	jsr AddChar
	jmp Flush
@r:	rts

; one character of a string (codes included): the run stays open
PutC:	cmp #32
	bcs @ch
	jmp Code
@ch:	pha
	jsr k_GetCharWidth      ; the glyph's width, and with the styles
	sta chGW
	ldx currentMode
	beq @w0
	jsr Styled
@w0:	sta chW
	sta lastW
	tay
	; right edge past rightMargin: StringFaultVec
	tya
	clc
	adc r11L
	sta kTmp
	lda r11H
	adc #0
	sta kTmp+1
	lda kTmp                ; kTmp = x + width - 1
	bne @d
	dec kTmp+1
@d:	dec kTmp
	CmpW rightMargin, kTmp
	bcs @in
	jmp PastR               ; (right of rightMargin: LATE)
@in:	CmpW r11, leftMargin    ; left of leftMargin: skipped
	bcs @draw
	jmp PastL
@draw:	pla
	jmp AddCharW            ; (chW is known)

;---------------------------------------------------------------
; WPutString: r0 string, r11 x, r12 baseline
;---------------------------------------------------------------
k_WPutString:
	MoveW r12, yb
@next:	ldy #0
	lda (r0),y
	beq @end
	IncW r0
	cmp #ESC_GRAPHICS
	beq @gr
	jsr PutC
	bra @next
@end:	IncW r0                 ; r0 past the 0 (i_PutString, ESC_GRAPHICS)
	jmp Flush
@gr:	jsr PutC                ; (V91) GEOS 64's rule: the GraphicsString's
	jmp Flush               ; 0 ends the string too, r0 past it

;---------------------------------------------------------------
; the run
;---------------------------------------------------------------
; a = a character >= 32 at r11, yb: into the strip; r11 advances
AddChar:
	pha
	jsr k_GetCharWidth
	sta chGW
	ldx currentMode
	beq @w0
	jsr Styled
@w0:	sta chW
	sta lastW
	pla
AddCharW:                       ; (chW and chGW are known)
	pha
	; a new run if none is open, the baseline moved, or it is full
	bit stOpen
	bpl @new
	CmpW yb, stBase
	bne @flush
	lda stRev
	eor currentMode         ; (reverse is bit 5)
	and #SET_REVERSE
	bne @flush
	lda stBit
	clc
	adc chW
	bcs @flush
	cmp #256 - 40           ; room for italic and the spill bytes
	bcs @flush
	bra @add
@flush:	jsr Flush
@new:	lda r11L
	and #7
	sta stLeft
	sta stBit
	lda r11L
	and #$F8
	sta stX0
	MoveB r11H, stX0+1
	MoveW yb, stBase
	lda currentMode
	and #SET_REVERSE
	beq @nr
	lda #$FF
@nr:	sta stRev
	jsr Seed                ; (stOpen: $80)
@add:	pla
	jsr Glyph
	lda stBit
	clc
	adc chW
	sta stBit
	lda chW
	clc
	adc r11L
	sta r11L
	bcc @r
	inc r11H
@r:	rts

; character a (>= 32) into the strip at stBit, with bold, italic, underline.
; Each row in chunks of up to 8 pixels: a 16-bit window of the font row is
; shifted left until the chunk is its top byte, masked to the chunk's
; width, made bold (v | v >> 1, the extra pixel spills into the next
; byte), shifted right into place (24 bits) and ORed into the strip.
Glyph:	sec
	sbc #32
	cmp #96
	bcc GlyLo
	jmp GlyHi               ; (V141: $80-$FF, LATE)
GlyLo:	bit sysFont             ; the system font, no bold or italic: fast
	bpl @slow
	pha
	lda currentMode
	and #SET_BOLD | SET_ITALIC
	bne @sl
	pla
	jmp GlyphFast
.ifdef NOFASTFONT
@sl:	pla
.else
@sl:	jmp SysSlow             ; (bold, italic: V122; its pla there)
.endif
@slow:	asl
	tay
	lda (curIndexTable),y
	sta chSrc
	iny
	lda (curIndexTable),y
	sta chSrc+1
	; the character's first byte in row 0: cardDataPntr + chSrc / 8
GlySrc:	lsr                     ; (a = chSrc + 1: GlyHi too)
	sta kTmp+1
	lda chSrc
	ror
	lsr kTmp+1
	ror
	lsr kTmp+1
	ror
	clc
	adc cardDataPntr
	sta rowSrc
	lda kTmp+1
	adc cardDataPntr+1
	sta rowSrc+1
	lda chSrc
	and #7
	sta sShift
	jsr UiFast              ; (V81: the UI font, c set: drawn)
	bcc GlyphGen
	rts
GlyphGen:                       ; (rowSrc, sShift, chGW set; SysSlow too)
	lda #0
	jsr StripRow            ; kPtr = row 0 of the strip
	stz row
@row:	lda row
	cmp curHeight
	bcc @r1
	jmp @ul
@r1:	cmp #STRIP_H
	bcc @r2
	jmp @ul
@r2:	; destination bit: stBit, italic: + (baseline + 2 - row) / 2
	lda stBit
	sta dbit
	lda currentMode
	and #SET_ITALIC
	beq @ni
	lda baselineOffset      ; (baseline + 2 - row) / 2, as GEOS
	clc
	adc #2
	sec
	sbc row
	bcc @ni
	lsr
	clc
	adc dbit
	sta dbit
@ni:	jsr RowPtr              ; kPtr2 = the glyph's row (V62: or a copy)
	lda chGW
	sta cnt                 ; pixels left
	bne @chunk
	jmp @next
@chunk:	; the window, shifted left by sShift
	lda (kPtr2)
	sta c0
	ldy #1
	lda (kPtr2),y
	sta c1
	ldx sShift
	beq @s1
@s0:	asl c1
	rol c0
	dex
	bne @s0
@s1:	; mask to min(8, cnt) pixels
	lda cnt
	cmp #8
	bcc @m
	lda #8
@m:	tax
	lda c0
	and LeadMask,x
	sta c0
	stz c1
	stz c2
	lda currentMode         ; bold
	and #SET_BOLD
	beq @nb
	lda c0
	lsr
	ror c1
	ora c0
	sta c0
@nb:	; into place: right by dbit AND 7
	lda dbit
	and #7
	tax
	beq @p1
@p0:	lsr c0
	ror c1
	ror c2
	dex
	bne @p0
@p1:	lda dbit
	lsr
	lsr
	lsr
	tay
	lda c0
	ora (kPtr),y
	sta (kPtr),y
	iny
	lda c1
	ora (kPtr),y
	sta (kPtr),y
	lda c2
	beq @p2
	iny
	ora (kPtr),y
	sta (kPtr),y
@p2:	; the next chunk: 8 pixels on
	inc kPtr2
	bne @p3
	inc kPtr2+1
@p3:	lda dbit
	clc
	adc #8
	sta dbit
	lda cnt
	sec
	sbc #8
	bcc @next
	beq @next
	sta cnt
	jmp @chunk
@next:	AddW curSetWidth, rowSrc
	AddVW STRIP_W, kPtr
	inc row
	jmp @row
@ul:
Underline:
	; underline: the row below the baseline, the character's full width
	lda currentMode
	and #SET_UNDERLINE
	beq @r
	LoadB stUL, $80
	lda baselineOffset
	clc
	adc #1
	cmp #STRIP_H
	bcs @r
	jsr StripRow
	lda stBit
	sta dbit
	lda chW
	sta cnt
@u:	jsr SetBit
	inc dbit
	dec cnt
	bne @u
@r:	rts
	; (GlyphFast's row loop stays in one page: V62, V81; the assert below)

; the system font, plain: its rows left aligned (SysRows, 9 a character),
; each shifted right once by stBit AND 7 and ORed into two strip bytes
GlyphFast:
	sta kTmp                ; kPtr2 = SysRows + index * 9
	stz kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	clc
	adc kTmp
	sta kPtr2
	lda kTmp+1
	adc #0
	sta kPtr2+1
	AddVW SysRows, kPtr2
	lda #SYS_H
GlyphRun:                       ; (a = rows, kPtr2 their left aligned bytes: UiFast too)
	sta row
	lda #0
	jsr StripRow
	lda stBit
	and #7
	sta sShift
	lda stBit
	lsr
	lsr
	lsr
	sta dbyte0
	; the shift by sShift: a jump into the unrolled chain below
	lda sShift
	asl
	asl
	sta kTmp
	lda #<ChainEnd
	sec
	sbc kTmp
	sta sVec
	lda #>ChainEnd
	sbc #0
	sta sVec+1
FRow:	lda (kPtr2)
	sta kTmp+2
	stz kTmp+3
	jmp (sVec)
Chain:
.repeat 7
	lsr kTmp+2
	ror kTmp+3
.endrepeat
ChainEnd:
	ldy dbyte0
	lda kTmp+2
	ora (kPtr),y
	sta (kPtr),y
	iny
	lda kTmp+3
	ora (kPtr),y
	sta (kPtr),y
	inc kPtr2
	bne @2
	inc kPtr2+1
@2:	lda kPtr
	clc
	adc #STRIP_W
	sta kPtr
	bcc @3
	inc kPtr+1
@3:	dec row
	bne FRow
.assert >FRow = >*, lderror, "GlyphFast's row loop crosses a page (a cycle a row more)"
	jmp Underline

; a = row -> kPtr = strip + row * STRIP_W
StripRow:
	stz kPtr+1
	asl
	asl
	asl
	asl
	rol kPtr+1
	asl
	rol kPtr+1
	clc
	adc #<strip
	sta kPtr
	lda kPtr+1
	adc #>strip
	sta kPtr+1
	rts

; the UI font (bank T), not italic, its width 1-8 (bold: 1-7): bank T
; puts its rows left aligned (shifted, masked, bold) on the stack (LK_ROWS)
; and the system font's loop (GlyphRun) takes them; c set when drawn
; (V81: 0.4 ms a character, from 0.9: no row copy and no bit loops a row)
UiFast:	lda fontBank
	sec
	sbc kBankBase
	cmp #BANK_T
	bne @no
	lda currentMode
	and #SET_ITALIC
	bne @no
	lda chGW
	beq @no
	bit currentMode         ; (bold, bit 6: a pixel wider)
	bvc @w
	ina
@w:	cmp #9
	bcs @no
	tsx                     ; curHeight bytes on the stack
	txa
	sec
	sbc curHeight
	tax
	txs
	inx
	stx kPtr
	LoadB kPtr+1, $01
	lda rowSrc              ; (an offset in the font's bank: from $A000)
	sta kPtr2
	lda rowSrc+1
	ora #$A0
	sta kPtr2+1
	MoveB sShift, kTmp
	MoveB chGW, kTmp+1
	ldx #LK_ROWS
	FARCALL Look
	MoveW kPtr, kPtr2
	lda curHeight
	jsr GlyphRun            ; (its Underline returns here)
	tsx
	txa
	clc
	adc curHeight
	tax
	txs
	sec
	rts
@no:	clc
	rts

; kPtr2 = the glyph's row rowSrc; a banked font (DECISIONS V62): a copy
; through FontRow, (width + 7) / 8 + 1 bytes (the chunks read a byte past
; each). Out of Glyph's way: GlyphFast, the system font's path, keeps its
; addresses, so its loops keep their places in their pages (a branch
; across a page costs a cycle: 1.4 us a character)
.segment "LATE"

; PutC's character (pushed) past rightMargin: StringFaultVec; with the
; clip (V81) drawn if it starts in it (its spans clipped), else skipped
PastR:	lda clipOn
	beq @fault
	CmpW rightMargin, r11
	bcs PDraw
	jsr Flush
	bra PSkip
@fault:	pla
	jsr Flush
	lda StringFaultVec
	ora StringFaultVec+1
	beq PRts
	jmp (StringFaultVec)
; left of leftMargin: skipped; with the clip drawn if it ends in it
PastL:	lda clipOn
	beq PSkip
	CmpW kTmp, leftMargin
	bcs PDraw
PSkip:	pla
	lda chW
	clc
	adc r11L
	sta r11L
	bcc PRts
	inc r11H
PRts:	rts
PDraw:	pla
	jmp AddCharW

; codes 0-31
Code:	cmp #8
	bcc @r
	cmp #28
	bcs @r
	pha
	jsr Flush
	pla
	sec
	sbc #8
	asl
	tax
	jmp (CodeTab,x)
@r:	rts

CodeTab:
	.word CBack, CTab, CLF, CHome, CUp, CCR, CULOn, CULOff
	.word CGraph, CRuler, CRevOn, CRevOff, CGotoX, CGotoY, CGotoXY, CNewSet
	.word CBold, CItal, COutl, CPlain

CBack:	lda r11L                ; back by the last width
	sec
	sbc lastW
	sta r11L
	bcs @1
	dec r11H
@1:	rts
CTab:	lda #' '
	jmp PutC
CLF:	lda curHeight
	clc
	adc yb
	sta yb
	bcc @1
	inc yb+1
@1:	rts
CHome:	MoveW leftMargin, r11
	lda windowTopW
	clc
	adc baselineOffset
	sta yb
	lda windowTopW+1
	adc #0
	sta yb+1
	rts
CUp:	lda yb
	sec
	sbc curHeight
	sta yb
	bcs @1
	dec yb+1
@1:	rts
CCR:	MoveW leftMargin, r11
	jmp CLF
CULOn:	lda #SET_UNDERLINE
	bra SetM
CULOff:	lda #<~SET_UNDERLINE
	bra ClrM
CRevOn:	lda #SET_REVERSE
	bra SetM
CRevOff: lda #<~SET_REVERSE
	bra ClrM
CBold:	lda #SET_BOLD
	bra SetM
CItal:	lda #SET_ITALIC
	bra SetM
COutl:	lda #SET_OUTLINE
SetM:	ora currentMode
	sta currentMode
	rts
ClrM:	and currentMode
	sta currentMode
	rts
CPlain:	stz currentMode
	rts
CGraph:	; a GraphicsString follows (bank G2): r0 points at it, and after it
	; when it ends
	FARCALL k_GraphicsString
	rts
CRuler:	rts                     ; documents only
CGotoX:	jsr Word
	sta r11L
	stx r11H
	rts
CGotoY:	jsr Byte
	sta yb
	stz yb+1
	rts
CGotoXY: jsr CGotoX
	jmp CGotoY
CNewSet: jsr Word
	sta kPtr
	stx kPtr+1
	PushW r0
	MoveW kPtr, r0
	jsr k_LoadCharSet
	PopW r0
	rts

; the next byte(s) of the string
Byte:	ldy #0
	lda (r0),y
	pha
	IncW r0
	pla
	rts
Word:	jsr Byte
	pha
	jsr Byte
	tax
	pla
	rts


.segment "LATE"

; characters $80-$FF (V141): bank G2's HiLook finds the glyph of $A0-$FF
; in a font that has them (an extended record: tools/fontcvt.py); else
; the font's '?' (31 = '?' - 32)
GcwHi:	phx
	jsr HiCall              ; y = the width, c set: none
	plx
	bcs @q
	tya
	rts
@q:	lda #'?' - 32
	jmp GcwLo
GlyHi:	jsr HiCall              ; chSrc (kTmp + 2) the glyph's bit, a its high
	bcs @q                  ; byte; c set: none
	jmp GlySrc
@q:	lda #'?' - 32
	jmp GlyLo
; FARCALL HiLook without a resident stub (kernel/exports.txt: -HiLook):
; bank G2's tail in the stubs
HiCall:	sta gA
	lda #<E_HiLook
	jmp Tail1               ; (BANK_G2)

RowPtr:	lda fontBank
	bne @b
	MoveW rowSrc, kPtr2
	rts
@b:	lda chGW
	clc
	adc #7
	ror
	lsr
	lsr
	ina
	cmp #ROWBUF
	bcc @1
	lda #ROWBUF
@1:	tay
	lda rowSrc
	ldx rowSrc+1
	jmp FontRow

.segment "CODE"

; set bit dbit of the strip row kPtr (dbit < 256)
SetBit:	phy
	lda dbit
	lsr
	lsr
	lsr
	tay
	lda dbit
	and #7
	tax
	lda BitMask,x
	ora (kPtr),y
	sta (kPtr),y
	ply
	rts

;---------------------------------------------------------------
; the strip to the screen, then cleared
;---------------------------------------------------------------
Flush:	bit stOpen
	bmi @1
	rts
@1:	stz stOpen
	jsr OhSetup             ; (V122: italic's overhang)
	lda stBit
	cmp stLeft
	bne @2
	jmp @clear              ; nothing in it (a seed, maybe)
@2:	; bytes: (stBit + 7) / 8; keep masks for the first and last pixel
	clc
	adc #7
	ror                     ; (c from the add: up to 263)
	lsr
	lsr
	sta fbCnt
	ldx stLeft
	lda KeepLeft,x
	sta fbKeepL
	lda stBit
	sec
	sbc #1
	and #7
	tax
	lda KeepRight,x
	sta fbKeepR
	lda stX0+1              ; first column = stX0 / 8
	lsr
	sta kTmp
	lda stX0
	ror
	lsr kTmp
	ror
	lsr
	sta fbCol
	; clip to the screen's width
	lda kStride             ; columns on the screen
	sec
	sbc fbCol
	bcc @off
	bne @on
@off:	jmp @clear
@on:	cmp fbCnt
	bcs @w
	sta fbCnt
	stz fbKeepR
@w:	MoveB stRev, fbXor
	LoadB fbOp, FBOP_BUF
	MoveB dispBufferOn, fbSel
	; rows: top = baseline - baselineOffset
	lda stBase
	sec
	sbc baselineOffset
	sta kTmp
	lda stBase+1
	sbc #0
	sta kTmp+1
	stz row
@row:	lda row
	cmp curHeight
	bcs @oh
	cmp #STRIP_H
	bcs @oh
	; on the screen and inside the window?
	lda kTmp+1
	bmi @skip
	CmpW kTmp, windowTopW
	bcc @skip
	CmpW windowBottomW, kTmp
	bcc @skip
	CmpW kTmp, screenHeight
	bcs @skip
	MoveW kTmp, fbRow
	lda row
	jsr StripRow
	MoveW kPtr, fbBufPtr
	lda fbCnt
	pha
	jsr fb_span
	pla
	sta fbCnt
@skip:	IncW kTmp
	inc row
	bra @row
@oh:	lda stLean              ; italic's overhang ORed on (V122)
	beq @clear
	jsr OhRows
@clear:	; clear the bytes used, every row (with the overhang's: V122)
	lda stBit
	clc
	adc stLean
	bcs @cf
	adc #7
	ror
	lsr
	lsr
	cmp #4                  ; (and a seed's 4 bytes)
	bcs @c6
	lda #4
	bra @c6
@cf:	lda #STRIP_W
@c6:	sta cnt
	lda stLean              ; an overhang: kept for the next run (Seed)
	beq @c9
	jmp OhClear
@c9:	stz row
@c1:	lda row
	cmp #STRIP_H
	bcs @r
	ldx curHeight           ; rows 0 .. curHeight - 1 (+ the underline)
	bit stUL
	bpl @c0
	inx
	inx
@c0:	cpx row
	beq @r
	bcc @r
	jsr StripRow
	ldy cnt
	lda #0
@c2:	dey
	sta (kPtr),y
	bne @c2
	inc row
	bra @c1
@r:	stz stUL
	rts

;---------------------------------------------------------------
; italic's overhang (V122), out of the text's loops' way
;---------------------------------------------------------------
.segment "LATE"

; Flush's start: an italic run's overhang: stLean pixels ((baselineOffset
; + 2) / 2, none past rightMargin) from stBit: its bytes oB0 .. oE (oM0,
; oEM: the first's and the end's masks); pX, pBase, pBo for Seed
OhSetup:
	stz stLean
	stz pOn
	lda currentMode
	and #SET_ITALIC
	beq @r
	lda stX0                ; pX = the run's end
	clc
	adc stBit
	sta pX
	lda stX0+1
	adc #0
	sta pX+1
	MoveW stBase, pBase
	lda baselineOffset
	sta pBo
	clc
	adc #2
	lsr
	tay                     ; (the lean)
	lda rightMargin         ; x = rightMargin - pX: at most x + 1 pixels
	sec
	sbc pX
	tax
	lda rightMargin+1
	sbc pX+1
	bmi @r                  ; (pX past it: none)
	bne @1
	inx
	beq @1                  ; (256)
	stx kTmp
	cpy kTmp
	bcc @1
	ldy kTmp
@1:	sty stLean
	dec pOn
	lda stBit
	lsr
	lsr
	lsr
	sta oB0
	lda stBit
	and #7
	tax
	lda KeepLeft,x
	eor #$FF
	sta oM0
	tya
	clc
	adc stBit               ; the end: stBit + stLean (255 at most)
	bcc @2
	lda #$FF
@2:	tax
	lsr
	lsr
	lsr
	sta oE
	txa
	and #7
	tax
	lda KeepLeft,x
	sta oEM
@r:	rts

; y = an overhang byte of the strip (oB0 .. oE) -> a = its pixels' mask
; (x kept)
OhMask:	lda #0
	cpy oE
	beq @e
	bcs @r                  ; (past the end)
	lda #$FF
	bra @f
@e:	lda oEM
@f:	cpy oB0
	bne @r
	and oM0
@r:	rts

; Flush, after the run's rows: the overhang's (0 .. baselineOffset) that
; are on the screen and in the window, its pixels ORed on (a span of one
; byte a byte, the byte's other pixels kept; fbOp, fbSel, fbXor the run's)
OhRows:	MoveB fbCol, oSv        ; (the run's first column)
	stz row
@row:	lda row
	cmp curHeight
	bcs @r
	cmp #STRIP_H
	bcs @r
	cmp baselineOffset      ; (below: no lean)
	beq @1
	bcs @r
@1:	jsr OhRow
	inc row
	bra @row
@r:	rts

; row a of them
OhRow:	clc                     ; fbRow = stBase - baselineOffset + row
	adc stBase
	tax
	lda stBase+1
	adc #0
	tay
	txa
	sec
	sbc baselineOffset
	sta fbRow
	tya
	sbc #0
	sta fbRow+1
	bmi @n
	CmpW fbRow, windowTopW
	bcc @n
	CmpW windowBottomW, fbRow
	bcc @n
	CmpW fbRow, screenHeight
	bcs @n
	lda row
	jsr StripRow
	ldy oB0
@b:	jsr OhMask
	and (kPtr),y
	beq @x
	eor #$FF
	sta fbKeepL
	sta fbKeepR
	tya                     ; its column
	clc
	adc oSv
	cmp kStride
	bcs @n                  ; (off the screen)
	sta fbCol
	LoadB fbCnt, 1
	tya
	clc
	adc kPtr
	sta fbBufPtr
	lda kPtr+1
	adc #0
	sta fbBufPtr+1
	phy
	jsr fb_span
	ply
@x:	cpy oE
	iny
	bcc @b
@n:	rts

; Flush's clear with an overhang: every row as there, each by OhKeep
OhClear:
	stz row
@c1:	lda row
	cmp #STRIP_H
	bcs @r
	ldx curHeight           ; rows 0 .. curHeight - 1 (+ the underline)
	bit stUL
	bpl @c0
	inx
	inx
@c0:	cpx row
	beq @r
	bcc @r
	jsr StripRow
	jsr OhKeep
	inc row
	bra @c1
@r:	stz stUL
	rts

; Flush's clear of row kPtr with an overhang: its 4 bytes from oB0
; (masked) kept, the row's cnt bytes cleared, the 4 put in bytes 0-3
OhKeep:	ldx #0
	ldy oB0
@k:	jsr OhMask
	and (kPtr),y
	sta kTmp,x
	iny
	inx
	cpx #4
	bne @k
	ldy cnt
	lda #0
@c:	dey
	sta (kPtr),y
	bne @c
	ldy #3
@w:	lda kTmp,y
	sta (kPtr),y
	dey
	bpl @w
	rts

; AddCharW's new run at r11, yb: the last run's overhang (strip bytes 0-3,
; rows 0 .. pBo) kept for it if it goes on from it, else cleared; stOpen
Seed:	LoadB stOpen, $80
	bit pOn
	bpl @r
	stz pOn
	CmpW r11, pX
	bne @cl
	CmpW yb, pBase
	bne @cl
	lda baselineOffset
	cmp pBo
	bne @cl
	cmp curHeight           ; (its rows this font's: Flush clears them)
	bcc @r
@cl:	ldx pBo
@c0:	cpx #STRIP_H
	bcs @c2
	txa
	jsr StripRow
	lda #0
	ldy #3
@c1:	sta (kPtr),y
	dey
	bpl @c1
@c2:	dex
	bpl @c0
@r:	rts

.ifndef NOFASTFONT
; Glyph's system font in bold or italic (V122; the index pushed): the
; generic rows (GlyphGen) from SysRows, a byte a row (its glyphs 1-8
; pixels, 9 bytes a character), so the font's own bitmap is not kept in
; this bank (576 bytes)
SysSlow:
	pla
	sta kTmp                ; rowSrc = SysRows + index * 9
	stz kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	clc
	adc kTmp
	sta rowSrc
	lda kTmp+1
	adc #0
	sta rowSrc+1
	AddVW SysRows, rowSrc
	stz sShift
	PushW curSetWidth       ; (a row: 1 byte)
	LoadW curSetWidth, 1
	jsr GlyphGen
	PopW curSetWidth
	rts
.endif

.segment "RODATA"

LeadMask:	.byte $00, $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF

SystemFont:
.ifdef NOFASTFONT
	.incbin "system.bin"
.else
	.incbin "system.bin", 0, 8 + 2 * 97 ; (V122: without its bitmap, which
	; is SysRows' rows again: SysSlow; cardDataPntr is SysRows, unread)
.endif
SysRows:
.ifndef NOFASTFONT
	.incbin "system_rows.bin"
.endif
SYS_H = 9                       ; (tools/mkfont.py)
