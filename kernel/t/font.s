; Veranda bank T: the font service (DECISIONS V62)
;
; A GEOS font file is a record file of type FONT: record n is the font at
; n points (tools/mkfont.py has the format of a record). LoadFont reads one
; record from the CVT file into RAM banks of its own, once: the font then
; stays there for every program (BankAlloc gives up the fonts no program
; has asked for since the current one started when it runs out of banks:
; bank S, kernel/s/banks.s). UseFont selects it: its header goes to GEOS's
; font variables, its index table to IDX_COPY in bank G, and text reads
; its glyph rows through the resident FontRow (kernel/res/font.s).
;
; Fonts are found in the fonts folder /VERANDA/FONTS, then in the current
; directory: "Name" is the FAT file "Name.cvt" (any long name of up to 31
; characters). Two fonts are built in: "System" (9 points, handle 0: the
; system font) and "Veranda UI" (12 points, FONT_UI: in this bank, from
; tools/mkfont.py), the font native programs may give their menus and
; dialog boxes (uiFont).
;
; Handles: 0 the system font, 1 the UI font, 2 .. NF the fonts loaded
; (table entry handle - 1).

.include "kernel.inc"

.export k_LoadFont, k_UseFont, k_FontInfo, k_FontList, k_FontSizes, k_FontFlush, FontSel
.import k_BankCopy, XferIn, kXA, kXN, kXB, kBankBase, fontBank, fontPage, sysFont
.global S_k_FOpen, S_k_FRead, S_k_FSeek, S_k_FClose, S_k_DirOpen, S_k_DirNext
.global S_k_UseSystemFont, S_FontBanks

