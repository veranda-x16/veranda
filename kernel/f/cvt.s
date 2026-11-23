; Veranda bank F: GEOS files as CVT files (docs/APPFORMAT.md)
;
; A GEOS name "Name" is the FAT32 file "Name.cvt". The classic calls open
; it on their own logical file (11), read the directory entry (30 bytes)
; into dirEntryBuf, the info block into fileHeader, the data where the
; info block says. A seek to 508 (or 762 for record files) finds the data.
;
; Long names (DECISIONS V82): a GEOS name is 16 characters at most, or
; LONG_MAX with longNames set; dataFileName (a long document's short
; form) stands for dataLongName (DocMap); FindFile keeps the name it
; found in fLong, so dirEntryBuf (16 characters) leads back to it
; (CvtEntryName).

.include "kernel.inc"

.export k_FindFile, k_GetFHdrInfo, k_LdFile, k_SaveFile, k_DeleteFile, k_RenameFile
.export k_FindFTypes, k_CalcBlksFree, k_OpenDisk, k_SetDevice, k_GetPtrCurDkNm
.export CvtName, CvtOpen, CvtClose, CvtSeek, CvtRead, CvtWrite, CvtEntryName, CvtHeader
.export CvtSig, cvtBuf, Zeros, CvtDone, CvtRaw, DocMap, KeepTo, recTab, Ren2, KtoBuf
.import DosOpen, DosClose, DosCmd, Scratch, nameLen, k_DirOpen, k_DirNext, Status
.import XferIn, XferOut, kXA, kXN, kXB, kName, kVolume

LFN     = 11
SIG_LEN = 224                   ; the signature, padded: 30 + 224 = 254

.segment "BSS"

cvtBuf:	.res 72                 ; a directory listing entry (FindFTypes)
cands:	.res 17 * 60            ; FindFTypes's names; between its calls (V82):
recTab = cands + 256            ; a record table as the file has it (rec.s,
				; load.s: while it is read or written)
fLong = cands + 512             ; FindFile's name (up to LONG_MAX and a 0)
nc:	.res 1
ci:	.res 1
cls:	.res 2
want:	.res 1
tmp:	.res 2
size:	.res 2
wErr:	.res 1                  ; CvtWrite: a write failed

.segment "CODE"

;---------------------------------------------------------------
; names, opening, reading, writing
;---------------------------------------------------------------
; kName = the GEOS name at a (low) x (high) (to 0, $A0 or 16 characters;
; LONG_MAX with longNames) and ".cvt"; nameLen its length; dataFileName
; stands for dataLongName (DocMap); kPtr the name used
CvtName:
	jsr DocMap
	bra Copy
; the same for a FAT name as it is (no DocMap; up to LONG_MAX): fLong, a
; record file's name
CvtRaw:	sta kPtr
	stx kPtr+1
	ldy #LONG_MAX
Copy:	sty tmp                 ; the most
	ldy #0
@1:	lda (kPtr),y
	beq @2
	cmp #$A0
	beq @2
	sta kName,y
	iny
	cpy tmp
	bne @1
@2:	ldx #0
@3:	lda Ext,x
	sta kName,y
	iny
	inx
	cpx #4
	bne @3
	sty nameLen
	rts
Ext:	.byte ".cvt"

