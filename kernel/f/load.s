; Veranda bank F: loading and starting applications (docs/APPFORMAT.md)
;
; LdApplic checks the info block (APPLICATION, "VRND", the API level),
; closes a record file, frees the RAM banks, loads the program (a
; sequential file's data; or record 0 of a VLIR file, its records 1-126
; into RAM banks as overlays), resets GEOS's state (AppReset, bank S:
; the video mode from the info block) and jumps to the start address with
; the stack empty and MainLoop as its return address (StartAppl).

.include "kernel.inc"

.export k_GetFile, k_LdApplic, k_LoadOverlay
.import CvtName, CvtOpen, CvtClose, CvtSeek, CvtRead, CvtEntryName, k_FindFile, k_GetFHdrInfo
.import k_LdFile, k_CloseRecordFile, RecTable, recTab, RecN, RecLenL, RecLenH, RecT
.import kXA, kXN, kXB, kVolume, k_StartAppl, k_BankCopy, k_ChDir, CallerBank, CloseAll, DocMap
.global S_k_BankAlloc, S_BanksInit, S_AppReset, S_DaRun, S_AudioReset, S_k_EnterDeskTop, S_k_TaskCtl
.export LdVars, LdVarsEnd       ; (the switcher keeps them per task: V83)

MAXREC = 127

.segment "BSS"

LdVars:
opt:	.res 1
ovN:	.res 1                  ; overlays: records 0 .. ovN - 1 (0 unused)
ovFirst: .res 1
ovL:	.res MAXREC             ; offset from ovFirst's $A000
ovM:	.res MAXREC
ovH:	.res MAXREC
ovLL:	.res MAXREC             ; length (ovLH $FF: empty)
ovLH:	.res MAXREC
heap:	.res 3
len:	.res 1                  ; Short: the long name's length,
ext:	.res 1                  ; its extension's (with the dot),
pre:	.res 1                  ; the characters kept before "~"
LdVarsEnd:

.segment "CODE"

; r6 name, r0L options (ST_LD_DATA: r3 a document's name, kept in
; dataLongName and, its short form if it is longer than 16, dataFileName:
; V82); x error (it returns only then)
k_GetFile:
	lda r0L
	sta opt
	bpl @1
	lda r3L                 ; the document's name (16 characters, or
	ldx r3H                 ; LONG_MAX with longNames; dataFileName:
	jsr DocMap              ; dataLongName's)
	sty kTmp                ; (the most)
	ldy #0
@c:	lda (kPtr),y
	cmp #$A0
	bne @c1
	lda #0
@c1:	cpy kTmp
	bne @c3
	lda #0
@c3:	sta dataLongName,y
	tax
	beq @c2
	iny
	bra @c
@c2:	jsr Short               ; (y its length)
@1:	jsr k_FindFile
	bne @r
	lda dirEntryBuf + 22
	cmp #APPLICATION
	bne @da
	LoadW r9, dirEntryBuf
	lda opt
	sta r0L
	jmp k_LdApplic
@da:	cmp #DESK_ACC           ; (bank S: kernel/s/desk.s)
	bne @inc
	lda opt                 ; (V168: ST_DA_ROOM)
	FARCALL DaRun
	rts
@inc:	ldx #INCOMPATIBLE
@r:	rts

