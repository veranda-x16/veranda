; gate disk (phase 5), part 2: GEOS files (CVT) and record files
;
;   F  SaveFile "Notes" (600 bytes at $3000), FindFile, GetFHdrInfo, LdFile
;   V  SaveFile "Book" (a record file), three records appended and
;      written, closed (written back); opened again: record 1 read and
;      compared, deleted, a new record 1 inserted (300 x "X"), closed
;   T  FindFTypes(APPL_DATA)
;   N  RenameFile Notes -> Memo
;   B  FWrite from and FRead into $A000 of the application's own RAM bank
; tests/check_disk.py checks Memo.cvt and Book.cvt on the host.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

DBUF = $3000
BUF  = $4000

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	; F
	ldx #0
@p:	txa
	eor #$5A
	sta DBUF,x
	sta DBUF+256,x
	sta DBUF+512,x
	inx
	bne @p
	LoadW r9, HdrNotes
	lda #0
	sta r10L
	jsr SaveFile
	lda #'s'
	jsr Err
	LoadW r6, NNotes
	jsr FindFile
	lda #'f'
	jsr Err
	lda dirEntryBuf + 22
	ldx #'t'
	jsr Show
	LoadW r9, dirEntryBuf
	jsr GetFHdrInfo
	lda #'h'
	jsr Err
	lda fileHeader + O_GHFNAME
	ldx #'c'
	jsr Show
	ldx #0                  ; clear, load, compare
	txa
@c:	sta DBUF,x
	sta DBUF+256,x
	sta DBUF+512,x
	inx
	bne @c
	LoadW r9, dirEntryBuf
	jsr LdFile
	lda #'l'
	jsr Err
	stz bad
	ldx #0
@k:	txa
	eor #$5A
	cmp DBUF,x
	beq @k1
	inc bad
@k1:	inx
	bne @k
	lda r7H                 ; r7: past the end ($3000 + 600 = $3258)
	cmp #>(DBUF + 600)
	beq @k2
	inc bad
@k2:	lda bad
	ldx #'F'
	jsr Show

	; V
	LoadW r9, HdrBook
	jsr SaveFile
	lda #'S'
	jsr Err
	LoadW r0, NBook
	jsr OpenRecordFile
	lda #'o'
	jsr Err
	stz n
@w:	jsr AppendRecord
	lda #'a'
	jsr Err
	lda n                   ; record n: (n + 1) * 100 bytes of n + 1
	ina
	jsr Fill
	LoadW r7, BUF
	jsr WriteRecord
	lda #'w'
	jsr Err
	inc n
	lda n
	cmp #3
	bne @w
	jsr CloseRecordFile
	lda #'C'
	jsr Err
	LoadW r0, NBook
	jsr OpenRecordFile
	lda #'O'
	jsr Err
	lda usedRecords
	ldx #'u'
	jsr Show
	lda #1
	jsr PointRecord
	LoadW r7, BUF
	LoadW r2, 1000
	jsr ReadRecord
	lda #'r'
	jsr Err
	lda r7L                 ; 200 bytes of 2
	sec
	sbc #<BUF
	ldx #'n'
	jsr Show
	lda BUF + 199
	ldx #'v'
	jsr Show
	jsr DeleteRecord
	lda #'d'
	jsr Err
	jsr InsertRecord
	lda #'i'
	jsr Err
	ldx #0
	lda #'X'
@x:	sta BUF,x
	sta BUF+256,x
	inx
	bne @x
	LoadW r7, BUF
	LoadW r2, 300
	jsr WriteRecord
	lda #'W'
	jsr Err
	jsr CloseRecordFile
	lda #'Z'
	jsr Err

	; T
	LoadW r6, Names
	LoadB r7L, APPL_DATA
	LoadB r7H, 8
	LoadW r10, 0
	jsr FindFTypes
	lda #8
	sec
	sbc r7H
	pha
	ldx #'T'
	jsr Show
	pla
	sta n                   ; the names found
	LoadW a0, Names
