; gate disk (phase 5): streams and DOS commands on device 8 (the emulator's
; host folder, or an SD card image). Each step logs a line; the host side
; (tests/check_disk.py) checks the files left behind.
;
;   W  32 KB written to DATA.BIN (a pattern), timed
;   R  read back into memory and compared, timed
;   S  seek to 1000 in a "m" stream, read 4 bytes
;   D  a directory DIRA, a file in it, back up
;   Q  a directory DIRE made and removed (RmDir)
;   N  RENAME OLD.BIN (made here) to NEW.BIN; DELETE GONE.BIN (made here)
;   L  the directory listing's names

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

SIZE = 32768
BUF  = $1000                    ; 32 KB: $1000-$8FFF would pass $87FF:
BUF2 = $2000                    ; written from BUF (4 KB repeated), read to BUF2

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	; the pattern: byte i = (i and 255) xor the high byte of BUF + i
	LoadW a0, BUF
	ldx #16                 ; 4 KB
	ldy #0
@p:	tya
	eor a0+1
	sta (a0),y
	iny
	bne @p
	inc a0+1
	dex
	bne @p

	; W: 32 KB in 8 writes of 4 KB
	jsr ClockStart
	LoadW r0, NData
	lda #'w'
	jsr FOpen
	jsr Check
	sta h
	LoadB n, 8
@w:	LoadW r0, BUF
	LoadW r1, 4096
	lda h
	jsr FWrite
	jsr Check
	dec n
	bne @w
	lda h
	jsr FClose
	lda #'W'
	jsr ClockLog

	; R: read back 4 KB at a time into BUF2, compared with BUF
	jsr ClockStart
	LoadW r0, NData
	lda #'r'
	jsr FOpen
	jsr Check
	sta h
	LoadB n, 8
	stz bad
@r:	LoadW r0, BUF2
	LoadW r1, 4096
	lda h
	jsr FRead
	jsr Check
	CmpWI r1, 4096
	beq @r1
	inc bad
@r1:	jsr Compare
	dec n
	bne @r
	LoadW r0, BUF2          ; past the end: 0 bytes
	LoadW r1, 16
	lda h
	jsr FRead
	lda r1L
	ora r1H
	beq @r2
	lda #'P'                ; (what came past the end)
	jsr Put
	lda r1H
	jsr Hex
	lda r1L
	jsr Hex
	lda BUF2
	jsr Hex
	jsr NL
	inc bad
@r2:	lda h
	jsr FClose
	lda #'R'
	jsr ClockLog
	lda #'R'
	ldx bad
	jsr Result

	; S: seek in a read-write stream
	LoadW r0, NData
	lda #'m'
	jsr FOpen
	jsr Check
	sta h
	LoadW r0, 1000
	LoadW r1, 0
	lda h
	jsr FSeek
	stx bad
	LoadW r0, BUF2
	LoadW r1, 4
	lda h
	jsr FRead
	; Z: FSize (API 2): the size, then the position (1004), 8 hex digits each
	lda h
	jsr FSize
	jsr Check
	ldx #7
@z:	lda r0,x
	sta BUF2+8,x
	dex
	bpl @z
	jsr Line
	lda #'Z'
	jsr Put
	lda BUF2+8+3
	jsr Hex
	lda BUF2+8+2
	jsr Hex
	lda BUF2+8+1
	jsr Hex
	lda BUF2+8+0
	jsr Hex
	lda BUF2+8+7
	jsr Hex
	lda BUF2+8+6
	jsr Hex
	lda BUF2+8+5
	jsr Hex
	lda BUF2+8+4
	jsr Hex
	jsr NL
	lda h
	jsr FClose
	jsr Line
	lda #'S'
	jsr Put
	ldx #0
