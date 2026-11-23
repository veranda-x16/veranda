; Veranda bank G2: CopyRect and ScrollRect (moved from bank G in phase 9,
; to make room there for the FX fills; docs/DECISIONS.md V29), and VCopy,
; the save-under's copies (bank U, kernel/u/under.s; V80)
;
; Whole cards on whole rows: port 1 reads the source row, port 0 writes
; the destination row; each row's addresses are the last row's plus or
; minus the stride (V80). With VERA FX (kFx bit 7) a row's middle goes
; through the 32-bit cache: 4 reads of DATA1 fill it, 1 write of DATA0
; stores its 4 bytes at a multiple of 4 (5 cycles a byte; 8 with the
; plain loop, unrolled; 13 before). The cache only with interrupts off,
; one row at a time (at most 500 cycles), as the FX fills (V29, V68).
; ScrollRect fills the uncovered rows with WRectangle (bank G).

.include "kernel.inc"

.import kStride, kFx
.export k_CopyRect, k_ScrollRect, VCopy
.global S_k_SetPattern, S_k_WRectangle

.segment "BSS"

cpN:	.res 2                  ; rows left
cpS:	.res 3                  ; the source row's address (17 bits)
cpD:	.res 3                  ; the destination row's
cpSs:	.res 1                  ; their steps (down; up if cpUp)
cpDs:	.res 1
cpUp:	.res 1                  ; bit 7: the rows from the bottom
cpW:	.res 1                  ; bytes a row
cpBack:	.res 1                  ; $08: right to left (ADDR_H's decrement)
cpFx:	.res 1                  ; bit 7: the rows through the cache
cpI1:	.res 1                  ; ADDR_H's increment (and decrement)
cpGeo:	.res 1                  ; 0: every row's groups alike
cpIdx:	.res 1                  ; FX_MULT: the cache's first byte
cpR0:	.res 1                  ; the first group's reads,
cpM0:	.res 1                  ; its write's mask
cpMb:	.res 1                  ; the middle groups: 4 at a time,
cpMs:	.res 1                  ; one at a time
cpRl:	.res 1                  ; the last group's reads (0: none),
cpMl:	.res 1                  ; its mask
cpBuf:	.res 1                  ; 0 the foreground, 1 the back screen
cpRow:	.res 2                  ; Addr's row
cpT:	.res 2
cpH:	.res 1                  ; a row: bytes to a multiple of 4,
cpG:	.res 1                  ; groups of 4,
cpR:	.res 1                  ; the rest
scPat:	.res 2

; a data port (selected) at addr (17 bits), increment inc
.macro SEEK addr, inc
	lda addr
	sta VERA_ADDR_L
	lda addr+1
	sta VERA_ADDR_M
	lda addr+2
	ora inc
	sta VERA_ADDR_H
.endmacro

; the next row: to done if none is left, else the addresses + (or -) the
; strides
.macro STEP done
	.local go, up, s1, s2, n, u1, u2, u3
	lda cpN
	bne go
	dec cpN+1
go:	dec cpN
	lda cpN
	ora cpN+1
	bne s1
	bra done
s1:	bit cpUp
	bmi up
	lda cpS
	clc
	adc cpSs
	sta cpS
	bcc s2
	inc cpS+1
	bne s2
	inc cpS+2
s2:	lda cpD
	clc
	adc cpDs
	sta cpD
	bcc n
	inc cpD+1
	bne n
	inc cpD+2
	bra n
up:	lda cpS
	sec
	sbc cpSs
	sta cpS
	bcs u1
	lda cpS+1
	bne u2
	dec cpS+2
u2:	dec cpS+1
u1:	lda cpD
	sec
	sbc cpDs
	sta cpD
	bcs n
	lda cpD+1
	bne u3
	dec cpD+2
u3:	dec cpD+1
n:
.endmacro

.segment "CODE"

;---------------------------------------------------------------
; CopyRect: r3L x, r3H width (cards), r11 y, r12 height, r4L to x,
; r13 to y; on the screens dispBufferOn selects (each from itself)
;---------------------------------------------------------------
k_CopyRect:
	lda r3H
	beq @r
	lda r12
	ora r12+1
	beq @r
	LoadB cpBuf, 0          ; foreground
	bit dispBufferOn
	bpl @1
	jsr CopyBuf
@1:	LoadB cpBuf, 1          ; back screen
	bit dispBufferOn
	bvc @r
	bra CopyBuf
@r:	rts

CopyBuf:
	MoveW r12, cpN
	MoveB r3H, cpW
	; the bytes right to left if they go right on the same rows (before
	; V80: whenever they went right; on other rows the result is the same)
	; or a row passes the row's end (as before there: other rows' bytes)
	stz cpBack
	lda kFx
	sta cpFx
	lda r3L
	clc
	adc r3H
	bcs @wrap
	cmp kStride
	beq @w1
	bcs @wrap
