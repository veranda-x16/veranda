; Veranda bank F: record files (VLIR), held in RAM banks while open
;
; OpenRecordFile reads the whole CVT file into banks: each record is an
; offset into the banks (24 bits from the first bank's $A000) and a length
; (lenH $FF: an empty record). WriteRecord puts the new data at the end of
; what is used (the old copy is left). The file is written back whole
; (UpdateRecordFile, CloseRecordFile if changed): to Name.tmp (VRTEMP.tmp
; for a name longer than 16: V82), then the old Name.cvt deleted and the
; new one renamed: there is always a whole CVT file. One record file is
; open at a time (as GEOS). Its name is kept as it was opened (recName:
; a long one, or dataLongName for dataFileName's short form, V82).

.include "kernel.inc"

.export k_OpenRecordFile, k_CloseRecordFile, k_UpdateRecordFile, k_NextRecord, k_PreviousRecord
.export k_PointRecord, k_DeleteRecord, k_InsertRecord, k_AppendRecord, k_ReadRecord, k_WriteRecord
.export k_RecordInfo, CallerBank
.export RecTable, Where, Pad, RecN, RecLenL, RecLenH, RecT
.export RecVars, RecVarsEnd     ; (the switcher keeps them per task: V83)
.import CvtName, CvtOpen, CvtClose, CvtSeek, CvtRead, CvtWrite, CvtSig, cvtBuf, Zeros, CvtDone
.import CvtRaw, KeepTo, recTab, Ren2, KtoBuf
.import DosCmd, nameLen, kXA, kXN, kXB, kName, k_BankCopy
.global S_k_BankAlloc, S_k_BankFree

MAXREC = 127

.segment "BSS"

RecVars:
isOpen:	.res 1
changed: .res 1
first:	.res 1                  ; the first bank, and how many
banks:	.res 1
heap:	.res 3                  ; the end of what is used (from first's $A000)
entry:	.res 30                 ; the file's directory entry, info block
info:	.res 254
recName: .res LONG_MAX + 1      ; the file's name as opened (V82)
offL:	.res MAXREC
offM:	.res MAXREC
offH:	.res MAXREC
lenL:	.res MAXREC
lenH:	.res MAXREC
n:	.res 1
blk:	.res 1
t:	.res 3
RecVarsEnd:
RecN = n                        ; (for load.s: RecTable's results)
RecLenL = lenL
RecLenH = lenH
RecT = t

.segment "CODE"

; x = 0 if open, else UNOPENED_VLIR (z clear)
IsOpen:	ldx #0
	lda isOpen
	bne @r
	ldx #UNOPENED_VLIR
@r:	cpx #0
	rts

; a record table (recTab) -> n records, their sizes in lenL/lenH (empty:
; lenH $FF); t = the bytes they take in the file (whole blocks)
RecTable:
	stz n
	stz t
	stz t+1
	stz t+2
	ldx #0
@1:	lda recTab,x
	ora recTab+1,x
	beq @r                  ; 0/0: the end
	ldy n
	lda recTab,x
	bne @full
	lda #$FF                ; 0/$FF: empty
	sta lenH,y
	bra @next
@full:	; size = (blocks - 1) * 254 + last - 1
	sta blk
	lda recTab+1,x
	sec
	sbc #1
	sta lenL,y
	lda #0
	sta lenH,y
@b:	dec blk
	beq @t
	lda lenL,y
	clc
	adc #254
	sta lenL,y
	lda lenH,y
	adc #0
	sta lenH,y
	; t += 254
	lda t
	clc
	adc #254
	sta t
	bcc @b
	inc t+1
	bne @b
	inc t+2
	bra @b
@t:	lda t                   ; and the last block
	clc
	adc #254
	sta t
	bcc @next
	inc t+1
	bne @next
	inc t+2
@next:	inc n
	inx
	inx
	cpx #254
	bne @1
@r:	rts

; record y's place: kXB, kXA (the banks), from offL/offM/offH
Where:	lda offM,y
	and #$1F
	ora #$A0
	sta kXA+1
	lda offL,y
	sta kXA
	lda offM,y              ; bank = first + offset >> 13
	lsr
	lsr
	lsr
	lsr
	lsr
	sta kXB
	lda offH,y
	asl
	asl
	asl
	ora kXB
	clc
	adc first
	sta kXB
	rts

; r0 name; x error
k_OpenRecordFile:
	lda isOpen
	beq @0
	PushW r0
	jsr k_CloseRecordFile
	PopW r0
@0:	lda r0L
	ldx r0H
	jsr CvtName
	lda #<recName
	ldx #>recName
	jsr KeepTo
	lda #'r'
	jsr CvtOpen
	beq @1
	rts
@1:	LoadW kXA, entry
	lda ram_bank
	sta kXB
	lda #30
	ldx #0
	jsr CvtRead
	lda entry + 21
	cmp #1
	beq @2
	jsr CvtClose
	ldx #STRUCT_MISMAT
	rts
@2:	lda #<254
	ldx #>254
	jsr CvtSeek
	LoadW kXA, info
	jsr Rd254               ; the info block
	LoadW kXA, recTab
	jsr Rd254               ; and the record table
	jsr RecTable
	; banks: the records and 64 KB to write into
	lda t+1
	lsr t+2
	ror
	lsr t+2
	ror
	lsr t+2
	ror
	lsr t+2
	ror
	lsr t+2
	ror                     ; / 8192
	sta blk                 ; the fewest: the file's bytes, rounded up (V68)
	clc
	adc #9
	sta banks
	lda t+1
	and #$1F
	ora t
	beq @a0
	inc blk
@a0:	lda blk
	bne @alloc
	inc blk                 ; (and at least one)
@alloc:	lda banks
	FARCALL k_BankAlloc
	cpx #0
	beq @got
	dec banks               ; fewer
	lda banks
	cmp blk
	bcs @alloc
	jsr CvtClose
	ldx #NO_BANKS
	rts
@got:	sta first
	stz heap
	stz heap+1
	stz heap+2
	; the records, one after the other (each padded to whole blocks: the
	; next one overwrites the padding)
	ldy #0
@r:	cpy n
	beq @done
	lda lenH,y
	cmp #$FF
	beq @rn
	lda heap
	sta offL,y
	lda heap+1
	sta offM,y
	lda heap+2
	sta offH,y
	phy
	jsr Where
	tya
	asl
	tax
	ply
	phy
	lda recTab,x            ; blocks * 254
	jsr Times254
	jsr CvtRead
	ply
	lda heap
	clc
	adc lenL,y
	sta heap
	lda heap+1
	adc lenH,y
	sta heap+1
	bcc @rn
	inc heap+2
@rn:	iny
	bra @r
@done:	jsr CvtClose
	lda #1
	sta isOpen
	stz changed
	stz curRecord
	lda n
	sta usedRecords
	stz fileWritten
	MoveW entry + 28, fileSize
	ldx #0
	rts

; a blocks -> a/x = a * 254
Times254:
	sta blk
	lda #0
	tax
	ldy blk
	beq @r
@1:	clc
	adc #254
	bcc @2
	inx
@2:	dey
	bne @1
@r:	rts

k_CloseRecordFile:
	jsr IsOpen
	bne @r
	lda changed
	beq @f
	jsr k_UpdateRecordFile
	phx
	bra @free
@f:	phx
@free:	lda first
	FARCALL k_BankFree
	stz isOpen
	plx
@r:	rts

k_NextRecord:
	jsr IsOpen
	bne @r
	lda curRecord
	ina
	cmp n
	bcs Out
	sta curRecord
@r:	rts
Out:	ldx #OUT_OF_RECORDS
	rts

k_PreviousRecord:
	jsr IsOpen
	bne @r
	lda curRecord
	beq Out
	dec curRecord
@r:	rts

; a record -> x error; y = $FF if it holds data, 0 if empty (GEOS: y is
; the record's track, 0 if empty)
k_PointRecord:
	pha
	jsr IsOpen
	pla
	cpx #0
	bne @r
	cmp n
	bcs @inv
	sta curRecord
	tay
	lda lenH,y
	ina                     ; $FF: empty
	beq @e
	ldy #$FF
	rts
@e:	tay
@r:	rts
@inv:	ldx #INV_RECORD
	rts

; the caller's RAM bank (under FarGo's return address: only for entries
; reached through the bank gate) into r3H/r3L for BankCopy: a pointer at
; $A000-$BFFF is in the bank the caller had mapped
CallerBank:
	tsx
	lda $0105,x             ; (this jsr's return, FarRet - 1, the bank)
	rts

; r7 destination, r2 the most -> r7 past the data; x error
k_ReadRecord:
	jsr IsOpen
	bne @r
	lda n
	beq Out
	ldy curRecord
	lda lenH,y
	cmp #$FF
	beq @ok                 ; empty: nothing
	lda r2L                 ; room?
	cmp lenL,y
	lda r2H
	sbc lenH,y
	bcc @ovf
	jsr Where
	MoveW kXA, r0
	MoveW r7, r1
	lda lenL,y
	sta r2L
	lda lenH,y
	sta r2H
	lda kXB
	sta r3L
	jsr CallerBank
	sta r3H
	jsr k_BankCopy
	lda r7L
	clc
	adc r2L
	sta r7L
	lda r7H
	adc r2H
	sta r7H
@ok:	ldx #0
@r:	rts
@ovf:	ldx #BFR_OVERFLOW
	rts

; r7 source, r2 count (0: the record emptied); x error
k_WriteRecord:
	jsr IsOpen
	bne @r
	lda n
	bne @n
	jmp Out
@n:	ldy curRecord
	lda #1
	sta changed
	sta fileWritten
	lda r2L
	ora r2H
	bne @1
	lda #$FF
	sta lenH,y
	ldx #0
@r:	rts
@1:	; room in the banks: heap + count <= banks * 8192 (to the byte)
	lda heap+1
	clc
	adc r2H
	sta t
	lda heap+2
	adc #0
	sta t+1
	lda heap
	clc
	adc r2L
	sta blk                 ; (the low byte: V68)
	lda t
	adc #0
	sta t
	lda t+1
	adc #0
	sta t+1                 ; (heap + count) >> 8 in t
	lda banks               ; banks * 32 pages
	sta t+2
	lda #0
	ldx #5
@m:	asl t+2
	rol
	dex
	bne @m
	cmp t+1
	bcc @full
	bne @fit
	lda t+2
	cmp t
	bcc @full
	bne @fit
	lda blk                 ; the same page: full past its first byte
	bne @full
@fit:	lda heap
	sta offL,y
	lda heap+1
	sta offM,y
	lda heap+2
	sta offH,y
	lda r2L
	sta lenL,y
	lda r2H
	sta lenH,y
	jsr Where
	MoveW r7, r0
	MoveW kXA, r1
	jsr CallerBank
	sta r3L
	lda kXB
	sta r3H
	jsr k_BankCopy
	lda heap
	clc
	adc r2L
	sta heap
	lda heap+1
	adc r2H
	sta heap+1
	bcc @ok
	inc heap+2
@ok:	ldx #0
	rts
@full:	ldx #INSUFF_SPACE
	rts

; the current record out (the rest moves down)
k_DeleteRecord:
	jsr IsOpen
	bne @r
	lda n
	beq Out2
	ldy curRecord
@1:	iny
	cpy n
	beq @2
	jsr Down
	bra @1
@2:	dec n
	lda curRecord
	cmp n
	bcc @3
	beq @3
	dec curRecord
@3:	lda curRecord           ; (the last one went: the one before it)
	cmp n
	bcc @4
	lda n
	beq @4
	dec curRecord
@4:	jsr Changed
@r:	rts
Out2:	ldx #OUT_OF_RECORDS
	rts

; entry y to y - 1
Down:	lda offL,y
	sta offL-1,y
	lda offM,y
	sta offM-1,y
	lda offH,y
	sta offH-1,y
	lda lenL,y
	sta lenL-1,y
	lda lenH,y
	sta lenH-1,y
	rts

Changed:
	lda #1
	sta changed
	sta fileWritten
	lda n
	sta usedRecords
	ldx #0
	rts

; an empty record before the current one (which it becomes)
k_InsertRecord:
	jsr IsOpen
	beq @i
	rts
@i:	ldy curRecord
Insert:	lda n
	cmp #MAXREC
	bcs Out2
	sty t
	ldy n                   ; entries y .. n - 1 up one
@1:	cpy t
	beq @2
	dey
	lda offL,y
	sta offL+1,y
	lda offM,y
	sta offM+1,y
	lda offH,y
	sta offH+1,y
	lda lenL,y
	sta lenL+1,y
	lda lenH,y
	sta lenH+1,y
	bra @1
@2:	lda #$FF
	sta lenH,y
	inc n
	sty curRecord
	jmp Changed

; an empty record after the current one (which it becomes)
k_AppendRecord:
	jsr IsOpen
	bne @r
	ldy curRecord
	lda n
	beq Insert              ; (no records: the first)
	iny
	bra Insert
@r:	rts

; a = 0: the info block to r0 (256 bytes, GEOS's layout: 0, $FF, then
; the 254 the file holds), else from r0 (it is written back with the file)
k_RecordInfo:
	pha
	jsr IsOpen
	pla
	cpx #0
	bne @r
	ldy #0
	cmp #0
	bne @put
	lda #0
	sta (r0),y
	dec a
	iny
	sta (r0),y
@g:	iny
	lda info-2,y
	sta (r0),y
	cpy #255
	bne @g
	rts
@put:	iny
@p:	iny
	lda (r0),y
	sta info-2,y
	cpy #255
	bne @p
	jmp Changed
@r:	rts

; write the file back: Name.tmp, then delete Name.cvt, rename
k_UpdateRecordFile:
	jsr IsOpen
	beq @1
	rts
@1:	jsr TmpName
	lda #'w'
	jsr CvtOpen
	beq @2
	rts
@2:	; the record table, the size
	ldx #0
	ldy #0
@t:	cpy n
	beq @te
	lda lenH,y
	cmp #$FF
	bne @tf
	lda #0
	sta recTab,x
	lda #$FF
	sta recTab+1,x
	bra @tn
@tf:	phx
	jsr Blocks              ; a/blk: blocks, last + 1 (it uses x)
	plx
	sta recTab,x
	lda blk
	sta recTab+1,x
@tn:	inx
	inx
	iny
	bra @t
@te:	cpx #254                ; (127 records: no room for the end)
	bcs @tz
	stz recTab,x            ; 0/0 ends it
	stz recTab+1,x
	inx
	inx
	bra @te
@tz:	jsr RecTable           ; t: the data's bytes in blocks
	; the entry's size: the blocks of the data, the info block, the table
	LoadW entry + 28, 2
@sz:	lda t
	ora t+1
	ora t+2
	beq @sz1
	IncW entry + 28
	lda t
	sec
	sbc #254
	sta t
	lda t+1
	sbc #0
	sta t+1
	lda t+2
	sbc #0
	sta t+2
	bra @sz
@sz1:	; entry, signature, info, table, records (each padded)
	LoadW kXA, entry
	lda ram_bank
	sta kXB
	lda #30
	ldx #0
	jsr CvtWrite
	jsr CvtSig
	LoadW kXA, info
	jsr Wr254
	LoadW kXA, recTab
	jsr Wr254
	ldy #0
@w:	cpy n
	beq @we
	lda lenH,y
	cmp #$FF
	beq @wn
	phy
	jsr Where
	lda lenL,y
	ldx lenH,y
	jsr CvtWrite
	ply
	phy
	jsr Pad
	ply
@wn:	iny
	bra @w
@we:	jsr CvtDone
	bne @bad
	; the old one gone, the new one in its place
	jsr DelName
	jsr DosCmd
	jsr TmpName             ; "R:Name.cvt=" the temporary file
	jsr KtoBuf
	jsr RecCvt
	jsr Ren2
	stz changed
	stz fileWritten
	rts
@bad:	phx                     ; a write failed (a full card): Name.tmp
	jsr TmpName             ; goes, Name.cvt stays as it was (V68)
	jsr Shift2
	lda #'S'
	sta kName
	jsr DosCmd
	plx
	rts

; record y's size -> a = blocks, blk = bytes in the last block + 1
Blocks:	lda lenL,y
	sta t
	lda lenH,y
	sta t+1
	lda #1
	sta blk + 0             ; (blocks count in t+2)
	stz t+2
@1:	inc t+2
	lda t
	sec
	sbc #254
	tax
	lda t+1
	sbc #0
	bcc @last               ; < 254 left: this is the last block
	stx t
	sta t+1
	ora t
	bne @1
	lda #254                ; exactly full
	sta t
@last:	lda t
	ina
	sta blk
	lda t+2
	rts

; zeros to the end of record y's last block
Pad:	jsr Blocks
	lda #255
	sec
	sbc blk                 ; 254 - (last bytes)
	beq @r
	ldx #0
	jmp Zeros
@r:	rts

; kName = Name.tmp; VRTEMP.tmp for a long name ("R:", 63 characters,
; ".cvt=" and it fit kName: V82)
TmpName:
	jsr RecCvt
	ldy nameLen
	cpy #16 + 5
	bcs @l
	lda #'t'
	sta kName-3,y
	lda #'m'
	sta kName-2,y
	lda #'p'
	sta kName-1,y
	rts
@l:	ldx #TMPLEN
	stx nameLen
@c:	lda TmpLong-1,x
	sta kName-1,x
	dex
	bne @c
	rts
TmpLong: .byte "VRTEMP.tmp"
TMPLEN = * - TmpLong

; kName = Name.cvt (the record file's name)
RecCvt:	lda #<recName
	ldx #>recName
	jmp CvtRaw

; "S:Name.cvt"
DelName:
	jsr RecCvt
	jsr Shift2
	lda #'S'
	sta kName
	rts

; 254 bytes to or from kXA in this bank
Rd254:	jsr Here
	jmp CvtRead
Wr254:	jsr Here
	jmp CvtWrite
Here:	lda ram_bank
	sta kXB
	lda #<254
	ldx #>254
	rts

; two bytes room at the front of kName; kName+1 = ':'
Shift2:	ldy nameLen
@1:	lda kName-1,y
	sta kName+1,y
	dey
	bne @1
	lda #':'
	sta kName+1
	inc nameLen
	inc nameLen
	rts
