; VeraBASIC Run: overlay 9, files and folders (phase 4, DECISIONS V90).
; Overlay 6 (vbui4.s) parses every statement: the arguments are in xi
; (integers), sbufb (the first string) and sbufa (the last) when these
; run; PRINT #, INPUT #, LINE INPUT # and GET # (overlay 6 too) call the
; byte routines here for the "selected" file (f9_sel).
;
; A file is the kernel's stream (FOpen, FAT long names; three at most,
; V68) under a handle of the program's (1-255), with a buffer of its own
; here (FRead and FWrite take a buffer in the caller's bank, V47): 255
; bytes read ahead, or 256 written behind. A "m" file reads ahead too; a
; write after a read seeks the stream back to the program's position
; first. Lines end with LF; read, they end at LF, CR or CR LF. The kernel's
; errors become the program's (ERRFILE: the kernel's code): 50 File not
; found, 51 Too many files, 58 File exists, 57 Disk error.
;
; MIT licence (LICENSE).

NF	= 3                     ; files open at once

.segment "OVERLAY9"
; loaded 0 with the overlay: the first start's f9_closeall reads them
; before anything wrote them (V106: RAM's power-on bytes)
fnum:	.byte 0, 0, 0           ; the program's handle (0: the slot is free)
fdir:	.byte 0                 ; 1: DIR$'s listing is open
.assert NF = 3, error, "fnum: NF bytes"

.segment "OVL9BSS"
fkh:	.res NF                 ; the kernel's
fmod:	.res NF                 ; 'r', 'w', 'm'
fst:	.res NF                 ; the buffer: 0 empty, 1 read ahead (frp .. frn), 2 written (frn bytes)
frn:	.res NF
frp:	.res NF
fcol:	.res NF                 ; PRINT's column
fpl:	.res NF                 ; the position (24 bits)
fpm:	.res NF
fph:	.res NF
fel:	.res NF                 ; the file's end (its size: the DOS's at the open, the
                                ; writes past it; the DOS's tell fails once a read met the end)
fem:	.res NF
feh:	.res NF
cur:	.res 1                  ; the selected file's slot
fend:	.res NF                 ; 1: a read met the stream's end (the host folder's DOS then
                                ; seeks no more: the file is opened again for SEEK)
fname:	.res NF * 80            ; the names (as cmdname makes them)
fquiet:	.res 1                  ; 1: the kernel's errors not raised (the program has ended)
fpath:	.res 70
fpat:	.res 64                 ; DIR$'s pattern (matched here: the host folder's DOS lists all)
gpi:	.res 1                  ; (the match)
gsi:	.res 1
gst:	.res 1
gmk:	.res 1
gmkn:	.res 1
fbuf:	.res NF * 256
; PICTURE$
PSTR	= 16                    ; a picture's rows: 16 bytes (128 pixels) at most
PROWS	= 160
ppw:	.res 1                  ; the width (cards), the height
pph:	.res 1
pqa:	.res 2
pqb:	.res 2
pqc:	.res 2
pqw:	.res 1                  ; the width (pixels)
plim:	.res 1                  ; (setrow: the pixels taken)
fgh:	.res 1                  ; PICTURE$(file$): the file, its bytes read ahead
fgn:	.res 1
fgp:	.res 1
fgbuf:	.res 64
praw:	.res PSTR * PROWS       ; a picture's rows

.segment "OVERLAY9"

g9run:	jmp (r14)

;---------------------------------------------------------------
; errors
;---------------------------------------------------------------
; the kernel's error x: the program's, ERRFILE = x
kerror:	stx kerr
	lda #E_FNF
	cpx #FILE_NOT_FOUND
	beq @r
	lda #E_FMANY
	cpx #TOO_MANY_FILES
	beq @r
	lda #E_FEXIST
	cpx #FILE_EXISTS
	beq @r
	lda #E_DISK
@r:	jmp raise
; x = 0, else the error
kcheck:	cpx #0
	bne @e
	rts
@e:	lda fquiet
	beq kerror
	rts

;---------------------------------------------------------------
; the files
;---------------------------------------------------------------
; a = the program's handle -> x its slot, carry clear; carry set: not open
fslot:	ldx #NF - 1
@l:	cmp fnum,x
	beq @y
	dex
	bpl @l
	sec
	rts
@y:	clc
	rts

; p2 = slot x's buffer
fbufp:	lda #<fbuf
	sta p2
	txa
	clc
	adc #>fbuf
	sta p2+1
	rts

