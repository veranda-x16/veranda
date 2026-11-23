; gate switch (DECISIONS V83): an application that the switcher puts
; aside and brings back. -D APPN=n (1-4).
;
; It fills its zero page $60-$6F, a 2 KB buffer and its bank 1's first
; page with patterns of its own, draws both screens differently, sets its
; colours and part of the colour map; ten main loop passes later it logs
; "SW n SUM <crc>" (zero page, buffer, bank 1, VRAM $00000-$1EFFF, palette
; entries 0-15, the video mode) and asks to be put aside (TaskCtl
; TASK_ASIDE). When it runs again (the next pass of its main loop is after
; it came back) it logs "SW n BACK <crc>" and "SW n SAME" or "SW n DIFF";
; the first time back it asks to be put aside again, the second time it
; quits (EnterDeskTop).
; -D KEYS: the two Returns as SwBig's (its header says stay = yes: it is
; never put aside, the kernel asks).
; -D ALTTAB: it never asks itself (V117): ten passes after it starts it
; logs its sum, sets $7F to $A5 for the gate's mouse script, which then
; presses Alt + Tab on the emulated keyboard, and waits (state 3).
; -D SHOT: the emulator ends (a dump) when it is back the first time.
; -D PORT: as a GEOS port would (no longNames, API 1, 640 x 240 in its
; header): a record file "SwData" made and kept open, a record written; the
; second time back it reads the record ("SW n REC <text>"), changes it,
; closes the file (written back) and quits.
; -D OWNFONT (V183): it loads Gate Sans 12 at its start ("SW n FONT 0000").
; -D SOME=n (V183): n banks of its own, each with a pattern, in its sum.
; -D HUGE (V145, Roomy): it takes every bank TaskCtl(TASK_ROOM) allows (all
; free banks but two), fills each with a pattern of its own and folds
; their CRCs into its sum: put aside onto the card and back, they must
; come back exactly; with BIG too (the card full) its two Returns: the
; kernel's box (OK alone) and the program goes on.
; -D BIG: it takes all free RAM banks (V145: not only the switcher's
; reserve: two free banks would put it onto the card), so that it cannot
; be put aside: the kernel's box asks; two Returns typed into the
; keyboard's queue with the request (the second is the box's: OK): it
; quits ("TASK QUIT").
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

RESERVE = 18

.segment "CODE"
	LoadW r0, MsgStart
	jsr LogText
	ldx #15                 ; zero page
@z:	txa
	clc
	adc #APPN * 16
	sta $60,x
	dex
	bpl @z
	LoadW r0, buf           ; the buffer
	ldy #0
	ldx #8
	lda #APPN
@b:	sta (r0),y
	clc
	adc #7
	iny
	bne @b
	inc r0H
	dex
	bne @b
	ldx #0                  ; bank 1's first page
@p:	txa
	eor #APPN * $11
	sta $A000,x
	inx
	bne @p
	; the screens: the foreground one pattern, the back screen another
	lda #APPN + 1
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 0
	MoveW screenWidth, r4
	AddVW $FFFF, r4
	MoveW screenHeight, r12
	AddVW $FFFF, r12
	jsr WRectangle
	LoadB dispBufferOn, ST_WR_BACK
	lda #APPN + 5
	jsr SetPattern
	LoadW r3, 16 * APPN
	LoadW r11, 8 * APPN
	LoadW r4, 300
	LoadW r12, 200
	jsr WRectangle
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	LoadW r0, $0F00 + APPN * $10    ; colours of its own
	LoadW r1, $0008 + APPN
	jsr SetColors
	LoadB r3L, 0            ; the colour map: rows 0-9 its colour
	LoadB r3H, 80
	LoadB r11L, 0
	LoadB r11H, 10
	lda #APPN + 2
	jsr ColorRect
.ifdef PORT
	LoadW r9, Hdr           ; its document, kept open
	stz r10L
	jsr SaveFile
	LoadW r0, NData
	jsr OpenRecordFile
	jsr AppendRecord
	LoadW r7, Text
	LoadW r2, TEXTLEN
	jsr WriteRecord
.endif
.if .defined(HUGE) .or .defined(SOME)
.ifdef SOME
	lda #SOME               ; (V183) banks of its own, as Veranda Write's
