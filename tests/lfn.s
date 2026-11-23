; gate disk, part 4 (DECISIONS V82): long file names in the GEOS file calls
;
;   G  GetFile with ST_LD_DATA on a program that is not there: the
;      document's name kept (dataLongName) and its short form
;      (dataFileName), for names of 16, 17, 37 (an extension), 24 (a
;      5-character extension), 26 (none), 23 (a dot at the end) and 63
;      characters; GEOS's 16 without longNames
;   P  a plain file written under a long name (FOpen), read back by
;      FOpen(dataFileName): the short form opens the long file
;   R  a record file of 39 characters: SaveFile, OpenRecordFile, two
;      records written, CloseRecordFile (written back through
;      VRTEMP.tmp), opened again, read; FindFile and GetFHdrInfo
;      (dirEntryBuf leads to the long name)
;   M  a record file of 63 characters (the longest), written back and read
;   Q  a sequential file of 34 characters: SaveFile, FindFile, LdFile
;   S  without longNames, as a GEOS program: the record file opened by
;      dataFileName (its short form), a record changed, closed: the long
;      file written, no file under the short form
;   D  DeleteFile of a long name; RenameFile of two long names (too long
;      for one command: BFR_OVERFLOW), of a long one to a short one
;   C  classic names (longNames 0): a 17-character name is cut to 16
; tests/check_lfn.py checks the lines and the files on the host.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

DBUF = $3000
BUF  = $4000

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	; G: the document names
	LoadB longNames, LONG_NAMES
	LoadW a1, Docs
@g:	lda (a1)
	beq @g1
	MoveW a1, r3
	jsr Doc
	ldy #0                  ; the next one
@g0:	lda (a1),y
	beq @g2
	iny
	bra @g0
@g2:	iny
	tya
	clc
	adc a1L
	sta a1L
	bcc @g
	inc a1H
	bra @g
@g1:	stz longNames           ; GEOS's 16 characters
	LoadW r3, NHoliday
	jsr Doc
	LoadB longNames, LONG_NAMES

	; P: a plain file of a long name, opened by the short form
	LoadW r3, NHoliday
	jsr Doc0
	LoadW r0, NHoliday
	lda #'w'
	jsr FOpen
	sta n
	LoadW r0, Text
	LoadW r1, TEXTLEN
	lda n
	jsr FWrite
	lda n
	jsr FClose
	stz longNames           ; (as a GEOS program)
	LoadW r0, dataFileName
	lda #'r'
	jsr FOpen
	sta n
	cpx #0
	beq @p1
	lda #'p'
	jsr Err
	bra @p2
@p1:	LoadW r0, BUF
	LoadW r1, 100
	lda n
	jsr FRead
	lda n
	jsr FClose
	lda #0
	ldx r1L
	sta BUF,x
	LoadW r0, MsgP
	jsr Str
	LoadW r0, BUF
	jsr StrNL
@p2:	LoadB longNames, LONG_NAMES

	; R: a record file of 39 characters
	LoadW r0, NPic
	jsr Rec
	LoadW r6, NPic          ; FindFile, GetFHdrInfo through dirEntryBuf
	jsr FindFile
	lda #'f'
	jsr Err
	LoadW r9, dirEntryBuf
	jsr GetFHdrInfo
	lda #'h'
	jsr Err
	LoadW r0, MsgR
	jsr Str
	LoadW r0, fileHeader + O_GHFNAME
	jsr StrNL

	; M: the longest (63)
	LoadW r0, NMax
	jsr Rec

	; Q: a sequential file
	ldx #0
@q:	txa
	eor #$3C
	sta DBUF,x
	inx
	bne @q
	LoadW r9, HdrSeq
	stz r10L
	jsr SaveFile
	lda #'s'
	jsr Err
	ldx #0
	txa
@q0:	sta DBUF,x
	inx
	bne @q0
	LoadW r6, NSeq
	jsr FindFile
	lda #'F'
	jsr Err
	LoadW r9, dirEntryBuf
	jsr LdFile
	lda #'l'
	jsr Err
	stz bad
	ldx #0
@q1:	txa
	eor #$3C
	cmp DBUF,x
	beq @q2
	inc bad
@q2:	inx
	bne @q1
	lda bad
	ldx #'Q'
	jsr Show

	; S: a GEOS program opens the record file by its short form
	LoadW r3, NPic
	jsr Doc0
	stz longNames
	LoadW r0, dataFileName
	jsr OpenRecordFile
	lda #'o'
	jsr Err
	lda #1
	jsr PointRecord
	LoadW r7, Changed
	LoadW r2, CHGLEN
	jsr WriteRecord
	lda #'w'
	jsr Err
	jsr CloseRecordFile
	lda #'c'
	jsr Err
	LoadW r0, dataFileName
	jsr OpenRecordFile
	lda #'O'
	jsr Err
	lda #1
	jsr PointRecord
	jsr ReadOut
	LoadW r0, MsgS
	jsr Str
	LoadW r0, BUF
	jsr StrNL
	jsr CloseRecordFile
	LoadB longNames, LONG_NAMES

	; D: delete, rename
	LoadW r9, HdrGone
	stz r10L
	jsr SaveFile
	lda #'g'
	jsr Err
	LoadW r0, NGone
	jsr DeleteFile
	txa
	ldx #'D'
	jsr Show
	LoadW r6, NGone
	jsr FindFile
	txa
	ldx #'d'
	jsr Show                ; (FILE_NOT_FOUND)
	LoadW r6, NSeq          ; two long names: one command too long
	LoadW r0, NMax
	jsr RenameFile
	txa
	ldx #'N'
	jsr Show                ; (BFR_OVERFLOW)
	LoadW r6, NSeq          ; to a short one
	LoadW r0, NShort
	jsr RenameFile
	txa
	ldx #'n'
	jsr Show

	; C: classic names: "Application Seven" is "Application Seve"
	LoadW r9, HdrSeven
	stz r10L
	jsr SaveFile
	lda #'v'
	jsr Err
	stz longNames
	LoadW r6, NSeven
	jsr FindFile
	txa
	ldx #'C'
	jsr Show                ; (FILE_NOT_FOUND)
	LoadB longNames, LONG_NAMES
	LoadW r6, NSeven
	jsr FindFile
	txa
	ldx #'c'
	jsr Show

	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; GetFile (ST_LD_DATA) on a program that is not there with the document