; dataFileName = dataLongName (its length y), or when it is longer than
; 16 its short form (DECISIONS V82): the first 11 characters less the
; extension's, "~", the CRC-16 of the whole name (the ROM's memory_crc) in
; four hexadecimal digits, the extension (a dot and 1-4 characters at the
; end; none for a GEOS document's name without one) and a 0
Short:	cpy #17
	bcs @long
@s:	lda dataLongName,y      ; (16 at most: as it is)
	sta dataFileName,y
	dey
	bpl @s
	rts
@long:	sty len
	ldx #0                  ; the extension's length with its dot
@e:	dey
	inx
	lda dataLongName,y
	cmp #'.'
	beq @dot
	cpx #5
	bne @e
@no:	ldx #0
@dot:	cpx #1                  ; (a dot at the end: none)
	beq @no
	stx ext
	lda #11
	sec
	sbc ext
	tax
	stx pre
@p:	dex
	lda dataLongName,x
	sta dataFileName,x
	txa
	bne @p
	ldx pre
	lda #'~'
	sta dataFileName,x
	LoadW r0, dataLongName
	lda len
	sta r1L
	stz r1H
	jsr k_memory_crc        ; r2 = the CRC-16 (r0-r2, x, y used)
	ldx pre
	inx
	lda r2H
	jsr Hex2
	lda r2L
	jsr Hex2
	lda len                 ; the extension and the 0
	sec
	sbc ext
	tay
@x:	lda dataLongName,y
	sta dataFileName,x
	inx
	iny
	cmp #0
	bne @x
	rts
Hex2:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @h
	pla
	and #$0F
@h:	cmp #10
	bcc @d
	adc #6                  ; ('A' - '0' - 10 - the carry)
@d:	adc #'0'
	sta dataFileName,x
	inx
	rts

; r9 directory entry, r0L options
k_LdApplic:
	lda r0L
	sta opt
	jsr k_GetFHdrInfo
	beq @1
	rts
@1:	lda fileHeader + O_GHGEOS_TYPE
	cmp #APPLICATION
	bne @inc
	ldx #3
@v:	lda fileHeader + 137,x
	cmp Vrnd,x
	bne @nv
	dex
	bpl @v
	lda fileHeader + 141
	cmp #API_LEVEL + 1
	bcs @new
	php                     ; the interrupt calls nothing of the old
	sei                     ; program's from now on: the load overwrites
	stz intFirstVector      ; it (V76; found on a real X16: Solitaire's
	stz intFirstVector+1    ; frame counter ran into the shell's bytes)
	stz intTopVector
	stz intTopVector+1
	stz intBotVector
	stz intBotVector+1
	stz mouseSource
	stz mouseSource+1
	plp
	FARCALL AudioReset      ; (V52: the old program's audio routine goes)
	jsr k_CloseRecordFile
	jsr CloseAll            ; the old program's streams, the listing (V68)
	FARCALL BanksInit
	stz ovN
	lda fileHeader + O_GHSTR_TYPE
	bne @vlir
	jsr k_LdFile
	bne @fail
	bra Start
@vlir:	jsr Vlir
	bne @fail
	bra Start
@inc:	ldx #INCOMPATIBLE
	rts
@nv:	ldx #NOT_VERANDA
	rts
@new:	ldx #TOO_NEW
	rts
@fail:	lda #TC_FAIL            ; (V83: the desktop learns why)
	FARCALL k_TaskCtl
	FARCALL k_EnterDeskTop  ; (its memory is partly overwritten)
Vrnd:	.byte "VRND"

; the state, the video mode, the jump
Start:	MoveW fileHeader + O_GHST_VEC, r7
	lda fileHeader + 142
	FARCALL AppReset
	lda opt
	sta r0L
	LoadW r2, kVolume
	LoadW r3, dataFileName
	jmp k_StartAppl

; a VLIR application: record 0 to the load address, the rest to banks
Vlir:	lda r9L
	ldx r9H
	jsr CvtEntryName
	lda #'r'
	jsr CvtOpen
	beq @1
	rts
@1:	lda #<508
	ldx #>508
	jsr CvtSeek
	LoadW kXA, recTab
	lda ram_bank
	sta kXB
	lda #<254
	ldx #>254
	jsr CvtRead
	jsr RecTable
	lda RecN
	sta ovN
	beq @bad
	lda RecLenH
	cmp #$FF
	beq @bad                ; record 0 must be there
	; banks for the overlays (and record 0's padding); banked: one a
	; record, and one for the last one's padding
	lda fileHeader + 143
	lsr
	bcc @pb
	lda RecN
	ina
	bra @ba
@pb:	lda RecT+1
	lsr RecT+2
	ror
	lsr RecT+2
	ror
	lsr RecT+2
	ror
	lsr RecT+2
	ror
	lsr RecT+2
	ror
	ina
@ba:	FARCALL k_BankAlloc
	cpx #0
	beq @got
	jsr CvtClose
	ldx #NO_BANKS
	rts
@bad:	jsr CvtClose
	ldx #STRUCT_MISMAT
	rts
@got:	sta ovFirst
	; record 0: its bytes to the load address, its padding to the banks
	MoveW fileHeader + O_GHST_ADDR, kXA
	stz kXB
	lda RecLenL
	ldx RecLenH
	jsr CvtRead
	jsr Pad0
	; the overlays, one after the other (flags bit 0: each in a bank of
	; its own, from its $A000: record y in bank ovFirst + y)
	stz heap
	stz heap+1
	stz heap+2
	ldy #1
@o:	cpy ovN
	beq @done
	lda fileHeader + 143
	lsr
	bcc @pk
	stz heap                ; heap = y * $2000
	tya
	asl
	asl
	asl
	asl
	asl
	sta heap+1
	tya
	lsr
	lsr
	lsr
	sta heap+2
	lda RecLenH,y
	cmp #>8193
	bcc @pk
	cmp #$FF
	beq @pk
	jsr CvtClose
	ldx #STRUCT_MISMAT
	rts
@pk:	lda RecLenH,y
	sta ovLH,y
	cmp #$FF
	beq @on
	lda RecLenL,y
	sta ovLL,y
	lda heap
	sta ovL,y
	lda heap+1
	sta ovM,y
	lda heap+2
	sta ovH,y
	phy
	jsr OvWhere
	ply
	phy
	jsr Padded              ; a/x = its bytes in whole blocks
	jsr CvtRead
	ply
	lda heap
	clc
	adc ovLL,y
	sta heap
	lda heap+1
	adc ovLH,y
	sta heap+1
	bcc @on
	inc heap+2
@on:	iny
	bra @o
@done:	jsr CvtClose
	ldx #0
	rts

; record 0's padding into the overlay banks (overwritten later)
Pad0:	lda #$A0
	sta kXA+1
	stz kXA
	lda ovFirst
	sta kXB
	ldy #0
	jsr Padded
	sec                     ; whole blocks - the length
	sbc RecLenL
	pha
	txa
	sbc RecLenH
	tax
	pla
	jmp CvtRead

; record y's length rounded up to whole 254-byte blocks -> a/x
Padded:	lda RecLenL,y
	sta kTmp
	lda RecLenH,y
	sta kTmp+1
	lda #0
	tax
@1:	clc                     ; a/x += 254, kTmp -= 254 while kTmp > 0
	adc #254
	bcc @2
	inx
@2:	pha
	lda kTmp
	sec
	sbc #254
	sta kTmp
	lda kTmp+1
	sbc #0
	sta kTmp+1
	pla
	bcc @r                  ; it went below 0
	ldy kTmp
	bne @1
	ldy kTmp+1
	bne @1
@r:	rts

; overlay y's place: kXB, kXA
OvWhere:
	lda ovM,y
	and #$1F
	ora #$A0
	sta kXA+1
	lda ovL,y
	sta kXA
	lda ovM,y
	lsr
	lsr
	lsr
	lsr
	lsr
	sta kXB
	lda ovH,y
	asl
	asl
	asl
	ora kXB
	clc
	adc ovFirst
	sta kXB
	rts

; a record, r7 address; x error. r7 = 0: nothing copied, a and r1L the RAM
; bank, r0 the address where the record is kept (banked overlays: $A000)
k_LoadOverlay:
	tay
	beq @inv
	cpy ovN
	bcs @inv
	lda ovLH,y
	cmp #$FF
	beq @inv
	jsr OvWhere
	lda r7L
	ora r7H
	bne @cp
	MoveW kXA, r0
	lda kXB
	sta r1L
	ldx #0
	rts
@cp:	MoveW kXA, r0
	MoveW r7, r1
	lda ovLL,y
	sta r2L
	lda ovLH,y
	sta r2H
	lda kXB
	sta r3L
	jsr CallerBank          ; (r7 at $A000-$BFFF: in the caller's bank)
	sta r3H
	jsr k_BankCopy
	ldx #0
	rts
@inv:	ldx #INV_RECORD
	rts