@w1:	lda r4L
	clc
	adc r3H
	bcs @wrap
	cmp kStride
	beq @w2
	bcs @wrap
@w2:	lda r4L
	cmp r3L
	beq @rows
	bcc @rows
	CmpW r13, r11
	bne @rows
	bra @back
@wrap:	stz cpFx                ; (the plain loop, byte by byte as before)
	lda r4L
	cmp r3L
	beq @rows
	bcc @rows
@back:	LoadB cpBack, $08
	stz cpFx
@rows:	; the rows: from the last if the target is lower
	lda kStride
	sta cpSs
	sta cpDs
	stz cpUp
	MoveW r11, cpRow
	MoveW r13, cpT
	CmpW r13, r11
	bcc @2
	beq @2
	dec cpUp                ; from the bottom: the addresses step down
	lda r12
	sec
	sbc #1
	tax
	lda r12+1
	sbc #0
	tay
	txa
	clc
	adc cpRow
	sta cpRow
	tya
	adc cpRow+1
	sta cpRow+1
	txa
	clc
	adc cpT
	sta cpT
	tya
	adc cpT+1
	sta cpT+1
@2:	MoveW cpT, cpD          ; (Addr uses cpT)
	lda r3L
	jsr Addr
	stx cpS
	sty cpS+1
	sta cpS+2
	MoveW cpD, cpRow
	lda r4L
	jsr Addr
	stx cpD
	sty cpD+1
	sta cpD+2
	; fall into Rows

; cpN rows of cpW bytes from cpS to cpD; the next row's addresses
; + cpSs, + cpDs (- if cpUp); cpBack, cpFx
Rows:	bit cpFx
	bpl @p
	jmp FxRows
@p:	lda #VERA_INC1          ; the ports' increments
	ora cpBack
	sta cpI1
PlRow:	lda #1
	sta VERA_CTRL
	SEEK cpS, cpI1
	stz VERA_CTRL
	SEEK cpD, cpI1
	ldx cpW
	jsr Plain
	STEP PlEnd
	jmp PlRow
PlEnd:	rts

; x bytes (1-255), groups of 8 unrolled, then the rest
Plain:	txa
	and #7
	sta cpR
	txa
	lsr
	lsr
	lsr
	tax
	beq @r
@g:
.repeat 8
	lda VERA_DATA1
	sta VERA_DATA0
.endrepeat
	dex
	bne @g
@r:	ldx cpR
	beq @e
@1:	lda VERA_DATA1
	sta VERA_DATA0
	dex
	bne @1
@e:	rts

; the rows through the cache, by the destination's groups of 4: port 0
; steps by 4, and a cache write stores at the multiple of 4 below its
; address; the reads fill the cache from byte (d AND 3) on, and the first
; and the last group's writes mask the bytes outside the row (2 bits a
; byte: 3 keeps it). DCSEL 2 stays selected (the ports' addresses do not
; depend on it); the cache is on with interrupts off, a row at a time.
FxRows:	lda cpDs                ; the rows' groups alike if the target's
	and #3                  ; stride is a multiple of 4 (the screens)
	sta cpGeo
	jsr Geo
	lda #VERA_INC1
	sta cpI1
FxRow:	lda #2 << 1 | 1         ; DCSEL 2, port 1
	sta VERA_CTRL
	SEEK cpS, cpI1
	lda #2 << 1
	sta VERA_CTRL
	lda cpD
	sta VERA_ADDR_L
	lda cpD+1
	sta VERA_ADDR_M
	lda cpD+2
	ora #$30                ; port 0 steps by 4
	sta VERA_ADDR_H
	php
	sei
	lda #$60                ; cache writes, cache fills from the reads
	sta VERA_FX_CTRL
	lda cpIdx
	sta VERA_FX_MULT        ; the cache's first byte: the row's place
	ldx cpR0
