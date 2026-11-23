; Veranda bank P: printing to a PDF file (docs/DECISIONS.md V38)
;
; A document (PrintOpen) is a PDF 1.4 file; each page is one 1 bpp image
; at printer resolution (150 or 300 dpi, A4 or US Letter), drawn as an
; /ImageMask in the ink colour, coded as CCITT Group 4 (T.6; /K -1) while
; the rows arrive (kernel/p/fax.s). The rows come in bands (PrintBand,
; in the spirit of GEOS's printer drivers: StartPrint, PrintBuffer,
; StopPrint): a page ends when its last row is in, or at PrintPage
; (the rest white), or at PrintClose. PrintRect prints a screen area as a
; page of its own, scaled to the page (kernel/p/rect.s).
;
; The file is written in one pass: every object's offset is counted as
; the bytes go out (pos) and kept (in the document's bank) for the cross
; reference table at the end; a page image's length is an indirect
; object written after its stream. Objects: 1 the catalogue, 2 the page
; tree (both written at the end), then for each page: the page, its
; content stream, its image, the image's length, and with colour
; (PrintRect) the paper colours as a second image.
;
; Output goes through a 256-byte buffer, written with the resident
; XferOut on the stream's channel (the handle FOpen gave). The offsets
; and the pages' objects are kept in a RAM bank of the document's own
; (BankAlloc; freed by PrintClose, or at the next application's start).

.include "kernel.inc"

.export k_PrintOpen, k_PrintBand, k_PrintPage, k_PrintClose
.export PageBegin, PageEnd, PutByte, PutStr, PutNum, PutSNum, PutSp, PutPal
.export prOpen, prErr, prFlags, pw, ph, rowBytes, rowA
.export rowsSent, inPage, pgCol, cBuf, cN, toBuf, num, InkRGB, PrReset
.export nPages, nextObj, prDpi, prMargin, CopyRow, src, cBank
.import k_BankCopy, XferOut, kXA, kXN, kXB
.import EncInit, EncRow, EncWhite, EncSame, EncEnd, rowPtr
.import ColourImage, ContentColour
.global S_k_FOpen, S_k_FClose, S_k_BankAlloc, S_k_BankFree

; the document's own RAM bank (BankAlloc): the objects' offsets (3 bytes
; each) from $A000, the pages' objects (2 bytes each) from $B800
OFFS     = $A000
KIDS     = $B800
MAXOBJ   = (KIDS - OFFS) / 3
MAXPAGES = 250
RBMAX    = 319                  ; bytes a row (Letter at 300 dpi)

.segment "BSS"

rowA:	.res RBMAX + 1          ; a row (and a stop byte after it: fax.s)
outBuf:	.res 256
cBuf:	.res 160                ; a content stream, made before it is written
oBank:	.res 1
three:	.res 3                  ; an offset to and from oBank
prOpen:	.res 1                  ; $80: a document is open
prH:	.res 1                  ; its handle
prErr:	.res 1                  ; the first error (sticky)
prFlags: .res 1                 ; PrintOpen's a
prDpi:	.res 1                  ; 0: 150, 1: 300
prMargin: .res 2                ; a quarter of an inch, in dots
pw:	.res 2                  ; the page in dots
ph:	.res 2
rowBytes: .res 2
pos:	.res 3                  ; the file's length so far
oN:	.res 1                  ; bytes in outBuf
cN:	.res 1                  ; bytes in cBuf
toBuf:	.res 1                  ; $80: PutByte to cBuf
nextObj: .res 2
nPages:	.res 1
inPage:	.res 1                  ; $80: a page is open
pgCol:	.res 1                  ; this page: $80 the paper colours, $40 the ink colour
rowsSent: .res 2                ; rows of the page so far
pObj:	.res 2                  ; this page's first object
sStart:	.res 3                  ; where its image's data starts
num:	.res 3                  ; PutNum's value
digit:	.res 1
lead:	.res 1
cBank:	.res 1                  ; PrintBand: the caller's RAM bank
src:	.res 2                  ; and the next row
left:	.res 1                  ; rows left of this band
tmpN:	.res 2                  ; an object number
nT:	.res 1

.segment "CODE"

;---------------------------------------------------------------
; PrintOpen: r0 name, a flags (bit 0 Letter, else A4; bit 1 300 dpi, else
; 150) -> x error; r1 bytes a row, r2 rows a page, r3 the width in dots
;---------------------------------------------------------------
k_PrintOpen:
	bit prOpen
	bpl @1
	ldx #INCOMPATIBLE       ; one document at a time
	rts
@1:	and #3
	sta prFlags
	asl                     ; the page: 6 bytes a format
	adc prFlags
	asl
	tax
	ldy #0
@d:	lda Formats,x
	sta pw,y
	inx
	iny
	cpy #6
	bne @d
	lda prFlags
	lsr
	lsr
	lda #0
	rol
	sta prDpi
	tax
	lda Margins,x
	sta prMargin
	stz prMargin+1
	; the offsets' bank, the file
	PushW r0
	lda #1
	FARCALL k_BankAlloc
	sta oBank
	PopW r0
	cpx #0
	beq @0
	rts
@0:	lda #'w'
	FARCALL k_FOpen
	cpx #0
	beq @2
	phx
	lda oBank
	FARCALL k_BankFree
	plx
	rts
@2:	sta prH
	stz prErr
	stz pos
	stz pos+1
	stz pos+2
	stz oN
	stz toBuf
	stz inPage
	stz nPages
	LoadW nextObj, 3
	LoadB prOpen, $80
	LoadW r9, SHead
	jsr PutStr
	MoveW rowBytes, r1
	MoveW ph, r2
	MoveW pw, r3
	ldx prErr
	rts

;---------------------------------------------------------------
; PrintBand: r0 the rows (bytes a row each, top first; at $A000-$BFFF in
; the caller's RAM bank), a the number of rows -> x error. A page starts
; with its first row and is full after its last; the next row starts a
; new page.
;---------------------------------------------------------------
k_PrintBand:
	sta left
	tsx
	lda $0103,x             ; the caller's RAM bank (under FarRet's address)
	sta cBank
	bit prOpen
	bmi @1
	ldx #INCOMPATIBLE
	rts
@1:	MoveW r0, src
@row:	lda left
	bne @go
	jmp @done
@go:
	bit inPage
	bpl @new
	CmpW rowsSent, ph
	bcc @in
	jsr PageEnd             ; full: ended now
@new:	stz pgCol
	jsr PageBegin
	bcc @in
	rts
@in:	MoveW src, rowPtr       ; (main RAM: coded where it is)
	lda src+1
	cmp #$A0
	bcc @c
	jsr CopyRow
@c:	jsr EncRow
	IncW rowsSent
	lda src                 ; the next row
	clc
	adc rowBytes
	sta src
	lda src+1
	adc rowBytes+1
	sta src+1
	cmp #$C0                ; past the caller's bank: the next one
	bcc @3
	sbc #$20
	sta src+1
	inc cBank
@3:	dec left
	jmp @row
@done:	ldx prErr
@r:	rts

; the row at src (in RAM bank cBank if at $A000 or above) to rowA;
; rowPtr = rowA
CopyRow:
	LoadW rowPtr, rowA
	lda src+1
	cmp #$A0
	bcs @bank
	MoveW src, r8           ; main RAM
	LoadW r7, rowA
	ldy #0
	ldx rowBytes+1
	beq @part
@pg:	lda (r8),y
	sta (r7),y
	iny
	bne @pg
	inc r8H
	inc r7H
@part:	cpy rowBytes
	beq @r
	lda (r8),y
	sta (r7),y
	iny
	bra @part
@r:	rts
@bank:	MoveW src, r0
	LoadW r1, rowA
	MoveW rowBytes, r2
	lda cBank
	sta r3L
	lda ram_bank
	sta r3H
	jmp k_BankCopy

;---------------------------------------------------------------
; PrReset (an application's start, AppReset): a document left open is
; closed as it is; its bank is not freed here (the loader's BanksInit has
; freed every bank already, and may have given it to the new application)
;---------------------------------------------------------------
PrReset:
	bit prOpen
	bpl @r
	stz prOpen
	stz inPage
	lda prH
	FARCALL k_FClose
@r:	rts

;---------------------------------------------------------------
; PrintPage: the page ends (its rows not sent white; with none sent, a
; blank page) -> x error
;---------------------------------------------------------------
k_PrintPage:
	bit prOpen
	bmi @1
	ldx #INCOMPATIBLE
	rts
@1:	bit inPage
	bmi @2
	stz pgCol
	jsr PageBegin
	bcs @r
@2:	jsr PageEnd
	ldx prErr
@r:	rts

;---------------------------------------------------------------
; PrintClose: the page being sent ends; the page tree, the cross
; reference table and the trailer; the file closed -> x error
;---------------------------------------------------------------
k_PrintClose:
	bit prOpen
	bmi @1
	ldx #INCOMPATIBLE
	rts
@1:	bit inPage
	bpl @2
	jsr PageEnd
@2:	LoadW tmpN, 1           ; 1: the catalogue
	jsr ObjStart
	LoadW r9, SCat
	jsr PutStr
	LoadW tmpN, 2           ; 2: the pages
	jsr ObjStart
	LoadW r9, SPages
	jsr PutStr
	lda nPages
	jsr PutNumA
	LoadW r9, SKids
	jsr PutStr
	LoadW tmpN, KIDS
	ldx nPages
	beq @k2
@k:	phx
	MoveW tmpN, r0          ; a page's object, from oBank
	lda #2
	jsr FromBank
	lda three
	sta num
	lda three+1
	sta num+1
	stz num+2
	jsr PutRef
	AddVW 2, tmpN
	plx
	dex
	bne @k
@k2:	LoadW r9, SKidsE
	jsr PutStr
	; the cross reference table
	MoveW pos, tmpN
	lda pos+2
	pha
	lda tmpN+1
	pha
	lda tmpN
	pha
	LoadW r9, SXref
	jsr PutStr
	MoveW nextObj, num
	stz num+2
	jsr PutNum
	LoadW r9, SXref0
	jsr PutStr
	LoadW tmpN, 1
@x:	CmpW tmpN, nextObj
	bcs @x2
	jsr OffPtr
	MoveW r9, r0
	lda #3
	jsr FromBank
	ldx #2
@xc:	lda three,x
	sta num,x
	dex
	bpl @xc
	lda #'0'                ; 10 digits: the offset is below 10^8
	jsr PutByte
	jsr PutByte
	LoadB lead, $80
	jsr PutNum8
	LoadW r9, SXrefN
	jsr PutStr
	IncW tmpN
	bra @x
@x2:	LoadW r9, STrail
	jsr PutStr
	MoveW nextObj, num
	stz num+2
	jsr PutNum
	LoadW r9, STrail2
	jsr PutStr
	pla
	sta num
	pla
	sta num+1
	pla
	sta num+2
	jsr PutNum
	LoadW r9, SEof
	jsr PutStr
	jsr Flush
	stz prOpen
	lda prH
	FARCALL k_FClose
	lda oBank
	FARCALL k_BankFree
	ldx prErr
	rts

;---------------------------------------------------------------
; PageBegin: a page's objects up to its image's data (pgCol: $80 with
; the paper colours, $40 the ink in its colour; kernel/p/rect.s sets the
; colours' placement). c set (x error) if there is no room for it.
;---------------------------------------------------------------
PageBegin:
	ldx nPages
	cpx #MAXPAGES
	bcs @full
	lda nextObj
	clc
	adc #5
	tay
	lda nextObj+1
	adc #0
	cmp #>MAXOBJ
	bne @c
	cpy #<MAXOBJ
@c:	bcc @ok
@full:	ldx #BFR_OVERFLOW
	sec
	rts
@ok:	MoveW nextObj, pObj
	txa                     ; KIDS + 2 * page = pObj
	asl
	sta r1L
	lda #0
	rol
	adc #>KIDS
	sta r1H
	MoveW pObj, three
	lda #2
	jsr ToBank
	inc nPages
	lda #4                  ; page, content, image, length (+ colours)
	bit pgCol
	bpl @n
	lda #5
@n:	clc
	adc nextObj
	sta nextObj
	bcc @n1
	inc nextObj+1
@n1:	; the page
	MoveW pObj, tmpN
	jsr ObjStart
	LoadW r9, SPage
	jsr PutStr
	lda prFlags
	and #1
	asl
	tax
	lda Boxes,x
	sta r9L
	lda Boxes+1,x
	sta r9H
	jsr PutStr
	LoadW r9, SRes
	jsr PutStr
	lda #2
	jsr PutObjN             ; /I <page + 2> 0 R
	bit pgCol
	bpl @nk
	LoadW r9, SResK
	jsr PutStr
	lda #4
	jsr PutObjN
@nk:	LoadW r9, SCont
	jsr PutStr
	lda #1
	jsr PutObjN
	LoadW r9, SPageE
	jsr PutStr
	; the content stream, made in cBuf first (its length)
	stz cN
	LoadB toBuf, $80
	LoadW r9, SQ
	jsr PutStr
	jsr PutScale
	bit pgCol
	bpl @nc
	jsr ContentColour       ; the clip and the colours' image
@nc:	bit pgCol
	bvc @ni
	jsr InkRGB              ; "r g b rg"
@ni:	MoveW pw, num
	stz num+2
	jsr PutNum
	LoadW r9, S00
	jsr PutStr
	MoveW ph, num
	stz num+2
	jsr PutNum
	LoadW r9, SDoI
	jsr PutStr
	stz toBuf
	MoveW pObj, tmpN
	IncW tmpN
	jsr ObjStart
	LoadW r9, SLen
	jsr PutStr
	lda cN
	jsr PutNumA
	LoadW r9, SStream
	jsr PutStr
	ldx #0
@cb:	cpx cN
	beq @cb2
	lda cBuf,x
	jsr PutByte
	inx
	bra @cb
@cb2:	LoadW r9, SEndS
	jsr PutStr
	; the paper colours
	bit pgCol
	bpl @nk2
	MoveW pObj, tmpN
	AddVW 4, tmpN
	jsr ObjStart
	jsr ColourImage
@nk2:	; the image
	MoveW pObj, tmpN
	AddVW 2, tmpN
	jsr ObjStart
	LoadW r9, SImg
	jsr PutStr
	jsr PutWH
	LoadW r9, SImg2
	jsr PutStr
	MoveW pw, num
	stz num+2
	jsr PutNum
	LoadW r9, SRows
	jsr PutStr
	MoveW ph, num
	stz num+2
	jsr PutNum
	LoadW r9, SImgL
	jsr PutStr
	lda #3
	jsr PutObjN
	LoadW r9, SStream
	jsr PutStr
	ldx #2
@s:	lda pos,x
	sta sStart,x
	dex
	bpl @s
	; the coder: the row before the first is white
	stz rowsSent
	stz rowsSent+1
	jsr EncInit
	LoadB inPage, $80
	clc
	rts

;---------------------------------------------------------------
; PageEnd: the page's rows not sent are white; the image's end, its
; length
;---------------------------------------------------------------
PageEnd:
	CmpW rowsSent, ph
	bcs @w2
	jsr EncWhite            ; white rows
@w:	IncW rowsSent
	CmpW rowsSent, ph
	bcs @w2
	jsr EncSame
	bra @w
@w2:	jsr EncEnd              ; EOFB, the last byte
	; the length
	sec
	lda pos
	sbc sStart
	sta num
	lda pos+1
	sbc sStart+1
	sta num+1
	lda pos+2
	sbc sStart+2
	sta num+2
	ldx #2
@k:	lda num,x
	pha
	dex
	bpl @k
	LoadW r9, SEndS
	jsr PutStr
	MoveW pObj, tmpN
	AddVW 3, tmpN
	jsr ObjStart
	pla
	sta num
	pla
	sta num+1
	pla
	sta num+2
	jsr PutNum
	LoadW r9, SEndO
	jsr PutStr
	stz inPage
	rts

;---------------------------------------------------------------
; small writers
;---------------------------------------------------------------
; the object tmpN starts here: its offset kept, "n 0 obj"
ObjStart:
	jsr OffPtr
	MoveW r9, r1
	ldx #2
@1:	lda pos,x
	sta three,x
	dex
	bpl @1
	lda #3
	jsr ToBank
	MoveW tmpN, num
	stz num+2
	jsr PutNum
	LoadW r9, SObj
	jmp PutStr

; r9 = OFFS + 3 * tmpN (in oBank)
OffPtr:	lda tmpN
	asl
	sta r9L
	lda tmpN+1
	rol
	sta r9H
	lda r9L
	clc
	adc tmpN
	sta r9L
	lda r9H
	adc tmpN+1
	clc
	adc #>OFFS
	sta r9H
	rts

; a bytes of three to oBank's r1 (ToBank), or from its r0 (FromBank)
ToBank:	sta r2L
	stz r2H
	LoadW r0, three
	lda ram_bank
	sta r3L
	lda oBank
	sta r3H
	jmp k_BankCopy
FromBank:
	sta r2L
	stz r2H
	LoadW r1, three
	lda oBank
	sta r3L
	lda ram_bank
	sta r3H
	jmp k_BankCopy

; " n 0 R" for object pObj + a
PutObjN:
	clc
	adc pObj
	sta num
	lda pObj+1
	adc #0
	sta num+1
	stz num+2
PutRef:	jsr PutNum
	LoadW r9, SRef
	jmp PutStr

; "/Width W/Height H"
PutWH:	MoveW pw, num
	stz num+2
	jsr PutNum
	LoadW r9, SHgt
	jsr PutStr
	MoveW ph, num
	stz num+2
	jmp PutNum

; the CTM to dots: "s 0 0 s 0 0 cm ", s = 0.48 (150 dpi) or 0.24 (300)
PutScale:
	jsr @s
	jsr @s
	LoadW r9, SCm
	jmp PutStr
@s:	LoadW r9, SScale150
	lda prDpi
	beq @1
	LoadW r9, SScale300
@1:	jsr PutStr
	LoadW r9, S00
	jmp PutStr

; the zero-terminated string at r9 (r9 past its 0)
PutStr:	lda (r9)
	IncW r9
	cmp #0
	beq @r
	jsr PutByte
	bra PutStr
@r:	rts

PutSp:	lda #' '
	jmp PutByte

; a as a decimal number
PutNumA:
	sta num
	stz num+1
	stz num+2
; num (24 bits) in decimal
PutNum:	stz lead
; (lead $80: leading zeros written, 8 digits)
PutNum8:
	ldx #0
@d:	stz digit
@s:	lda num                 ; num >= 10^k?
	sec
	sbc Pow10,x
	tay
	lda num+1
	sbc Pow10+8,x
	sta nT
	lda num+2
	sbc Pow10+16,x
	bcc @o
	sta num+2
	lda nT
	sta num+1
	sty num
	inc digit
	bra @s
@o:	lda digit
	bne @w
	bit lead
	bmi @w
	cpx #7                  ; the last digit always
	bne @n
@w:	ora #'0'
	jsr PutByte
	LoadB lead, $80
@n:	inx
	cpx #8
	bne @d
	rts

; num (16 bits, signed) in decimal
PutSNum:
	stz num+2
	bit num+1
	bpl PutNum
	lda #'-'
	jsr PutByte
	sec
	lda #0
	sbc num
	sta num
	lda #0
	sbc num+1
	sta num+1
	bra PutNum

; the ink, palette entry 1: "r g b rg "
InkRGB:	lda #1
	jsr PutPal
	LoadW r9, SRg
	jmp PutStr

; palette entry a: "r g b " (each 0-1)
PutPal:	asl
	stz VERA_CTRL
	clc
	adc #<VRAM_PALETTE
	sta VERA_ADDR_L
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	lda VERA_DATA0          ; GGGGBBBB
	pha
	lda VERA_DATA0          ; 0000RRRR
	jsr @c
	pla
	pha
	lsr
	lsr
	lsr
	lsr
	jsr @c
	pla
@c:	and #$0F              ; n / 15: FracS + 5 n
	sta r9L
	asl
	asl
	adc r9L
	adc #<FracS
	sta r9L
	lda #>FracS
	adc #0
	sta r9H
	jsr PutStr
	jmp PutSp

;---------------------------------------------------------------
; PutByte: a to the file (or to cBuf); keeps a, x and y
;---------------------------------------------------------------
PutByte:
	bit toBuf
	bmi @buf
	phx
	ldx oN
	sta outBuf,x
	inc pos
	bne @1
	inc pos+1
	bne @1
	inc pos+2
@1:	inx
	stx oN
	bne @2
	pha
	phy
	LoadW kXN, 256
	jsr Write
	ply
	pla
@2:	plx
	rts
@buf:	phx
	ldx cN
	sta cBuf,x
	inc cN
	plx
	rts

; what is left in outBuf
Flush:	lda oN
	beq @r
	sta kXN
	stz kXN+1
	stz oN
	jmp Write
@r:	rts

; kXN bytes of outBuf to the file (not after an error)
Write:	lda prErr
	bne @r
	LoadW kXA, outBuf
	lda ram_bank
	sta kXB
	ldx prH
	jsr k_chkout
	bcs @e
	jsr XferOut
	and #%10000011
	beq @ok
@e:	LoadB prErr, DOS_ERROR
@ok:	jsr k_clrchn
@r:	rts

.segment "RODATA"

; A4 150, Letter 150, A4 300, Letter 300: width, height, bytes a row
Formats:
	.word 1240, 1754, 155
	.word 1275, 1650, 160
	.word 2480, 3508, 310
	.word 2550, 3300, 319
Margins: .byte 37, 75
.assert 2550 / 8 + 1 = RBMAX, error, "print.s: RBMAX"

Pow10:	.byte <10000000, <1000000, <100000, <10000, <1000, <100, <10, <1
	.byte >10000000 & $FF, >1000000 & $FF, >100000 & $FF, >10000 & $FF, >1000 & $FF, >100 & $FF, >10 & $FF, >1 & $FF
	.byte ^10000000, ^1000000, ^100000, ^10000, ^1000, ^100, ^10, ^1

Boxes:	.word SBoxA4, SBoxLt

; n / 15 for n = 0-15 (the palette's 4-bit values), 5 bytes each
FracS:	.byte "0", 0, 0, 0, 0, ".067", 0, ".133", 0, ".2", 0, 0, 0, ".267", 0
	.byte ".333", 0, ".4", 0, 0, 0, ".467", 0, ".533", 0, ".6", 0, 0, 0
	.byte ".667", 0, ".733", 0, ".8", 0, 0, 0, ".867", 0, ".933", 0, "1", 0, 0, 0, 0

SHead:	.byte "%PDF-1.4", 10, "%", $E2, $E3, $CF, $D3, 10, 0
SObj:	.byte " 0 obj", 10, 0
SRef:	.byte " 0 R ", 0
SEndO:	.byte 10, "endobj", 10, 0
SCat:	.byte "<</Type/Catalog/Pages 2 0 R>>", 10, "endobj", 10, 0
SPages:	.byte "<</Type/Pages/Count ", 0
SKids:	.byte "/Kids[", 0
SKidsE:	.byte "]>>", 10, "endobj", 10, 0
SPage:	.byte "<</Type/Page/Parent 2 0 R/MediaBox[0 0 ", 0
SBoxA4:	.byte "595.2 841.92]", 0
SBoxLt:	.byte "612 792]", 0
SRes:	.byte "/Resources<</XObject<</I ", 0
SResK:	.byte "/K ", 0
SCont:	.byte ">>>>/Contents ", 0
SPageE:	.byte ">>", 10, "endobj", 10, 0
SQ:	.byte "q ", 0
SScale150: .byte "0.48", 0
SScale300: .byte "0.24", 0
SCm:	.byte "cm ", 0
S00:	.byte " 0 0 ", 0
SDoI:	.byte " 0 0 cm /I Do Q", 10, 0
SRg:	.byte "rg ", 0
SLen:	.byte "<</Length ", 0
SStream: .byte ">>", 10, "stream", 10, 0
SEndS:	.byte 10, "endstream", 10, "endobj", 10, 0
SImg:	.byte "<</Type/XObject/Subtype/Image/Width ", 0
SHgt:	.byte "/Height ", 0
SImg2:	.byte "/ImageMask true/Filter/CCITTFaxDecode/DecodeParms<</K -1/Columns ", 0
SRows:	.byte "/Rows ", 0
SImgL:	.byte ">>/Length ", 0
SXref:	.byte "xref", 10, "0 ", 0
SXref0:	.byte 10, "0000000000 65535 f", 13, 10, 0
SXrefN:	.byte " 00000 n", 13, 10, 0
STrail:	.byte "trailer", 10, "<</Size ", 0
STrail2: .byte "/Root 1 0 R>>", 10, "startxref", 10, 0
SEof:	.byte 10, "%%EOF", 10, 0