; r3: "G <dataFileName>|<dataLongName>" (Doc0: no line)
Doc:	jsr Doc0
	LoadW r0, MsgG
	jsr Str
	LoadW r0, dataFileName
	jsr Str1
	lda #'|'
	jsr Put
	LoadW r0, dataLongName
	jmp StrNL
Doc0:	LoadW r6, NNone
	LoadB r0L, ST_LD_DATA
	jmp GetFile

; the record file r0: made, two records written, closed, opened again,
; record 1 read: "R <its text>"
Rec:	MoveW r0, a2
	MoveW r0, HdrRec
	LoadW r9, HdrRec
	stz r10L
	jsr SaveFile
	lda #'S'
	jsr Err
	MoveW a2, r0
	jsr OpenRecordFile
	lda #'o'
	jsr Err
	jsr AppendRecord
	LoadW r7, Text
	LoadW r2, 4
	jsr WriteRecord
	jsr AppendRecord
	LoadW r7, Text
	LoadW r2, TEXTLEN
	jsr WriteRecord
	lda #'w'
	jsr Err
	jsr CloseRecordFile
	lda #'c'
	jsr Err
	MoveW a2, r0
	jsr OpenRecordFile
	lda #'O'
	jsr Err
	lda usedRecords
	ldx #'u'
	jsr Show
	lda #1
	jsr PointRecord
	jsr ReadOut
	jsr CloseRecordFile
	LoadW r0, MsgRec
	jsr Str
	LoadW r0, BUF
	jmp StrNL

; the current record into BUF, 0-terminated
ReadOut:
	LoadW r7, BUF
	LoadW r2, 200
	jsr ReadRecord
	lda #'r'
	jsr Err
	lda #0
	sta (r7)
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
	ldx #1
@r:	rts

; x a letter, a a value: "<x><hex a>"
Show:	jsr Line
	pha
	txa
	jsr Put
	pla
	jsr Hex
	jmp NL

; the text at r0 (StrNL: and a new line; Str starts a line)
Str:	jsr Line
Str1:	ldy #0
@1:	lda (r0),y
	beq @r
	jsr Put
	iny
	bne @1
@r:	rts
StrNL:	jsr Str1
	jmp NL

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

n:	.byte 0
bad:	.byte 0
HdrRec:	.word 0                 ; (the name: Rec)
	.byte 3, 21, $BF
	.res 63, $AA
	.byte $83, APPL_DATA, 1
	.word 0, 0, 0
	.byte "LongRec     V1.0", 0, 0, 0, 0
	.res 256 - 97, 0

.segment "RODATA"

MsgStart:	.byte "LFN START", 0
MsgDone:	.byte "LFN DONE", 0
MsgG:	.byte "G ", 0
MsgP:	.byte "P ", 0
MsgR:	.byte "H ", 0
MsgS:	.byte "S ", 0
MsgRec:	.byte "R ", 0
NNone:	.byte "No such program", 0
NHoliday: .byte "Holiday photos from the lake 2026.txt", 0
NPic:	.byte "A picture with a long name for the test", 0
NMax:	.byte "A record file whose name is sixty-three characters long exactly", 0
NSeq:	.byte "A sequential file with a long name", 0
NGone:	.byte "A file with a long name to delete", 0
NShort:	.byte "Short", 0
NSeven:	.byte "Application Seven", 0
Docs:	.byte "Exactly sixteen!", 0
	.byte "Seventeen letters", 0
	.byte "Holiday photos from the lake 2026.txt", 0
	.byte "Budget for the year.X16S", 0
	.byte "A picture with a long name", 0
	.byte "A name ending in a dot.", 0
	.byte "A record file whose name is sixty-three characters long exactly", 0
	.byte 0
Text:	.byte "Long names reach the file.", 0
TEXTLEN = * - Text
Changed: .byte "Changed by its short form.", 0
CHGLEN = * - Changed

.macro HEADER name, struct, start, end
	.word name
	.byte 3, 21, $BF
	.res 63, $AA
	.byte $83, APPL_DATA, struct
	.word start, end, start
	.byte "LongSeq     V1.0", 0, 0, 0, 0
	.res 256 - 97, 0
.endmacro
HdrSeq:	HEADER NSeq, 0, DBUF, DBUF + 256
HdrGone: HEADER NGone, 0, DBUF, DBUF + 10
HdrSeven: HEADER NSeven, 0, DBUF, DBUF + 10