@r1:	lda VERA_DATA1
	dex
	bne @r1
	lda cpM0
	sta VERA_DATA0
	ldy cpMb
	beq @m1
@m4:
.repeat 4
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	stz VERA_DATA0          ; (0: all four bytes)
.endrepeat
	dey
	bne @m4
@m1:	ldx cpMs
	beq @l
@m:	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	lda VERA_DATA1
	stz VERA_DATA0
	dex
	bne @m
@l:	ldx cpRl
	beq @e
@l1:	lda VERA_DATA1
	dex
	bne @l1
	lda cpMl
	sta VERA_DATA0
@e:	stz VERA_FX_CTRL
	plp
	STEP FxEnd
	lda cpGeo
	beq @next
	jsr Geo                 ; (the save-under's stack: rows of uW bytes)
@next:	jmp FxRow
FxEnd:	stz VERA_FX_MULT        ; (the cache's index 0 again; DCSEL 2)
	stz VERA_CTRL
	rts

; a row's groups from cpD AND 3 and cpW: the first's reads and mask, the
; middle ones (4 at a time and the rest), the last's reads (0: none) and
; mask
Geo:	lda cpD
	and #3
	sta cpH                 ; the first byte's place in its group
	asl
	asl
	sta cpIdx
	tax
	lda HeadMask,x          ; (x = 4 * place)
	sta cpM0
	lda cpH
	clc
	adc cpW
	tay
	and #3
	tax                     ; bytes in the last group (0: 4)
	lda TailMask,x
	sta cpMl
	txa
	bne @1
	lda #4
@1:	sta cpRl
	tya
	clc
	adc #3
	lsr
	lsr
	tay                     ; groups
	lda #4
	sec
	sbc cpH
	sta cpR0
	dey
	bne @2
	lda cpMl                ; one group: the last's mask too, w reads
	ora cpM0
	sta cpM0
	lda cpW
	sta cpR0
	stz cpRl
	stz cpMs
	stz cpMb
	rts
@2:	dey                     ; the middle ones
	tya
	and #3
	sta cpMs
	tya
	lsr
	lsr
	sta cpMb
	rts

; y.x.a: buffer cpBuf's address of row cpRow, card a (+ the width - 1 if
; right to left): row * 80 = row * 64 + row * 16 (half of it at 40)
Addr:	ldx cpBack
	beq @1
	clc
	adc cpW
	dec a                   ; (cards past 255 only for a bad call)
@1:	sta cpH
	lda cpRow
	sta cpT
	lda cpRow+1
	asl cpT
	rol
	asl cpT
	rol
	asl cpT
	rol
	asl cpT
	rol
	sta cpT+1               ; row * 16
	lda cpT
	sta cpG
	lda cpT+1
	asl cpG
	rol
	asl cpG
	rol
	tay                     ; row * 64: y, cpG
	lda cpG
	clc
	adc cpT
	sta cpT
	tya
	adc cpT+1
	ldy kStride
	cpy #80
	beq @2
	lsr                     ; 40 a row: half
	ror cpT
@2:	sta cpT+1
	lda cpT
	clc
	adc cpH
	tax
	lda cpT+1
	adc #0
	ldy cpBuf
	beq @3
	clc
	adc #>VRAM_BG
@3:	tay
	lda #0
	adc #0                  ; address bit 16 (the back screen crosses $10000)
	rts
HeadMask:	.byte $00, 0, 0, 0, $03, 0, 0, 0, $0F, 0, 0, 0, $3F    ; (4 * place)
TailMask:	.byte $00, $FC, $F0, $C0
.assert <VRAM_FG = 0 && <VRAM_BG = 0 && >VRAM_FG = 0, error, "Addr: the screens on pages, the foreground at 0"

;---------------------------------------------------------------
; VCopy (bank U's save-under, V80): rows of bytes VRAM to VRAM; on the
; caller's stack (pushed last first): source (3 bytes, 17 bits), target
; (3), bytes a row, rows (2), the source's stride, the target's
;---------------------------------------------------------------
VCopy:	tsx
	ldy #0
@p:	lda $0100 + FAR_STACK,x
	sta cpS,y
	inx
	iny
	cpy #6
	bne @p
	lda $0100 + FAR_STACK,x
	sta cpW
	lda $0100 + FAR_STACK + 1,x
	sta cpN
	lda $0100 + FAR_STACK + 2,x
	sta cpN+1
	lda $0100 + FAR_STACK + 3,x
	sta cpSs
	lda $0100 + FAR_STACK + 4,x
	sta cpDs
	stz cpUp
	stz cpBack
	lda kFx
	sta cpFx
	lda cpW
	beq @r
	lda cpN
	ora cpN+1
	beq @r
	jmp Rows
@r:	rts
.assert cpD = cpS + 3, error, "VCopy: cpS, cpD in a row"

;---------------------------------------------------------------
; ScrollRect: r3L x, r3H width (cards), r11 top, r12 bottom, r13 dy
; (signed lines; < 0 up), a = pattern number for the uncovered lines
;---------------------------------------------------------------
k_ScrollRect:
	pha
	MoveW curPattern, scPat
	pla
	FARCALL k_SetPattern
	; the moved part: height = bottom - top + 1 - |dy|
	lda r13+1
	bpl :+
	jmp @up
:
	; down: rows top .. bottom-dy -> top+dy ..
	lda r12
	sec
	sbc r11
	sta kTmp
	lda r12+1
	sbc r11+1
	sta kTmp+1
	IncW kTmp               ; height
	SubW r13, kTmp
	bcs :+
	jmp @fillall
:
	lda kTmp
	ora kTmp+1
	bne :+
	jmp @fillall
:
	PushW r12
	PushW r11
	MoveB r3L, r4L
	PushW r13
	AddW r11, r13           ; to y = top + dy
	MoveW kTmp, r12
	jsr k_CopyRect
	PopW r13
	PopW r11
	PopW r12
	; fill top .. top + dy - 1
	PushW r12
	MoveW r11, r12
	AddW r13, r12
	lda r12
	bne @d1
	dec r12+1
@d1:	dec r12
	jsr FillCards
	PopW r12
	jmp @done
@up:	; up by n = -dy: rows top+n .. bottom -> top ..; fill bottom-n+1 .. bottom
	lda #0
	sec
	sbc r13
	sta kTmp+2
	lda #0
	sbc r13+1
	sta kTmp+3              ; n
	lda r12
	sec
	sbc r11
	sta kTmp
	lda r12+1
	sbc r11+1
	sta kTmp+1
	IncW kTmp
	lda kTmp
	sec
	sbc kTmp+2
	sta kTmp
	lda kTmp+1
	sbc kTmp+3
	sta kTmp+1              ; height of the moved part
	bcc @fillall
	ora kTmp
	beq @fillall
	lda kTmp+2              ; (Seek uses kTmp+2 and +3: n kept on the stack)
	pha
	lda kTmp+3
	pha
	PushW r12
	PushW r11
	MoveW r11, r13          ; to y = top
	lda r11                 ; from y = top + n
	clc
	adc kTmp+2
	sta r11
	lda r11+1
	adc kTmp+3
	sta r11+1
	MoveB r3L, r4L
	MoveW kTmp, r12
	jsr k_CopyRect
	PopW r11
	PopW r12
	pla
	sta kTmp+3
	pla
	sta kTmp+2
	; fill bottom - n + 1 .. bottom
	PushW r11
	lda r12
	sec
	sbc kTmp+2
	sta r11
	lda r12+1
	sbc kTmp+3
	sta r11+1
	IncW r11
	jsr FillCards
	PopW r11
	bra @done
@fillall:
	jsr FillCards
@done:	MoveW scPat, curPattern
	rts

; the cards r3L .. r3L + r3H - 1 of rows r11 .. r12 with the pattern
FillCards:
	PushW r3
	PushW r4
	lda r3L                 ; x = r3L * 8 .. (r3L + r3H) * 8 - 1
	clc
	adc r3H
	sta r4L
	stz r4H
	ldx #3
@1:	asl r4L
	rol r4H
	dex
	bne @1
	lda r4L
	bne @2
	dec r4H
@2:	dec r4L
	stz r3H
	ldx #3
@3:	asl r3L
	rol r3H
	dex
	bne @3
	FARCALL k_WRectangle
	PopW r4
	PopW r3
	rts