.else				; overlays and pool
	lda #TASK_ROOM          ; (V145) every bank it may take but one (V183:
	jsr TaskCtl             ; a font loaded while it is on the card goes
	dea                     ; there)
.endif
	sta hugeN
	jsr BankAlloc
	sta hugeB
	ldy hugeN
	ldx hugeB
@hb:	stx ram_bank             ; each bank: its number + APPN, rising
	stx r1L
	LoadW r0, $A000
@hp:	lda r1L
	sta (r0)
	inc r1L
	inc r0L
	bne @hp
	inc r0H
	lda r0H
	cmp #$C0
	bne @hp
	inx
	dey
	bne @hb
	lda #1
	sta ram_bank
.elseif .defined(BIG)
@ba:	LoadW r0, sum           ; every free bank (V145: not even the card's
	ldx #$FF                ; two banks are left), in runs as long as
	lda #TASK_INFO          ; they come (the free ones need not be in one)
	jsr TaskCtl
	lda sum + TS_FREE
	beq @nb
@bh:	sta hugeN
	jsr BankAlloc
	cmp #0
	bne @ba
	lda hugeN
	lsr
	bne @bh
@nb:
.endif
.ifdef OWNFONT
	LoadW r0, FontNm        ; (V183) a font of its own, kept by the font
	lda #12                 ; service while it is aside ("SW n FONT" x)
	jsr LoadFont
	stx r2L
	stz r2H
	LoadW r0, MsgFont
	jsr LogSum
.endif
	LoadW appMain, Main
	rts

Main:	inc passes
	lda state
	beq @0
	cmp #1
	beq @1
	cmp #3                  ; (-D ALTTAB: waiting for the keyboard)
	beq @r
	; 2: back, waiting
	lda passes
	cmp #10
	bne @r
	lda backs
	cmp #2
	beq @quit
	lda #1
	sta state
	lda #TASK_ASIDE
	jsr TaskCtl
@r:	rts
@0:	lda passes
	cmp #10
	bne @r
	jsr Sum
	MoveW r2, sum0
	LoadW r0, MsgSum
	jsr LogSum
	lda #1
	sta state
.ifdef ALTTAB
	lda #3
	sta state
	lda #$A5
	sta $7F
	rts
.endif
.if .defined(BIG) .or .defined(KEYS)
	lda #13                 ; two Returns: the next pass takes the first,
	jsr k_kbdbuf_put        ; the kernel's box (its nested main loop) the
	lda #13                 ; second: OK
	jsr k_kbdbuf_put
.endif
	lda #TASK_ASIDE
	jmp TaskCtl
@1:	; back
	jsr Sum
	LoadW r0, MsgBack
	jsr LogSum
	LoadW r0, MsgSame
	lda r2L
	cmp sum0
	bne @d
	lda r2H
	cmp sum0+1
	beq @s
@d:	LoadW r0, MsgDiff
@s:	jsr LogText
.ifdef SHOT
	lda #1                  ; -D SHOT: the end there, with a dump (its
	sta EMU_SAVE_ON_EXIT    ; screen as it came back)
	jmp $FFFF
.endif
	inc backs
	stz passes
	lda #2
	sta state
	rts
@quit:
.ifdef PORT
	lda #0
	jsr PointRecord
	LoadW r7, line + 10
	LoadW r2, 40
	jsr ReadRecord
	lda #0
	sta (r7)
	ldx #9
@m:	lda MsgRec,x
	sta line,x
	dex
	bpl @m
	LoadW r0, line
	jsr LogText
	LoadW r7, Text2         ; changed, then written back by the close
	LoadW r2, TEXT2LEN
	jsr WriteRecord
	jsr CloseRecordFile
.endif
	LoadW r0, MsgQuit
	jsr LogText
	jmp EnterDeskTop

; r0's text and the hex of r2 on the console
LogSum:	ldy #0
@c:	lda (r0),y
	sta line,y
	beq @h
	iny
	bra @c
@h:	lda r2H
	jsr Hex
	lda r2L
	jsr Hex
	lda #0
	sta line,y
	LoadW r0, line
	jmp LogText
Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	sta line,y
	iny
	rts