@s:	lda BUF2,x
	jsr Hex
	inx
	cpx #4
	bne @s
	jsr NL

	; D: a directory, a file in it, back up
	LoadW r0, NDir
	jsr MkDir
	LoadW r0, NDir
	jsr ChDir
	stx bad
	LoadW r0, NInner
	lda #'w'
	jsr FOpen
	sta h
	LoadW r0, NInner
	LoadW r1, 5
	lda h
	jsr FWrite
	lda h
	jsr FClose
	LoadW r0, NUp
	jsr ChDir
	lda #'D'
	ldx bad
	jsr Result

	; Q: a directory made and removed (RmDir)
	LoadW r0, NDirE
	jsr MkDir
	LoadW r0, NDirE
	jsr RmDir
	lda #'Q'
	jsr Result

	; N: rename and delete
	LoadW r0, NOld
	jsr Make
	LoadW r0, NGone
	jsr Make
	LoadW r0, NOld
	LoadW r1, NNew
	jsr FRename
	stx bad
	LoadW r0, NGone
	jsr FDelete
	txa
	ora bad
	tax
	lda #'N'
	jsr Result
	LoadW r0, NGone         ; deleting it again: not found
	jsr FDelete
	jsr Line
	lda #'X'
	jsr Put
	txa
	jsr Hex
	jsr NL

	; L: the listing
	LoadW r0, 0
	jsr DirOpen
@l:	LoadW r0, Entry
	jsr DirNext
	cpx #0
	bne @le
	jsr Line
	lda #'L'
	jsr Put
	lda Entry
	jsr Put
	lda #' '
	jsr Put
	ldx #3
@ln:	lda Entry,x
	beq @l1
	jsr Put
	inx
	bra @ln
@l1:	jsr NL
	bra @l
@le:	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; a small file named r0
Make:	lda #'w'
	jsr FOpen
	sta h
	LoadW r0, NInner
	LoadW r1, 3
	lda h
	jsr FWrite
	lda h
	jmp FClose

; x = 0 or an error: "E" and the error, the step stops being trusted
Check:	cpx #0
	beq @r
	pha
	lda #'E'
	jsr Put
	txa
	jsr Hex
	lda dosStatus
	jsr Hex
	jsr NL
	pla
@r:	rts

; BUF2 against BUF (4 KB)
Compare:
	LoadW a0, BUF
	LoadW a1, BUF2
	ldx #16
	ldy #0
@1:	lda (a0),y
	cmp (a1),y
	beq @2
	inc bad
@2:	iny
	bne @1
	inc a0+1
	inc a1+1
	dex
	bne @1
	rts

; "<a> ok" or "<a> bad <x>"
Result:	jsr Line
	jsr Put
	cpx #0
	bne @b
	lda #' '
	jsr Put
	lda #'o'
	jsr Put
	lda #'k'
	jsr Put
	jmp NL
@b:	lda #' '
	jsr Put
	txa
	jsr Hex
	jmp NL

ClockStart:
	sta EMU_CLOCK
	rts
; "T<a> " and the clock's 4 bytes
ClockLog:
	pha
	lda EMU_CLOCK
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	jsr Line
	lda #'T'
	jsr Put
	pla
	jsr Put
	lda #' '
	jsr Put
	ldx #3
@1:	lda clk,x
	jsr Hex
	dex
	bpl @1
	jmp NL

Put:	sta EMU_STDOUT
	rts
; a line of the log starts on a line of its own (CHROUT to the DOS's
; command channel is echoed on the console)
Line:	pha
	lda #10
	sta EMU_STDOUT
	pla
	rts
NL:	lda #10
	bra Put
Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @n
	pla
	and #$0F
@n:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra Put

.segment "DATA"

h:	.byte 0
n:	.byte 0
bad:	.byte 0
clk:	.res 4
Entry:	.res 72

.segment "RODATA"

MsgStart:	.byte "DISK START", 0
MsgDone:	.byte "DISK DONE", 0
NData:	.byte "DATA.BIN", 0
NDir:	.byte "DIRA", 0
NDirE:	.byte "DIRE", 0
NInner:	.byte "IN.TXT", 0
NUp:	.byte "..", 0
NOld:	.byte "OLD.BIN", 0
NNew:	.byte "NEW.BIN", 0
NGone:	.byte "GONE.BIN", 0
