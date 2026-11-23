; gate disk, part 3: writing into the middle of a file (DECISIONS V55)
;
; Each CASE makes its own file Mxx.BIN (xx: the case's number in hex):
; a base of <base> bytes (byte i = (i and 255) xor (i >> 8) xor $5A), then
; <len> bytes of the write pattern (byte j = j * 5 + $33) at offset <off>,
; then the file is closed. tests/check_rmw.py reads the CASE lines of this
; file and checks every Mxx.BIN on the host. The kinds:
;
;   K_M     'w' the base, close; 'm', FSeek, one FWrite (MCIOUT), close
;   K_CH    the same, the bytes sent by CHROUT one at a time
;   K_M1    the same, an FWrite of 1 byte for each byte (MCIOUT of 1)
;   K_OPENW 'w' the base, left open; a second stream 'm' on the same
;           file: FSeek, FWrite, close it; then close the 'w' stream (not
;           in the table: two streams on one file come out wrong on the
;           host folder and the card alike, V55)
;   K_MNEW  'm' on a new file: the base written through it, FSeek back,
;           FWrite, close
;   K_WSEEK 'w' the base, FSeek in the same 'w' stream, FWrite, close
;   K_M2    'w' the base, close; 'm', FSeek, FWrite, FSeek, FWrite (the
;           same bytes again: two seeks in one stream), close
;
; Logs "Cxx", for K_M, K_CH, K_M1 and K_M2 "T" and the cycles from the
; 'm' open to the close (8 hex digits), and on an error "E", the step and
; the error.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

BBUF = $3000                    ; the base (up to 4 KB)
cp   = a9                       ; the case table pointer
WBUF = $4000                    ; the write pattern (up to 4 KB)

K_M     = 0
K_CH    = 1
K_M1    = 2
K_OPENW = 3
K_MNEW  = 4
K_WSEEK = 5
K_M2    = 6

.macro CASE kind, base, off, len
	.byte kind
	.word base, off, len
.endmacro

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	LoadW a0, BBUF          ; the base pattern
	ldx #0
@b:	ldy #0
@b1:	tya
	eor a0+1
	eor #>BBUF              ; i >> 8 (BBUF is page aligned)
	eor #$5A
	sta (a0),y
	iny
	bne @b1
	inc a0+1
	inx
	cpx #16
	bne @b
	LoadW a0, WBUF          ; the write pattern ((j * 5 + $33) mod 256
	ldx #16                 ; repeats every 256 bytes)
@w:	ldy #0
	lda #$33
@w1:	sta (a0),y
	clc
	adc #5
	iny
	bne @w1
	inc a0+1
	dex
	bne @w

	stz idx
	LoadW cp, Cases
CaseLoop:	lda (cp)
	cmp #$FF
	bne @go
	jmp Done
@go:	sta kind
	ldy #1
@c:	lda (cp),y
	sta base-1,y
	iny
	cpy #7
	bne @c
	AddVW 7, cp
	lda idx                 ; the name: "Mxx.BIN"
	lsr
	lsr
	lsr
	lsr
	jsr Digit
	sta Name+1
	lda idx
	and #$0F
	jsr Digit
	sta Name+2
	jsr Line
	lda #'C'
	jsr Put
	lda idx
	jsr Hex
	jsr NL
	lda kind
	asl
	tax
	jmp (Kinds,x)
Next:	inc idx
	jmp CaseLoop

Done:	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Kinds:	.word DoM, DoM, DoM, DoOpenW, DoMNew, DoWSeek, DoM

; 'w' the base, close
WBase:	jsr OpenW
	jsr WriteBase
	lda h
	jsr FClose
	rts

OpenW:	LoadW r0, Name
	lda #'w'
	jsr FOpen
	sta h
	lda #'o'
	jmp Err

OpenM:	LoadW r0, Name
	lda #'m'
	jsr FOpen
	sta h
	lda #'m'
	jmp Err

WriteBase:
	MoveW base, r1
	LoadW r0, BBUF
	lda h
	jsr FWrite
	lda #'b'
	jmp Err

Seek:	MoveW off, r0
	LoadW r1, 0
	lda h
	jsr FSeek
	lda #'s'
	jmp Err

; the pattern, as the kind says
WritePat:
	lda kind
	cmp #K_CH
	beq @ch
	cmp #K_M1
	beq @one
	MoveW len, r1
	LoadW r0, WBUF
	lda h
	jsr FWrite
	lda #'w'
	jmp Err
@one:	LoadW a0, WBUF
	MoveW len, a1
@o1:	MoveW a0, r0
	LoadW r1, 1
	lda h
	jsr FWrite
	lda #'1'
	jsr Err
	IncW a0
	lda a1L
	bne @o2
	dec a1H
@o2:	dec a1L
	lda a1L
	ora a1H
	bne @o1
	rts
@ch:	ldx h                   ; the ROM's CHKOUT/CHROUT/CLRCHN
	jsr k_chkout
	LoadW a0, WBUF
	MoveW len, a1
@c1:	lda (a0)
	jsr k_chrout
	IncW a0
	lda a1L
	bne @c2
	dec a1H
@c2:	dec a1L
	lda a1L
	ora a1H
	bne @c1
	jmp k_clrchn

DoM:	jsr WBase
	sta EMU_CLOCK           ; timed: open, write, close ("T" and 4 bytes)
	jsr OpenM
	jsr Seek
	jsr WritePat
	lda kind
	cmp #K_M2
	bne @c
	jsr Seek
	jsr WritePat
@c:	lda h
	jsr FClose
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
	ldx #3
@t:	lda clk,x
	jsr Hex
	dex
	bpl @t
	jsr NL
	jmp Next

DoOpenW:
	jsr OpenW
	jsr WriteBase
	lda h
	sta h2
	jsr OpenM
	jsr Seek
	jsr WritePat
	lda h
	jsr FClose
	lda h2
	jsr FClose
	jmp Next

DoMNew:	jsr OpenM
	jsr WriteBase
	jsr Seek
	jsr WritePat
	lda h
	jsr FClose
	jmp Next

DoWSeek:
	jsr OpenW
	jsr WriteBase
	jsr Seek
	jsr WritePat
	lda h
	jsr FClose
	jmp Next

Digit:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	rts

; x <> 0: "E", a, the error
Err:	cpx #0
	beq @r
	pha
	jsr Line
	lda #'E'
	jsr Put
	pla
	jsr Put
	txa
	jsr Hex
	jsr NL
@r:	rts

Put:	sta EMU_STDOUT
	rts
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

idx:	.byte 0
kind:	.byte 0
base:	.word 0
off:	.word 0
len:	.word 0
h:	.byte 0
h2:	.byte 0
clk:	.res 4
Name:	.byte "Mxx.BIN", 0

.segment "RODATA"

MsgStart:	.byte "RMW START", 0
MsgDone:	.byte "RMW DONE", 0

; kind, base, offset, length (tests/check_rmw.py reads these lines)
Cases:
	CASE K_M, 1536, 254, 1
	CASE K_M, 1536, 254, 2
	CASE K_M, 1536, 254, 4
	CASE K_M, 1536, 254, 5
	CASE K_M, 1536, 254, 256
	CASE K_M, 1536, 256, 1
	CASE K_M, 1536, 256, 4
	CASE K_M, 1536, 256, 256
	CASE K_M, 1536, 508, 1
	CASE K_M, 1536, 508, 2
	CASE K_M, 1536, 508, 4
	CASE K_M, 1536, 508, 5
	CASE K_M, 1536, 508, 254
	CASE K_M, 1536, 508, 256
	CASE K_M, 1536, 510, 4
	CASE K_M, 1536, 511, 1
	CASE K_M, 1536, 511, 2
	CASE K_M, 1536, 512, 1
	CASE K_M, 1536, 512, 4
	CASE K_M, 1536, 512, 256
	CASE K_M, 1536, 1020, 5
	CASE K_M, 1536, 1024, 1
	CASE K_M, 1536, 1024, 256
	CASE K_M, 1536, 1400, 256
	CASE K_M, 512, 508, 254
	CASE K_M, 1024, 508, 254
	CASE K_M, 4000, 508, 254
	CASE K_M, 4000, 2044, 254
	CASE K_M, 0, 0, 300
	CASE K_M, 4096, 0, 4096
	CASE K_CH, 1536, 508, 4
	CASE K_CH, 1536, 508, 5
	CASE K_CH, 1536, 508, 254
	CASE K_CH, 1536, 1020, 5
	CASE K_M1, 1536, 508, 5
	CASE K_M1, 1536, 508, 254
	CASE K_MNEW, 1536, 508, 254
	CASE K_MNEW, 1536, 510, 4
	CASE K_MNEW, 1536, 254, 4
	CASE K_WSEEK, 1536, 508, 254
	CASE K_WSEEK, 1536, 510, 4
	CASE K_M2, 1536, 508, 254
	CASE K_M2, 1536, 1020, 5
	.byte $FF
