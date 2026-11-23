; VeraBASIC, the editor (DECISIONS V93): the entries of its main RAM part
; (LOW, at vb.s _ide_s0: ide/ide.cfg puts LOWENT first) and the calls
; between its banks.
;
;   _ide_s0 + 0   jmp enter: main.c's ide_back calls it once the editor's
;                 part is in its place again: the vectors, appBank (the
;                 view's bank), then B_CMD's ide_resume (the first time:
;                 the part's BSS cleared first)
;   appMain       main: B_VIEW's ide_tick; a request (ide_req) then goes
;                 to main.c's ide_go with overlay 1 mapped and made appBank
;                 (a jmp: nothing of the editor's is left on the stack while
;                 ide_go gives the interpreter its code back)
;   xcall         a routine of another bank (appBank meanwhile)
;   ide_fread     FRead into a RAM bank (the kernel reads into the caller's
;                 bank: this code is below $A000)
;   mn_*          the menus' actions (the kernel calls them with appBank,
;                 B_VIEW, mapped): B_CMD's do_*
;   vr_win ...    the window chrome: overlay 7's (VeraBASIC's main link
;                 compiled the SDK's vrwin.c there; vbgfx.s f7_win)
;
; MIT licence (LICENSE).

.setcpu "65C02"
.include "veranda.inc"
.include "x16hw.inc"

.import popa, pusha
.import _ide_banks, _ide_req, _ide_ovl1, _ide_govec
.import _ide_tick, _ide_key, _ide_press, _ide_resume, _vx_ovl7
.import _do_about, _do_new, _do_open, _do_save, _do_saveas, _do_quit, _do_saveprog, _do_makeapp
.import _do_undo, _do_cut, _do_copy, _do_paste, _do_selall, _do_format, _do_gutter
.import _do_find, _do_findnext, _do_replnext, _do_goto, _do_nexterr
.import _do_run, _do_check, _do_stop, _do_output, _do_newline
.import _do_help, _do_contents, _do_index, _do_tutorial, _do_errors
.import _dbg_cont, _dbg_step, _dbg_over, _dbg_out, _dbg_bp, _dbg_watch, _dbg_tron, _dbg_trace
.import __VRWIN__, __VRTITLE__, __VRSTATUS__
B_CMD = 6
B_DBG = 8
.import __BSS_RUN__, __BSS_SIZE__
.import _docname
.importzp ptr1
.export _vr_win, _vr_win_title, _vr_win_status
.export _xcall, _ide_fread, _fr_bank, _fr_at, _fr_n, _vb_docname, _ide_bget, _bg_bank, _bg_at, _bg_to, _bg_n
.export _ide_bput

_vb_docname = _docname          ; (main.c's: the run's title)

.segment "LOWENT"
	jmp enter

.segment "DATA"
first:	.byte 1

.segment "BSS"
_fr_bank: .res 1
_fr_at:	.res 2
_fr_n:	.res 2
_bg_bank: .res 1
_bg_at:	.res 2
_bg_to:	.res 2
_bg_n:	.res 1

.segment "CODE"

enter:	lda first
	beq @v
	stz first
	lda #<__BSS_RUN__       ; the part's variables cleared, once
	sta ptr1
	lda #>__BSS_RUN__
	sta ptr1+1
	ldx #>__BSS_SIZE__
	ldy #0
	tya
@p:	cpx #0
	beq @t
@pg:	sta (ptr1),y
	iny
	bne @pg
	inc ptr1+1
	dex
	bra @p
@t:	cpy #<__BSS_SIZE__
	beq @v
	sta (ptr1),y
	iny
	bra @t
@v:	lda #<_ide_key
	sta keyVector
	lda #>_ide_key
	sta keyVector+1
	lda #<_ide_press
	sta otherPressVec
	lda #>_ide_press
	sta otherPressVec+1
	lda #<main
	sta appMain
	lda #>main
	sta appMain+1
	lda _ide_banks          ; B_VIEW
	sta appBank
	lda _ide_banks + B_CMD
	jsr pusha
	lda #<_ide_resume
	ldx #>_ide_resume
	jmp _xcall

; appMain (B_VIEW mapped: appBank)
main:	jsr _ide_tick
	lda _ide_req
	bne @go
	rts
@go:	lda _ide_ovl1
	sta appBank
	sta ram_bank
	jmp (_ide_govec)

; void __fastcall__ xcall(unsigned char bank, void (*f)(void))
_xcall:	sta @j+1
	stx @j+2
	jsr popa
	tay
	lda appBank
	pha
	lda ram_bank
	pha
	sty appBank
	sty ram_bank
@j:	jsr $FFFF
	pla
	sta ram_bank
	pla
	sta appBank
	rts

; unsigned int __fastcall__ ide_fread(unsigned char h): FRead(h) of fr_n
; bytes at most to fr_at in bank fr_bank; the bytes read
_ide_fread:
	ldx ram_bank
	phx
	ldx _fr_bank
	stx ram_bank
	ldx _fr_at
	stx r0
	ldx _fr_at+1
	stx r0+1
	ldx _fr_n
	stx r1
	ldx _fr_n+1
	stx r1+1
	jsr FRead
	pla
	sta ram_bank
	lda r1
	ldx r1+1
	rts

; void ide_bget(void): bg_n bytes (1-255, not across $C000) from bg_at in
; bank bg_bank to bg_to below $A000 (the kernel's BankCopy costs 2,100
; cycles a call: Format reads names and lines with this)
_ide_bget:
	lda _bg_at
	sta @s+1
	lda _bg_at+1
	sta @s+2
	lda _bg_to
	sta @d+1
	lda _bg_to+1
	sta @d+2
	ldx ram_bank
	lda _bg_bank
	sta ram_bank
	ldy #0
@s:	lda $FFFF,y
@d:	sta $FFFF,y
	iny
	cpy _bg_n
	bne @s
	stx ram_bank
	rts

; void ide_bput(void): the other way: bg_n bytes from bg_to (below $A000)
; to bg_at in bank bg_bank (the debugger's data bank: DECISIONS V97)
_ide_bput:
	lda _bg_to
	sta @s+1
	lda _bg_to+1
	sta @s+2
	lda _bg_at
	sta @d+1
	lda _bg_at+1
	sta @d+2
	ldx ram_bank
	lda _bg_bank
	sta ram_bank
	ldy #0
@s:	lda $FFFF,y
@d:	sta $FFFF,y
	iny
	cpy _bg_n
	bne @s
	stx ram_bank
	rts

; the menus' actions: B_CMD's do_* (the kernel calls with B_VIEW mapped)
.macro MN name
.export .ident(.concat("_mn_", name))
.ident(.concat("_mn_", name)):
	lda #<.ident(.concat("_do_", name))
	ldx #>.ident(.concat("_do_", name))
	jmp mncall
.endmacro
	MN "about"
	MN "new"
	MN "open"
	MN "save"
	MN "saveas"
	MN "saveprog"
	MN "makeapp"
	MN "quit"
	MN "undo"
	MN "cut"
	MN "copy"
	MN "paste"
	MN "selall"
	MN "format"
	MN "gutter"
	MN "find"
	MN "findnext"
	MN "replnext"
	MN "goto"
	MN "nexterr"
	MN "run"
	MN "check"
	MN "stop"
	MN "output"
	MN "newline"
	MN "help"
	MN "contents"
	MN "index"
	MN "tutorial"
	MN "errors"
; the debugger's (B9's dbg_*, DECISIONS V97)
.macro MD name
.export .ident(.concat("_mn_", name))
.ident(.concat("_mn_", name)):
	lda #<.ident(.concat("_dbg_", name))
	ldx #>.ident(.concat("_dbg_", name))
	jmp mdcall
.endmacro
	MD "cont"
	MD "step"
	MD "over"
	MD "out"
	MD "bp"
	MD "watch"
	MD "tron"
	MD "trace"
mdcall:	ldy _ide_banks + B_DBG
	bra mnc2
mncall:	ldy _ide_banks + B_CMD
mnc2:	sta @f
	stx @f+1
	tya
	jsr pusha
	lda @f
	ldx @f+1
	jmp _xcall
@f:	.word 0

; the window chrome (vrwin.h): overlay 7's vr_win, vr_win_title,
; vr_win_status; their first argument on the C stack, the last in a/x
_vr_win:
	ldy #0
	bra vrw
_vr_win_title:
	ldy #2
	bra vrw
_vr_win_status:
	ldy #4
vrw:	sta @a
	stx @a+1
	lda vtab,y
	sta @j+1
	lda vtab+1,y
	sta @j+2
	lda ram_bank
	pha
	lda _vx_ovl7
	sta ram_bank
	lda @a
	ldx @a+1
@j:	jsr $FFFF
	pla
	sta ram_bank
	rts
@a:	.word 0
vtab:	.word __VRWIN__, __VRTITLE__, __VRSTATUS__
