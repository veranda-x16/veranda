; VeraBASIC Run: the prepare pass on the X16 (DECISIONS V87), banked
; overlay 3: tools/vbtokens.py's Preparer, line by line as vbtok.s makes
; the line records, then its finish: the uses checked, the names' kinds,
; the locals rewritten, the targets filled, record 0 made. The error
; messages are vbtokens.py's (the first by line is kept).
;
; MIT licence (LICENSE).

.segment "OVERLAY3"

; token classes (decoded)
KC_INT	= 0
KC_FLT	= 1
KC_STR	= 2
KC_VAR	= 3
KC_LREF	= 4
KC_NREF	= 5
KC_REM	= 6
KC_DATA	= 7
KC_BLK	= 8
KC_P	= 9
KC_KW	= 10
; keyword ids: page 1 as the token; page 2 apart
KD_DIALOG = 1
KD_ENDDIALOG = 2
KD_EXT	= 3

; prepare's error ids (after vbtok.s's)
VE_WITHOUT = 11			; A without B
VE_MISSING = 12			; A missing for B in line C
VE_NEXTFOR = 13			; NEXT C does not match FOR D in line A
VE_TWOELSE = 14
VE_ELSEIF = 15
VE_TWOCATCH = 16
VE_AFTERCE = 17
VE_CASEEXP = 18
VE_THENIF = 19
VE_THENEI = 20
VE_INSIDE = 21
VE_PROCIN = 22			; A [D ]inside B C (line num D2)
VE_DEFTWICE = 23
VE_NAMEEXP = 24
VE_PARAM = 25
VE_PTWICE = 26
VE_PAREN = 27
VE_OUTSIDE = 28
VE_OUTPROC = 29
VE_ALOCAL = 30
VE_LOCSH = 31
VE_CTWICE = 32
VE_RETURN = 33
VE_DEFINT = 34
VE_LTWICE = 35
VE_LNTWICE = 36
VE_UNDEFL = 37
VE_BOTH = 38
VE_UNDLAB = 39
VE_UNDSUB = 40
VE_ASSIGN = 41
VE_BUILTIN = 42

K_VAR	= 1
; the test build: the emulator's cycle counter into a (4 bytes)
.macro TCLOCK dst
.ifdef VB_TEST
	lda EMU_CLOCK
	sta dst
	lda EMU_CLOCK+1
	sta dst+1
	lda EMU_CLOCK+2
	sta dst+2
	lda EMU_CLOCK+3
	sta dst+3
.endif
.endmacro
K_BUILTIN = 64
K_ARRAY	= 2
K_CONST	= 4
K_SUB	= 8
K_FUNC	= 16
K_LABEL	= 32
; attribute flags (vbtok.s): byte 0
AF_SCALAR = 1
AF_DIM	= 2
AF_CONST = 4
AF_SUB	= 8
AF_FUNC	= 16
AF_LABEL = 32
AF_PAREN = 64
AF_ASSIGN = 128

F_BYREF	= 1
F_ARRAY	= 2
F_PARAM	= 4
F_RESULT = 8

NTOK	= 250
NSEG	= 128
NSTK	= 24
NEXITS	= 48
NINL	= 16
NFRAME	= 100
NPROC	= 128
NSHARED	= 32

; vt_e's fields: A (+3), B (+5), C (+7), D (+9)
.macro EA lo, hi
	lda lo
	sta vt_e+3
	lda hi
	sta vt_e+4
.endmacro
.macro EB lo, hi
	lda lo
	sta vt_e+5
	lda hi
	sta vt_e+6
.endmacro
.macro EC lo, hi
	lda lo
	sta vt_e+7
	lda hi
	sta vt_e+8
.endmacro
.macro ED lo, hi
	lda lo
	sta vt_e+9
	lda hi
	sta vt_e+10
.endmacro

; (shared by overlays 3 and 4: in main RAM)
.segment "BSS"
nlb:	.res 2			; the lines the end's pass needs (_vt_lb)
nproc:	.res 1
nidx:	.res 2			; the line index's entries (_vt_r2b)
ndata:	.res 2			; the DATA items (_vt_r3b)
nchk:	.res 2			; the uses to check (_vt_cb, 6 bytes each)
nlines:	.res 2
optint:	.res 1
defint:	.res 4
lastsrc: .res 2