@t:	lda n
	beq @te
	jsr Line
	lda #'='
	jsr Put
	ldy #0
@tn:	lda (a0),y
	beq @tx
	jsr Put
	iny
	bra @tn
@tx:	jsr NL
	AddVW 17, a0
	dec n
	bra @t
@te:
	; N
	LoadW r6, NNotes
	LoadW r0, NMemo
	jsr RenameFile
	lda #'N'
	jsr Err
	lda dosStatus
	ldx #'D'
	jsr Show

	; B: FWrite from and FRead into $A000+ of the application's own bank
	; (the buffer is in the caller's bank, not the kernel's: V47)
	lda #1
	jsr BankAlloc
	cpx #0
	beq @b0
	lda #'b'
	jsr Err
	jmp @be
@b0:	sta ram_bank
	ldx #0
@b1:	txa
	eor #$A5
	sta $A000,x
	stz $A100,x
	inx
	bne @b1
	LoadW r0, NBank
	lda #'w'
	jsr FOpen
	sta n
	LoadW r0, $A000
	LoadW r1, 256
	lda n
	jsr FWrite
	lda n
	jsr FClose
	LoadW r0, NBank
	lda #'r'
	jsr FOpen
	sta n
	LoadW r0, $A100
	LoadW r1, 256
	lda n
	jsr FRead
	lda n
	jsr FClose
	stz bad
	ldx #0
@b2:	txa
	eor #$A5
	cmp $A100,x
	beq @b3
	inc bad
@b3:	inx
	bne @b2
	lda bad
	ldx #'B'
	jsr Show
@be:
	; the listing as DirNext gives it
	LoadW r0, 0
	jsr DirOpen
@l:	LoadW r0, Names
	jsr DirNext
	cpx #0
	bne @le
	jsr Line
	lda #'L'
	jsr Put
	ldx #3
@ln:	lda Names,x
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

; BUF = a * 100 bytes of a; r2 = the count
Fill:	sta t
	stz r2L
	stz r2H
	ldx t
@1:	AddVW 100, r2
	dex
	bne @1
	LoadW a0, BUF
	ldy #0
@2:	lda r2L
	ora r2H
	beq @r
	lda t
	sta (a0),y
	IncW a0
	lda r2L
	bne @3
	dec r2H
@3:	dec r2L
	bra @2
@r:	stz r2L                 ; again
	stz r2H
	ldx t
@4:	AddVW 100, r2
	dex
	bne @4
	rts

; x <> 0: "E", a, the error
Err:	cpx #0
	beq @ok
	jsr Line
@ok:	cpx #0
	beq @r
	pha
	lda #'E'
	jsr Put
	pla
	jsr Put
	txa
	jsr Hex
	jsr NL
@r:	rts

; x a letter, a a value: "<x><hex a>"
Show:	jsr Line
	pha
	txa
	jsr Put
	pla
	jsr Hex
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

n:	.byte 0
t:	.byte 0
bad:	.byte 0
Names:	.res 17 * 8

.segment "RODATA"

MsgStart:	.byte "DISK2 START", 0
MsgDone:	.byte "DISK2 DONE", 0
NNotes:	.byte "Notes", 0
NMemo:	.byte "Memo", 0
NBook:	.byte "Book", 0
NBank:	.byte "BANK.BIN", 0

; an info block: the name, the icon, types, addresses, class
.macro HEADER name, struct, start, end
	.word name
	.byte 3, 21, $BF
	.res 63, $AA
	.byte $83, APPL_DATA, struct
	.word start, end, start
	.byte "Notes       V1.0", 0, 0, 0, 0
	.res 256 - 97, 0
.endmacro
HdrNotes: HEADER NNotes, 0, DBUF, DBUF + 600
HdrBook:  HEADER NBook, 1, 0, 0