NF      = 16                    ; table entries (the UI font's included)
NL      = FONT_NAME_LEN         ; a name with its 0
MAXLEN  = 4 * $2000             ; the largest record (4 banks)
CWDLFN  = 12                    ; FontList's "$=C" (bank F: 2-11)

.segment "BSS"

eName:	.res NF * NL
eSize:	.res NF
eBank:	.res NF                 ; its first RAM bank, 0: a free entry
eN:	.res NF                 ; banks
eHt:	.res NF                 ; height, baseline
eBl:	.res NF
fName:	.res NL                 ; the name asked for
fSize:	.res 1
fH:	.res 1                  ; the open file
fSP:	.res 1
fErr:	.res 1
fEnt:	.res 1
fLen:	.res 2
fOff:	.res 3
fFirst:	.res 1
fCnt:	.res 1
fMax:	.res 1
fTry:	.res 1
hdr:	.res 8
buf:	.res 254                ; the CVT's head, the info block, then its
rtab    = buf                   ; record table (V159: one buffer; the info
fType:	.res 1                  ; block's GEOS type kept)
sv:	.res 8                  ; r0-r3
idxOwn:	.res 2                  ; the banked font whose index table IDX_COPY holds
hdrOwn:	.res 8                  ; its font variables (baselineOffset ..) as FontSel left them
cwdPos:	.res 1
; FontList: the current directory (80 bytes) in rtab, which only a font's
; record table uses (Open, Locate, FontSizes: FontList reads no font head;
; V146: the room for the menus' items, look.s)
cwd     = rtab

.segment "CODE"

; r0-r3 kept by the calls (their results apart)
SaveR:	ldx #7
@1:	lda r0,x
	sta sv,x
	dex
	bpl @1
	rts
RestR:	ldx #7
@1:	lda sv,x
	sta r0,x
	dex
	bpl @1
	rts

;---------------------------------------------------------------
; FontSel: a = a font's first RAM bank, x = the page of its header there
; (bank G's text reads it through FontRow); a = 0: the current banked
; font's index table again, after its state was put back (menus, dialog
; boxes, desk accessories), if another banked font used IDX_COPY since
;---------------------------------------------------------------
FontSel:
	cmp #0
	bne @sel
	lda fontBank
	beq @r
	cmp idxOwn
	bne @re
	lda fontPage
	cmp idxOwn+1
	bne @re
@r:	rts
@re:	lda fontBank
	ldx fontPage
	bra @full
@sel:	cmp idxOwn              ; (V81) IDX_COPY holds its table already: its
	bne @full               ; variables from hdrOwn, no copies
	cpx idxOwn+1
	bne @full
	sta fontBank
	stx fontPage
	ldx #7
@h:	lda hdrOwn,x
	sta baselineOffset,x
	dex
	bpl @h
	stz sysFont
	rts
@full:	sta fontBank
	stx fontPage
	sta idxOwn
	stx idxOwn+1
	ldx #7
@pu:	lda r0,x
	pha
	dex
	bpl @pu
	stz r0L                 ; the header: 8 bytes to baselineOffset
	lda fontPage
	clc
	adc #$A0
	sta r0H
	LoadW r1, baselineOffset
	LoadW r2, 8
	MoveB fontBank, r3L
	jsr k_BankCopy
	lda curIndexTable       ; the index table to bank G's IDX_COPY
	sta r0L
	lda curIndexTable+1
	clc
	adc r0H
	sta r0H
	LoadW r1, IDX_COPY
	LoadW r2, 2 * 97
	lda kBankBase
	clc
	adc #BANK_G
	sta r3H
	jsr k_BankCopy
	LoadW curIndexTable, IDX_COPY
	lda cardDataPntr+1      ; the bitmap: from $A000 of the bank
	clc
	adc fontPage
	sta cardDataPntr+1
	stz sysFont
	ldx #7                  ; (the cache: V81)
@hc:	lda baselineOffset,x
	sta hdrOwn,x
	dex
	bpl @hc
	ldx #0
@po:	pla
	sta r0,x
	inx
	cpx #8
	bne @po
	rts


;---------------------------------------------------------------
; UseFont: a = a handle -> x = 0, or INV_RECORD (no such font)
;---------------------------------------------------------------
k_UseFont:
	pha
	jsr UiEntry
	pla
	cmp #0
	bne @1
	FARCALL k_UseSystemFont
	ldx #0
	rts
@1:	jsr Entry
	bcs @bad
	lda eBank,x
	beq @bad
	cpx #0
	bne @2
	ldx #(>UiFont) - $A0    ; the UI font: in this bank
	bra @3
@2:	ldx #0
@3:	jsr FontSel
	ldx #0
	rts
@bad:	ldx #INV_RECORD
	rts

; a = handle -> x = its entry, c set if out of range
Entry:	dea
	cmp #NF
	bcs @r
	tax
	clc
@r:	rts

; the UI font's entry, once (the bank is known only at run time)
UiEntry:
	lda eBank
	bne @r
	lda kBankBase
	clc
	adc #BANK_T
	sta eBank
	lda #1
	sta eN
	lda #12
	sta eSize
	lda UiFont + 3
	sta eHt
	lda UiFont
	sta eBl
	ldx #0
@n:	lda NameUI,x
	sta eName,x
	beq @r
	inx
	bra @n
@r:	rts

;---------------------------------------------------------------
; LoadFont: r0 = the name, a = the point size -> a = the handle (0 the
; system font, FONT_UI, 2-16), x = 0; or a = FONT_NONE, x = the error:
; FILE_NOT_FOUND (no file, or no such size), INCOMPATIBLE (not a font),
; STRUCT_MISMAT (a bad record), NO_BANKS, BFR_OVERFLOW (16 fonts in use)
;---------------------------------------------------------------
k_LoadFont:
	sta fSize
	jsr SaveR
	jsr UiEntry
	jsr GetName
	jsr Builtin             ; System, Veranda UI
	bcs @nb
	cmp fSize
	bne @nf
	txa
	ldx #0
	bra @out
@nb:	jsr Prune
	ldx #1                  ; loaded already?
@f:	lda eBank,x
	beq @fn
	lda eSize,x
	cmp fSize
	bne @fn
	jsr SameName
	bne @fn
	stx fEnt                ; yes: in use by this program now
	lda eBank,x
	ldy eN,x
	ldx #2
	FARCALL FontBanks
	lda fEnt
	ina
	ldx #0
	bra @out
@fn:	inx
	cpx #NF
	bne @f
	jsr Load
	cpx #0
	bne @err
	lda fEnt
	ina
	bra @out
@nf:	ldx #FILE_NOT_FOUND
@err:	lda #FONT_NONE
@out:	pha
	phx
	jsr RestR
	plx
	pla
	rts

; fName = r0's name (at most NL - 1 characters)
GetName:
	ldy #0
@1:	lda (r0),y
	sta fName,y
	beq @r
	iny
	cpy #NL - 1
	bne @1
	lda #0
	sta fName,y
@r:	rts

; fName a built-in font? c clear: a = its size, x = its handle
Builtin:
	ldx #0
@s:	lda NameSys,x
	cmp fName,x
	bne @u
	inx
	cmp #0
	bne @s
	lda #9
	ldx #0
	clc
	rts
@u:	ldx #0
@v:	lda NameUI,x
	cmp fName,x
	bne @no
	inx
	cmp #0
	bne @v
	lda #12
	ldx #FONT_UI
	clc
	rts
@no:	sec
	rts

; entry x's name = fName? z set if so (x kept)
SameName:
	txa
	jsr NamePtr             ; (x kept)
	ldy #0
@1:	lda (kPtr),y
	cmp fName,y
	bne @r
	iny
	cmp #0
	bne @1
@r:	rts

; a = entry -> kPtr = its name
NamePtr:
	stz kPtr+1
	asl
	asl
	asl
	asl
	rol kPtr+1
	asl
	rol kPtr+1              ; * 32 (NL)
	clc
	adc #<eName
	sta kPtr
	lda kPtr+1
	adc #>eName
	sta kPtr+1
	rts

; entries whose banks were given up (bank S) go
Prune:	ldx #1
@1:	lda eBank,x
	beq @n
	phx
	ldx #3
	FARCALL FontBanks
	plx
	cmp #0
	bne @n
	stz eBank,x
@n:	inx
	cpx #NF
	bne @1
	rts

; the record fSize of the file fName into banks: fEnt, x = 0 or an error
Load:	jsr Open
	cpx #0
	beq @1
	rts
@1:	ldx #INCOMPATIBLE
	lda fType               ; the info block: GEOS type FONT
	cmp #FONT
	beq :+
	jmp @close
:
	jsr Locate              ; fOff, fLen
	cpx #0
	beq :+
	jmp @close
:
	ldx #1                  ; a free entry, else a spare one
@e:	lda eBank,x
	beq @got
	inx
	cpx #NF
	bne @e
	ldx #1                  ; spare: no program asked for it since the
@sp:	lda eBank,x             ; current one started, and not the current
	cmp fontBank            ; font or the UI font (V68; it tested a bank
	beq @sn                 ; bit, not the spare state)
	txa
	ina
	cmp uiFont
	beq @sn
	phx
	lda eBank,x
	ldx #4
	FARCALL FontBanks
	plx
	cmp #0
	bne @free
@sn:	inx
	cpx #NF
	bne @sp
	ldx #BFR_OVERFLOW
	jmp @close
@free:	stx fEnt
	lda eBank,x
	ldy eN,x
	ldx #1
	FARCALL FontBanks
	ldx fEnt
	stz eBank,x
@got:	stx fEnt
	lda fLen                ; banks: (length + 8191) / 8192 (the low
	cmp #1                  ; byte too: V68)
	lda fLen+1
	adc #$1F
	lsr
	lsr
	lsr
	lsr
	lsr
	sta fCnt
	ldx #0
	FARCALL FontBanks
	cpx #0
	beq :+
	jmp @close
:
	sta fFirst
	MoveW fOff, r0          ; the record
	lda fOff+2
	sta r1L
	stz r1H
	lda fH
	FARCALL k_FSeek
	cpx #0
	bne @fail
	ldx fH
	jsr k_chkin
	LoadW kXA, $A000
	MoveW fLen, kXN
	MoveB fFirst, kXB
	jsr XferIn
	stz idxOwn              ; (a font in banks that may have held another: V81)
	jsr k_clrchn
	ldx #STRUCT_MISMAT
	lda kXN
	ora kXN+1
	bne @fail
	jsr Check
	cpx #0
	bne @fail
	ldx fEnt                ; the entry
	lda fFirst
	sta eBank,x
	lda fCnt
	sta eN,x
	lda fSize
	sta eSize,x
	lda hdr + 3
	sta eHt,x
	lda hdr
	sta eBl,x
	txa
	jsr NamePtr
	ldy #0
@nm:	lda fName,y
	sta (kPtr),y
	beq @nd
	iny
	bra @nm
@nd:	ldx #0
	bra @close
@fail:	phx
	lda fFirst
	ldy fCnt
	ldx #1
	FARCALL FontBanks
	plx
@close:	phx
	lda fH
	FARCALL k_FClose
	plx
	rts

; the record's header (hdr): height 1-32, baseline below it, the index
; table and the bitmap inside the record; x = 0 or STRUCT_MISMAT
Check:	stz r0L
	LoadW r0, $A000
	LoadW r1, hdr
	LoadW r2, 8
	MoveB fFirst, r3L
	MoveB ram_bank, r3H
	jsr k_BankCopy
	ldx #STRUCT_MISMAT
	lda hdr + 3
	beq @r
	cmp #STRIP_ROWS + 1
	bcs @r
	lda hdr
	cmp hdr + 3
	bcs @r
	lda hdr + 4             ; index + 194 <= length
	clc
	adc #2 * 97
	sta r0L
	lda hdr + 5
	adc #0
	sta r0H
	CmpW fLen, r0
	bcc @r
	MoveW hdr + 6, r0       ; bitmap + width * height <= length
	ldy hdr + 3
@m:	AddW hdr + 1, r0
	bcs @r
	dey
	bne @m
	CmpW fLen, r0
	bcc @r
	ldx #0
@r:	rts

; fOff, fLen = record fSize's place in the CVT file (rtab), x = 0 or
; FILE_NOT_FOUND
Locate:	LoadW fOff, 762
	stz fOff+2
	ldx #FILE_NOT_FOUND
	lda fSize
	beq @r
	cmp #127
	bcs @r
	ldy #0
@1:	cpy fSize
	beq @2
	tya
	asl
	tax
	lda rtab,x
	ora rtab+1,x
	beq @nf                 ; the table ends first
	lda rtab,x              ; + blocks * 254
	beq @n
	sta kTmp
@a:	AddVW 254, fOff
	bcc @a1
	inc fOff+2
@a1:	dec kTmp
	bne @a
@n:	iny
	bra @1
@2:	tya
	asl
	tax
	lda rtab,x
	beq @nf
	sta kTmp                ; (blocks - 1) * 254 + last - 1
	lda rtab+1,x
	beq @nf
	sec
	sbc #1
	sta fLen
	stz fLen+1
@b:	dec kTmp
	beq @b1
	AddVW 254, fLen
	lda fLen+1
	cmp #>MAXLEN
	bcs @nf
	bra @b
@b1:	lda fLen
	ora fLen+1
	beq @nf
	ldx #0
	rts
@nf:	ldx #FILE_NOT_FOUND
@r:	rts

;---------------------------------------------------------------
; Open: the CVT file fName (the fonts folder, else the current directory),
; its head read: a record file (else INCOMPATIBLE); buf = its info block,
; rtab = its record table; fH open (x = 0) or closed (x = the error)
;---------------------------------------------------------------
Open:	stz fTry
@try:	tsx                     ; the path, on the stack (FOpen reads it
	stx fSP                 ; below $A000)
	txa
	sec
	sbc #72
	tax
	txs
	inx
	stx r0L
	LoadB r0H, $01
	ldy #0
	lda fTry
	bne @nm
@pf:	lda FontDir,y
	beq @nm
	sta (r0),y
	iny
	bra @pf
@nm:	ldx #0
@n:	lda fName,x
	beq @x
	sta (r0),y
	iny
	inx
	bra @n
@x:	ldx #0
@e:	lda Ext,x
	sta (r0),y
	iny
	inx
	cpx #5
	bne @e
	lda #'r'
	FARCALL k_FOpen
	sta fH
	stx fErr
	ldx fSP
	txs
	ldx fErr
	bne @no
	lda dosStatus
	cmp #20
	bcs @dos
	lda fH                  ; the head: the entry, the signature, the info
	cmp #2                  ; block, the record table
	bcc @no
	cmp #10
	bcs @no
	ldx #INCOMPATIBLE
	lda #30
	jsr Rd
	bne @cl
	lda buf + 21
	cmp #1
	bne @cl
	lda #224
	jsr Rd
	bne @cl
	lda #254
	jsr Rd
	bne @cl
	lda buf + 69 - 2        ; (the GEOS type: rtab is buf)
	sta fType
	ldx #<rtab
	stx r0L
	ldx #>rtab
	stx r0H
	lda #254
	jsr Rd0
	bne @cl
	ldx #0
	rts
@cl:	phx
	lda fH
	FARCALL k_FClose
	plx
	rts
@dos:	lda fH
	FARCALL k_FClose
@no:	inc fTry
	lda fTry
	cmp #2
	beq :+
	jmp @try
:
	ldx #FILE_NOT_FOUND
	rts

; a bytes into buf (Rd0: into r0) -> z set if all came
; (a stream may give fewer bytes than asked: read on)
Rd:	ldx #<buf
	stx r0L
	ldx #>buf
	stx r0H
Rd0:	sta fCnt
@more:	lda fCnt
	sta r1L
	stz r1H
	lda fH
	FARCALL k_FRead
	lda r1L
	beq @r                  ; nothing more: z clear (fCnt > 0)
	clc
	adc r0L
	sta r0L
	bcc @1
	inc r0H
@1:	lda fCnt
	sec
	sbc r1L
	sta fCnt
	bne @more
@r:	lda fCnt                ; z set: all of it
	rts

;---------------------------------------------------------------
; FontFlush: r0 = a font's name: its sizes loaded are forgotten (their
; banks freed), so that LoadFont reads the file again (a font editor has
; written it); the current font stays. x = 0
;---------------------------------------------------------------
k_FontFlush:
	jsr SaveR
	jsr GetName
	ldx #1
@e:	lda eBank,x
	beq @n
	cmp fontBank
	beq @n
	jsr SameName
	bne @n
	stx fEnt
	lda eBank,x
	ldy eN,x
	ldx #1
	FARCALL FontBanks
	ldx fEnt
	stz eBank,x
@n:	inx
	cpx #NF
	bne @e
	jsr RestR
	ldx #0
	rts

;---------------------------------------------------------------
; FontInfo: a = a handle, r0 = 32 bytes for its name (or 0) -> a = its
; point size, r1L its height, r1H its baseline, x = 0 (or INV_RECORD)
;---------------------------------------------------------------
k_FontInfo:
	pha
	jsr UiEntry
	pla
	cmp #0
	bne @1
	lda #9                  ; the system font
	sta r1L
	lda #6
	sta r1H
	LoadW kPtr, NameSys
	lda #9
	bra @name
@1:	jsr Entry
	bcs @bad
	lda eBank,x
	beq @bad
	lda eHt,x
	sta r1L
	lda eBl,x
	sta r1H
	phx
	txa
	jsr NamePtr
	pla
	tax
	lda eSize,x
@name:	pha
	lda r0L
	ora r0H
	beq @r
	ldy #0
@c:	lda (kPtr),y
	sta (r0),y
	beq @r
	iny
	bra @c
@r:	pla
	ldx #0
	rts
@bad:	lda #0
	ldx #INV_RECORD
	rts

;---------------------------------------------------------------
; FontSizes: r0 = a font's name, r1 = a buffer (63 bytes) -> a = the
; number of point sizes the font has, in the buffer in increasing order;
; x = 0 or an error (a = 0)
;---------------------------------------------------------------
k_FontSizes:
	jsr SaveR
	jsr GetName
	jsr Builtin
	bcs @f
	sta (r1)
	lda #1
	ldx #0
	bra @out
@f:	jsr Open
	cpx #0
	bne @err
	lda fType
	cmp #FONT
	beq @ok
	lda fH
	FARCALL k_FClose
	ldx #INCOMPATIBLE
@err:	lda #0
	bra @out
@ok:	lda fH
	FARCALL k_FClose
	MoveW sv + 2, kPtr      ; (r1)
	ldy #0
	ldx #2                  ; records 1-62
@s:	lda rtab,x
	ora rtab+1,x
	beq @end
	lda rtab,x
	beq @nx
	txa
	lsr
	sta (kPtr),y
	iny
@nx:	inx
	inx
	cpx #2 * 63
	bne @s
@end:	tya
	ldx #0
@out:	pha
	phx
	jsr RestR
	plx
	pla
	rts

;---------------------------------------------------------------
; FontList: r0 = a buffer for a names of FONT_NAME_LEN bytes -> a = the
; fonts: "System", "Veranda UI", then the .cvt files of the fonts folder
; in alphabetical order (as far as there is room). The folder is listed
; from inside it (a host folder lists only the current directory): the
; current directory is read first ("$=C", its path from the bottom up)
; and changed back to after.
;---------------------------------------------------------------
k_FontList:
	sta fMax
	jsr SaveR
	stz fCnt
	LoadW kPtr2, NameSys
	jsr Add
	LoadW kPtr2, NameUI
	jsr Add
	tsx                     ; names and DirNext's entries: on the stack
	stx fSP
	txa
	sec
	sbc #80
	tax
	txs
	inx
	stx r0L
	LoadB r0H, $01
	jsr GetCwd
	bcs @done
	LoadW kPtr2, FontDirCD
	jsr StrR0
	FARCALL k_ChDir
	cpx #0
	bne @back
	LoadW kPtr2, Star
	jsr StrR0
	FARCALL k_DirOpen
	cpx #0
	bne @back
@next:	FARCALL k_DirNext
	cpx #0
	bne @back
	ldy #0                  ; a file
	lda (r0),y
	cmp #'F'
	bne @next
	ldy #3                  ; its name's end: ".cvt"
@l:	lda (r0),y
	beq @le
	iny
	bra @l
@le:	cpy #3 + 5
	bcc @next
	cpy #3 + 4 + NL
	bcs @next
	dey
	ldx #3
@x:	lda (r0),y
	ora #$20
	cmp ExtL,x
	bne @next
	dey
	dex
	bpl @x
	iny
	lda #0
	sta (r0),y              ; the name without it
	lda r0L
	clc
	adc #3
	sta kPtr2
	lda r0H
	sta kPtr2+1
	jsr Add
	bra @next
@back:	LoadW kPtr2, cwd        ; the directory as it was
	jsr StrR0
	FARCALL k_ChDir
@done:	ldx fSP
	txs
	jsr RestR
	lda fCnt
	ldx #0
	rts

; the string at kPtr2 (at most 79 bytes) to r0
StrR0:	ldy #0
@1:	lda (kPtr2),y
	sta (r0),y
	beq @r
	iny
	bra @1
@r:	rts

; cwd = the current directory's path, "/A/B" (c set: unknown): "$=C"
; lists it from the current directory up to "/", a name a line; each
; name goes in front of the ones before it
GetCwd:	lda #'$'                ; (r0: the stack buffer)
	sta (r0)
	ldy #1
	lda #'='
	sta (r0),y
	iny
	lda #'C'
	sta (r0),y
	lda #3
	ldx r0L
	ldy r0H
	jsr k_setnam
	lda #CWDLFN
	ldx #8
	ldy #0
	jsr k_setlfs
	jsr k_open
	bcc :+
	jmp @fail
:
	ldx #CWDLFN
	jsr k_chkin
	stz cwdPos              ; the path is built down from cwd + 79
	LoadB cwdPos, 79
	lda #0
	sta cwd + 79
	ldy #6                  ; the load address, the header's link and number
@h:	phy
	jsr k_chrin
	ply
	dey
	bne @h
	jsr Line                ; the header
@line:	jsr k_chrin             ; the link: 0 0 ends it
	sta kTmp
	jsr k_chrin
	ora kTmp
	beq @end
	jsr k_readst
	bne @end
	jsr k_chrin             ; the number
	jsr k_chrin
@q:	jsr k_chrin             ; to the name's quote
	cmp #0
	beq @line
	cmp #'"'
	bne @q
	ldy #0                  ; the name into r0's buffer
@n:	jsr k_chrin
	cmp #'"'
	beq @nd
	cpy #40
	bcs @n
	sta (r0),y
	iny
	bra @n
@nd:	sty kTmp+1
	jsr Line                ; the rest of the line
	ldy kTmp+1
	beq @line
	cpy #1                  ; "/": the root
	bne @put
	lda (r0)
	cmp #'/'
	beq @line
@put:	tya                     ; room for the name and its "/"?
	ina
	cmp cwdPos
	bcs @line
@c:	dey                     ; in front
	bmi @sl
	lda (r0),y
	ldx cwdPos
	dex
	sta cwd,x
	stx cwdPos
	bra @c
@sl:	ldx cwdPos
	dex
	lda #'/'
	sta cwd,x
	stx cwdPos
	bra @line
@end:	jsr k_clrchn
	lda #CWDLFN
	jsr k_close
	ldx cwdPos              ; to the start of cwd; "/" if none
	ldy #0
	cpx #79
	bne @mv
	lda #'/'
	sta cwd
	iny
	bra @z
@mv:	lda cwd,x
	sta cwd,y
	beq @ok
	inx
	iny
	bra @mv
@z:	lda #0
	sta cwd,y
@ok:	clc
	rts
@fail:	lda #CWDLFN
	jsr k_close
	sec
	rts

; the rest of a listing's line, to its 0
Line:	jsr k_readst
	bne @r
	jsr k_chrin
	cmp #0
	bne Line
@r:	rts

; the name at kPtr2 into the caller's buffer (sv: r0), sorted, unless it
; is there already or the buffer is full
Add:	lda fCnt
	cmp fMax
	bcs @r
	ldx #2                  ; i: the first name after this one (after the
	cpx fCnt                ; two built-in ones, which come first)
	bcc @i
	ldx fCnt
@i:	cpx fCnt
	beq @ins
	jsr SlotI
	ldy #0
@c:	lda (kPtr2),y
	cmp (kPtr),y
	bcc @ins                ; before it
	bne @nx
	cmp #0
	beq @r                  ; the same
	iny
	bra @c
@nx:	inx
	bra @i
@ins:	stx fEnt                ; the names from i on: one slot down
	ldx fCnt
@mv:	cpx fEnt
	beq @put
	dex
	jsr SlotI               ; kPtr = slot x
	ldy #NL - 1
@m:	lda (kPtr),y
	pha
	tya
	clc
	adc #NL
	tay
	pla
	sta (kPtr),y
	tya
	sec
	sbc #NL + 1
	tay
	bpl @m
	bra @mv
@put:	ldx fEnt
	jsr SlotI
	ldy #0
@w:	lda (kPtr2),y
	sta (kPtr),y
	beq @wd
	iny
	cpy #NL - 1
	bne @w
	lda #0
	sta (kPtr),y
@wd:	inc fCnt
@r:	rts

; kPtr = the caller's slot x (x kept)
SlotI:	stz kPtr+1
	txa
	asl
	asl
	asl
	asl
	rol kPtr+1
	asl
	rol kPtr+1
	clc
	adc sv
	sta kPtr
	lda kPtr+1
	adc sv+1
	sta kPtr+1
	rts

.segment "RODATA"

NameSys: .byte "System", 0
NameUI:	.byte "Veranda UI", 0
FontDir: .byte VR_FONTSPATH, 0
FontDirCD: .byte VR_FONTSDIR, 0
Star:	.byte "*", 0
Ext:	.byte ".cvt", 0
ExtL:	.byte ".cvt"

; the UI font (tools/mkfont.py --ui), on a page of its own: FontSel
; finds a font's header at the start of a page (cfg/bank.cfg: PAGED)
.segment "PAGED"
UiFont:	.incbin "uifont.bin"