;===============================================================
; overlay 3: a line at a time
;===============================================================
.scope P3
.define HBSS "OVL3BSS"
.define HCODE "OVERLAY3"
.include "vbphelp.s"
.undefine HBSS
.undefine HCODE
.segment "OVL3BSS"
nseg:	.res 1
sgs:	.res ::NSEG		; segments: first token, past the last
sge:	.res ::NSEG
seg:	.res 1			; the segment being done
s0:	.res 1			; its first token, past its last
s1:	.res 1
peol:	.res 2			; the line's $00
tg:	.res 2			; setblk's target
at:	.res 2			; setblk's place
first:	.res 1			; first token's index
fid:	.res 1			; its keyword id (0 not a keyword)
bat:	.res 2			; b_at
inl:	.res 1			; one-line IFs open (before this statement)
; one-line IFs of the line
ninl:	.res 1
ia:	.res ::NINL * 2		; their $0B (lo, hi interleaved)
ihe:	.res ::NINL
itg:	.res ::NINL * 2
; the block stack
nstk:	.res 1
bk:	.res ::NSTK		; kind (an opener's id)
bsrc:	.res ::NSTK * 2
bob:	.res ::NSTK * 2		; the opener's $0B
bot:	.res ::NSTK * 2		; the opener
bpb:	.res ::NSTK * 2		; the pending part's $0B
bhe:	.res ::NSTK		; has_else
bec:	.res ::NSTK		; expect_case
bvar:	.res ::NSTK * 2		; FOR's variable ($FFFF none)
bex:	.res ::NSTK		; its EXITs: the first ($FF none)
exn:	.res ::NEXITS		; EXITs: next, the $0B
exa:	.res ::NEXITS * 2
exfree:	.res 1
; the procedures
pcur:	.res 1			; 0 none, else the procedure + 1
ppos:	.res ::NPROC * 2		; its header in _vt_pb
pbtop:	.res 2
psym:	.res 2
pfn:	.res 1			; a FUNCTION
npar:	.res 1
nsh:	.res 1
shs:	.res ::NSHARED * 2
; the rest
firstfor: .res 1
ctx:	.res 1
nseen:	.res 1
inproc:	.res 1
nni:	.res 1
ck:	.res 1
da:	.res 1
db:	.res 1

.segment "OVERLAY3"

;---------------------------------------------------------------
; the start: nothing open
;---------------------------------------------------------------
prep_init:
	stz nlb
	stz nlb+1
	stz nstk
	stz ninl
	stz pcur
	stz nproc
	stz pbtop
	lda #$A0
	sta pbtop+1
	stz nidx
	stz nidx+1
	stz ndata
	stz ndata+1
	stz nchk
	stz nchk+1
	stz nlines
	stz nlines+1
	stz optint
	stz defint
	stz defint+1
	stz defint+2
	stz defint+3
	stz nsh
	; the EXITs' free list
	ldx #0
@e:	txa
	inc a
	sta exn,x
	inx
	cpx #NEXITS
	bne @e
	lda #$FF
	sta exn+NEXITS-1
	stz exfree
	rts


; ab = the $0B after token x (0: none)
blkof:	stz ab
	stz ab+1
	inx
	cpx nt
	bcs @r
	lda tkt,x
	cmp #KC_BLK
	bne @r
	jsr absof
@r:	dex
	rts


; record 1 at n0 (2 bytes) = pw
r1poke2:
	jsr r1at3
	ldy #0
	lda pw
	jsr fpoke
	inc n0
	bne @1
	inc n0+1
@1:	jsr r1at3
	lda pw+1
	jmp fpoke

; setblk(at, tg): at's two bytes after its tag
setblk:	lda at
	ora at+1
	beq @r
	lda at
	clc
	adc #1
	sta n0
	lda at+1
	adc #0
	sta n0+1
	lda tg
	sta pw
	lda tg+1
	sta pw+1
	jmp r1poke2
@r:	rts







; an error (vt_e: id in a; the fields already set) at vt_src
perr:	sta vt_e
	lda vt_src
	sta vt_e+1
	lda vt_src+1
	sta vt_e+2
	jmp perr2

;---------------------------------------------------------------
; a line (tb, at vt_off): decoded, split, its statements prepared
;---------------------------------------------------------------
prep_line:
	lda vt_src
	sta lastsrc
	lda vt_src+1
	sta lastsrc+1
	lda pcur
	sta inproc		; (in a procedure at the line's start)
	inc nlines
	bne @n0
	inc nlines+1
@n0:	; the line index: (number, offset), sorted
	lda tb+1
	ora tb+2
	beq @nonum
	jsr lidx_add
@nonum:	jsr decode
	; peol
	lda vt_tl
	sec
	sbc #1
	clc
	adc vt_off
	sta peol
	lda vt_off+1
	adc #0
	sta peol+1
	stz ninl
	; segments (and the DATA index)
	stz nseg
	ldy #$FF		; y: cur's first ($FF empty)
	ldx #0
@t:	cpx nt
	jcs @tend
	lda tkt,x
	cmp #KC_DATA
	bne @t1
	jsr data_add
@t1:	lda #':'
	jsr ispc
	bne @t2
	cpy #$FF
	beq @tn
	jsr segpush		; (y .. x)
	ldy #$FF
	bra @tn
@t2:	lda #TK_ELSE
	jsr iskw
	bne @t3
	cpy #$FF
	beq @t2a
	jsr segpush
@t2a:	txa
	tay
	bra @tn
@t3:	lda tkt,x
	cmp #KC_BLK
	bne @t4
	; a $0B right after a lone ELSE
	tya
	inc a
	sta pk
	cpx pk
	bne @t4
	cpy #$FF
	beq @t4
	phx
	tya
	tax
	lda #TK_ELSE
	jsr iskw
	plx
	bne @t4
	inx
	jsr segpush
	dex
	ldy #$FF
	bra @tn
@t4:	cpy #$FF
	bne @t5
	txa
	tay
@t5:	lda #TK_THEN
	jsr iskw
	bne @tn
	inx
	jsr segpush
	dex
	ldy #$FF
@tn:	inx
	jmp @t
@tend:	cpy #$FF
	beq @lab
	jsr segpush
@lab:	; a label line
	stz seg
	lda tb+5
	and #2
	beq @stm
	lda nt
	beq @stm
	lda tkt
	cmp #KC_NREF
	bne @stm
	ldx #0
	jsr tsym
	lda #AF_LABEL
	jsr aflag
	beq @lnew
	ldy #6			; defined twice
	jsr fpeek
	sta vt_e+5
	iny
	jsr fpeek
	sta vt_e+6
	EC psy, psy+1
	EA vt_src, vt_src+1
	lda #VE_LTWICE
	jsr perr
	bra @l2
@lnew:	lda #AF_LABEL
	jsr aor
	ldy #6
	lda vt_src
	jsr fpoke
	iny
	lda vt_src+1
	jsr fpoke
	ldy #2
	lda vt_off
	jsr fpoke
	iny
	lda vt_off+1
	jsr fpoke
@l2:	lda nseg		; segs[0] == [0]: dropped
	beq @stm
	lda sgs
	bne @stm
	lda sge
	cmp #1
	bne @stm
	inc seg
@stm:	lda seg
	cmp nseg
	bcs @inl
	tax
	lda sgs,x
	sta s0
	lda sge,x
	sta s1
	jsr do_stmt
	inc seg
	bra @stm
@inl:	; the one-line IFs' $0B: their ELSE, or the line's end
	ldx #0
@i1:	cpx ninl
	bcs @r
	txa
	asl a
	tay
	lda ia,y
	sta at
	lda ia+1,y
	sta at+1
	lda peol
	sta tg
	lda peol+1
	sta tg+1
	lda ihe,x
	beq @i2
	lda itg,y
	sta tg
	lda itg+1,y
	sta tg+1
@i2:	phx
	jsr setblk
	plx
	inx
	bra @i1
@r:	; the end's pass needs this line: in a procedure, or a name reference
	lda inproc
	ora pcur
	bne @mark
	ldx nt
@nr:	dex
	cpx #$FF
	beq @r2
	lda tkt,x
	cmp #KC_NREF
	bne @nr
@mark:	lda nlb+1
	cmp #$10		; (a bank: 4096 lines; then all)
	bcs @r2
	lda nlb
	asl a
	sta fpp
	lda nlb+1
	rol a
	ora #$A0
	sta fpp+1
	lda _vt_lb
	sta fpb
	ldy #0
	lda vt_off
	jsr fpoke
	iny
	lda vt_off+1
	jsr fpoke
	inc nlb
	bne @r2
	inc nlb+1
@r2:	rts

; a segment: y .. x (exclusive)
segpush:
	phx
	ldx nseg
	cpx #NSEG
	bcs @big
	tya
	sta sgs,x
	pla
	pha
	sta sge,x
	inc nseg
@r:	plx
	rts
@big:	phy
	lda #VE_PROGBIG		; (too many statements in a line for the X16)
	jsr perr
	ply
	bra @r

; the DATA index: token x's offset
data_add:
	phx
	phy
	jsr absof
	lda ndata+1
	cmp #$10		; (4096 items: a bank)
	bcs @big
	lda ndata
	asl a
	sta fpp
	lda ndata+1
	rol a
	ora #$A0
	sta fpp+1
	lda _vt_r3b
	sta fpb
	ldy #0
	lda ab
	jsr fpoke
	iny
	lda ab+1
	jsr fpoke
	inc ndata
	bne @r
	inc ndata+1
@r:	ply
	plx
	rts
@big:	lda #VE_PROGBIG
	jsr perr
	bra @r

; the line index: (tb's number, vt_off) inserted by number; a number
; twice is an error
lidx_add:
	lda nidx+1
	cmp #$08		; (2048 entries: a bank)
	bcc @ok
	lda #VE_PROGBIG
	jmp perr
@ok:	lda _vt_r2b
	sta fpb
	; from the end down: entries above the number move up
	lda nidx
	sta pw
	lda nidx+1
	sta pw+1
@l:	lda pw
	ora pw+1
	jeq @put
	; entry pw - 1
	lda pw
	sec
	sbc #1
	sta pw2
	lda pw+1
	sbc #0
	sta pw2+1
	jsr lix			; fpp = entry pw2
	ldy #1
	jsr fpeek
	cmp tb+2
	jcc @put
	bne @up
	dey
	jsr fpeek
	cmp tb+1
	jcc @put
	beq @twice
@up:	ldy #3			; entry pw2 -> pw
@u:	jsr fpeek
	sta fbuf,y
	dey
	bpl @u
	lda pw
	sta pw2
	lda pw+1
	sta pw2+1
	jsr lix
	ldy #3
@u2:	lda fbuf,y
	jsr fpoke
	dey
	bpl @u2
	lda pw
	bne @d
	dec pw+1
@d:	dec pw
	bra @l
@twice:	; Line number N used twice (lines M and N): M from its record
	ldy #2
	jsr fpeek
	sta n0
	iny
	jsr fpeek
	sta n0+1
	inc n0
	bne @t1
	inc n0+1
@t1:	inc n0
	bne @t2
	inc n0+1
@t2:	inc n0
	bne @t3
	inc n0+1
@t3:	jsr r1at3
	ldy #0
	jsr fpeek
	sta vt_e+5
	inc n0
	bne @t4
	inc n0+1
@t4:	jsr r1at3
	jsr fpeek
	sta vt_e+6
	EA tb+1, tb+2
	ED vt_src, vt_src+1
	lda #VE_LNTWICE
	jsr perr
	rts
@put:	lda pw
	sta pw2
	lda pw+1
	sta pw2+1
	jsr lix
	ldy #0
	lda tb+1
	jsr fpoke
	iny
	lda tb+2
	jsr fpoke
	iny
	lda vt_off
	jsr fpoke
	iny
	lda vt_off+1
	jsr fpoke
	inc nidx
	bne @r
	inc nidx+1
@r:	rts

; fpp = line index entry pw2
lix:	lda pw2
	asl a
	sta fpp
	lda pw2+1
	rol a
	asl fpp
	rol a
	ora #$A0
	sta fpp+1
	rts


;---------------------------------------------------------------
; a statement: tokens s0 .. s1
;---------------------------------------------------------------
do_stmt:
	ldx s0
	stx first
	lda tkt,x
	cmp #KC_REM
	beq @r0
	lda #$27
	jsr ispc
	beq @r0
	lda #TK_REM
	jsr iskw
	bne @go
@r0:	rts
@go:	jsr scan_names
	; SELECT CASE waiting for its CASE
	ldx nstk
	beq @nsel
	lda bk-1,x
	cmp #TK_SELECT_CASE
	bne @nsel
	lda bec-1,x
	beq @nsel
	ldx first
	lda tkt,x
	cmp #KC_KW
	bne @cexp
	lda tkv,x
	cmp #TK_CASE
	beq @nsel
	cmp #TK_CASE_ELSE
	beq @nsel
	cmp #TK_END_SELECT
	beq @nsel
@cexp:	ldx nstk
	stz bec-1,x
	txa
	asl a
	tax
	EA {bsrc-2,x}, {bsrc-1,x}
	lda #VE_CASEEXP
	jsr perr
@nsel:	ldx first
	stz fid
	lda tkt,x
	cmp #KC_KW
	beq @kw
	cmp #KC_VAR
	bne @r0
	lda s1			; an assignment?
	sec
	sbc s0
	cmp #2
	bcc @r0
	jmp check_assign
@kw:	lda tkv,x
	sta fid
	jsr blkof
	lda ab
	sta bat
	lda ab+1
	sta bat+1
	lda ninl
	sta inl
	beq @disp
	; a block word inside a one-line IF
	lda fid
	ldx #0
@ib:	ldy inline_bad,x
	beq @disp
	cmp inline_bad,x
	beq @bad
	inx
	bra @ib
@bad:	sta vt_e+3
	stz vt_e+4
	lda #VE_INSIDE
	jmp perr
@disp:	; the keyword's routine
	lda fid
	ldx #0
@d:	ldy stmt_tab,x
	beq @r
	cmp stmt_tab,x
	beq @j
	inx
	inx
	inx
	bra @d
@j:	lda stmt_tab+1,x
	sta @jj+1
	lda stmt_tab+2,x
	sta @jj+2
@jj:	jmp $FFFF
@r:	rts

inline_bad:
	.byte TK_ELSEIF, TK_END_IF, TK_WHILE, TK_WEND, TK_REPEAT, TK_UNTIL, TK_DO, TK_LOOP
	.byte TK_SELECT_CASE, TK_CASE, TK_CASE_ELSE, TK_END_SELECT, TK_SUB, TK_END_SUB
	.byte TK_FUNCTION, TK_END_FUNCTION, TK_TRY, TK_CATCH, TK_END_TRY, KD_DIALOG
	.byte KD_ENDDIALOG, 0

.macro ST id, rout
	.byte id
	.addr rout
.endmacro
stmt_tab:
	ST TK_IF, s_if
	ST TK_ELSE, s_else
	ST TK_ELSEIF, s_elseif
	ST TK_WHILE, s_open
	ST TK_REPEAT, s_open
	ST TK_DO, s_open
	ST TK_TRY, s_open
	ST KD_DIALOG, s_open
	ST TK_SELECT_CASE, s_open
	ST TK_FOR, s_for
	ST TK_NEXT, s_next
	ST TK_WEND, s_loopend
	ST TK_UNTIL, s_loopend
	ST TK_LOOP, s_loopend
	ST TK_CASE, s_case
	ST TK_CASE_ELSE, s_case
	ST TK_CATCH, s_catch
	ST TK_END_IF, s_endb
	ST TK_END_SELECT, s_endb
	ST TK_END_TRY, s_endb
	ST KD_ENDDIALOG, s_endb
	ST TK_SUB, s_proc
	ST TK_FUNCTION, s_proc
	ST TK_END_SUB, s_endproc
	ST TK_END_FUNCTION, s_endproc
	ST TK_EXIT_FOR, s_exit
	ST TK_EXIT_WHILE, s_exit
	ST TK_EXIT_DO, s_exit
	ST TK_EXIT_REPEAT, s_exit
	ST TK_EXIT_SUB, s_exit
	ST TK_EXIT_FUNCTION, s_exit
	ST TK_LOCAL, s_local
	ST TK_SHARED, s_local
	ST TK_CONST, s_const
	ST TK_DIM, s_dim
	ST TK_REDIM, s_dim
	ST TK_RETURN, s_return
	ST TK_LET, s_let
	ST TK_OPTION, s_option
	ST TK_DEFINT, s_defint
	.byte 0

; the closer of each opener; an EXIT's block
openers:
	.byte TK_IF, TK_END_IF, TK_WHILE, TK_WEND, TK_REPEAT, TK_UNTIL, TK_DO, TK_LOOP
	.byte TK_FOR, TK_NEXT, TK_SELECT_CASE, TK_END_SELECT, TK_SUB, TK_END_SUB
	.byte TK_FUNCTION, TK_END_FUNCTION, TK_TRY, TK_END_TRY, KD_DIALOG, KD_ENDDIALOG, 0
exits:	.byte TK_EXIT_FOR, TK_FOR, TK_EXIT_WHILE, TK_WHILE, TK_EXIT_DO, TK_DO
	.byte TK_EXIT_REPEAT, TK_REPEAT, TK_EXIT_SUB, TK_SUB, TK_EXIT_FUNCTION, TK_FUNCTION, 0
closes:	.byte TK_WEND, TK_WHILE, TK_UNTIL, TK_REPEAT, TK_LOOP, TK_DO
	.byte TK_END_IF, TK_IF, TK_END_SELECT, TK_SELECT_CASE, TK_END_TRY, TK_TRY
	.byte KD_ENDDIALOG, KD_DIALOG, TK_END_SUB, TK_SUB, TK_END_FUNCTION, TK_FUNCTION, 0

; a -> its pair in the table at (pw) (a, b, ...): a = b; 0 if none
pairof:	ldy #0
@l:	pha
	lda (n1),y
	beq @no
	pla
	cmp (n1),y
	beq @f
	iny
	iny
	bra @l
@f:	iny
	lda (n1),y
	rts
@no:	pla
	lda #0
	rts

.macro PAIR tab
	ldy #<tab
	sty n1
	ldy #>tab
	sty n1+1
	jsr pairof
.endmacro

; the names of a statement's segment: line and name uses (checked at the
; end), "(" uses, scalar uses
scan_names:
	stz ctx			; 0 call, 1 goto, 2 def
	ldx s0
@l:	cpx s1
	jcs @r
	lda tkt,x
	cmp #KC_KW
	bne @n1
	lda tkh,x
	jne @nx
	lda tkv,x
	cmp #TK_GOTO
	beq @g
	cmp #TK_GOSUB
	beq @g
	cmp #TK_RESTORE
	beq @g
	cmp #TK_RESUME
	jne @nx
@g:	lda #1
	sta ctx
	jmp @nx
@n1:	cmp #KC_LREF
	bne @n2
	; allow0: ON and ERROR before it in the statement
	stz pk
	phx
	txa
	tay
	ldx s0
@a:	stx pk2
	cpy pk2
	beq @ad
	lda #TK_ON
	jsr iskw
	bne @a1
	lda pk
	ora #1
	sta pk
@a1:	lda #TK_ERROR
	jsr iskw
	bne @a2
	lda pk
	ora #2
	sta pk
@a2:	inx
	bra @a
@ad:	plx
	lda pk
	cmp #3
	beq @a3
	lda #0
	.byte $2C		; (bit: skip the next)
@a3:	lda #1
	sta pk
	lda #1
	jsr chk_add
	bra @nx
@n2:	cmp #KC_NREF
	bne @n3
	cpx #0			; the label itself
	bne @n2a
	lda tb+5
	and #2
	bne @nx
@n2a:	lda ctx
	sta pk
	; the token before it (not a $0B): SUB, FUNCTION, CALL
	phx
@pv:	cpx s0
	beq @pvd
	dex
	lda tkt,x
	cmp #KC_BLK
	beq @pv
	lda #TK_SUB
	jsr iskw
	beq @def
	lda #TK_FUNCTION
	jsr iskw
	beq @def
	lda #TK_CALL
	jsr iskw
	bne @pvd
	stz pk
	bra @pvd
@def:	lda #2
	sta pk
@pvd:	plx
	lda pk
	cmp #2
	beq @nx
	lda #2
	jsr chk_add
	bra @nx
@n3:	cmp #KC_VAR
	bne @nx
	jsr tsym
	inx
	lda #'('
	cpx s1
	bcs @sc
	jsr ispc
	bne @sc
	dex
	lda #AF_PAREN
	jsr aor
	bra @nx
@sc:	dex
	lda #AF_SCALAR
	jsr aor
@nx:	inx
	jmp @l
@r:	rts

; a use to check at the end: a type (1 a line number, 2 a name), token
; x's value, the line, pk (allow0; or 0 call, 1 goto)
chk_add:
	sta pk2
	phx
	lda nchk+1
	cmp #$0A		; (2 banks: 2730 uses)
	bcs @r
	; 6 * nchk
	lda nchk
	asl a
	sta pw2
	lda nchk+1
	rol a
	sta pw2+1		; 2n
	lda pw2
	asl a
	sta fpp
	lda pw2+1
	rol a
	sta fpp+1		; 4n
	lda fpp
	clc
	adc pw2
	sta fpp
	lda fpp+1
	adc pw2+1		; 6n
	sta pw2+1
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc _vt_cb
	sta fpb
	lda pw2+1
	and #$1F
	ora #$A0
	sta fpp+1
	; (6 bytes may cross into the next bank: one at a time)
	plx
	phx
	lda pk2
	jsr chkput
	lda tkv,x
	jsr chkput
	lda tkh,x
	jsr chkput
	lda vt_src
	jsr chkput
	lda vt_src+1
	jsr chkput
	lda pk
	jsr chkput
	inc nchk
	bne @r
	inc nchk+1
@r:	plx
	rts
chkput:	ldy #0
	jsr fpoke
	inc fpp
	bne @r
	inc fpp+1
	lda fpp+1
	cmp #$C0
	bne @r
	lda #$A0
	sta fpp+1
	inc fpb
@r:	rts

ca_ret:	rts

; LET's or a bare assignment: tokens from x (a variable), then "=" or "("
check_assign:
	ldx s0
	lda tkt,x
	cmp #KC_KW
	bne ca1
	inx			; (LET)
ca1:	lda tkt,x
	cmp #KC_VAR
	bne ca_ret
	inx
	cpx s1
	bcs ca_ret
	lda #'='
	jsr ispc
	beq @y
	lda #'('
	jsr ispc
	bne ca_ret
@y:	dex
assigned:			; token x's name is assigned (its first line kept)
	jsr tsym
	lda #AF_ASSIGN
	jsr aflag
	bne @r
	lda #AF_ASSIGN
	jsr aor
	ldy #8
	lda vt_src
	jsr fpoke
	iny
	lda vt_src+1
	jsr fpoke
@r:	rts

s_let:	ldx s0
	inx
	cpx s1
	bcs @r
	lda tkt,x
	cmp #KC_VAR
	bne @r
	jmp ca1
@r:	rts

;---------------------------------------------------------------
; the block stack
;---------------------------------------------------------------
; push a block of kind a (fid's token is its opener: first)
bpush:	ldx nstk
	cpx #NSTK
	bcc @ok
	lda #VE_PROGBIG		; (too deep for the X16)
	jsr perr
	sec
	rts
@ok:	sta bk,x
	stz bhe,x
	stz bec,x
	cmp #TK_SELECT_CASE
	bne @1
	lda #1
	sta bec,x
@1:	lda #$FF
	sta bex,x
	txa
	asl a
	tay
	lda vt_src
	sta bsrc,y
	lda vt_src+1
	sta bsrc+1,y
	lda bat
	sta bob,y
	sta bpb,y
	lda bat+1
	sta bob+1,y
	sta bpb+1,y
	lda #$FF
	sta bvar,y
	sta bvar+1,y
	phy
	ldx first
	jsr absof
	ply
	lda ab
	sta bot,y
	lda ab+1
	sta bot+1,y
	inc nstk
	clc
	rts

; the innermost open block of kind a (not across a procedure) -> x
; (its index); carry set: none
bfind:	ldx nstk
@l:	dex
	bmi @no
	cmp bk,x
	beq @y
	ldy bk,x
	cpy #TK_SUB
	beq @no
	cpy #TK_FUNCTION
	beq @no
	bra @l
@y:	clc
	rts
@no:	sec
	rts

; top(want a, what fid): the block, the ones above it dropped (an
; error); carry set: none ("what without want")
btop:	sta pk
	jsr bfind
	bcc @f
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda pk
	sta vt_e+5
	stz vt_e+6
	lda #VE_WITHOUT
	jsr perr
	sec
	rts
@f:	inx
	cpx nstk
	beq @ok
	stx pk2
	jsr missing_top		; "X missing for Y in line N" (the top)
	ldx pk2
	jsr bdrop		; the blocks from x up
@ok:	ldx nstk
	dex
	clc
	rts

; the top block's "closer missing for kind in line" error
missing_top:
	ldx nstk
	dex
missing_x:
	lda bk,x
	sta vt_e+5
	stz vt_e+6
	PAIR openers
	sta vt_e+3
	stz vt_e+4
	txa
	asl a
	tay
	lda bsrc,y
	sta vt_e+7
	lda bsrc+1,y
	sta vt_e+8
	lda #VE_MISSING
	jmp perr

; drop the blocks from x up (their EXITs freed)
bdrop:	cpx nstk
	bcs @r
	phx
	ldx nstk
	dex
	jsr exfree_x
	dec nstk
	plx
	bra bdrop
@r:	rts

; block x's EXITs back to the free list
exfree_x:
	ldy bex,x
@l:	cpy #$FF
	beq @r
	lda exn,y
	pha
	lda exfree
	sta exn,y
	sty exfree
	ply
	bra @l
@r:	lda #$FF
	sta bex,x
	rts

; setblk(block x's pending $0B, token first's offset); pending = first's $0B
link_pending:
	phx
	txa
	asl a
	tay
	lda bpb,y
	sta at
	lda bpb+1,y
	sta at+1
	phy
	ldx first
	jsr absof
	lda ab
	sta tg
	lda ab+1
	sta tg+1
	jsr setblk
	ply
	lda bat
	sta bpb,y
	lda bat+1
	sta bpb+1,y
	plx
	rts

; a loop's end at token first: the opener's $0B -> here, b_at -> the
; opener, the EXITs -> here (block x)
link_close:
	phx
	txa
	asl a
	tay
	lda bob,y
	sta at
	lda bob+1,y
	sta at+1
	phy
	ldx first
	jsr absof
	lda ab
	sta tg
	lda ab+1
	sta tg+1
	jsr setblk
	ply
	lda bat
	sta at
	lda bat+1
	sta at+1
	lda bot,y
	sta tg
	lda bot+1,y
	sta tg+1
	jsr setblk
	plx
	jmp exits_here

; block x's EXITs -> first's offset (ab = it)
exits_here:
	phx
	ldx first
	jsr absof
	plx
	lda ab
	sta tg
	lda ab+1
	sta tg+1
	ldy bex,x
@l:	cpy #$FF
	beq @r
	phx
	phy
	tya
	asl a
	tay
	lda exa,y
	sta at
	lda exa+1,y
	sta at+1
	jsr setblk
	ply
	plx
	lda exn,y
	tay
	bra @l
@r:	rts

; pop block x (the top)
bpop:	jsr exfree_x
	dec nstk
	rts

;---------------------------------------------------------------
; the statements
;---------------------------------------------------------------
s_open:	lda fid
	jmp bpush

s_if:	; THEN or GOTO in the statement
	stz pk
	ldx s0
@l:	cpx s1
	bcs @d
	lda #TK_THEN
	jsr iskw
	bne @1
	lda pk
	ora #1
	sta pk
@1:	lda #TK_GOTO
	jsr iskw
	bne @2
	lda pk
	ora #2
	sta pk
@2:	inx
	bra @l
@d:	lda pk
	bne @ok
	lda #VE_THENIF
	jmp perr
@ok:	; a block: THEN last, and nothing after it but a comment
	and #1
	beq @line
	ldx s1
	dex
	lda #TK_THEN
	jsr iskw
	bne @line
	lda seg
	inc a
	cmp nseg
	beq @blk
	inc a
	cmp nseg
	bne @line
	ldx seg
	lda sgs+1,x
	tax
	lda tkt,x
	cmp #KC_REM
	beq @blk
	lda #$27
	jsr ispc
	beq @blk
	lda #TK_REM
	jsr iskw
	bne @line
@blk:	lda inl
	bne @line
	lda #TK_IF
	jmp bpush
@line:	ldx ninl
	cpx #NINL
	bcs @big
	stz ihe,x
	txa
	asl a
	tay
	lda bat
	sta ia,y
	lda bat+1
	sta ia+1,y
	inc ninl
@r:	rts
@big:	lda #VE_PROGBIG
	jmp perr

s_else:	; the nearest one-line IF without one
	ldx ninl
@l:	dex
	bmi @blk
	lda ihe,x
	bne @l
	lda #1
	sta ihe,x
	phx
	ldx first
	jsr absof
	plx
	txa
	asl a
	tay
	lda ab
	sta itg,y
	lda ab+1
	sta itg+1,y
	lda bat
	sta at
	lda bat+1
	sta at+1
	lda peol
	sta tg
	lda peol+1
	sta tg+1
	jmp setblk
@blk:	lda inl
	beq @b
	lda #TK_ELSE
	sta vt_e+3
	stz vt_e+4
	lda #TK_IF
	sta vt_e+5
	stz vt_e+6
	lda #VE_WITHOUT
	jmp perr
@b:	lda #TK_IF
	jsr btop
	bcs @r
	lda bhe,x
	beq @ok
	txa
	asl a
	tay
	EA {bsrc,y}, {bsrc+1,y}
	lda #VE_TWOELSE
	jmp perr
@ok:	jsr link_pending
	lda #1
	sta bhe,x
@r:	rts

s_elseif:
	lda #TK_IF
	jsr btop
	bcs @r
	lda bhe,x
	beq @ok
	txa
	asl a
	tay
	EA {bsrc,y}, {bsrc+1,y}
	lda #VE_ELSEIF
	jmp perr
@ok:	phx
	ldx s1
	dex
	lda #TK_THEN
	jsr iskw
	beq @t
	lda #VE_THENEI
	jsr perr
@t:	plx
	jmp link_pending
@r:	rts

s_for:	lda inl
	bne @r			; one-line: matched at run time
	lda #TK_FOR
	jsr bpush
	bcs @r
	; its variable: FOR [$0B] name
	ldx s0
	inx
	cpx s1
	bcs @r
	lda tkt,x
	cmp #KC_BLK
	bne @r
	inx
	cpx s1
	bcs @r
	lda tkt,x
	cmp #KC_VAR
	bne @r
	phx
	ldx nstk
	dex
	txa
	asl a
	tay
	plx
	lda tkv,x
	sta bvar,y
	lda tkh,x
	sta bvar+1,y
	jmp assigned
@r:	rts

s_next:	lda inl
	beq @go
	rts
@go:	stz firstfor
	stz nseen
	lda s0
	sta nni
@nl:	ldx nni
	cpx s1
	bcs @nd
	inc nni
	lda tkt,x
	cmp #KC_VAR
	bne @nl
	lda #1
	sta nseen
	jsr next_name
	bcc @nl
	rts
@nd:	lda nseen
	bne @r
	lda #TK_FOR		; NEXT alone
	jsr btop
	bcs @r
	jsr link_close
	jmp bpop
@r:	rts

; NEXT's name at token x: carry set to stop
next_name:
	lda tkv,x
	sta psy
	lda tkh,x
	sta psy+1
	lda #TK_FOR
	jsr bfind
	bcc @f
	lda #TK_NEXT
	sta vt_e+3
	stz vt_e+4
	lda #TK_FOR
	sta vt_e+5
	stz vt_e+6
	lda #VE_WITHOUT
	jsr perr
	sec
	rts
@f:	stx pk2			; k
	; the top a FOR of this name (or of none)?
	ldx nstk
	dex
	lda bk,x
	cmp #TK_FOR
	bne @named
	txa
	asl a
	tay
	lda bvar+1,y
	cmp #$FF
	bne @tv
	lda bvar,y
	cmp #$FF
	jeq @pop
@tv:	lda bvar,y
	cmp psy
	bne @named
	lda bvar+1,y
	cmp psy+1
	bne @named
	bra @pop
@named:	; the innermost FOR of this name at or below k
	ldx pk2
@nm:	lda bk,x
	cmp #TK_FOR
	bne @nm1
	txa
	asl a
	tay
	lda bvar,y
	cmp psy
	bne @nm1
	lda bvar+1,y
	cmp psy+1
	beq @nmf
@nm1:	dex
	bpl @nm
	bra @nomatch
@nmf:	; no SUB or FUNCTION from it up
	stx fbuf
@ck:	lda bk,x
	cmp #TK_SUB
	beq @nomatch
	cmp #TK_FUNCTION
	beq @nomatch
	inx
	cpx nstk
	bcc @ck
	jsr missing_top
	ldx fbuf
	inx
	jsr bdrop
	bra @pop
@nomatch:
	ldx pk2
	txa
	asl a
	tay
	EA {bsrc,y}, {bsrc+1,y}
	EC psy, psy+1
	ED {bvar,y}, {bvar+1,y}
	lda #VE_NEXTFOR
	jsr perr
	sec
	rts
@pop:	; the FOR's $0B -> NEXT; its EXITs; the first FOR: b_at -> it
	ldx nstk
	dex
	txa
	asl a
	tay
	lda bob,y
	sta at
	lda bob+1,y
	sta at+1
	phx
	phy
	ldx first
	jsr absof
	lda ab
	sta tg
	lda ab+1
	sta tg+1
	jsr setblk
	ply
	plx
	jsr exits_here
	txa
	asl a
	tay
	lda firstfor
	bmi @nf
	lda #$80
	sta firstfor
	lda bat
	sta at
	lda bat+1
	sta at+1
	lda bot,y
	sta tg
	lda bot+1,y
	sta tg+1
	phx
	jsr setblk
	plx
@nf:	jsr bpop
	clc
	rts

s_loopend:
	lda fid
	PAIR closes
	jsr btop
	bcs @r
	jsr link_close
	jmp bpop
@r:	rts

s_case:	lda #TK_SELECT_CASE
	jsr btop
	bcs @r
	lda bhe,x
	beq @ok
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda #VE_AFTERCE
	jmp perr
@ok:	stz bec,x
	jsr link_pending
	lda fid
	cmp #TK_CASE_ELSE
	bne @r
	lda #1
	sta bhe,x
@r:	rts

s_catch:
	lda #TK_TRY
	jsr btop
	bcs @r
	lda bhe,x
	beq @ok
	txa
	asl a
	tay
	EA {bsrc,y}, {bsrc+1,y}
	lda #VE_TWOCATCH
	jmp perr
@ok:	jsr link_pending
	lda #1
	sta bhe,x
@r:	rts

s_endb:	lda fid
	PAIR closes
	jsr btop
	bcs @r
	jsr link_pending
	jmp bpop
@r:	rts

s_endproc:
	lda fid
	PAIR closes
	jsr btop
	bcs @r
	; the opener's $0B and the EXITs -> here; the procedure's end
	phx
	txa
	asl a
	tay
	lda bob,y
	sta at
	lda bob+1,y
	sta at+1
	ldx first
	jsr absof
	lda ab
	sta tg
	lda ab+1
	sta tg+1
	jsr setblk
	plx
	jsr exits_here
	jsr bpop
	lda pcur
	beq @r
	; its end and frame count in its header
	jsr phdr
	ldy #4
	lda ab
	jsr fpoke
	iny
	lda ab+1
	jsr fpoke
	stz pcur
	stz nsh
@r:	rts

; fpb/fpp = procedure a's first line ($BF00 of the procedures' bank)
psrcat:	asl a
	sta fpp
	lda #$BF
	sta fpp+1
	lda _vt_pb
	sta fpb
	rts

; fpb/fpp = the current procedure's header
phdr:	lda _vt_pb
	sta fpb
	lda pcur
	dec a
	asl a
	tax
	lda ppos,x
	sta fpp
	lda ppos+1,x
	sta fpp+1
	rts

s_exit:	lda fid
	PAIR exits
	sta pk
	jsr bfind
	bcc @f
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda pk
	sta vt_e+5
	stz vt_e+6
	lda #VE_OUTSIDE
	jmp perr
@f:	; bat onto block x's EXITs
	ldy exfree
	cpy #$FF
	beq @big
	lda exn,y
	sta exfree
	lda bex,x
	sta exn,y
	tya
	sta bex,x
	asl a
	tay
	lda bat
	sta exa,y
	lda bat+1
	sta exa+1,y
@r:	rts
@big:	lda #VE_PROGBIG		; (too many EXITs open for the X16)
	jmp perr

s_return:
	lda s1
	sec
	sbc s0
	cmp #2
	bcc @r
	lda pcur
	beq @e
	lda pfn
	bne @r
@e:	lda #VE_RETURN
	jmp perr
@r:	rts

s_option:
	ldx s0
	inx
	cpx s1
	bcs @r
	lda #TK_INTEGER
	jsr iskw
	bne @r
	lda #1
	sta optint
@r:	rts

s_const:
	ldx s0
	inx
@l:	cpx s1
	bcs @r
	lda tkt,x
	cmp #KC_VAR
	bne @n
	stx ck
	inx
	cpx s1
	bcs @r
	lda #'='
	jsr ispc
	bne @n0
	ldx ck
	dex
	cpx s0
	beq @y
	lda #','
	jsr ispc
	bne @n0
@y:	ldx ck
	jsr tsym
	lda #AF_CONST
	jsr aflag
	beq @new
	EC psy, psy+1
	lda #VE_CTWICE
	jsr perr
@new:	lda #AF_CONST
	jsr aor
@n0:	ldx ck
@n:	inx
	bra @l
@r:	rts

s_dim:	stz pk			; the depth
	ldx s0
@l:	cpx s1
	bcs @r
	lda #'('
	jsr ispc
	bne @1
	inc pk
	bra @n
@1:	lda #')'
	jsr ispc
	bne @2
	dec pk
	bra @n
@2:	lda tkt,x
	cmp #KC_VAR
	bne @n
	lda pk
	bne @n
	inx
	cpx s1
	bcs @r
	lda #'('
	jsr ispc
	php
	dex
	plp
	bne @n
	jsr tsym
	lda #AF_DIM
	jsr aor
@n:	inx
	bra @l
@r:	rts

s_defint:
	ldx s0
	inx
@l:	cpx s1
	jcs @r
	lda tkt,x
	cmp #KC_VAR
	beq @v
	cmp #KC_NREF
	bne @n
@bad:	phx
	lda #VE_DEFINT
	jsr perr
	plx
	bra @n
@v:	jsr tsym
	jsr symname		; pw: the spelling's length, pk: the first letter
	lda pw
	cmp #1
	bne @bad
	lda pk
	sta da
	sta db
	; a "-" b?
	txa
	clc
	adc #2
	cmp s1
	bcs @set
	inx
	lda #'-'
	jsr ispc
	bne @d1
	inx
	lda tkt,x
	cmp #KC_VAR
	bne @d2
	jsr tsym
	jsr symname
	lda pk
	sta db
	bra @set
@d2:	dex
@d1:	dex
@set:	lda da
@s1:	cmp db
	beq @s2
	bcs @n
@s2:	pha
	sec
	sbc #'A'
	cmp #32
	bcs @s3
	phx
	tay
	and #7
	tax
	lda bitm3,x
	pha
	tya
	lsr a
	lsr a
	lsr a
	tay
	pla
	ora defint,y
	sta defint,y
	plx
@s3:	pla
	inc a
	bra @s1
@n:	inx
	jmp @l
@r:	rts


s_local:
	lda pcur
	bne @in
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda #VE_OUTPROC
	jmp perr
@in:	ldx s0
	inx
@l:	cpx s1
	bcs @r
	lda tkt,x
	cmp #KC_VAR
	bne @n
	txa
	dec a
	cmp s0
	beq @y
	dex
	lda #','
	jsr ispc
	php
	inx
	plp
	bne @n
@y:	stz pk			; an array: "(" follows
	inx
	cpx s1
	bcs @y1
	lda #'('
	jsr ispc
	bne @y1
	lda #F_ARRAY
	sta pk
@y1:	dex
	jsr tsym
	phx
	jsr declare
	plx
@n:	inx
	bra @l
@r:	rts

; psy LOCAL (fid) or SHARED in the current procedure (pk: F_ARRAY)
declare:
	jsr inframe
	php
	lda fid
	cmp #TK_SHARED
	bne @loc
	plp
	bcs @sh
	EC psy, psy+1		; x is LOCAL and SHARED
	lda #VE_LOCSH
	jsr perr
@sh:	ldx nsh
	cpx #NSHARED
	bcs @r
	txa
	asl a
	tay
	lda psy
	sta shs,y
	lda psy+1
	sta shs+1,y
	inc nsh
@r:	rts
@loc:	plp
	bcs @new
	EC psy, psy+1		; already local
	ED psym, psym+1
	lda #TK_SUB
	ldx pfn
	beq @s
	lda #TK_FUNCTION
@s:	sta vt_e+3
	stz vt_e+4
	lda #VE_ALOCAL
	jmp perr
@new:	; in SHARED?
	ldx nsh
@sl:	dex
	bmi @add
	txa
	asl a
	tay
	lda shs,y
	cmp psy
	bne @sl
	lda shs+1,y
	cmp psy+1
	bne @sl
	EC psy, psy+1
	lda #VE_LOCSH
	jsr perr
@add:	lda pk
	jmp fradd


; a frame entry: psy, flags a (also to the procedure's bank)
fradd:	ldx nfr
	cpx #NFRAME
	bcc @ok
	lda #VE_PROGBIG
	jmp perr
@ok:	sta frf,x
	pha
	txa
	asl a
	tay
	lda psy
	sta frs,y
	lda psy+1
	sta frs+1,y
	; at header + 9 + 3 slot
	jsr phdr
	lda nfr
	sta pw
	stz pw+1
	asl pw
	rol pw+1
	lda pw
	clc
	adc nfr
	bcc @1
	inc pw+1
	clc
@1:	adc #9
	bcc @2
	inc pw+1
	clc
@2:	adc fpp
	sta fpp
	lda pw+1
	adc fpp+1
	sta fpp+1
	ldy #0
	lda psy
	jsr fpoke
	iny
	lda psy+1
	jsr fpoke
	iny
	pla
	jsr fpoke
	inc nfr
	jsr phdr		; the frame's count
	ldy #7
	lda nfr
	jmp fpoke

; SUB / FUNCTION
s_proc:	lda pcur
	beq @1
	; inside another: "SUB B inside SUB A (line N)"
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda #$FF
	sta vt_e+9
	sta vt_e+10
	ldx s0
	inx
	inx
	cpx s1
	bcs @in1
	lda tkt,x
	cmp #KC_NREF
	bne @in1
	lda tkv,x
	sta vt_e+9
	lda tkh,x
	sta vt_e+10
@in1:	lda #TK_SUB
	ldx pfn
	beq @in2
	lda #TK_FUNCTION
@in2:	sta vt_e+5
	stz vt_e+6
	EC psym, psym+1
	lda pcur
	dec a
	jsr psrcat
	ldy #0
	jsr fpeek
	sta vt_e+12
	iny
	jsr fpeek
	sta vt_e+13
	lda #VE_PROCIN
	jmp perr
@1:	lda nstk		; blocks still open: the top's error, all dropped
	beq @2
	jsr missing_top
	ldx #0
	jsr bdrop
@2:	; the name
	ldx s0
	inx
	inx
	cpx s1
	bcs @noname
	lda tkt,x
	cmp #KC_NREF
	beq @name
@noname:
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda #VE_NAMEEXP
	jmp perr
@name:	jsr tsym
	lda psy
	sta psym
	lda psy+1
	sta psym+1
	lda nproc
	cmp #NPROC
	bcc @3
	lda #VE_PROGBIG
	jmp perr
@3:	; defined twice?
	jsr pattr
	ldy #12
	jsr fpeek
	beq @new
	dec a
	jsr psrcat
	ldy #0
	jsr fpeek
	sta vt_e+5
	iny
	jsr fpeek
	sta vt_e+6
	EC psym, psym+1
	ED vt_src, vt_src+1
	lda fid
	sta vt_e+3
	stz vt_e+4
	lda #VE_DEFTWICE
	jsr perr
@new:	; the procedure: its number in the name, its header at pbtop
	ldx nproc
	inx
	stx pcur
	jsr pattr
	lda pcur
	ldy #12
	jsr fpoke
	lda #AF_SUB
	ldx fid
	stz pfn
	cpx #TK_FUNCTION
	bne @4
	lda #1
	sta pfn
	lda #AF_FUNC
@4:	jsr aor
	ldx s0
	jsr absof
	jsr pattr		; the target: the SUB token
	ldy #2
	lda ab
	jsr fpoke
	iny
	lda ab+1
	jsr fpoke
	lda nproc
	jsr psrcat
	ldy #0
	lda vt_src
	jsr fpoke
	iny
	lda vt_src+1
	jsr fpoke
	; pbtop: past the last procedure's frame
	lda nproc
	beq @5
	dec a
	asl a
	tay
	lda nfr			; (nfr is still the last one's count)
	sta pw
	stz pw+1
	asl pw
	rol pw+1
	lda pw
	clc
	adc nfr
	sta pw
	bcc @5a
	inc pw+1
@5a:	lda ppos,y
	clc
	adc #9
	sta pbtop
	lda ppos+1,y
	adc #0
	sta pbtop+1
	lda pbtop
	clc
	adc pw
	sta pbtop
	lda pbtop+1
	adc pw+1
	sta pbtop+1
@5:	lda pbtop+1
	cmp #$BF		; (the bank's room)
	bcc @6
	lda #VE_PROGBIG
	jmp perr
@6:	lda nproc
	asl a
	tax
	lda pbtop
	sta ppos,x
	lda pbtop+1
	sta ppos+1,x
	inc nproc
	stz nfr
	stz npar
	stz nsh
	; its header: symbol, start, end 0, parameters, frame, flags
	jsr phdr
	ldy #0
	lda psym
	jsr fpoke
	iny
	lda psym+1
	jsr fpoke
	iny
	lda ab
	jsr fpoke
	iny
	lda ab+1
	jsr fpoke
	lda #0
	iny
	jsr fpoke
	iny
	jsr fpoke
	iny
	jsr fpoke
	iny
	jsr fpoke
	iny
	lda pfn
	jsr fpoke
	lda pfn			; a FUNCTION: its result first
	beq @par
	lda psym
	sta psy
	lda psym+1
	sta psy+1
	lda #F_RESULT
	jsr fradd
@par:	; ( [BYREF] name [()] , ... )
	ldx s0
	inx
	inx
	inx
	cpx s1
	jcs @blk
	lda #'('
	jsr ispc
	jne @blk
	inx
@pl:	cpx s1
	jcs @nopar
	lda #')'
	jsr ispc
	jeq @blk
	stz pk
	lda #TK_BYREF
	jsr iskw
	bne @p1
	lda #F_BYREF
	sta pk
	inx
@p1:	cpx s1
	bcs @pexp
	lda tkt,x
	cmp #KC_VAR
	beq @p2
@pexp:	lda #VE_PARAM
	jsr perr
	jmp @blk
@p2:	jsr tsym
	inx
	cpx s1
	bcs @p3
	lda #'('
	jsr ispc
	bne @p3
	inx
	cpx s1
	bcs @p3b
	lda #')'
	jsr ispc
	bne @p3b
	inx
	lda pk
	ora #F_ARRAY
	sta pk
	bra @p3
@p3b:	dex
@p3:	phx
	jsr inframe
	bcs @p4
	EC psy, psy+1
	lda #VE_PTWICE
	jsr perr
@p4:	lda pk
	ora #F_PARAM
	jsr fradd
	inc npar
	jsr phdr
	ldy #6
	lda npar
	jsr fpoke
	plx
	cpx s1
	bcs @nopar
	lda #','
	jsr ispc
	jne @pl
	inx
	jmp @pl
@nopar:	lda #VE_PAREN
	jsr perr
@blk:	lda fid
	jmp bpush

;---------------------------------------------------------------
; the end: checks, kinds, locals, targets, record 0
;---------------------------------------------------------------
prep_finish:
	; blocks still open: "X missing for Y in line N" at the last line
@open:	ldx nstk
	beq @o2
	dex
	lda bk,x
	sta vt_e+5
	stz vt_e+6
	PAIR openers
	sta vt_e+3
	stz vt_e+4
	txa
	asl a
	tay
	EC {bsrc,y}, {bsrc+1,y}
	lda #VE_MISSING
	sta vt_e
	lda lastsrc
	sta vt_e+1
	lda lastsrc+1
	sta vt_e+2
	jsr perr2
	dec nstk
	bra @open
@o2:	lda #<P4::finish
	ldx #>P4::finish
	ldy _vt_ovl4
	jmp bcall


















.endscope

;===============================================================
; overlay 4: the end (the uses checked, the kinds, the locals, record 0),
; the messages
;===============================================================
.scope P4
.define HBSS "OVL4BSS"
.define HCODE "OVERLAY4"
.include "vbphelp.s"
.undefine HBSS
.undefine HCODE
.segment "OVL4BSS"
pend:	.res 2			; the procedure range (finish)
pstart:	.res 2
cpi:	.res 1
lofs:	.res 2
ppcur:	.res 2			; the procedure's header (pload)
lbi:	.res 2			; the listed line
opos:	.res 1			; the message's next character
chand:	.res 1			; compile's
cn:	.res 1
ck2:	.res 1
ctoo:	.res 1
cgot:	.res 2
.segment "OVERLAY4"

; each name a predefined constant's? its kind K_BUILTIN, its value
builtins:
	stz psy
	stz psy+1
@l:	lda psy
	cmp vt_nsym
	bne @1
	lda psy+1
	cmp vt_nsym+1
	bne @1
	rts
@1:	jsr symname		; fpp: the entry; pw: the length
	lda pw
	sta pk
	lda #<consts
	sta n1
	lda #>consts
	sta n1+1
@e:	lda (n1)
	beq @n
	cmp pk
	bne @nx
	ldy #5			; the key: entry + 5
	sty pk2
	ldy #1
@c:	phy
	ldy pk2
	jsr fpeek
	inc pk2
	ply
	cmp (n1),y
	bne @nx
	iny
	cpy pk
	bcc @c
	beq @c
	lda (n1),y
	sta pw
	iny
	lda (n1),y
	sta pw+1
	jsr pattr
	ldy #13
	lda #K_BUILTIN
	jsr fpoke
	iny
	lda pw
	jsr fpoke
	iny
	lda pw+1
	jsr fpoke
	bra @n
@nx:	lda (n1)
	clc
	adc #3
	adc n1
	sta n1
	bcc @e
	inc n1+1
	bra @e
@n:	inc psy
	jne @l
	inc psy+1
	jmp @l
consts:	vb_consts_table

;---------------------------------------------------------------
; main.c's compile: the .BAS file _vt_name read into a run of banks
; (64 KB at most), the banks the tokenizer works in, the tokenizer
; (overlay 2), its banks given back; the records' runs in _vt_recb
;---------------------------------------------------------------
compile:
	stz _vt_recb
	stz _vt_recb+1
	stz _vt_recb+2
	stz _vt_recb+3
	stz _vt_r1b
	stz _vt_r2b
	stz _vt_r3b
	stz _vt_nb
	stz _vt_ab
	stz _vt_pb
	stz _vt_cb
	stz _vt_lb
	stz _vt_r0b
	lda #2
	sta _vt_err
.ifdef VB_IDE
	lda _vt_inmem           ; (the editor: the text in _vt_src already)
	beq @file
	stz _vt_inmem
	lda #3
	sta _vt_err
	jmp @sz
@file:
.endif
	lda _vt_name
	sta r0
	lda _vt_name+1
	sta r0+1
	lda #'r'
	jsr FOpen
	cmp #2
	bcs @op
	rts
@op:	sta chand
	lda #3
	sta _vt_err
	lda #8			; the text: as many banks as there are, up to 8
	sta cn
@al:	lda cn
	jsr BankAlloc
	cmp #0
	bne @got
	dec cn
	bne @al
	lda chand
	jmp FClose
@got:	sta _vt_src
	stz _vt_srclen
	stz _vt_srclen+1
	stz ctoo
	stz ck2
@rd:	lda _vt_src
	clc
	adc ck2
	sta _vb_fbank
	stz _vb_faddr
	lda #$A0
	sta _vb_faddr+1
	stz _vb_fcount
	lda #$20
	sta _vb_fcount+1
	lda chand
	jsr _vb_fread		; a/x: the bytes read
	sta cgot
	stx cgot+1
	clc
	adc _vt_srclen
	sta _vt_srclen
	txa
	adc _vt_srclen+1
	sta _vt_srclen+1
	bcc @r1
	inc ctoo
@r1:	lda cgot+1
	cmp #$20
	bcc @rend		; a bank not filled: the end
	inc ck2
	lda ck2
	cmp cn
	bcc @rd
	; every bank full: is there more?
	stz _vb_fbank
	lda #<cgot
	sta _vb_faddr
	lda #>cgot
	sta _vb_faddr+1
	lda #1
	sta _vb_fcount
	stz _vb_fcount+1
	lda chand
	jsr _vb_fread
	cmp #0
	beq @rend
	inc ctoo
@rend:	lda chand
	jsr FClose
	lda ctoo
	bne @big
	lda _vt_srclen+1
	cmp #$FF
	bcc @sz
@big:	lda #4
	sta _vt_err
	lda _vt_src
	jmp BankFree
@sz:	; record 1's banks: the text's size and a half, and 1 KB; 8 at most
	lda _vt_srclen+1
	lsr a
	clc
	adc _vt_srclen+1
	bcs @n8
	adc #4
	bcs @n8
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	inc a
	cmp #9
	bcc @n1
@n8:	lda #8
@n1:	sta cn
@a1:	lda cn
	jsr BankAlloc
	cmp #0
	bne @a2
	dec cn
	bne @a1
	jmp @nomem
@a2:	sta _vt_r1b
	lda cn
	sta _vt_r1n
	lda #1
	jsr BankAlloc
	sta _vt_r2b
	cmp #0
	jeq @nomem
	lda #1
	jsr BankAlloc
	sta _vt_r3b
	cmp #0
	beq @nomem
	lda #1
	jsr BankAlloc
	sta _vt_nb
	cmp #0
	beq @nomem
	lda #1
	jsr BankAlloc
	sta _vt_ab
	cmp #0
	beq @nomem
	lda #1
	jsr BankAlloc
	sta _vt_pb
	cmp #0
	beq @nomem
	lda #2
	jsr BankAlloc
	sta _vt_cb
	cmp #0
	beq @nomem
	lda #1
	jsr BankAlloc
	sta _vt_lb
	cmp #0
	beq @nomem
	TCLOCK tclk0
	lda #<tok_main
	ldx #>tok_main
	ldy _vt_ovl2
	jsr bcall
	TCLOCK tclk1
	bra @free
@nomem:	lda #3
	sta _vt_err
@free:	; the work's banks back; the records' runs kept (an error: back too)
	lda _vt_src
	jsr bfree
	lda _vt_nb
	jsr bfree
	lda _vt_ab
	jsr bfree
	lda _vt_pb
	jsr bfree
	lda _vt_cb
	jsr bfree
	lda _vt_lb
	jsr bfree
	lda _vt_err
	beq @keep
	lda _vt_r0b
	jsr bfree
	lda _vt_r1b
	jsr bfree
	lda _vt_r2b
	jsr bfree
	lda _vt_r3b
	jmp bfree
@keep:	lda _vt_r0b
	sta _vt_recb
	lda _vt_r1b
	sta _vt_recb+1
	lda _vt_r2b
	sta _vt_recb+2
	lda _vt_r3b
	sta _vt_recb+3
	rts

.ifdef VB_TEST
;---------------------------------------------------------------
; the test build: "VB REC n HEX" for each record, "VB TOKCYC cycles
; LINES n BYTES n" (the emulator's cycle counter; numbers in hex)
;---------------------------------------------------------------
dump:	stz pk
@rec:	ldx #0
@m:	lda MRec,x
	beq @m1
	sta EMU_STDOUT
	inx
	bra @m
@m1:	lda pk
	ora #'0'
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	lda pk
	tax
	lda _vt_recb,x
	sta fpb
	stz fpp
	lda #$A0
	sta fpp+1
	txa
	asl a
	tax
	lda _vt_size,x
	sta pw
	lda _vt_size+1,x
	sta pw+1
@b:	lda pw
	ora pw+1
	beq @e
	ldy #0
	jsr fpeek
	jsr hexo
	inc fpp
	bne @b1
	inc fpp+1
	lda fpp+1
	cmp #$C0
	bne @b1
	lda #$A0
	sta fpp+1
	inc fpb
@b1:	lda pw
	bne @b2
	dec pw+1
@b2:	dec pw
	bra @b
@e:	lda #10
	sta EMU_STDOUT
	inc pk
	lda pk
	cmp #4
	bne @rec
	ldx #0
@c:	lda MCyc,x
	beq @c1
	sta EMU_STDOUT
	inx
	bra @c
@c1:	sec			; the cycles: tclk1 - tclk0
	ldx #0
	ldy #4
@c2:	lda tclk1,x
	sbc tclk0,x
	sta tclk1,x
	inx
	dey
	bne @c2
	ldx #3
@c3:	lda tclk1,x
	jsr hexo
	dex
	bpl @c3
	ldx #0
@l:	lda MLin,x
	beq @l1
	sta EMU_STDOUT
	inx
	bra @l
@l1:	lda _vt_lines+1
	jsr hexo
	lda _vt_lines
	jsr hexo
	ldx #0
@y:	lda MByt,x
	beq @y1
	sta EMU_STDOUT
	inx
	bra @y
@y1:	lda _vt_srclen+1
	jsr hexo
	lda _vt_srclen
	jsr hexo
.ifdef VB_PROF
	lda #' '
	sta EMU_STDOUT
	ldx #0
@p:	lda _vt_prof,x
	jsr hexo
	stz _vt_prof,x
	inx
	cpx #32
	bne @p
.endif
	lda #10
	sta EMU_STDOUT
	rts
hexo:	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr @d
	pla
	and #15
@d:	cmp #10
	bcc @1
	adc #6
@1:	adc #'0'
	sta EMU_STDOUT
	rts
MRec:	.byte "VB REC ", 0
MCyc:	.byte "VB TOKCYC ", 0
MLin:	.byte " LINES ", 0
MByt:	.byte " BYTES ", 0
.endif

bfree:	cmp #0
	beq @r
	jmp BankFree
@r:	rts

finish:	jsr chk_all
	jsr builtins
	jsr sym_all
	jsr locals_all
	lda vt_pe
	beq @ok
	jmp perr_text
@ok:	jmp rec0

; the uses: line numbers in the index, labels, procedures
chk_all:
	stz pw
	stz pw+1
	lda _vt_cb
	sta fpb
	stz fpp
	lda #$A0
	sta fpp+1
@l:	lda pw
	cmp nchk
	bne @1
	lda pw+1
	cmp nchk+1
	bne @1
	rts
@1:	ldx #0
@g:	ldy #0
	jsr fpeek
	sta fbuf,x
	jsr chkadv
	inx
	cpx #6
	bne @g
	lda fpb			; (kept: the lookups below map others)
	pha
	lda fpp
	pha
	lda fpp+1
	pha
	jsr chk1
	pla
	sta fpp+1
	pla
	sta fpp
	pla
	sta fpb
	inc pw
	bne @l
	inc pw+1
	bra @l

chkadv:	inc fpp
	bne @r
	inc fpp+1
	lda fpp+1
	cmp #$C0
	bne @r
	lda #$A0
	sta fpp+1
	inc fpb
@r:	rts

; one use: fbuf = type, value (2), line (2), pk
chk1:	lda fbuf+3
	sta vt_e+1
	lda fbuf+4
	sta vt_e+2
	lda fbuf
	cmp #1
	bne @name
	; a line number: 0 with ON ERROR; else in the index
	lda fbuf+1
	ora fbuf+2
	bne @ln
	lda fbuf+5
	bne @r
@ln:	lda fbuf+1
	sta pw2
	lda fbuf+2
	sta pw2+1
	jsr lfind
	bcc @r
	EA pw2, pw2+1
	lda #VE_UNDEFL
	sta vt_e
	jmp perr2
@name:	lda fbuf+1
	sta psy
	sta vt_e+7
	lda fbuf+2
	sta psy+1
	sta vt_e+8
	lda fbuf+5
	beq @call
	lda #AF_LABEL
	jsr aflag
	bne @r
	lda #VE_UNDLAB
	sta vt_e
	jmp perr2
@call:	lda #AF_SUB | AF_FUNC
	jsr aflag
	bne @r
	lda #VE_UNDSUB
	sta vt_e
	jmp perr2
@r:	rts

; the line number pw2 in the index? carry clear: yes, pw2 its offset
; (a binary search)
lfind:	lda _vt_r2b
	sta fpb
	stz fbuf		; lo .. hi (entries)
	stz fbuf+1
	lda nidx
	sta fbuf+2
	lda nidx+1
	sta fbuf+3
@l:	lda fbuf
	cmp fbuf+2
	lda fbuf+1
	sbc fbuf+3
	bcs @no
	; mid
	lda fbuf
	clc
	adc fbuf+2
	sta lofs
	lda fbuf+1
	adc fbuf+3
	ror a
	sta lofs+1
	ror lofs
	lda lofs
	asl a
	sta fpp
	lda lofs+1
	rol a
	asl fpp
	rol a
	ora #$A0
	sta fpp+1
	ldy #1
	jsr fpeek
	cmp pw2+1
	bcc @up
	bne @down
	dey
	jsr fpeek
	cmp pw2
	bcc @up
	bne @down
	ldy #2
	jsr fpeek
	sta pw2
	iny
	jsr fpeek
	sta pw2+1
	clc
	rts
@up:	lda lofs
	clc
	adc #1
	sta fbuf
	lda lofs+1
	adc #0
	sta fbuf+1
	bra @l
@down:	lda lofs
	sta fbuf+2
	lda lofs+1
	sta fbuf+3
	bra @l
@no:	sec
	rts

; every name: errors (both a label and a procedure, assigned constants,
; a built-in constant misused), then its kind and type into attribute 13
; and 1
sym_all:
	stz psy
	stz psy+1
@l:	lda psy
	cmp vt_nsym
	bne @1
	lda psy+1
	cmp vt_nsym+1
	bne @1
	rts
@1:	jsr pattr
	ldy #0
	jsr fpeek
	sta pk			; the flags
	ldy #13
	jsr fpeek
	sta pk2			; K_BUILTIN or 0
	; a label and a procedure
	lda pk
	and #AF_LABEL
	beq @2
	lda pk
	and #AF_SUB | AF_FUNC
	beq @2
	ldx #TK_SUB
	and #AF_FUNC
	beq @b1
	ldx #TK_FUNCTION
@b1:	stx vt_e+3
	stz vt_e+4
	EC psy, psy+1
	ldy #6
	jsr fpeek
	sta vt_e+1
	iny
	jsr fpeek
	sta vt_e+2
	lda #VE_BOTH
	sta vt_e
	jsr perr2
	jsr pattr
@2:	; an assigned constant
	lda pk
	bpl @3
	and #AF_CONST
	ora pk2
	beq @3
	EC psy, psy+1
	ldy #8
	jsr fpeek
	sta vt_e+1
	iny
	jsr fpeek
	sta vt_e+2
	lda #VE_ASSIGN
	sta vt_e
	jsr perr2
	jsr pattr
@3:	; the kind
	lda pk2			; K_BUILTIN
	sta pw
	lda pk
	and #AF_CONST
	tsb pw			; (K_CONST = AF_CONST)
	lda pk
	and #AF_SUB | AF_FUNC | AF_LABEL	; (the same bits)
	tsb pw
	lda pk
	and #AF_DIM
	bne @arr
	lda pk
	and #AF_PAREN
	beq @4
	lda pw
	and #K_FUNC
	bne @4
@arr:	lda #K_ARRAY
	tsb pw
@4:	lda pk
	and #AF_SCALAR
	beq @5
	lda pw
	and #K_CONST | K_BUILTIN
	bne @5
	lda #K_VAR
	tsb pw
@5:	lda pw
	bne @6
	lda #K_VAR
	sta pw
@6:	ldy #13
	jsr fpoke
	; a built-in constant used as something else
	lda pw
	and #K_BUILTIN
	beq @7
	lda pw
	and #K_ARRAY | K_SUB | K_FUNC | K_LABEL | K_CONST
	beq @7
	EC psy, psy+1
	ldy #4
	jsr fpeek
	sta vt_e+1
	iny
	jsr fpeek
	sta vt_e+2
	lda #VE_BUILTIN
	sta vt_e
	jsr perr2
	jsr pattr
@7:	; the type: an unsuffixed name is an integer by OPTION INTEGER, DEFINT
	ldy #1
	jsr fpeek
	bne @n
	lda optint
	bne @int
	jsr symname		; pk: the first letter
	jsr pattr
	lda pk
	sec
	sbc #'A'
	cmp #26
	bcs @n
	tay
	and #7
	tax
	tya
	lsr a
	lsr a
	lsr a
	tay
	lda defint,y
	and bitm3,x
	beq @n
@int:	ldy #1
	lda #TY_I
	jsr fpoke
@n:	inc psy
	jne @l
	inc psy+1
	jmp @l

; record 1 again: each procedure's names made locals, the name
; references' targets
locals_all:
	stz lofs
	stz lofs+1
	stz cpi
	stz lbi
	stz lbi+1
	jsr pload
@line:	lda nlb+1		; the next listed line (or every line)
	cmp #$10
	bcs @all
	lda lbi
	cmp nlb
	bne @ls
	lda lbi+1
	cmp nlb+1
	bne @ls
	rts
@ls:	lda lbi
	asl a
	sta fpp
	lda lbi+1
	rol a
	ora #$A0
	sta fpp+1
	lda _vt_lb
	sta fpb
	ldy #0
	jsr fpeek
	sta lofs
	iny
	jsr fpeek
	sta lofs+1
	inc lbi
	bne @all
	inc lbi+1
@all:	lda lofs
	sta n0
	lda lofs+1
	sta n0+1
	jsr r1at3
	ldy #0
	jsr fpeek
	bne @1
	rts			; the end
@1:	sta vt_tl
	; the record into tb
	clc
	jsr r1io
	lda lofs
	sta vt_off
	lda lofs+1
	sta vt_off+1
	jsr decode
	; the procedure range: past its end, the next one
@adv:	lda cpi
	cmp nproc
	bcs @tok
	lda pend
	ora pend+1
	beq @tok
	lda pend
	cmp lofs
	lda pend+1
	sbc lofs+1
	bcs @tok		; end >= off
	inc cpi
	jsr pload
	bra @adv
@tok:	ldx #0
@t:	cpx nt
	jcs @wr
	lda tkt,x
	cmp #KC_NREF
	jeq @nref
	cmp #KC_VAR
	jne @tn
	; a local? inside the range (start < a < end)
	lda cpi
	cmp nproc
	jcs @tn
	jsr absof
	lda pstart
	cmp ab
	lda pstart+1
	sbc ab+1
	jcs @tn			; a <= start
	lda pend
	ora pend+1
	beq @in
	lda ab
	cmp pend
	lda ab+1
	sbc pend+1
	jcs @tn			; a >= end
@in:	jsr tsym
	phx
	jsr inframe
	txa
	plx
	jcs @tn
	sta pk			; the slot
	tay
	lda frf,y
	and #F_RESULT
	beq @loc
	inx			; the result followed by "(": a call
	cpx nt
	bcs @loc0
	lda #'('
	jsr ispc
	php
	dex
	plp
	jeq @tn
	bra @loc
@loc0:	dex
@loc:	ldy tkp,x
	lda pk
	sta tb+7,y
	lda #$80
	sta tb+8,y
	bra @tn
@nref:	jsr tsym
	phx
	jsr pattr
	ldy #13
	jsr fpeek
	plx
	and #K_SUB | K_FUNC | K_LABEL
	beq @tn
	phx
	ldy #2
	jsr fpeek
	sta pw
	iny
	jsr fpeek
	sta pw+1
	plx
	ldy tkp,x
	lda pw
	sta tb+9,y
	lda pw+1
	sta tb+10,y
@tn:	inx
	jmp @t
@wr:	; back to record 1
	sec
	jsr r1io
	lda lofs
	clc
	adc vt_tl
	sta lofs
	jcc @line
	inc lofs+1
	jmp @line

; the line record at lofs (vt_tl bytes) into tb (carry clear) or back
; (carry set): xcopy, in two parts across a bank's end
r1io:	php
	lda lofs
	sta n0
	lda lofs+1
	sta n0+1
	jsr r1at3
	lda fpb
	sta xbk
	lda fpp
	sta xp
	lda fpp+1
	sta xp+1
	lda #<tb
	sta xm
	lda #>tb
	sta xm+1
	lda #0
	sec
	sbc fpp
	sta pw
	lda #$C0
	sbc fpp+1
	bne @one
	lda pw
	cmp vt_tl
	bcs @one
	sta xn
	plp
	php
	jsr xc
	lda xm
	clc
	adc xn
	sta xm
	bcc @1
	inc xm+1
@1:	lda vt_tl
	sec
	sbc xn
	sta xn
	inc xbk
	stz xp
	lda #$A0
	sta xp+1
	plp
	jmp xc
@one:	lda vt_tl
	sta xn
	plp
	jmp xc

; procedure cpi: its range (pstart, pend) and frame (frs, frf, nfr)
pload:	lda cpi
	bne @nx
	stz ppcur		; the first: the bank's start
	lda #$A0
	sta ppcur+1
	bra @go
@nx:	; past the one before: 9 + 3 entries
	lda nfr
	sta pw
	stz pw+1
	asl pw
	rol pw+1
	lda pw
	clc
	adc nfr
	bcc @n1
	inc pw+1
	clc
@n1:	adc #9
	bcc @n2
	inc pw+1
	clc
@n2:	adc ppcur
	sta ppcur
	lda pw+1
	adc ppcur+1
	sta ppcur+1
@go:	stz nfr
	lda cpi
	cmp nproc
	bcs @r
	lda _vt_pb
	sta fpb
	lda ppcur
	sta fpp
	lda ppcur+1
	sta fpp+1
	ldy #2
	jsr fpeek
	sta pstart
	iny
	jsr fpeek
	sta pstart+1
	iny
	jsr fpeek
	sta pend
	iny
	jsr fpeek
	sta pend+1
	ldy #7
	jsr fpeek
	sta nfr
	lda fpp
	clc
	adc #9
	sta fpp
	bcc @a
	inc fpp+1
@a:	ldx #0
@f:	cpx nfr
	bcs @r
	ldy #0
	jsr fpeek
	sta pw
	iny
	jsr fpeek
	sta pw+1
	iny
	jsr fpeek
	sta frf,x
	txa
	asl a
	tay
	lda pw
	sta frs,y
	lda pw+1
	sta frs+1,y
	lda fpp
	clc
	adc #3
	sta fpp
	bcc @b
	inc fpp+1
@b:	inx
	bra @f
@r:	rts

;---------------------------------------------------------------
; record 0: the header, the symbols, the procedures (a run of banks
; allocated now, its size known)
;---------------------------------------------------------------
rec0:	stz fbuf		; its size (3 bytes)
	stz fbuf+1
	stz fbuf+2
	lda #24
	sta fbuf
	stz psy
	stz psy+1
@l:	lda psy
	cmp vt_nsym
	bne @1
	lda psy+1
	cmp vt_nsym+1
	beq @p
@1:	jsr symname
	lda pw
	clc
	adc #8
	jsr addsz
	inc psy
	bne @l
	inc psy+1
	bra @l
@p:	; the procedures: up to pbtop's end
	jsr pbend
	lda pw
	jsr addsz
	lda pw+1
	clc
	adc fbuf+1
	sta fbuf+1
	bcc @a
	inc fbuf+2
@a:	; banks: size / 8192, + 1
	lda fbuf+2
	sta pk
	lda fbuf+1
	lsr pk
	ror a
	lsr pk
	ror a
	lsr pk
	ror a
	lsr pk
	ror a
	lsr pk
	ror a
	inc a
@b:	sta _vt_r0n
	jsr BankAlloc
	cmp #0
	bne @c
	lda #VE_PROGBIG
	sta vt_e
	stz vt_e+1
	stz vt_e+2
	jsr perr2
	jmp perr_text
@c:	sta _vt_r0b
	lda fbuf
	sta _vt_size
	lda fbuf+1
	sta _vt_size+1
	; the writer at the run's start
	lda _vt_r0b
	sta wb
	stz wp
	lda #$A0
	sta wp+1
	; the header
	lda #'V'
	jsr w0
	lda #'B'
	jsr w0
	lda #VB_TOKFORMAT
	jsr w0
	lda #1
	jsr w0
	lda vt_nsym
	jsr w0
	lda vt_nsym+1
	jsr w0
	lda nproc
	jsr w0
	lda #0
	jsr w0
	lda nlines
	jsr w0
	lda nlines+1
	jsr w0
	lda _vt_size+2
	jsr w0
	lda _vt_size+3
	jsr w0
	lda nidx
	jsr w0
	lda nidx+1
	jsr w0
	lda ndata
	jsr w0
	lda ndata+1
	jsr w0
	lda optint
	ora #$80
	jsr w0
	ldx #0
@d:	lda defint,x
	jsr w0
	inx
	cpx #4
	bne @d
	lda #0
	jsr w0
	jsr w0
	jsr w0
	; the symbols: kind, type, target (3), value (2), length, name
	stz psy
	stz psy+1
@s:	lda psy
	cmp vt_nsym
	bne @s1
	lda psy+1
	cmp vt_nsym+1
	jeq @procs
@s1:	jsr pattr
	ldy #13
	jsr fpeek
	jsr w0
	ldy #1
	jsr fpeek
	jsr w0
	ldy #13			; the target: a procedure's or a label's only
	jsr fpeek
	and #K_SUB | K_FUNC | K_LABEL
	beq @nt
	ldy #2
	jsr fpeek
	jsr w0
	iny
	jsr fpeek
	jsr w0
	bra @t3
@nt:	lda #0
	jsr w0
	jsr w0
@t3:	lda #0
	jsr w0
	ldy #13			; the value: a built-in constant's
	jsr fpeek
	and #K_BUILTIN
	beq @nv
	ldy #14
	jsr fpeek
	jsr w0
	iny
	jsr fpeek
	jsr w0
	bra @nm
@nv:	lda #0
	jsr w0
	jsr w0
@nm:	jsr symname
	lda pw
	jsr w0
	; the spelling: entry + 5 + length
	lda pw
	clc
	adc #5
	tay
	ldx pw
@sp:	jsr fpeek
	jsr w0
	iny
	dex
	bne @sp
	inc psy
	jne @s
	inc psy+1
	jmp @s
@procs:	; the procedures' bank, as it is
	jsr pbend
	lda _vt_pb
	sta fpb
	stz fpp
	lda #$A0
	sta fpp+1
@pc:	lda pw
	ora pw+1
	beq @done
	ldy #0
	jsr fpeek
	jsr w0
	inc fpp
	bne @pc1
	inc fpp+1
@pc1:	lda pw
	bne @pc2
	dec pw+1
@pc2:	dec pw
	bra @pc
@done:	; the other records' sizes
	lda nidx
	asl a
	sta _vt_size+4
	lda nidx+1
	rol a
	asl _vt_size+4
	rol a
	sta _vt_size+5
	lda ndata
	asl a
	sta _vt_size+6
	lda ndata+1
	rol a
	sta _vt_size+7
	stz _vt_err
	rts

; fbuf (3 bytes) += a
addsz:	clc
	adc fbuf
	sta fbuf
	bcc @r
	inc fbuf+1
	bne @r
	inc fbuf+2
@r:	rts

; pw = the procedures' bytes (the last one's header + frame end)
pbend:	stz cpi		; (walks them all: ppcur past the last)
	stz nfr
@l:	jsr pload
	lda cpi
	cmp nproc
	bcs @d
	inc cpi
	bra @l
@d:	lda ppcur
	sta pw
	lda ppcur+1
	sec
	sbc #$A0
	sta pw+1
	rts

; record 0's writer: a byte at wp in wb
w0:	phy
	phx
	ldx fpb
	phx
	ldx fpp
	phx
	ldx fpp+1
	phx
	ldx wb
	stx fpb
	ldx wp
	stx fpp
	ldx wp+1
	stx fpp+1
	ldy #0
	jsr fpoke
	pha
	inc wp
	bne @1
	inc wp+1
	lda wp+1
	cmp #$C0
	bne @1
	lda #$A0
	sta wp+1
	inc wb
@1:	pla
	plx
	stx fpp+1
	plx
	stx fpp
	plx
	stx fpb
	plx
	ply
	rts

.segment "OVL4BSS"
tclk0:	.res 4
tclk1:	.res 4
wb:	.res 1
wp:	.res 2
.segment "OVERLAY4"

;---------------------------------------------------------------
; the messages
;---------------------------------------------------------------
; the first lexing error's text (vtok.s found no prepare)
prep_lexerr:
	ldx #VE_SIZE - 1
@c:	lda vt_le,x
	sta vt_pe,x
	dex
	bpl @c

perr_text:
	; _vt_msg = the text of vt_pe; _vt_erl its line
	lda vt_pe+1
	sta _vt_erl
	lda vt_pe+2
	sta _vt_erl+1
	lda #1
	sta _vt_err
	lda vt_pe
	asl a
	tax
	lda msgs,x
	sta n1
	lda msgs+1,x
	sta n1+1
	stz opos			; the output's place
	ldx #0
@li:	lda MLine,x
	beq @li2
	phx
	jsr put_c
	plx
	inx
	bra @li
@li2:	lda vt_pe+1
	sta psy
	lda vt_pe+2
	sta psy+1
	jsr put_num
	lda #':'
	jsr put_c
	lda #' '
	jsr put_c
@l:	lda (n1)
	jeq @end
	cmp #16
	bcs @ch
	; a field: 1-4 keyword A-D, 5-8 name A-D, 9-12 number A-D,
	; 13 the character, 14 number F, 15 name D and a blank (or nothing)
	cmp #13
	beq @char
	cmp #14
	beq @numf
	cmp #15
	beq @named
	dec a
	pha
	and #3
	asl a
	tax
	lda vt_pe+3,x
	sta psy
	lda vt_pe+4,x
	sta psy+1
	pla
	lsr a
	lsr a
	beq @kw
	cmp #1
	beq @nm
	jsr put_num
	bra @nx
@kw:	jsr put_kw
	bra @nx
@nm:	jsr put_name
	bra @nx
@numf:	lda vt_pe+12
	sta psy
	lda vt_pe+13
	sta psy+1
	jsr put_num
	bra @nx
@named:	lda vt_pe+9
	sta psy
	lda vt_pe+10
	sta psy+1
	cmp #$FF
	beq @nx
	jsr put_name
	lda #' '
	jsr put_c
	bra @nx
@char:	lda #$27
	jsr put_c
	lda vt_pe+11
	jsr put_c
	lda #$27
	jsr put_c
	bra @nx
@ch:	jsr put_c
@nx:	inc n1
	jne @l
	inc n1+1
	jmp @l
@end:	ldx opos
	stz _vt_msg,x
	rts

put_c:	ldx opos
	cpx #78
	bcs @r
	sta _vt_msg,x
	inc opos
@r:	rts

; psy: a number
put_num:
	lda psy
	sta pw2
	lda psy+1
	sta pw2+1
	ldx #0
@d:	; pw2 / 10
	stz pk2
	ldy #16
@b:	asl pw2
	rol pw2+1
	rol pk2
	lda pk2
	cmp #10
	bcc @n
	sbc #10
	sta pk2
	inc pw2
@n:	dey
	bne @b
	lda pk2
	ora #'0'
	pha
	inx
	lda pw2
	ora pw2+1
	bne @d
@o:	pla
	phx
	jsr put_c
	plx
	dex
	bne @o
	rts

; psy: a name ($FFFF: nothing)
put_name:
	lda psy+1
	cmp #$FF
	beq @r
	jsr symname
	lda pw
	sta pk2
	lda pw
	clc
	adc #5
	tay
@c:	jsr fpeek
	phy
	jsr put_c
	ply
	iny
	dec pk2
	bne @c
@r:	; (pw, the message's place, was clobbered: symname's pw)
	rts

; psy: a keyword id
put_kw:	lda psy
	ldx #0
@f:	ldy kwnames,x
	beq @r
	cmp kwnames,x
	beq @y
@s:	inx
	lda kwnames,x
	bne @s
	inx
	lda psy
	bra @f
@y:	inx
@c:	lda kwnames,x
	beq @r
	phx
	jsr put_c
	plx
	inx
	bra @c
@r:	rts

kwnames:
	.byte TK_IF, "IF", 0, TK_ELSE, "ELSE", 0, TK_ELSEIF, "ELSEIF", 0
	.byte TK_END_IF, "END IF", 0, TK_WHILE, "WHILE", 0, TK_WEND, "WEND", 0
	.byte TK_REPEAT, "REPEAT", 0, TK_UNTIL, "UNTIL", 0, TK_DO, "DO", 0
	.byte TK_LOOP, "LOOP", 0, TK_FOR, "FOR", 0, TK_NEXT, "NEXT", 0
	.byte TK_SELECT_CASE, "SELECT CASE", 0, TK_CASE, "CASE", 0
	.byte TK_CASE_ELSE, "CASE ELSE", 0, TK_END_SELECT, "END SELECT", 0
	.byte TK_SUB, "SUB", 0, TK_END_SUB, "END SUB", 0, TK_FUNCTION, "FUNCTION", 0
	.byte TK_END_FUNCTION, "END FUNCTION", 0, TK_TRY, "TRY", 0, TK_CATCH, "CATCH", 0
	.byte TK_END_TRY, "END TRY", 0, KD_DIALOG, "DIALOG", 0, KD_ENDDIALOG, "END DIALOG", 0
	.byte TK_EXIT_FOR, "EXIT FOR", 0, TK_EXIT_WHILE, "EXIT WHILE", 0
	.byte TK_EXIT_DO, "EXIT DO", 0, TK_EXIT_REPEAT, "EXIT REPEAT", 0
	.byte TK_EXIT_SUB, "EXIT SUB", 0, TK_EXIT_FUNCTION, "EXIT FUNCTION", 0
	.byte TK_LOCAL, "LOCAL", 0, TK_SHARED, "SHARED", 0, 0

; the texts (vbtokens.py's): fields 1-4 keyword A-D, 5-8 name A-D, 9-12
; number A-D, 13 the character
msgs:	.addr M0, M1, M2, M3, M4, M5, M6, M7, M8, M9, M10
	.addr M11, M12, M13, M14, M15, M16, M17, M18, M19, M20, M21, M22, M23, M24
	.addr M25, M26, M27, M28, M29, M30, M31, M32, M33, M34, M35, M36, M37, M38
	.addr M39, M40, M41, M42
MLine:	.byte "Line ", 0
M0:	.byte 0
M1:	.byte "Unexpected character ", 13, 0
M2:	.byte "Line too long", 0
M3:	.byte "String too long", 0
M4:	.byte "Number too big", 0
M5:	.byte "Line number expected", 0
M6:	.byte "Number too long", 0
M7:	.byte "Name too long", 0
M8:	.byte "Line number out of range", 0
M9:	.byte "Too many names", 0
M10:	.byte "Program too big", 0
M11:	.byte 1, " without ", 2, 0
M12:	.byte 1, " missing for ", 2, " in line ", 11, 0
M13:	.byte "NEXT ", 7, " does not match FOR ", 8, " in line ", 9, 0
M14:	.byte "Two ELSE parts for IF in line ", 9, 0
M15:	.byte "ELSEIF after ELSE for IF in line ", 9, 0
M16:	.byte "Two CATCH parts for TRY in line ", 9, 0
M17:	.byte 1, " after CASE ELSE", 0
M18:	.byte "CASE expected after SELECT CASE in line ", 9, 0
M19:	.byte "THEN missing after IF", 0
M20:	.byte "THEN missing after ELSEIF", 0
M21:	.byte 1, " inside a one-line IF", 0
M22:	.byte 1, " ", 15, "inside ", 2, " ", 7, " (line ", 14, ")", 0
M23:	.byte 1, " ", 7, " defined twice (lines ", 10, " and ", 12, ")", 0
M24:	.byte "Name expected after ", 1, 0
M25:	.byte "Parameter name expected", 0
M26:	.byte "Parameter ", 7, " given twice", 0
M27:	.byte $22, ")", $22, " missing after the parameters", 0
M28:	.byte 1, " outside ", 2, 0
M29:	.byte 1, " outside a SUB or FUNCTION", 0
M30:	.byte 7, " is already local in ", 1, " ", 8, 0
M31:	.byte 7, " is LOCAL and SHARED", 0
M32:	.byte "Constant ", 7, " defined twice", 0
M33:	.byte "RETURN with a value outside a FUNCTION", 0
M34:	.byte "DEFINT takes letters", 0
M35:	.byte "Label ", 7, " defined twice (lines ", 10, " and ", 9, ")", 0
M36:	.byte "Line number ", 9, " used twice (lines ", 10, " and ", 12, ")", 0
M37:	.byte "Undefined line ", 9, 0
M38:	.byte 7, " is both a label and a ", 1, 0
M39:	.byte "Undefined label ", 7, 0
M40:	.byte "Undefined SUB ", 7, 0
M41:	.byte "Cannot assign to constant ", 7, 0
M42:	.byte 7, " is a built-in constant", 0

.endscope