; r2 = a CRC of the state: zero page $60-$6F, the buffer, bank 1's page,
; then VRAM, the palette and the mode folded in
Sum:	LoadW r0, $60
	LoadW r1, 16
	jsr k_memory_crc
	MoveW r2, acc
	LoadW r0, buf
	LoadW r1, 2048
	jsr k_memory_crc
	jsr Fold
	LoadW r0, $A000
	LoadW r1, 256
	jsr k_memory_crc
	jsr Fold
	stz VERA_CTRL           ; VRAM: both screens ($00000-$12BFF), the
	stz VERA_ADDR_L         ; sprites and the colour map ($16C00-$1EFFF),
	stz VERA_ADDR_M         ; not the save-under stack (what is free there
	LoadB VERA_ADDR_H, VERA_INC1 ; holds nothing: the switcher clears it)
	stz r2L
	stz r2H
	ldy #$12C / 2
	jsr VSum
	ldy #$12C / 2
	jsr VSum
	jsr Fold
	LoadB VERA_ADDR_L, <VRAM_SPRITES
	LoadB VERA_ADDR_M, >VRAM_SPRITES
	LoadB VERA_ADDR_H, ^VRAM_SPRITES | VERA_INC1
	stz r2L
	stz r2H
	ldy #$1F0 - $16C
	jsr VSum
	jsr Fold
	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldy #0
	stz r2L
	stz r2H
@p:	lda VERA_DATA0
	eor r2L
	sta r2L
	inc r2H
	iny
	cpy #32
	bne @p
	lda graphMode
	eor r2H
	sta r2H
	jsr Fold
.if .defined(HUGE) .or .defined(SOME)
	ldx hugeB               ; (V145) its banks
	ldy hugeN
@hb:	phx
	phy
	stx ram_bank
	LoadW r0, $A000
	LoadW r1, $2000
	jsr k_memory_crc
	jsr Fold
	ply
	plx
	inx
	dey
	bne @hb
	lda #1
	sta ram_bank
.endif
	MoveW acc, r2
	rts
VSum:	ldx #0
@1:	lda VERA_DATA0
	clc
	adc r2L
	sta r2L
	bcc @2
	inc r2H
@2:	eor r2H
	sta r2H
	dex
	bne @1
	dey
	bne VSum
	rts
Fold:
.ifdef DBG
	PushW r0
	PushW r2
	LoadW r0, MsgPart
	jsr LogSum
	PopW r2
	PopW r0
.endif
	lda r2L
	eor acc+1
	sta acc+1
	lda r2H
	clc
	adc acc
	sta acc
	asl acc+1
	rol acc
	bcc @r
	inc acc+1
@r:	rts


.segment "RODATA"
MsgStart: .byte 10, "SW ", '0' + APPN, " START", 0
MsgSum:	.byte 10, "SW ", '0' + APPN, " SUM ", 0
MsgBack: .byte 10, "SW ", '0' + APPN, " BACK ", 0
MsgSame: .byte 10, "SW ", '0' + APPN, " SAME", 0
MsgDiff: .byte 10, "SW ", '0' + APPN, " DIFF", 0
MsgPart: .byte 10, "SW ", '0' + APPN, " PART ", 0
MsgQuit: .byte 10, "SW ", '0' + APPN, " QUIT", 0
.ifdef OWNFONT
MsgFont: .byte 10, "SW ", '0' + APPN, " FONT ", 0
FontNm:	.byte "Gate Sans", 0
.endif
.ifdef PORT
MsgRec:	.byte 10, "SW ", '0' + APPN, " REC "
NData:	.byte "SwData", 0
Text:	.byte "Kept open while aside", 0
TEXTLEN = * - Text
Text2:	.byte "Written back after", 0
TEXT2LEN = * - Text2
.endif

.segment "DATA"
passes:	.byte 0
state:	.byte 0
backs:	.byte 0
.ifdef PORT
Hdr:	.word NData
	.byte 3, 21, $BF
	.res 63, $AA
	.byte $83, APPL_DATA, 1
	.word 0, 0, 0
	.byte "SwData      V1.0", 0, 0, 0, 0
	.res 256 - 97, 0
.endif

.segment "BSS"
sum0:	.res 2
hugeN:	.res 1              ; (BIG: the run tried)
hugeB:	.res 1
acc:	.res 2
sum:	.res TASK_SUM
line:	.res 64
buf:	.res 2048
