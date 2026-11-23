; gate review, finding 2 (DECISIONS V68): streams a program leaves open.
; An application (AUTOSTART.cvt) that starts itself again: dataFileName's
; first character counts the runs ('0' .. '9', then 'A'; empty: START).
;
; Runs 0-9: A.TXT, B.TXT, C.TXT opened for reading, never closed ("LEAK n
; e e e", the errors), then GetFile AUTOSTART with the next count (an
; error: "GETFILE x"). Run 10:
;   the desk accessory LEAKDA (-D DA) over A.TXT open: it opens B.TXT and
;   C.TXT and leaves them open ("DA e e"); back, A.TXT still reads, B.TXT
;   and C.TXT open and read ("AF a e e b c": the errors, the first bytes)
;   then A.TXT opened until an error: "OP n e" and a byte read from each
;   (STREAMS: three; R49's DOS does not report a fifth open on a card
;   with an error, its reads fail: V68)
;   "LEAK DONE", the emulator stops.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.ifndef START
START = 0
.endif

.segment "CODE"

.ifdef DA
Start:	jsr NL
	lda #'D'
	jsr Put
	lda #'A'
	jsr Put
	LoadW r0, NB
	jsr Open
	LoadW r0, NC
	jsr Open
	jsr NL
	jmp RstrAppl
.else
Start:	lda dataFileName
	beq @s
	sec
	sbc #'0'
	cmp #10
	bcc @n
	lda #10
	bra @n
@s:	lda #START
@n:	sta run
	cmp #10
	bcs Last
	jsr NL
	lda #'L'
	jsr Put
	lda #'K'
	jsr Put
	lda run
	jsr Hex
	LoadW r0, NA
	jsr Open
	LoadW r0, NB
	jsr Open
	LoadW r0, NC
	jsr Open
	jsr NL
	; the next run
	lda run
	ina
	clc
	adc #'0'
	sta Doc
	LoadW r6, NAuto
	LoadW r3, Doc
	LoadB r0L, ST_LD_DATA
	jsr GetFile
	phx
	LoadW r0, TGet
	jsr LogText
	pla
	jsr Hex
	jsr NL
	jmp Stop

Last:	; the accessory over a stream of ours
	LoadW r0, NA
	lda #'r'
	jsr FOpen
	sta h
	LoadW r6, NDa
	stz r0L
	jsr GetFile
	cpx #0
	beq @back
	phx
	LoadW r0, TGet
	jsr LogText
	pla
	jsr Hex
	jsr NL
@back:	jsr NL
	lda #'A'
	jsr Put
	lda #'F'
	jsr Put
	LoadW r0, buf
	LoadW r1, 1
	lda h
	jsr FRead
	lda buf
	jsr Hex
	LoadW r0, NB
	jsr Open
	sta hb
	LoadW r0, NC
	jsr Open
	sta hc
	lda hb
	jsr Read1
	lda hc
	jsr Read1
	jsr NL
	; all closed: ours (2-9)
	ldx #2
@c:	phx
	txa
	jsr FClose
	plx
	inx
	cpx #10
	bne @c
	; as many as there are
	stz n
@o:	LoadW r0, NA
	lda #'r'
	jsr FOpen
	cpx #0
	bne @full
.ifdef DEBUG
	lda dosStatus
	jsr Hex
.endif
	inc n
	lda n
	cmp #20
	bne @o
@full:	phx
	jsr NL
	lda #'O'
	jsr Put
	lda #'P'
	jsr Put
	lda n
	jsr Hex
	pla
	jsr Hex
	; and each read: the first byte, or its error
	ldx #2
@rd:	phx
	txa
	jsr Read1
	plx
	inx
	txa
	sec
	sbc #2
	cmp n
	bne @rd
	jsr NL
	LoadW r0, TDone
	jsr LogText
Stop:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
.endif

; FOpen r0 for reading: " <error>"; a = the handle
Open:	lda #'r'
	jsr FOpen
	pha
	txa
	jsr Hex
	pla
	rts

; a byte from stream a: " <the byte>", or " <the error>"
Read1:	pha
	stz buf
	LoadW r0, buf
	LoadW r1, 1
	pla
	jsr FRead
	txa
	bne @e
	lda buf
@e:	jmp Hex

Put:	sta EMU_STDOUT
	rts
NL:	lda #10
	bra Put
; " <a in hex>"
Hex:	pha
	lda #' '
	jsr Put
	pla
	pha
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

run:	.byte 0
h:	.byte 0
n:	.byte 0
buf:	.byte 0
hb:	.byte 0
hc:	.byte 0
Doc:	.byte "0", 0

.segment "RODATA"

NA:	.byte "A.TXT", 0
NB:	.byte "B.TXT", 0
NC:	.byte "C.TXT", 0
ND:	.byte "D.TXT", 0
NAuto:	.byte "AUTOSTART", 0
NDa:	.byte "LEAKDA", 0
TGet:	.byte "GETFILE", 0
TDone:	.byte "LEAK DONE", 0
