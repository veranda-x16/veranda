; Veranda bank F: streams and DOS commands (CMDR-DOS, device 8: the SD card,
; or the emulator's host folder)
;
; A stream is a logical file 2-4 (its secondary address the same), opened
; with ",S,R", "@:...,S,W" (create or replace) or ",S,M" (read and write,
; seekable). An 'm' stream, and any stream once seeked, is written byte by
; byte (CHROUT), never by MCIOUT: R49's MCIOUT garbles an overwrite that
; crosses a 512-byte sector of the file (DECISIONS V55). The command
; channel (15) stays open. After every open and command the status is read
; into dosStatus (two digits as a number).
;
; Directory entries (DirNext): +0 type ('D' a directory, 'F' a file), +1
; size in blocks (word, as the listing gives it), +3 the name, 0-terminated
; (at most 63 characters). A pattern that starts with '=' ("=L", "=L:*",
; CMDR-DOS's listing options) is sent as "$=L" ... and the lines come raw:
; the header line first, then each line: +0 'R', +1 its number, +3 its
; text 0-terminated (at most 122 bytes; a 125-byte entry), the footer
; ("... FREE.") last.

.include "kernel.inc"

.export k_FOpen, k_FRead, k_FWrite, k_FSeek, k_FClose, k_DirOpen, k_DirNext
.export k_ChDir, k_MkDir, k_RmDir, k_FDelete, k_FRename, k_FSize, DosCmd, Scratch, DosOpen, DosClose, Status, CmdOpen, nameLen
.export CloseAll
.export StrOpen, StrDir         ; (the switcher: a program with streams or a
				; listing open is not put aside, V83)
.import XferIn, XferOut, kXA, kXN, kXB, kXSlow, kName, DocMap

UNIT    = 8
CMD     = 15                    ; the command channel
DIRLFN  = 10                    ; the directory listing
FIRST   = 2                     ; streams 2-4
STREAMS = 3                     ; (a card's DOS has four contexts: one stays
				; for the kernel's own files or a listing; R49
				; reports no error for a fifth open: V68)

.segment "BSS"

StrOpen:
open:	.res STREAMS            ; <> 0: in use
cmdOpen: .res 1
nameLen: .res 1
tmp:	.res 2
track:	.res 1
commas:	.res 1
StrDir:
dirOn:	.res 1
dirRaw:	.res 1                  ; <> 0: a pattern from '=' (the lines raw)

.segment "CODE"

;---------------------------------------------------------------
; the command channel and the status
;---------------------------------------------------------------
CmdOpen:
	lda cmdOpen
	bne @r
	lda #0
	jsr k_setnam
	lda #CMD
	ldx #UNIT
	ldy #15
	jsr k_setlfs
	jsr k_open
	bcs @r
	inc cmdOpen
@r:	rts

; dosStatus = the command channel's two digits; a = it, z set if 0
Status:	jsr CmdOpen
	lda #CMD
; the same from logical file a
Status2:
	tax
	jsr k_chkin
	jsr k_chrin
	sec
	sbc #'0'
	sta tmp
	asl
	asl
	adc tmp
	asl
	sta tmp
	jsr k_chrin
	sec
	sbc #'0'
	clc
	adc tmp
	sta dosStatus
	stz track               ; the rest: ",message,TT,SS"; TT as a number
	stz commas
	ldy #60
@1:	jsr k_readst
	bne @2
	jsr k_chrin
	cmp #CR
	beq @2
	cmp #','
	bne @d
	inc commas
	bra @n
@d:	ldx commas
	cpx #2
	bne @n
	sec
	sbc #'0'
	cmp #10
	bcs @n
	pha
	lda track               ; track * 10 + digit
	asl
	asl
	adc track
	asl
	sta track
	pla
	clc
	adc track
	sta track
@n:	dey
	bne @1
@2:	jsr k_clrchn
	lda dosStatus
	rts

; the command kName (nameLen bytes) to the command channel (one channel
; with secondary address 15; a second one confused CMDR-DOS on the SD
; card); x = 0 or the error
DosCmd:	jsr DosSend
	jsr Status
	cmp #20                 ; 00-19: no error (01: files scratched)
	bcc Ok
	bra Err
; the command kName (nameLen bytes), sent; the status not read
DosSend:
	jsr CmdOpen
	ldx #CMD
	jsr k_chkout
	ldy #0
@1:	cpy nameLen
	beq @2
	lda kName,y
	phy
	jsr k_chrout
	ply
	iny
	bra @1
@2:	jmp k_clrchn
Err:	ldx #TOO_MANY_FILES     ; 70 NO CHANNEL: the DOS's contexts (four on
	cmp #70                 ; a card, R49) are all in use (V68)
	beq @2
	ldx #DOS_ERROR
	cmp #62
	bne @1
	ldx #FILE_NOT_FOUND
@1:	cmp #63
	bne @2
	ldx #FILE_EXISTS
@2:	rts
Ok:	ldx #0
	rts

; kName = the text of a (low) x (high), from offset y; nameLen = the end
Append:	sta kPtr
	stx kPtr+1
	phy
	ldy #0
	plx
@1:	lda (kPtr),y
	beq @2
	sta kName,x
	iny
	inx
	cpx #70
	bcc @1
@2:	stx nameLen
	rts

; append the characters a, then (if not 0) x
Add2:	ldy nameLen
	sta kName,y
	iny
	txa
	beq @1
	sta kName,y
	iny
@1:	sty nameLen
	rts

; OPEN kName (nameLen) as logical file a (secondary address the same);
; x = 0 or the error
DosOpen:
	pha
	lda nameLen
	ldx #<kName
	ldy #>kName
	jsr k_setnam
	pla
	pha
	tay
	ldx #UNIT
	jsr k_setlfs
	jsr k_open
	pla
	bcs @nf
	pha
	jsr Status
	tax
	pla
	cpx #20
	bcc Ok
	jsr k_close
	lda dosStatus
	jmp Err
@nf:	ldx #DEV_NOT_FOUND
	rts

DosClose:
	jsr k_close
	jmp k_clrchn

;---------------------------------------------------------------
; streams
;---------------------------------------------------------------
; r0 name, a mode -> a handle, x error
k_FOpen:
	sta tmp+1               ; (the mode)
	ldx #0
@f:	lda open,x
	beq @free
	inx
	cpx #STREAMS
	bne @f
	ldx #TOO_MANY_FILES
	rts
@free:	phx
	stz nameLen
	lda tmp+1
	cmp #'w'
	bne @n
	ldx #':'                ; "@:" in front; a path ("//DIR/:NAME") takes
	lda (r0)                ; "@" alone (DECISIONS V54)
	cmp #'/'
	bne @at
	ldx #0
@at:	lda #'@'
	jsr Add2
@n:	lda r0L
	ldx r0H
	jsr DocMap              ; (dataFileName: dataLongName, V82)
	lda kPtr
	ldx kPtr+1
	ldy nameLen
	jsr Append
	lda #','
	ldx #'S'
	jsr Add2
	lda tmp+1
	ldx #'R'
	cmp #'r'
	beq @m
	ldx #'W'
	cmp #'w'
	beq @m
	ldx #'M'
@m:	lda #','
	jsr Add2                ; ",W" etc.: the second character
	plx
	phx
	txa
	clc
	adc #FIRST
	jsr DosOpen
	pla
	cpx #0
	bne @r
	tay
	lda tmp+1               ; 1: in use; $81: an 'm' stream (V55)
	cmp #'r'
	lda #1
	bcs @w
	lda #$81
@w:	sta open,y
	tya
	clc
	adc #FIRST              ; the handle
@r:	rts

; a handle -> c set if not open; x = its logical file
Handle:	sec
	sbc #FIRST
	cmp #STREAMS
	bcs @no
	tay
	lda open,y
	beq @no
	tya
	clc
	adc #FIRST
	tax
	clc
	rts
@no:	sec
	rts

; a handle, r0 buffer, r1 count -> r1 the bytes read, x error
k_FRead:
	jsr Handle
	bcs Bad
	jsr k_chkin
	jsr Xfer
	jsr XferIn
Done:	pha
	jsr k_clrchn
	lda r1L                 ; r1 = asked - left
	sec
	sbc kXN
	sta r1L
	lda r1H
	sbc kXN+1
	sta r1H
	pla
	and #%10000011
	bne @e
	ldx #0
	rts
@e:	ldx #DOS_ERROR
	rts
Bad:	ldx #UNOPENED_VLIR
	rts

; the buffer: an address at $A000 or above is in the RAM bank the caller
; had mapped (V47), read from under FarGo's return address: FRead and
; FWrite are only entered through the bank gate (applications, and bank X's
; ExportRect by FARCALL), and Xfer is called straight from them. (It took
; ram_bank, which is bank F itself here: a buffer in the caller's bank
; was written over the kernel's code.)
Xfer:	MoveW r0, kXA
	MoveW r1, kXN
	tsx
	lda $0105,x             ; Xfer's return, FarRet - 1, then the bank
	sta kXB
	rts

k_FWrite:
	jsr Handle
	bcs Bad
	lda open,y              ; bit 7: byte by byte (V55; XferOut clears it)
	sta kXSlow
	jsr k_chkout
	jsr Xfer
	jsr XferOut
	bra Done

; a handle, r0 low word, r1 high word of the position
k_FSeek:
	jsr Handle
	bcs Bad
	lda open,y              ; seeked: written byte by byte from now (V55)
	ora #$80
	sta open,y
	lda #'P'
	sta kName
	stx kName+1             ; the channel
	lda r0L
	sta kName+2
	lda r0H
	sta kName+3
	lda r1L
	sta kName+4
	lda r1H
	sta kName+5
	LoadB nameLen, 6
	jmp DosCmd

k_FClose:
	cmp #FIRST
	bcc Ends
	jsr Handle
	bcs Bad
	lda #0
	sta open - FIRST,x
	txa
	jsr DosClose
	ldx #0
	rts

; streams a program left open (V68): CloseAll (LdApplic: a program ends)
; closes every stream and the listing; FClose with a = 1 (DaRun: an
; accessory starts) marks the program's open streams (bit 6), with a = 0
; (RstrAppl: it ends) closes the others (the accessory's) and the listing,
; the marks cleared. x = 0.
CloseAll:
	ldx #STREAMS - 1
@u:	lda open,x
	and #<~$40
	sta open,x
	dex
	bpl @u
	lda #0
Ends:	sta tmp
	ldx #STREAMS - 1
@1:	lda open,x
	beq @n
	ldy tmp
	bne @m                  ; 1: marked
	bit #$40
	bne @k                  ; marked: kept, unmarked
	stz open,x
	phx
	txa
	clc
	adc #FIRST
	jsr DosClose
	plx
	bra @n
@k:	and #<~$40
	bra @s
@m:	ora #$40
@s:	sta open,x
@n:	dex
	bpl @1
	lda tmp
	bne @r
	jsr DirClose
@r:	ldx #0
	rts

; a handle -> r0:r1 its size, r2:r3 the position (bytes), x error: the
; DOS's tell command ("T" and the channel), whose status is
; "07,<position> <size>,00,00", both as 8 hex digits (CMDR-DOS and the
; emulator's host folder)
k_FSize:
	jsr Handle
	bcc @h
	jmp Bad
@h:
	lda #'T'
	sta kName
	stx kName+1             ; the channel
	LoadB nameLen, 2
	jsr DosSend
	ldx #CMD
	jsr k_chkin
	jsr k_chrin             ; the status: two digits
	and #$0F
	sta tmp
	asl
	asl
	adc tmp
	asl
	sta tmp
	jsr k_chrin
	and #$0F
	clc
	adc tmp
	sta dosStatus
	jsr k_chrin             ; ","
	ldx #r2
	jsr Hex8
	jsr k_chrin             ; " "
	ldx #r0
	jsr Hex8
	ldy #40                 ; the rest of the line
@d:	jsr k_readst
	bne @e
	jsr k_chrin
	cmp #CR
	beq @e
	dey
	bne @d
@e:	jsr k_clrchn
	lda dosStatus
	cmp #7
	bne @x
	ldx #0
	rts
@x:	ldx #DOS_ERROR
	rts

; 8 hex digits into the 4 bytes at zero page x (low byte first)
Hex8:	stz 0,x
	stz 1,x
	stz 2,x
	stz 3,x
	ldy #8
@1:	phy
	phx
	jsr k_chrin
	plx
	sec
	sbc #'0'
	cmp #10
	bcc @2
	sbc #7                  ; 'A' -> 10
@2:	and #$0F
	pha
	ldy #4
@3:	asl 0,x
	rol 1,x
	rol 2,x
	rol 3,x
	dey
	bne @3
	pla
	ora 0,x
	sta 0,x
	ply
	dey
	bne @1
	rts

;---------------------------------------------------------------
; the directory
;---------------------------------------------------------------
; r0 pattern ("*" or 0: all)
k_DirOpen:
	jsr DirClose
	stz dirRaw
	LoadB kName, '$'
	LoadB nameLen, 1
	lda r0L
	ora r0H
	beq @o
	ldy #0
	lda (r0),y
	beq @o
	cmp #'='                ; "=L" ...: "$=L" ..., the lines raw
	bne @c
	sta dirRaw
	bra @a
@c:	lda #':'
	ldx #0
	jsr Add2
@a:	lda r0L
	ldx r0H
	ldy nameLen
	jsr Append
@o:	lda nameLen
	ldx #<kName
	ldy #>kName
	jsr k_setnam
	lda #DIRLFN
	ldx #UNIT
	ldy #0                  ; as LOAD"$" gives it: a BASIC listing
	jsr k_setlfs
	jsr k_open
	bcs @nf
	inc dirOn
	ldx #DIRLFN
	jsr k_chkin
	jsr k_chrin             ; the load address
	jsr k_chrin
	lda dirRaw
	bne @h                  ; (raw: the header is the first line)
	jsr Line                ; the header line (the volume name)
@h:	jsr k_clrchn
	ldx #0
	rts
@nf:	ldx #DEV_NOT_FOUND
	rts

DirClose:
	lda dirOn
	beq @r
	stz dirOn
	lda #DIRLFN
	jmp DosClose
@r:	rts

; skip a BASIC line: link, number, text to 0; c set at the end of the listing
Line:	jsr k_chrin
	sta tmp
	jsr k_chrin
	ora tmp
	beq @end                ; link 0: the end
	jsr k_chrin             ; the number
	sta tmp
	jsr k_chrin
	sta tmp+1
@1:	jsr k_readst
	bne @end
	jsr k_chrin
	cmp #0
	bne @1
	clc
	rts
@end:	sec
	rts

; r0 entry -> x 0, or not 0 at the end
k_DirNext:
	lda dirOn
	beq @end0
	ldx #DIRLFN
	jsr k_chkin
	jsr k_chrin             ; the link
	sta tmp
	jsr k_chrin
	ora tmp
	beq @end
	jsr k_chrin             ; the number: the size in blocks
	ldy #1
	sta (r0),y
	jsr k_chrin
	iny
	sta (r0),y
	lda dirRaw
	bne @raw
	; the text: spaces, "name", spaces, the type; or "... BLOCKS FREE."
@q:	jsr k_readst
	bne @end
	jsr k_chrin
	cmp #0
	beq @end                ; a line without a name: the last
	cmp #'"'
	bne @q
	ldy #3
@n:	jsr k_chrin
	cmp #'"'
	beq @nq
	cpy #66
	bcs @n
	sta (r0),y
	iny
	bra @n
@nq:	lda #0
	sta (r0),y
	lda #'F'
	sta tmp
@t:	jsr k_chrin             ; the type: DIR or not
	cmp #0
	beq @tz
	cmp #'D'
	bne @t
	lda #'D'
	sta tmp
	bra @t
@tz:	lda tmp
	ldy #0
	sta (r0),y
	jsr k_clrchn
	ldx #0
	rts
@end:	jsr k_clrchn
	jsr DirClose
@end0:	ldx #FILE_NOT_FOUND
	rts
	; raw: the line's text from +3, 0-terminated (at most 122 bytes kept)
@raw:	ldy #3
@r:	jsr k_chrin
	cpy #125
	bcs @s
	sta (r0),y
	iny
@s:	cmp #0
	bne @r
	lda #'R'
	sta tmp
	bra @tz

;---------------------------------------------------------------
; commands
;---------------------------------------------------------------
; "CD:" r0
k_ChDir:
	lda #'C'
	ldx #'D'
Cmd2:	stz nameLen
	jsr Add2
	lda #':'
	ldx #0
	jsr Add2
	lda r0L
	ldx r0H
	ldy nameLen
	jsr Append
	jmp DosCmd

k_MkDir:
	lda #'M'
	ldx #'D'
	bra Cmd2

; "RD:" r0 (DECISIONS V45): an empty directory
k_RmDir:
	lda #'R'
	ldx #'D'
	bra Cmd2

; "S:" r0
k_FDelete:
	stz nameLen
	lda #'S'
	ldx #':'
	jsr Add2
	lda r0L
	ldx r0H
	ldy nameLen
	jsr Append
; a scratch command (kName: "S:name"): the file is opened first (its
; absence is FILE_NOT_FOUND: the DOS's count of files scratched is 0 on
; the emulator's host folder whether it scratched one or not)
Scratch:
	lda nameLen
	pha
	ldy #2                  ; "name,S,R"
@d:	lda kName,y
	sta kName-2,y
	iny
	cpy nameLen
	bne @d
	dey
	dey
	sty nameLen
	lda #','
	ldx #'S'
	jsr Add2
	lda #','
	ldx #'R'
	jsr Add2
	lda #12
	jsr DosOpen
	pla
	cpx #0
	bne @r                  ; not there
	pha
	lda #12
	jsr DosClose
	pla
	sta nameLen             ; "S:name" again
	ldy nameLen
@u:	dey
	cpy #2
	bcc @s
	lda kName-2,y
	sta kName,y
	bra @u
@s:	lda #'S'
	sta kName
	lda #':'
	sta kName+1
	jmp DosCmd
@r:	rts

; "R:" r1 "=" r0 (new = old)
k_FRename:
	stz nameLen
	lda #'R'
	ldx #':'
	jsr Add2
	lda r1L
	ldx r1H
	ldy nameLen
	jsr Append
	lda #'='
	ldx #0
	jsr Add2
	lda r0L
	ldx r0H
	ldy nameLen
	jsr Append
	jmp DosCmd