; slot x's written bytes out (x kept)
flush:	lda fst,x
	cmp #2
	bne @r
	stz fst,x
	lda frn,x
	beq @r
	phx
	jsr fbufp
	MoveW p2, r0
	lda frn,x
	sta r1L
	stz r1H
	stz frn,x
	lda fkh,x
	jsr FWrite
	jsr kcheck
	plx
@r:	rts

; sbufb's name into sbounce; with a "/" in it in CMD's syntax: "dir/name"
; as "/dir/:name", "/dir/name" as "//dir/:name" (the folders from the
; current one, or from the top), 64 characters at most so made (the
; kernel's name holds 70 with the mode's: File not found)
cmdname:
	ldx #$FF                ; the last "/"
	ldy #0
@f:	lda sbufb,y
	beq @fd
	cmp #'/'
	bne @f1
	tya
	tax
@f1:	iny
	bra @f
@fd:	cpx #$FF
	bne @p
	ldy #0                  ; none: as it is
@c:	lda sbufb,y
	sta sbounce,y
	beq @r
	iny
	bra @c
@r:	rts
@p:	stx t3
	lda #'/'
	sta sbounce
	ldy #0
	ldx #1
	lda t3                  ; ("/name": "//:name")
	bne @d
	sta sbounce+2
	lda #'/'
	sta sbounce+1
	lda #':'
	sta sbounce+2
	ldx #3
	iny
	bra @n
@d:	cpy t3                  ; the folders (a "/" first: "//")
	beq @dd
	lda sbufb,y
	sta sbounce,x
	inx
	iny
	bra @d
@dd:	lda #'/'
	sta sbounce,x
	inx
	lda #':'
	sta sbounce,x
	inx
	iny                     ; the name after the "/"
@n:	lda sbufb,y
	sta sbounce,x
	beq @r9
	inx
	iny
	cpx #65
	bcc @n
	ldx #FILE_NOT_FOUND     ; (the kernel's name: 70 characters with the mode's)
	jmp kerror
@r9:	rts

; p2 = slot x's name (80 bytes a slot; x kept)
fnamep:	txa
	asl a
	asl a
	sta p2                  ; x * 16, + x * 64
	asl a
	asl a
	clc
	adc p2
	clc
	adc #<fname
	sta p2
	lda #>fname
	adc #0
	sta p2+1
	rts

; slot x's stream to the program's position (the read ahead dropped); a
; stream whose end a read met opened again first
fseekp:	stz fst,x
	lda fend,x
	beq @s
	stz fend,x
	phx
	lda fkh,x
	jsr FClose
	plx
	phx
	jsr fnamep
	ldy #0                  ; (the name below $A000)
@c:	lda (p2),y
	sta sbounce,y
	beq @o
	iny
	bra @c
@o:	LoadW r0, sbounce
	lda fmod,x
	cmp #'r'
	beq @r
	lda #'m'                ; ("w": its bytes written already, kept)
@r:	jsr FOpen
	jsr kcheck
	plx
	sta fkh,x
@s:	phx
	lda fpl,x
	sta r0L
	lda fpm,x
	sta r0H
	lda fph,x
	sta r1L
	stz r1H
	lda fkh,x
	jsr FSeek
	jsr kcheck
	plx
	rts

; slot x closed (written out first)
fclose1:
	lda fnum,x
	beq @r
	phx
	jsr flush
	plx
	stz fnum,x
	phx
	lda fkh,x
	jsr FClose
	plx
@r:	rts

; every file closed, DIR$'s listing too (a program's end and start)
f9_closeall:
	lda #1
	sta fquiet              ; (an error writing out is not raised here)
	ldx #NF - 1
@l:	phx
	jsr fclose1
	plx
	dex
	bpl @l
	stz fquiet
	lda fdir
	beq @r
	stz fdir
	lda #0                  ; FClose 0: the listing (and streams of nobody's)
	jsr FClose
@r:	rts

; OPEN #h, name$, mode$
f9_open:
	lda xi+1
	bne @num
	lda xi
	beq @num
	jsr fslot
	bcs @1
	ERR E_FOPEN
@num:	ERR E_FNUM
@1:	lda xi+5                ; the mode: one letter
	bne @mode
	lda xi+4
	cmp #1
	bne @mode
	lda sbufa
	ora #$20
	cmp #'r'
	beq @2
	cmp #'w'
	beq @2
	cmp #'m'
	beq @2
@mode:	ERR E_FMODE
@2:	sta t2
	ldx #NF - 1             ; a free slot
@f:	lda fnum,x
	beq @3
	dex
	bpl @f
	ldx #TOO_MANY_FILES
	jmp kerror