; the name in a directory entry at a/x (its bytes 3-18): fLong when they
; are its first 16 characters (FindFile's long name, V82), else CvtName
CvtEntryName:
	clc
	adc #3
	bcc @1
	inx
@1:	sta kPtr
	stx kPtr+1
	LoadW kPtr2, fLong
	jsr Same
	bne @n
	lda #<fLong
	ldx #>fLong
	bra CvtRaw
@n:	lda kPtr
	ldx kPtr+1
	bra CvtName

; z set: the names at kPtr ($A0 or 0 ends it) and kPtr2 (0 ends it) are
; the same up to their end or 16 characters; y the characters compared
Same:	ldy #0
@c:	lda (kPtr),y
	cmp #$A0
	bne @1
	lda #0
@1:	cmp (kPtr2),y
	bne @r
	tax
	beq @r
	iny
	cpy #16
	bne @c
	lda #0
@r:	rts

; kPtr = the name at a/x, y = the most characters: 16, or LONG_MAX with
; longNames; a name the same as dataFileName while dataLongName is longer
; than 16 (a long document's short form, V82): kPtr = dataLongName, y =
; LONG_MAX
DocMap:	sta kPtr
	stx kPtr+1
	LoadW kPtr2, dataFileName
	jsr Same
	bne @no
	lda dataLongName + 16
	beq @no
	LoadW kPtr, dataLongName
	bra @l
@no:	ldy #16
	lda longNames
	beq @r
@l:	ldy #LONG_MAX
@r:	rts

; kName up to its ".cvt" (after CvtName), 0-terminated, to a/x
KeepTo:	sta kPtr2
	stx kPtr2+1
	lda nameLen
	sec
	sbc #4
	tay
	lda #0
@1:	sta (kPtr2),y
	dey
	bmi @r
	lda kName,y
	bra @1
@r:	rts

; open kName (CvtName) for reading (a = 'r') or writing ('w': created or
; replaced); x = 0 or the error
CvtOpen:
	cmp #'w'
	bne @r
	ldy nameLen             ; "@:" in front
@m:	lda kName - 1,y
	sta kName + 1,y
	dey
	bne @m
	lda #'@'
	sta kName
	lda #':'
	sta kName+1
	inc nameLen
	inc nameLen
	lda #'W'
	bra @s
@r:	lda #'R'
@s:	ldy nameLen
	pha
	lda #','
	sta kName,y
	iny
	lda #'S'
	sta kName,y
	iny
	lda #','
	sta kName,y
	iny
	pla
	sta kName,y
	iny
	sty nameLen
	stz wErr                ; (CvtWrite's failures since: V68)
	lda #LFN
	jsr DosOpen
	cpx #DEV_NOT_FOUND
	beq @e
	cpx #0
	beq @e
	ldx #FILE_NOT_FOUND
@e:	cpx #0
	rts

CvtClose:
	lda #LFN
	jmp DosClose

; to byte a (low) x (high) of the open file; x = 0 or the error
CvtSeek:
	sta kName+2
	stx kName+3
	lda #'P'
	sta kName
	lda #LFN
	sta kName+1
	stz kName+4
	stz kName+5
	LoadB nameLen, 6
	jmp DosCmd

; r0 = r0 bytes read to kXA (kXB its bank if at $A000 or above): read
; count a (low) x (high) to the address in kXA; a = READST
CvtRead:
	sta kXN
	stx kXN+1
	ldx #LFN
	jsr k_chkin
	jsr XferIn
	pha
	jsr k_clrchn
	pla
	rts

; a = READST; wErr not 0 once a write of this file failed (an error
; status, or bytes left: V68)
CvtWrite:
	sta kXN
	stx kXN+1
	ldx #LFN
	jsr k_chkout
	jsr XferOut
	pha
	and #%10000011          ; device gone, a time-out (a write error)
	ora kXN
	ora kXN+1
	tsb wErr
	jsr k_clrchn
	pla
	rts

; the file written closed: x = 0, or DOS_ERROR when a write failed or
; the DOS reports an error after the close (V68)
CvtDone:
	jsr CvtClose
	jsr Status
	ldx #DOS_ERROR
	cmp #20
	bcs @r
	lda wErr
	bne @r
	ldx #0
@r:	rts

; kXA = a/x in this bank (below $A000 or bank F's own memory)
At:	sta kXA
	stx kXA+1
	lda ram_bank
	sta kXB
	rts

; the first 30 bytes of the open file into dirEntryBuf, then (CvtHeader)
; the info block into fileHeader + 2 (fileHeader: 0, $FF); r7 = its load
; address
CvtEntry:
	lda #<dirEntryBuf
	ldx #>dirEntryBuf
	jsr At
	lda #30
	ldx #0
	jmp CvtRead
CvtHeader:
	lda #<254
	ldx #>254
	jsr CvtSeek
	lda #<(fileHeader + 2)
	ldx #>(fileHeader + 2)
	jsr At
	lda #<254
	ldx #>254
	jsr CvtRead
	stz fileHeader
	LoadB fileHeader+1, $FF
	MoveW fileHeader + O_GHST_ADDR, r7
	rts

;---------------------------------------------------------------
; the calls
;---------------------------------------------------------------
; r6 name -> dirEntryBuf; x error
k_FindFile:
	lda r6L
	ldx r6H
	jsr CvtName
	lda #<fLong             ; (the name found: CvtEntryName, V82)
	ldx #>fLong
	jsr KeepTo
	lda #'r'
	jsr CvtOpen
	bne @r
	jsr CvtEntry
	jsr CvtClose
	ldy #0                  ; the name: the file's (as found), $A0 padded
@n:	lda (r6),y
	beq @p
	sta dirEntryBuf + 3,y
	iny
	cpy #16
	bne @n
@p:	cpy #16
	beq @ok
	lda #$A0
	sta dirEntryBuf + 3,y
	iny
	bra @p
@ok:	ldx #0
@r:	rts

; r9 directory entry -> fileHeader, r7 the load address; x error
k_GetFHdrInfo:
	lda r9L
	ldx r9H
	jsr CvtEntryName
	lda #'r'
	jsr CvtOpen
	bne @r
	jsr CvtHeader
	jsr CvtClose
	ldx #0
@r:	rts

; r9 directory entry: a sequential file's data to its load address (r7:
; past its end); x error
k_LdFile:
	jsr k_GetFHdrInfo
	bne @r
	lda fileHeader + O_GHSTR_TYPE
	beq @seq
	ldx #STRUCT_MISMAT
	rts
@seq:	lda r9L
	ldx r9H
	jsr CvtEntryName
	lda #'r'
	jsr CvtOpen
	bne @r
	lda #<508
	ldx #>508
	jsr CvtSeek
	MoveW r7, kXA
	stz kXB
	lda #<$8800             ; up to the end of application memory
	sec
	sbc r7L
	pha
	lda #>$8800
	sbc r7H
	tax
	pla
	jsr CvtRead
	MoveW kXA, r7
	jsr CvtClose
	ldx #0
@r:	rts

; r9 an info block (its bytes 0-1: the file's name): a new file, the data
; from its start to its end address; a record file gets no records; x
; error
k_SaveFile:
	ldy #1                  ; the name: the info block's first word
	lda (r9),y
	tax
	lda (r9)
	jsr CvtName
	lda #'w'
	jsr CvtOpen
	beq @1
	rts
@1:	; the directory entry
	ldx #29
@z:	stz cvtBuf,x
	dex
	bpl @z
	ldy #O_GHCMDR_TYPE
	lda (r9),y
	ora #$80
	sta cvtBuf
	ldx #0                  ; the name, padded with $A0
	ldy #0
	lda (r9)
	sta kPtr
	ldy #1
	lda (r9),y
	sta kPtr+1
	ldy #0
@n:	lda (kPtr),y
	beq @p
	sta cvtBuf + 3,y
	iny
	cpy #16
	bne @n
@p:	cpy #16
	beq @np
	lda #$A0
	sta cvtBuf + 3,y
	iny
	bra @p
@np:	ldy #O_GHSTR_TYPE
	lda (r9),y
	sta cvtBuf + 21
	ldy #O_GHGEOS_TYPE
	lda (r9),y
	sta cvtBuf + 22
	ldx #0
@d:	lda year,x
	sta cvtBuf + 23,x
	inx
	cpx #5
	bne @d
	; the size: end - start (sequential), blocks of 254 (+ the info block)
	ldy #O_GHEND_ADDR
	lda (r9),y
	ldy #O_GHST_ADDR
	sec
	sbc (r9),y
	sta size
	ldy #O_GHEND_ADDR + 1
	lda (r9),y
	ldy #O_GHST_ADDR + 1
	sbc (r9),y
	sta size+1
	lda cvtBuf + 21
	beq @s
	stz size                ; a record file: no data
	stz size+1
@s:	jsr Blocks
	; write: the entry, the signature, the info block, the data
	lda #<cvtBuf
	ldx #>cvtBuf
	jsr At
	lda #30
	ldx #0
	jsr CvtWrite
	jsr CvtSig
	lda r9L
	clc
	adc #2
	tax
	lda r9H
	adc #0
	sta kXA+1
	stx kXA
	lda #<254
	ldx #>254
	jsr CvtWrite
	lda cvtBuf + 21
	beq @data
	lda #<254               ; a record file: an empty record table
	ldx #>254
	jsr Zeros
	bra @end
@data:	ldy #O_GHST_ADDR
	lda (r9),y
	sta kXA
	iny
	lda (r9),y
	sta kXA+1
	lda size
	ldx size+1
	jsr CvtWrite
@end:	jmp CvtDone             ; (a write error: x DOS_ERROR, V68)

; the size word of cvtBuf (28-29): size / 254 rounded up, + 1
Blocks:	MoveW size, tmp
	lda #1
	sta cvtBuf + 28
	stz cvtBuf + 29
@1:	lda tmp+1
	bne @sub
	lda tmp
	beq @r
@sub:	inc cvtBuf + 28
	bne @2
	inc cvtBuf + 29
@2:	lda tmp
	sec
	sbc #254
	sta tmp
	lda tmp+1
	sbc #0
	sta tmp+1
	bcs @1
@r:	rts

; the signature, zero padded to 224 bytes (MCIOUT: CHROUT is echoed on
; the emulator's console)
CvtSig:	lda #<Sig
	ldx #>Sig
	jsr At
	lda #SIG_STR
	ldx #0
	jsr CvtWrite
	lda #SIG_LEN - SIG_STR
; zeros: a of them (at most 254), from cands (FindFTypes's, free while a
; file is written: a block of zeros was 254 bytes of this bank, V68)
Zeros:	pha
	ldx #0
@z:	stz cands,x
	inx
	bne @z
	lda #<cands
	ldx #>cands
	jsr At
	pla
	ldx #0
	jmp CvtWrite
Sig:	.byte "PRG formatted GEOS file V1.0"
SIG_STR = * - Sig

; r0 name; x error
k_DeleteFile:
	lda r0L
	ldx r0H
	jsr CvtName
	ldy nameLen             ; "S:" in front
@m:	lda kName - 1,y
	sta kName + 1,y
	dey
	bne @m
	lda #'S'
	sta kName
	lda #':'
	sta kName+1
	inc nameLen
	inc nameLen
	jmp Scratch

; r6 old name, r0 new name; x error
k_RenameFile:
	; "R:" new ".cvt=" old ".cvt"
	lda r6L
	ldx r6H
	jsr CvtName             ; old -> cvtBuf
	jsr KtoBuf
	lda r0L
	ldx r0H
	jsr CvtName             ; new in kName
; "R:" kName "=" cvtBuf (want bytes): x error (BFR_OVERFLOW: longer than
; kName, long names: V82)
Ren2:	lda nameLen
	sec
	adc want
	cmp #80 - 1             ; (2 + nameLen + 1 + want <= 80)
	bcc @ok
	ldx #BFR_OVERFLOW
	rts
@ok:	ldy nameLen
@m:	lda kName - 1,y
	sta kName + 1,y
	dey
	bne @m
	lda #'R'
	sta kName
	lda #':'
	sta kName+1
	ldy nameLen
	iny
	iny
	lda #'='
	sta kName,y
	iny
	ldx #0
@c:	lda cvtBuf,x
	sta kName,y
	iny
	inx
	cpx want
	bne @c
	sty nameLen
	jmp DosCmd

; kName (nameLen bytes) to cvtBuf, want = nameLen
KtoBuf:	ldx nameLen
	stx want
@o:	lda kName - 1,x
	sta cvtBuf - 1,x
	dex
	bne @o
	rts

; r6 buffer (17 bytes a name), r7L type, r7H the most, r10 class (0: any)
; -> r7H the room left. Two passes: the ".cvt" names of the listing first
; (at most CANDS; CMDR-DOS on the SD card does not read a listing while
; another file is open), then each file's type and class
CANDS = 60
k_FindFTypes:
	MoveW r10, cls
	stz nc
	LoadW r0, 0
	jsr k_DirOpen
	beq @l
	jmp @end
@l:	LoadW r0, cvtBuf
	jsr k_DirNext
	bne @l2                 ; (the listing closes at its end)
	lda cvtBuf
	cmp #'F'
	bne @l
	lda nc
	cmp #CANDS
	bcs @l
	ldy #3                  ; up to ".cvt" (either case), then the end:
@f:	lda cvtBuf,y            ; after at most 16 characters, other dots
	beq @l                  ; before it (V68)
	cmp #'.'
	beq @dot
@fn:	iny
	cpy #3 + 17
	bne @f
	bra @l
@dot:	lda cvtBuf+1,y
	ora #$20
	cmp #'c'
	bne @fn
	lda cvtBuf+2,y
	ora #$20
	cmp #'v'
	bne @fn
	lda cvtBuf+3,y
	ora #$20
	cmp #'t'
	bne @fn
	lda cvtBuf+4,y
	bne @fn
	lda #0
	sta cvtBuf,y
	jsr Slot                ; kPtr = candidate nc
	ldy #0
@c:	lda cvtBuf + 3,y
	sta (kPtr),y
	beq @c1
	iny
	bra @c
@c1:	inc nc
	bra @l
@l2:	; each candidate: its type, its class
	stz ci
@next:	lda r7H
	beq @end
	lda ci
	cmp nc
	beq @end
	jsr CiSlot
	lda kPtr
	ldx kPtr+1
	jsr CvtName
	lda #'r'
	jsr CvtOpen
	bne @skip
	jsr CvtEntry
	lda dirEntryBuf + 22
	cmp r7L
	bne @no
	lda cls
	ora cls+1
	beq @yes
	lda r7H                 ; (CvtHeader sets r7: the load address)
	pha
	lda r7L
	pha
	jsr CvtHeader           ; the class: equal up to cls's 0
	pla
	sta r7L
	pla
	sta r7H
	MoveW cls, kPtr
	ldy #0
@k:	lda (kPtr),y
	beq @yes
	cmp fileHeader + O_GHFNAME,y
	bne @no
	iny
	bra @k
@yes:	jsr CvtClose
	jsr CiSlot
	ldy #0                  ; the name into r6's buffer
@y:	lda (kPtr),y
	sta (r6),y
	beq @y1
	iny
	bra @y
@y1:	AddVW 17, r6
	dec r7H
	bra @skip
@no:	jsr CvtClose
@skip:	inc ci
	bra @next
@end:	ldx #0
	rts

; kPtr = candidate slot ci (CiSlot) or nc (Slot): cands + 17 * n
CiSlot:	lda ci
	bra Sl
Slot:	lda nc
Sl:	sta kPtr
	stz kPtr+1
	ldx #4                  ; n * 16
	lda kPtr
@1:	asl
	rol kPtr+1
	dex
	bne @1
	clc
	adc kPtr                ; + n
	sta kPtr
	bcc @2
	inc kPtr+1
@2:	lda kPtr
	clc
	adc #<cands
	sta kPtr
	lda kPtr+1
	adc #>cands
	sta kPtr+1
	rts

; the free space: unknown on FAT32 through CMDR-DOS: the most
k_CalcBlksFree:
	LoadW r4, $FFFF
	LoadW r3, $FFFF
	ldx #0
	rts

k_OpenDisk:
	ldx #0
	rts

; only device 8
k_SetDevice:
	ldx #0
	cmp #8
	beq @r
	ldx #DEV_NOT_FOUND
@r:	rts

; zero page x = the volume's name
k_GetPtrCurDkNm:
	lda #<kVolume
	sta 0,x
	lda #>kVolume
	sta 1,x
	rts
