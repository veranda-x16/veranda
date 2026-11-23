; gate review (DECISIONS V68): record files at the end of their banks
; (finding 5a, 5b) and written back on a full card (finding 6). The files
; from tests/review_fixture.py rec.
;
;   OR e g       REC3 (20066 bytes in the file: three banks) opened with
;                two banks free and a guard bank after them: NO_BANKS (13)
;                and the guard intact (00), or not (FF)
;   O3 e c       the same with three free: its error, its record read back
;                and compared (00: equal)
;   WR a b c d e g   REC1 (9 banks, 10 bytes used) and a guard bank after
;                it: WriteRecord of 32000, 32000, then 9818 and 9719 bytes
;                (past the end: INSUFF_SPACE, 03), then 9718 (exactly to
;                the end: 00); the guard intact (00)
; -D FULL (on a full card): RECW (a record of 5000 bytes) given one of
; 30000, UpdateRecordFile: "UP e" (an error; the gate checks RECW.cvt as
; it was, no RECW.tmp)

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

BUF = $1000

.segment "CODE"

.ifdef FULL
Start:	LoadW r0, NW
	jsr OpenRecordFile
	lda #0
	jsr PointRecord
	LoadW r7, BUF
	LoadW r2, 30000
	jsr WriteRecord
	jsr UpdateRecordFile
	stx e
	jsr NL
	lda #'U'
	jsr Put
	lda #'P'
	jsr Put
	lda e
	jsr Hex
	jsr NL
	jmp Done
.else
Start:	; the largest run of free banks: L
	LoadB n, 60
@big:	lda n
	jsr BankAlloc
	cpx #0
	beq @got
	dec n
	bne @big
@got:	jsr BankFree
	lda n
	sec
	sbc #3
	jsr BankAlloc           ; all but three
	lda #2
	jsr BankAlloc
	sta r2b
	lda #1
	jsr BankAlloc
	sta g
	jsr Guard
	lda r2b
	jsr BankFree            ; two free, the guard after them
	LoadW r0, N3
	jsr OpenRecordFile
	stx e
	jsr NL
	lda #'O'
	jsr Put
	lda #'R'
	jsr Put
	lda e
	jsr Hex
	jsr Check
	jsr Hex
	jsr NL
	lda e
	bne @3
	jsr CloseRecordFile
@3:	lda g                   ; three free
	jsr BankFree
	LoadW r0, N3
	jsr OpenRecordFile
	stx e
	lda #0
	jsr PointRecord
	LoadW r7, BUF
	LoadW r2, 20000
	jsr ReadRecord
	jsr NL
	lda #'O'
	jsr Put
	lda #'3'
	jsr Put
	lda e
	jsr Hex
	LoadW a0, BUF           ; byte i = i * 7
	stz t
	stz t+1
	stz c
	ldx #0                  ; i * 7, low byte
@cmp:	ldy #0
	txa
	cmp (a0),y
	beq @c1
	inc c
@c1:	txa
	clc
	adc #7
	tax
	IncW a0
	IncW t
	CmpWI t, 20000
	bne @cmp
	lda c
	jsr Hex
	jsr NL
	jsr CloseRecordFile
	jsr BanksAllFree

	; WriteRecord to the end of REC1's 9 banks
	LoadW r0, N1
	jsr OpenRecordFile
	lda #1
	jsr BankAlloc
	sta g
	jsr Guard
	lda #0
	jsr PointRecord
	jsr NL
	lda #'W'
	jsr Put
	lda #'R'
	jsr Put
	ldx #0
@w:	phx
	LoadW r7, BUF
	lda Counts,x
	sta r2L
	lda Counts+1,x
	sta r2H
	jsr WriteRecord
	txa
	jsr Hex
	plx
	inx
	inx
	cpx #10
	bne @w
	jsr Check
	jsr Hex
	jsr NL
.endif
Done:	LoadW r0, TDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

.ifndef FULL
; the program's banks freed (BankFree each run it was given: from bank 2)
BanksAllFree:
	lda #2
	sta t
@1:	lda t
	jsr BankFree
	inc t
	lda t
	cmp #250
	bne @1
	rts

; bank g's first 256 bytes = $5A
Guard:	php
	sei
	lda g
	sta ram_bank
	ldx #0
	lda #$5A
@1:	sta $A000,x
	inx
	bne @1
	lda #1
	sta ram_bank
	plp
	rts
; a = 0 if bank g's first 256 bytes are still $5A, else $FF
Check:	php
	sei
	lda g
	sta ram_bank
	ldx #0
	lda #0
@1:	ldy $A000,x
	cpy #$5A
	beq @2
	lda #$FF
@2:	inx
	bne @1
	ldy #1
	sty ram_bank
	plp
	rts
.endif

Put:	sta EMU_STDOUT
	rts
NL:	lda #10
	bra Put
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

n:	.byte 0
e:	.byte 0
g:	.byte 0
c:	.byte 0
r2b:	.byte 0
t:	.word 0

.segment "RODATA"

Counts:	.word 32000, 32000, 9818, 9719, 9718
N1:	.byte "REC1", 0
N3:	.byte "REC3", 0
NW:	.byte "RECW", 0
TDone:	.byte "REC DONE", 0