@3:	phx
	jsr cmdname             ; sbounce: the name, a path in CMD's syntax
	lda t2                  ; "m": the file must be there (the host
	cmp #'m'                ; folder's DOS opens a missing one)
	bne @4
	LoadW r0, sbounce
	lda #'r'
	jsr FOpen
	jsr kcheck
	jsr FClose
@4:	LoadW r0, sbounce
	lda t2
	jsr FOpen
	jsr kcheck
	plx
	sta fkh,x
	jsr fnamep              ; its name kept
	ldy #0
@nm:	lda sbounce,y
	sta (p2),y
	beq @nm9
	iny
	bra @nm
@nm9:	stz fend,x
	lda xi
	sta fnum,x
	lda t2
	sta fmod,x
	stz fst,x
	stz frn,x
	stz frp,x
	stz fcol,x
	stz fpl,x
	stz fpm,x
	stz fph,x
	stz fel,x
	stz fem,x
	stz feh,x
	cmp #'w'
	beq @r
	phx                     ; its size
	lda fkh,x
	jsr FSize
	jsr kcheck
	plx
	lda r0L
	sta fel,x
	lda r0H
	sta fem,x
	lda r1L
	sta feh,x
@r:	rts

; CLOSE [#h, ...]: those (none: all); one not open is no error
f9_close:
	lda xi_n
	bne @some
	ldx #NF - 1
@a:	phx
	jsr fclose1
	plx
	dex
	bpl @a
	rts
@some:	ldy #0
@l:	cpy xi_n
	beq @r
	phy
	tya
	asl a
	tay
	lda xi+1,y
	bne @n
	lda xi,y
	beq @n
	jsr fslot
	bcs @n
	jsr fclose1
@n:	ply
	iny
	bra @l
@r:	rts

; the file of handle n0 selected (cur): n1 = 0 to read, 1 to write
f9_sel:	lda n0
	jsr fslot
	bcc @1
	lda n0
	bne @no
	ERR E_FNUM
@no:	ERR E_FNOPEN
@1:	stx cur
	lda fmod,x
	ldy n1
	bne @w
	cmp #'w'
	beq @bad
	rts
@w:	cmp #'r'
	beq @bad
	rts
@bad:	ERR E_FMODE

; the position (slot x) one on
pos_inc:
	inc fpl,x
	bne @r
	inc fpm,x
	bne @r
	inc fph,x
@r:	rts

; a byte (a) to the selected file
wbyte:	ldx cur
	pha
	lda fst,x
	cmp #1
	bne @1
	lda frp,x               ; ("m": read ahead, the stream past the position)
	cmp frn,x
	beq @0
	jsr fseekp
@0:	stz fst,x
@1:	lda fst,x
	bne @2
	lda #2
	sta fst,x
	stz frn,x
@2:	jsr fbufp
	ldy frn,x
	pla
	sta (p2),y
	cmp #10
	beq @c0
	inc fcol,x
	bne @c1
	dec fcol,x              ; (255 at most)
	bra @c1
@c0:	stz fcol,x
@c1:	inc frn,x
	bne @3
	lda #0                  ; 256 bytes: out (frn 0 is 256 here)
	sta r1L
	lda #1
	sta r1H
	MoveW p2, r0
	stz fst,x
	phx
	lda fkh,x
	jsr FWrite
	jsr kcheck
	plx
@3:	jsr pos_inc
	lda fph,x               ; past the end: the end
	cmp feh,x
	bcc @r
	bne @e
	lda fpm,x
	cmp fem,x
	bcc @r
	bne @e
	lda fpl,x
	cmp fel,x
	bcc @r
@e:	lda fpl,x
	sta fel,x
	lda fpm,x
	sta fem,x
	lda fph,x
	sta feh,x
@r:	rts

; PRINT #'s parts: t0 bytes of sbufa, t2 of numbuf and a blank, a new
; line, blanks to column t2, t2 blanks; x = the column
f9_wbuf:
	ldy #0
@l:	cpy t0
	beq @r
	phy
	lda sbufa,y
	jsr wbyte
	ply
	iny
	bra @l
@r:	rts
f9_wnum:
	ldy #0
@l:	cpy t2
	beq @b
	phy
	lda numbuf,y
	jsr wbyte
	ply
	iny
	bra @l
@b:	lda #' '
	jmp wbyte
f9_wnl:	lda #10
	jmp wbyte
f9_col:	ldx cur
	lda fcol,x
	tax
	rts
f9_pad:	ldx cur
	lda fcol,x
	cmp t2
	bcs @r
	lda #' '
	jsr wbyte
	bra f9_pad
@r:	rts
f9_spc:	lda t2
	beq @r
	lda #' '
	jsr wbyte
	dec t2
	bra f9_spc
@r:	rts

; PUT #h, s$: its bytes, nothing added
f9_put:	lda xi+1
	beq @1
	ERR E_FNUM
@1:	lda xi
	sta n0
	lda #1
	sta n1
	jsr f9_sel
	lda xi+2
	sta t0
	jmp f9_wbuf

; the next byte of the selected file: a, carry clear; carry set at its end
rbyte:	ldx cur
	lda fst,x
	cmp #1
	beq @1
	jsr flush               ; ("m": written behind, then read)
	lda #1
	sta fst,x
	stz frn,x
	stz frp,x
@1:	lda frp,x
	cmp frn,x
	bne @2
	jsr fbufp               ; read ahead: 255 bytes
	MoveW p2, r0
	lda #255
	sta r1L
	stz r1H
	stz frp,x
	stz frn,x
	phx
	lda fkh,x
	jsr FRead               ; (at the end the DOS's status is an error,
	plx                     ; DOS_ERROR: the bytes read count)
	lda r1L
	sta frn,x
	cmp #255
	beq @f
	lda #1                  ; the stream's end
	sta fend,x
@f:	lda frn,x
	bne @2
	sec                     ; the end
	rts
@2:	jsr fbufp
	ldy frp,x
	inc frp,x
	jsr pos_inc
	lda (p2),y
	clc
	rts
; the last byte read given back (it is still in the buffer)
runget:	ldx cur
	dec frp,x
	lda fpl,x
	bne @1
	lda fpm,x
	bne @2
	dec fph,x
@2:	dec fpm,x
@1:	dec fpl,x
	rts

; the next line of the selected file into inbuf (inp_len, inp_pos 0): to
; LF, CR or CR LF, 255 bytes at most; Input past end at the file's end
f9_rline:
	stz inp_len
	stz inp_pos
	jsr rbyte
	bcc @c
	ERR E_FEND
@l:	jsr rbyte
	bcs @r
@c:	cmp #10
	beq @r
	cmp #13
	beq @cr
	ldx inp_len
	sta inbuf,x
	inc inp_len
	lda inp_len
	cmp #255
	bne @l
@r:	rts
@cr:	jsr rbyte
	bcs @r
	cmp #10
	beq @r
	jmp runget

; GET #h, v$, n: up to t2 bytes into sbufa (t0 of them)
f9_get:	stz t0
@l:	lda t0
	cmp t2
	beq @r
	jsr rbyte
	bcs @r
	ldx t0
	sta sbufa,x
	inc t0
	bra @l
@r:	rts

; the slot of handle xi (open), x
xslot:	lda xi+1
	bne @n
	lda xi
	beq @n
	jsr fslot
	bcs @no
	rts
@n:	ERR E_FNUM
@no:	ERR E_FNOPEN

; SEEK #h, position (24 bits: xi + 2 .. xi + 4)
f9_seek:
	jsr xslot
	jsr flush
	lda xi+2
	sta fpl,x
	lda xi+3
	sta fpm,x
	lda xi+4
	sta fph,x
	jmp fseekp

; LOF(h), LOC(h): ac0-ac2
f9_loc:	jsr xslot
	lda fpl,x
	sta ac0
	lda fpm,x
	sta ac1
	lda fph,x
	sta ac2
	rts
f9_lof:	jsr xslot
	lda fel,x
	sta ac0
	lda fem,x
	sta ac1
	lda feh,x
	sta ac2
	rts

; EOF(h): -1 at the end ("w": always), else 0
f9_eof:	jsr xslot
	stx cur
	lda fmod,x
	cmp #'w'
	beq @y
	jsr rbyte
	bcs @y
	jsr runget
	stz ac0
	stz ac1
	rts
@y:	lda #$FF
	sta ac0
	sta ac1
	rts

;---------------------------------------------------------------
; folders
;---------------------------------------------------------------
; KILL name$
f9_kill:
	LoadW r0, sbufb
	jsr FDelete
	jmp kcheck
; NAME old$ AS new$
f9_name:
	LoadW r0, sbufb
	LoadW r1, sbufa
	jsr FRename
	jmp kcheck
f9_mkdir:
	LoadW r0, sbufb
	jsr MkDir
	jmp kcheck
; RMDIR path$: the folder must be there and empty (checked here: the
; host folder's DOS says 63 for a full one, the card's nothing; a missing
; one 62 here, nothing there)
f9_rmdir:
	jsr cpath
	LoadW r0, sbounce
	jsr ChDir
	jsr kcheck
	stz fdir                ; (DIR$'s listing replaced)
	stz t3                  ; its entries but "." and ".."
	lda #'*'
	sta sbounce+128
	stz sbounce+129
	LoadW r0, sbounce+128
	jsr DirOpen
	cpx #0
	bne @back
@l:	LoadW r0, sbounce
	jsr DirNext
	cpx #0
	bne @back               ; (the end: the kernel closed it)
	lda sbounce+3
	cmp #'.'
	bne @full
	lda sbounce+4
	beq @l
	cmp #'.'
	bne @full
	lda sbounce+5
	beq @l
@full:	inc t3
	bra @l
@back:	ldx #0                  ; back to curDirName
	lda curDirName
	cmp #'/'
	beq @c
	lda #'/'
	sta sbounce
	stz sbounce+1
	bra @cd
@c:	lda curDirName,x
	sta sbounce,x
	beq @cd
	inx
	bra @c
@cd:	LoadW r0, sbounce
	jsr ChDir
	jsr kcheck
	lda t3
	beq @rd
	ldx #DOS_ERROR          ; not empty
	jmp kerror
@rd:	LoadW r0, sbufb
	jsr RmDir
	jmp kcheck

; CHDIR path$: the folder made current, and curDirName (the path programs
; keep, V71) with it: the path from "/", or from curDirName; ".." up
f9_chdir:
	jsr cpath
	LoadW r0, sbounce
	jsr ChDir
	jsr kcheck
	ldx #0
@cc:	lda sbounce,x
	sta curDirName,x
	beq @r
	inx
	bra @cc
@r:	rts

; sbufb's path from "/" (or curDirName's) into fpath and sbounce
cpath:	ldx #0                  ; fpath = the start
	lda sbufb
	cmp #'/'
	beq @abs
	lda curDirName
	cmp #'/'
	bne @abs
@c:	lda curDirName,x
	sta fpath,x
	beq @p
	inx
	cpx #63
	bcc @c
	jmp @long
@abs:	stz fpath
	ldx #0
@p:	cpx #1                  ; ("/" alone: nothing)
	bne @p1
	dex
	stz fpath
@p1:	stx t2                  ; its length
	ldy #0                  ; each part of sbufb
@part:	lda sbufb,y
	beq @done
	cmp #'/'
	bne @w
	iny
	bra @part
@w:	sty t3                  ; the part from y to "/" or the end
@e:	lda sbufb,y
	beq @pe
	cmp #'/'
	beq @pe
	iny
	bra @e
@pe:	tya
	sec
	sbc t3
	cmp #1
	bne @dd
	ldx t3
	lda sbufb,x
	cmp #'.'
	beq @part               ; "."
	bra @add
@dd:	cmp #2
	bne @add
	ldx t3
	lda sbufb,x
	cmp #'.'
	bne @add
	lda sbufb+1,x
	cmp #'.'
	bne @add
	ldx t2                  ; "..": the last part off
@u:	cpx #0
	beq @u1
	dex
	lda fpath,x
	cmp #'/'
	bne @u
@u1:	stx t2
	stz fpath,x
	bra @part
@add:	ldx t2                  ; "/" and the part
	lda #'/'
	sta fpath,x
	inx
	phy
	ldy t3
@a:	cpx #63
	bcs @long
	lda sbufb,y
	beq @a1
	cmp #'/'
	beq @a1
	sta fpath,x
	inx
	iny
	bra @a
@a1:	ply
	stx t2
	stz fpath,x
	bra @part
@long:	ERR E_LONG
@done:	ldx t2                  ; the top: "/"
	bne @go
	lda #'/'
	sta fpath
	stz fpath+1
@go:	ldx #0
@cb:	lda fpath,x             ; to sbounce (the kernel reads below $A000)
	sta sbounce,x
	beq @cd
	inx
	bra @cb
@cd:	rts

; CURDIR$: curDirName ("/" when not set)
f9_curdir:
	ldx #0
	lda curDirName
	cmp #'/'
	beq @c
	lda #'/'
	sta sbufa
	lda #1
	sta t0
	rts
@c:	lda curDirName,x
	beq @r
	sta sbufa,x
	inx
	cpx #63
	bcc @c
@r:	stx t0
	rts

; DIR$(pattern$): the listing started, its first name; DIR$(): the next;
; "" at the end. A folder's name ends with "/"; "." and ".." are left out
f9_dir:	lda xi_n
	beq @next
	ldx #0                  ; the pattern kept
@pc:	lda sbufb,x
	sta fpat,x
	beq @po
	inx
	cpx #63
	bcc @pc
	stz fpat,x
@po:	lda #'*'                ; every entry listed (DirOpen closes a listing still open)
	sta sbounce
	stz sbounce+1
	LoadW r0, sbounce
	jsr DirOpen
	jsr kcheck
	lda #1
	sta fdir
@next:	stz t0
	lda fdir
	beq @r
	LoadW r0, sbounce
	jsr DirNext
	cpx #0
	beq @1
	stz fdir                ; the end (the kernel closed it)
@r:	rts
@1:	lda sbounce+3           ; "." and ".."
	cmp #'.'
	bne @2
	lda sbounce+4
	beq @next
	cmp #'.'
	bne @2
	lda sbounce+5
	beq @next
@2:	jsr gmatch
	bcc @next
	ldx #0
@c:	lda sbounce+3,x
	beq @d
	sta sbufa,x
	inx
	cpx #63
	bcc @c
@d:	lda sbounce
	cmp #'D'
	bne @e
	lda #'/'
	sta sbufa,x
	inx
@e:	stx t0
	rts

; carry set if the name at sbounce + 3 matches fpat ("*" any run, "?"
; any one; letters in either case)
gmatch:	stz gpi
	stz gsi
	lda #$FF
	sta gst
@l:	ldx gsi
	lda sbounce+3,x
	beq @end
	ldy gpi
	lda fpat,y
	beq @back
	cmp #'*'
	beq @star
	cmp #'?'
	beq @one
	jsr glow
	sta gmk+0               ; (the pattern's, in lower case)
	lda sbounce+3,x
	jsr glow
	cmp gmk
	bne @back
@one:	inc gpi
	inc gsi
	bra @l
@star:	sty gst
	inc gpi
	stx gmk                 ; (the name's place for the star)
	lda gmk
	sta gmkn
	bra @l
@back:	lda gst
	cmp #$FF
	beq @no
	inc a
	sta gpi
	inc gmkn
	lda gmkn
	sta gsi
	bra @l
@end:	ldy gpi
@e:	lda fpat,y
	beq @yes
	cmp #'*'
	bne @no
	iny
	bra @e
@yes:	sec
	rts
@no:	clc
	rts
glow:	cmp #'A'
	bcc @r
	cmp #'Z' + 1
	bcs @r
	ora #$20
@r:	rts

; FOLDER$(DOCS | APPS | FONTS | SYSTEM | DATA): the card's folders (V71)
f9_folder:
	lda xi+1
	bne @ill
	ldx xi
	beq @ill
	cpx #6
	bcs @ill
	lda fol_l-1,x
	sta p2
	lda fol_h-1,x
	sta p2+1
	ldy #0
@c:	lda (p2),y
	beq @r
	sta sbufa,y
	iny
	bra @c
@r:	sty t0
	rts
@ill:	ERR E_ILLQ
fol_l:	.byte <fol1, <fol2, <fol3, <fol4, <fol5
fol_h:	.byte >fol1, >fol2, >fol3, >fol4, >fol5
fol1:	.byte VR_DOCSDIR, 0
fol2:	.byte VR_APPSDIR, 0
fol3:	.byte VR_FONTSDIR, 0
fol4:	.byte VR_SYSDIR, 0
fol5:	.byte VR_DATADIR, 0

; DOCUMENT$: the document a made application was opened with (DECISIONS
; V99: its whole name, dataLongName; main.c's _vb_appdoc set); VeraBASIC Run
; is opened with the program itself: ""
.import _vb_appdoc
f9_document:
	ldy #0
	lda _vb_appdoc
	beq @r
@c:	lda dataLongName,y
	beq @r
	sta sbufa,y
	iny
	cpy #63
	bne @c
@r:	sty t0
	rts

;---------------------------------------------------------------
; PICTURE$ (overlay 6, vbui4.s): a picture made from a file or DATA items
; (a string: its width in cards, its height, the bitmap compacted as
; BitmapUp reads it: repeats of 3-127, runs of up to 91 bytes as they are;
; tools/vbveranda2.py compact packs the same bytes)
;---------------------------------------------------------------
; PICTURE$(file$) (t3 1) | PICTURE$(DATA): rows of "#" and "."
f9_picture:
	jsr pclear
	lda t3
	jne pfile
	lda xi+1                ; DATA (5)
	bne @ill
	lda xi
	cmp #5
	bne @ill
	jsr ditem_n             ; the width
	cmp #129
	bcs @bad
	cmp #1
	bcc @bad
	sta pqw
	jsr ditem_n             ; the height
	cmp #PROWS + 1
	bcs @bad
	cmp #1
	bcc @bad
	sta pph
	lda pqw
	sta plim
	stz pqb                  ; the rows
@row:	lda pqb
	cmp pph
	beq @done
	jsr ditem               ; sbufa, t0
	jsr setrow
	inc pqb
	bra @row
@done:	jmp pack
@ill:	ERR E_ILLQ
@bad:	ERR E_PICT
; praw cleared, pqw (the width in pixels) 0
pclear:	LoadW p1, praw
	ldx #>(PSTR * PROWS)
	ldy #0
	tya
@p:	sta (p1),y
	iny
	bne @p
	inc p1+1
	dex
	bne @p
	stz pqw
	rts
; sbufa's t0 characters as row pqb (at most pqw of them)
setrow:	lda pqb
	asl a
	asl a
	asl a
	asl a
	sta p1
	lda pqb
	lsr a
	lsr a
	lsr a
	lsr a
	sta p1+1
	lda p1
	clc
	adc #<praw
	sta p1
	lda p1+1
	adc #>praw
	sta p1+1
	ldy #0
@c:	cpy t0
	beq @r
	cpy plim
	beq @r
	lda sbufa,y
	cmp #'#'
	bne @n
	tya
	lsr a
	lsr a
	lsr a
	sta pqa                  ; its byte
	tya
	and #7
	tax
	lda bits,x
	phy
	ldy pqa
	ora (p1),y
	sta (p1),y
	ply
@n:	iny
	bra @c
@r:	rts
bits:	.byte $80, $40, $20, $10, $08, $04, $02, $01

; PICTURE$(file$): every line of only "#" and "." a row (tile.txt's
; "colour" line left out); the width the longest
pfile:	LoadW r0, sbufb
	lda #'r'
	jsr FOpen
	cpx #0
	beq @o
	jmp kerror
@o:	sta fgh
	stz fgn
	stz fgp
	stz pqb                  ; the rows
	lda #128
	sta plim
	stz t0
@l:	jsr fgetc
	bcs @eof
	cmp #10
	beq @eol
	cmp #13
	beq @eol
	ldx t0
	cpx #128
	bcs @l                  ; (too long: the rest left out)
	sta sbufa,x
	inc t0
	bra @l
@eol:	jsr prow1
	bra @l
@eof:	jsr prow1
	lda fgh
	jsr FClose
	lda pqb
	beq @bad
	sta pph
	lda pqw
	beq @bad
	jmp pack
@bad:	ERR E_PICT
; the line in sbufa (t0): a row if it is only "#" and "."
prow1:	ldx t0
	beq @r
	ldy #0
@c:	lda sbufa,y
	cmp #'#'
	beq @n
	cmp #'.'
	bne @no
@n:	iny
	cpy t0
	bne @c
	lda pqb
	cmp #PROWS
	bcs @no
	lda t0
	cmp pqw
	bcc @w
	sta pqw
@w:	jsr setrow
	inc pqb
@no:	stz t0
@r:	rts
; the next byte of the file: a, carry set at its end (64 bytes read ahead)
fgetc:	ldx fgp
	cpx fgn
	bne @b
	LoadW r0, fgbuf
	LoadW r1, 64
	lda fgh
	jsr FRead
	lda r1L
	sta fgn
	stz fgp
	bne fgetc
	sec
	rts
@b:	lda fgbuf,x
	inc fgp
	clc
	rts

; praw's rows (pqw pixels wide, pph of them) compacted into sbufa: the
; header, then repeats of 3-127 (count, byte) and runs of up to 91 bytes
; as they are (128 + count, the bytes); t0 its length
pack:	lda pqw                 ; the width in cards
	clc
	adc #7
	lsr a
	lsr a
	lsr a
	sta ppw
	; the rows close up: ppw bytes each, from praw on
	LoadW p0, praw          ; to
	LoadW p1, praw          ; from (PSTR a row)
	ldx pph
@r:	ldy #0
@rb:	lda (p1),y
	sta (p0),y
	iny
	cpy ppw
	bne @rb
	lda p0
	clc
	adc ppw
	sta p0
	bcc @r1
	inc p0+1
@r1:	lda p1
	clc
	adc #PSTR
	sta p1
	bcc @r2
	inc p1+1
@r2:	dex
	bne @r
	MoveW p0, n1            ; the end
	lda ppw
	sta sbufa
	lda pph
	sta sbufa+1
	lda #2
	sta t0
	LoadW p0, praw          ; i
@next:	lda p0                  ; i < end?
	cmp n1
	lda p0+1
	sbc n1+1
	bcc @1
	rts
@1:	jsr runlen              ; a = the repeats at p0 (127 at most)
	cmp #3
	bcc @lit
	pha
	jsr out1
	lda (p0)
	jsr out1
	pla
	clc
	adc p0
	sta p0
	bcc @next
	inc p0+1
	bra @next
@lit:	MoveW p0, p1            ; j: a run of bytes as they are
	stz pqa                  ; its count
@lj:	lda p1
	cmp n1
	lda p1+1
	sbc n1+1
	bcs @le
	lda pqa
	cmp #91
	beq @le
	MoveW p1, n0
	jsr runlen3             ; a run of 3 at j ends it
	cmp #3
	bcs @le
	inc pqa
	inc p1
	bne @lj
	inc p1+1
	bra @lj
@le:	lda pqa
	ora #128
	jsr out1
	ldy #0
@lc:	cpy pqa
	beq @l9
	lda (p0),y
	jsr out1
	iny
	bra @lc
@l9:	MoveW p1, p0
	jmp @next
; the repeats of the byte at p0 (to n1, 127 at most): a
runlen:	MoveW p0, n0
	ldx #127
	bra rl
; the same at n0, 3 at most
runlen3:
	ldx #3
rl:	stx pqa+1
	lda (n0)
	sta pqc
	ldy #1
@l:	cpy pqa+1
	beq @d
	tya
	clc
	adc n0
	sta pqb
	lda n0+1
	adc #0
	cmp n1+1
	bcc @in
	bne @d
	lda pqb
	cmp n1
	bcs @d
@in:	lda (n0),y
	cmp pqc
	bne @d
	iny
	bra @l
@d:	tya
	rts
; a to sbufa at t0 (String too long past 255)
out1:	ldx t0
	sta sbufa,x
	inc t0
	beq @long
	rts
@long:	ERR E_LONG

;---------------------------------------------------------------
; DATA items (as READ takes them: tools/vbasic.py s_read)
;---------------------------------------------------------------
; the next item's text, blanks off, a string's quotes off: sbufa, t0
ditem:	lda dataptr
	cmp _ndata
	lda dataptr+1
	sbc _ndata+1
	bcc @1
	ERR E_DATA
@1:	lda dataptr             ; its offset: the index (mbank)
	asl a
	sta p2
	lda dataptr+1
	rol a
	ora #$A0
	sta p2+1
	lda _mbank
	sta xb
	ldy #0
	jsr fpeek
	sta n0
	iny
	jsr fpeek
	sta n0+1
	inc dataptr
	bne @2
	inc dataptr+1
@2:	lda n0+1                ; the item: TAG_DATA, length, text
	jsr div31
	clc
	adc #$A0
	sta p2+1
	txa
	clc
	adc _pbase
	sta xb
	lda n0
	sta p2
	ldy #1
	jsr fpeek
	sta pqa                  ; its length
	ldx #0
	ldy #2
@c:	cpx pqa
	beq @t
	jsr fpeek
	sta sbufa,x
	inx
	iny
	bra @c
@t:	stx t0                  ; the blanks off: the end
@te:	ldx t0
	beq @tb
	lda sbufa-1,x
	cmp #' '
	bne @tb
	dec t0
	bra @te
@tb:	ldx #0                  ; the start
@ts:	cpx t0
	beq @sh
	lda sbufa,x
	cmp #' '
	bne @sh
	inx
	bra @ts
@sh:	stx pqa
	ldy #0                  ; moved down
@m:	cpx t0
	beq @md
	lda sbufa,x
	sta sbufa,y
	inx
	iny
	bra @m
@md:	sty t0
	lda t0                  ; a string's quotes
	beq @r
	lda sbufa
	cmp #'"'
	bne @r
	ldx #1
	ldy #0
@q:	cpx t0
	beq @qd
	lda sbufa,x
	cmp #'"'
	beq @qd
	sta sbufa,y
	inx
	iny
	bra @q
@qd:	sty t0
@r:	rts
; the next item as a number 0-255: a
ditem_n:
	jsr ditem
	lda t0
	bne @1
	lda #0
	rts
@1:	PCALL pnum1
	bcc @2
	ERR E_TYPE
@2:	PCALL toint
	lda ac1
	beq @3
	ERR E_PICT
@3:	lda ac0
	rts
