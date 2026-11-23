; VeraBASIC Run: the interpreter (DECISIONS V86). It runs the prepared
; token form of docs/vbasic/FORMAT.md in slices from appMain; tools/vbasic.py
; run is the reference it must agree with, statement for statement.
;
;   vb.s       zero page, the dispatcher, the slicer, errors, control flow
;   vbexpr.s   the evaluator: precedence climbing, operators, functions
;   vbstr.s    strings (the heap, temporaries, the compacting collector),
;              arrays across banks, assignment
;   vbio.s     the console's text, PRINT, INPUT, READ, numbers, the ROM's maths
;
; The rules that make slicing work: between statements the 6502 stack holds
; nothing of BASIC (sp0); every frame is on the BASIC stack in its bank; a
; FUNCTION called inside an expression saves the evaluator's part of the
; 6502 stack into its frame and gives it back at its end. Anything a
; statement needs after an eval call is on the 6502 stack or the value
; stack, never in zero page. ram_bank is pbank (the program's bank) except
; inside the helpers that map another for a moment.
;
; MIT licence (LICENSE).

.setcpu "65C02"
.macpack longbranch
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"
.include "vb.inc"
; the interpreter's tables: RODATA; with VB_IDE (VeraBASIC, the editor:
; DECISIONS V93) in CODE, so that the place the editor's main RAM part takes
; while no program runs (_ide_s0 .. _ide_s1) holds them too
.ifdef VB_IDE
.define RO_SEG "CODE"
.else
.define RO_SEG "RODATA"
.endif
; the lexer's tables (VB_LEXTABLES) go to overlay 2 (vbtok.s)
VB_LEXTABLES = 1
.segment "OVERLAY2"
.include "tokens.inc"
.segment "CODE"
; the interpreter's code: _ide_s0 .. _ide_s1 (everything of vb.o's CODE).
; VeraBASIC, the editor (DECISIONS V93), keeps its own main RAM part here
; while no program runs: the two change places (main.c, VB_IDE)
_ide_s0:
.export _ide_s0, _ide_s1

.export _vb_slice, _vb_key, _vb_begin, _vb_rewrite, _vb_reset
.export _vb_tiny, _vb_state, _vb_how, _vb_errno, _vb_erl, _vb_test, _vb_stopreq, _vb_fault
.export _pbase, _npb, _sbank, _mbank, _cellbase, _proctab, _nprocs, _ndata
.export _limitb, _nbanks, _dynbase, _vb_relbank, _vb_reln, _vb_free, _vb_slices
.export _cbank, _tbank, _ctop, _ccy, _ccol, _cscroll, _cdirty, _cwait, _con_reset
.export _kq, _kqh, _kqt, _scr_ptr, _scr_end, _vb_aside, _vb_readrec, _vb_fread, _vb_fbank, _vb_faddr, _vb_fcount
.import _con_flush, _vb_idle
.import __BSS_RUN__, __BSS_SIZE__, __STACKSTART__, __STACKSIZE__
.export _vb_dynsize

.segment "ZEROPAGE2": zeropage
ip:	.res 2          ; the token being read (in pbank)
pbank:	.res 1
aty:	.res 1          ; the accumulator: a value (type, 5 bytes)
ac0:	.res 1
ac1:	.res 1
ac2:	.res 1
ac3:	.res 1
ac4:	.res 1
bty:	.res 1          ; the left operand of an operator
b0:	.res 1
b1:	.res 1
b2:	.res 1
b3:	.res 1
b4:	.res 1
t0:	.res 1
t1:	.res 1
t2:	.res 1
t3:	.res 1
p0:	.res 2
p1:	.res 2
p2:	.res 2
fp:	.res 2          ; the current procedure's slots (sbank)
bsp:	.res 2          ; the BASIC stack's top (sbank)
vsp:	.res 1          ; the value stack's top (bytes)
xb:	.res 1          ; the bank of p0's cell (0: main RAM)
n0:	.res 2
n1:	.res 2
scount:	.res 1
ttop:	.res 1          ; temporaries in use: slots below ttop
cproc:	.res 1          ; the current procedure ($FF: the main lines)

.segment "ZEROPAGE"
fq:	.res 2          ; the frames' trailers

.segment "BSS"
_vb_state: .res 1
_vb_how: .res 1         ; how it ended: 0 END, 1 error, 2 waiting for input with no keys (test)
_vb_errno: .res 1
_vb_erl: .res 2
.ifdef VB_IDE
_vb_esrc: .res 2        ; (the editor) the error's source line
.export _vb_esrc
_vb_eproc: .res 1       ; (the editor) the procedure an error was raised in ($FF the main lines)
.export _vb_eproc
_vx_dbg: .res 1         ; (the editor) the debugger's overlay (vbdbg.s: record 23)
.export _vx_dbg
dlhdr:	.res 6          ; the debugger: the line record's head (trace)
dbgtrap: .res 1         ; 1: an error goes back to the debugger (dbg_trapped)
dbgsp:	.res 1
.endif
_vb_test: .res 1
_vb_stopreq: .res 1
_vb_fault: .res 1
_vb_aside: .res 1
_vb_tiny: .res 1
_pbase:	.res 1          ; the program's first bank
_npb:	.res 1
_sbank:	.res 1          ; the BASIC stack's bank
_mbank:	.res 1          ; the DATA index's bank
_cellbase: .res 2
_proctab: .res 2
_nprocs: .res 1
_ndata:	.res 2
_limitb: .res 1         ; OPTION MEMORY: data banks at most
_nbanks: .res 1         ; data banks in use (heap and arrays)
_dynbase: .res 2
_vb_relbank: .res 1        ; the line index (record 2) while vb_rewrite runs
_vb_reln: .res 2
_vb_slices: .res 2
sp0:	.res 1          ; the 6502 stack between statements
sip:	.res 2          ; the statement running: its first token
sipb:	.res 1
vbase:	.res 1          ; the value stack's bottom for this procedure level
tbase:	.res 1          ; the temporaries' bottom likewise
errmsg:	.res 64         ; ERR$
_vb_errmsg = errmsg
.export _vb_errmsg
.ifdef VB_IDE
.import _edit_idle
.endif
errfile: .res 1
kerr:	.res 1          ; the kernel's error of the error being raised (ERRFILE; phase 4)
erl:	.res 2
errno:	.res 1
onerr:	.res 3          ; ON ERROR GOTO's place (ptr, bank); bank 0: none
inhandler: .res 1
errip:	.res 3          ; the failing statement (for RESUME)
tron:	.res 1
dataptr: .res 2
t_slice: .res 3         ; the slice's start: jiffies (low), the scan line
ti0:	.res 3          ; jiffies at the program's start
vstk:	.res VSTK + 6
temps:	.res NTEMP * 4
bkind:	.res 256        ; each RAM bank's use: 1 program, 2 heap
fpa:	.res 6          ; a float operand for the ROM
fpsp:	.res 1
romkeep: .res 1
sleepto: .res 3
inp_on:	.res 1          ; INPUT: 1 the prompt is out and a line is being typed
inp_ok:	.res 1          ; 1: the line is in inbuf
inp_len: .res 1
inp_more: .res 1        ; 1: typing a "??" line
inp_tgt: .res 2         ; the target INPUT goes on with
inp_tgtb: .res 1
inp_pos: .res 1         ; the next field in inbuf
inp_line: .res 1        ; LINE INPUT
inbuf:	.res 256
_kq:	.res 32         ; keys typed
_kqh:	.res 1
_kqt:	.res 1
_scr_ptr: .res 2        ; the test's keys (vb_test)
_scr_end: .res 2
hbanks:	.res 24         ; the heap's banks
nhb:	.res 1
hv:	.res 1          ; the heap's top: bank index, address
hp:	.res 2
abanks:	.res 24         ; the arrays' banks
nab:	.res 1
atop:	.res 3          ; the arrays' top (linear)
sbounce: .res 256
sbufa:	.res 256
sbufb:	.res 256
numbuf:	.res 40
; the C overlays' scratch (vbc.cfg, DECISIONS V90): sbounce .. numbuf, the
; interpreter's while a statement runs, theirs during a call; inbuf their
; arguments
_vb_scratch = sbounce
_vb_inbuf = inbuf
.assert numbuf - sbounce = 768, error, "vb.s: the scratch is not one run"
.export _vb_scratch, _vb_inbuf

; the console's text: CON_H rows of CON_W characters, a ring at $A000 of
; its own bank (cbank); the test's keys in tbank
_cbank:	.res 1
_tbank:	.res 1
_ctop:	.res 1          ; the ring row at the top
_ccy:	.res 1          ; the cursor's row (0 .. CON_H - 1, on the screen)
_ccol:	.res 1
_cscroll: .res 1        ; rows scrolled since the last drawing
_cdirty: .res CON_H     ; screen rows to draw
_cwait:	.res 1          ; 1: the cursor shows (waiting for a key)
crowp:	.res 2          ; the cursor row's text

.segment "CODE"

.macro INCIP
	inc ip
	bne :+
	inc ip+1
:
.endmacro

.macro ADDIP n
	lda ip
	clc
	adc #n
	sta ip
	bcc :+
	inc ip+1
:
.endmacro

.macro MAPP                     ; the program's bank back
	lda pbank
	sta ram_bank
.endmacro

.macro ERR code                 ; (the commonest by one jump: V107)
.if code = E_SYNTAX
	jmp err_syntax
.elseif code = E_TYPE
	jmp err_type
.elseif code = E_ILLQ
	jmp err_illq
.elseif code = E_SUBS
	jmp err_subs
.elseif code = E_NOTARR
	jmp err_notarr
.else
	lda #code
	jmp raise
.endif
.endmacro

;---------------------------------------------------------------
; the slice: appMain
;---------------------------------------------------------------
_vb_slice:
	lda _vb_state
	cmp #VS_RUN
	beq @run
	jmp _vb_idle
@run:	lda menuNumber          ; a menu open: BASIC waits (phase 3, vbx.s)
	beq @run1
	jmp _vb_idle
@run1:	tsx
	stx sp0
	inc _vb_slices
	bne @s
	inc _vb_slices+1
@s:	MAPP
.ifdef VB_LOG
	lda _vb_test
	beq @nt
	jsr idle_in             ; (the test: the time between slices, counted)
@nt:
.endif
.ifdef VBDEBUG
	lda #'@'
	sta EMU_STDOUT
	lda pbank
	jsr dbg_hex
	lda ip+1
	jsr dbg_hex
	lda ip
	jsr dbg_hex
	lda bsp+1
	jsr dbg_hex
	lda bsp
	jsr dbg_hex
	lda #10
	sta EMU_STDOUT
.endif
	jsr slice_start
	lda _vb_stopreq
	beq @go
	stz _vb_stopreq
	stz inp_on
	ERR E_STOP
@go:	lda #32
	ldx _vb_tiny            ; (the test: a statement a slice)
	beq @g1
	lda #2
@g1:	sta scount
	jmp next

.ifdef VBDEBUG
dbg_hex:
	pha
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
.endif

; the slice ends: back to the main loop (between statements: nothing of
; BASIC on the 6502 stack)
yield:	ldx sp0
	txs
.ifdef VB_LOG
	stz wd_n
	stz wd_n+1
	lda _vb_test
	beq @nt
	jsr idle_out
@nt:
.endif
	lda _cwait
	bne @f
	jsr flush_due
	bcc @r
@f:	jsr _con_flush
@r:
.ifdef VB_IDE
	lda #1                  ; (the editor: the test player goes on)
	sta _edit_idle
.endif
	lda appBank
	sta ram_bank
	rts

.ifdef VB_LOG
; the test build: a watchdog in the interrupt (vr_set_irq): 600 frames
; with no slice ended, the interpreter's state once to the log
_vb_wd:	lda _vb_state
	cmp #VS_RUN
	bne @r
	inc wd_n
	bne @r
	inc wd_n+1
	lda wd_n+1
	cmp #3
	bne @r
	ldx #0
@m:	lda MWd,x
	beq @d
	sta EMU_STDOUT
	inx
	bra @m
@d:	ldx #0
@h:	lda ip,x                ; the zero page from ip on, in hex
	jsr wd_hex
	inx
	cpx #38
	bne @h
	lda sip+1
	jsr wd_hex
	lda sip
	jsr wd_hex
	lda sipb
	jsr wd_hex
	lda #10
	sta EMU_STDOUT
@r:	rts
wd_hex:	pha
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
wd_n:	.word 0
MWd:	.byte "VB WATCHDOG ", 0
.export _vb_wd

; the test build: the emulator's cycles outside the slices (_vb_idlecyc)
idle_out:
	lda EMU_CLOCK
	sta idle_t
	lda EMU_CLOCK+1
	sta idle_t+1
	lda EMU_CLOCK+2
	sta idle_t+2
	lda EMU_CLOCK+3
	sta idle_t+3
	lda #1
	sta idle_ok
	rts
idle_in:
	lda idle_ok
	beq @r
	stz idle_ok
	lda EMU_CLOCK
	sec
	sbc idle_t
	sta idle_t
	lda EMU_CLOCK+1
	sbc idle_t+1
	sta idle_t+1
	lda EMU_CLOCK+2
	sbc idle_t+2
	sta idle_t+2
	lda EMU_CLOCK+3
	sbc idle_t+3
	sta idle_t+3
	ldx #0
	clc
@a:	lda _vb_idlecyc,x
	adc idle_t,x
	sta _vb_idlecyc,x
	inx
	txa
	eor #4
	bne @a
@r:	rts
idle_t:	.res 4
idle_ok: .byte 0
.endif
_vb_idlecyc: .res 4
.export _vb_idlecyc

; carry set if the console's last drawing is 1/4 s old
flush_due:
	jsr K_RDTIM
	sec
	sbc lastflush
	cmp #15
	bcc @no
	jsr K_RDTIM
	sta lastflush
	sec
	rts
@no:	clc
	rts
lastflush: .byte 0

slice_start:
	jsr K_RDTIM
	sta t_slice
	lda VERA_SCAN_L
	sta t_slice+1
	lda VERA_IEN
	and #$40
	sta t_slice+2
	rts

; carry set when the slice has run its 8 ms (252 scan lines of 525)
slice_over:
	lda _vb_tiny
	beq @t
	sec
	rts
@t:
	jsr K_RDTIM
	sec
	sbc t_slice
	beq @same
	cmp #1
	bne @yes
	; one frame boundary: 525 - start + now
	jsr scanline
	clc
	adc #<525
	tax
	tya
	adc #>525
	tay
	txa
	sec
	sbc t_slice+1
	tax
	tya
	sbc #0
	tay
	lda t_slice+2
	beq @1
	dey                     ; start's bit 8
@1:	txa
	bra @cmp
@same:	jsr scanline
	sec
	sbc t_slice+1
	tax
	tya
	sbc #0
	tay
	lda t_slice+2
	beq @2
	dey
@2:	txa
@cmp:	; y:a = lines
	cpy #0
	bmi @no
	bne @yes
	cmp #252
	bcs @yes
@no:	clc
	rts
@yes:	sec
	rts

; y:a = the scan line
scanline:
	ldy #0
	lda VERA_IEN
	and #$40
	beq @1
	iny
@1:	lda VERA_SCAN_L
	rts

;---------------------------------------------------------------
; the dispatcher
;---------------------------------------------------------------
next:	dec scount
	bne next1
	jsr slice_over
	bcc @more
	jmp yield
@more:	lda #32
	sta scount
next1:	lda (ip)
	beq eol
	cmp #':'
	bne stmt
	INCIP
	bra next1

eol:	INCIP                   ; the next record
	lda (ip)
	bne @1
	jmp prog_end
@1:	lda ip+1                ; past this bank's 7936 bytes: the next bank
	cmp #$A0 + PSTRIDE
	bcc @2
	sbc #PSTRIDE
	sta ip+1
	inc pbank
	MAPP
@2:	lda tron
	beq @3
	jsr trace
@3:	ADDIP 6
	jmp next

; a statement: a = its first byte
stmt:	ldx ip
	stx sip
	ldx ip+1
	stx sip+1
	ldx pbank
	stx sipb
	ldx ttop                ; the last statement's temporaries
	cpx tbase
	beq @t
	pha
	jsr free_temps
	pla
@t:	stz vsp                 ; (vbase: 0, a FUNCTION keeps its caller's values in its frame)
	cmp #$80
	bcs @kw
	cmp #T_VAR
	bne @n1
	jsr st_assign
	jmp endstmt
@n1:	cmp #T_NAMEREF
	bne @n2
	jmp st_nameref
@n2:	cmp #T_COMMENT
	beq @rem
	cmp #$27
	beq @rem
@sy:	ERR E_SYNTAX
@rem:	jmp st_rem
@k1:	cmp #T_EXT
	bne @sy
	jmp ext_stmt            ; a Veranda statement (vbx.s)
@kw:	cmp #$C8                ; ($C8-$FE: not a statement's token)
	bcs @k1
	INCIP
	asl a
	tax
	jsr stmt_disp
endstmt:
	lda (ip)
	beq @ok
	cmp #':'
	beq @ok
	cmp #TK_ELSE
	beq @ok
	cmp #$27
	beq @ok
	ERR E_SYNTAX
@ok:	jmp next
stmt_disp:
	jmp (stmttab,x)

; a statement that moved ip elsewhere: on from there (any depth of calls)
jumped:	ldx sp0
	txs
	jmp next

; the end of a statement must be here
need_end:
	lda (ip)
	beq @ok
	cmp #':'
	beq @ok
	cmp #TK_ELSE
	beq @ok
	cmp #$27
	beq @ok
	ERR E_SYNTAX
@ok:	rts

; the end of the program's lines: the events' turn, if it has handlers
prog_end:
	jmp main_end

;---------------------------------------------------------------
; places: a record's offset in record 1 <-> (bank, address)
;---------------------------------------------------------------
; n0 = an offset -> ip, pbank (mapped)
off_to_ip:
	lda n0+1
	jsr div31               ; x = the bank's number, a = the page in it
	clc
	adc #$A0
	sta ip+1
	txa
	clc
	adc _pbase
	sta pbank
	sta ram_bank
	lda n0
	sta ip
	rts

; a (an offset's high byte) -> x = a / 31 (the program's bank), a = a mod 31
div31:	ldx #0
@l:	cmp #PSTRIDE
	bcc @r
	sbc #PSTRIDE
	inx
	bra @l
@r:	rts

; the offset of ip (pbank) -> n0
ip_to_off:
	lda pbank
	sec
	sbc _pbase
	tax
	lda mul31,x
	clc
	adc ip+1
	sec
	sbc #$A0
	sta n0+1
	lda ip
	sta n0
	rts

; a $0B offset at ip -> n0; ip past it (E_SYNTAX if none)
block:	lda (ip)
	cmp #T_BLOCK
	beq @1
	ERR E_SYNTAX
@1:	ldy #1
	lda (ip),y
	sta n0
	iny
	lda (ip),y
	sta n0+1
	ADDIP 3
	rts

; the token at offset n0: a = its first byte (ip, pbank unchanged)
tok_at:	lda ip
	pha
	lda ip+1
	pha
	lda pbank
	pha
	jsr off_to_ip
	lda (ip)
	sta t3
	pla
	sta pbank
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	lda t3
	rts

; the word at offset n0 + 2 (a block word's own $0B offset) -> n0
partner_of:
	lda ip
	pha
	lda ip+1
	pha
	lda pbank
	pha
	jsr off_to_ip
	ldy #2
	lda (ip),y
	tax
	iny
	lda (ip),y
	sta n0+1
	stx n0
	pla
	sta pbank
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	rts

; to a line record: p1 its address, a its bank (0: none) -> ip at its tokens
goto_rec:
	sta pbank
	sta ram_bank
	lda p1
	sta ip
	lda p1+1
	sta ip+1
	lda tron
	beq @1
	jsr trace
@1:	ADDIP 6
	rts

; the target of the TAG_LINEREF / TAG_NAMEREF at ip -> p1, a (bank); ip past it
ref_target:
	lda (ip)
	cmp #T_LINEREF
	beq @ok
	cmp #T_NAMEREF
	beq @ok
	ERR E_SYNTAX
@ok:	ldy #3
	lda (ip),y
	sta p1
	iny
	lda (ip),y
	sta p1+1
	iny
	lda (ip),y
	pha
	ADDIP 6
	pla
	bne @r
	ldy #1                  ; (a line that is not there: ON ERROR GOTO 0)
	lda #0
@r:	rts

; ip at the token after the current one
skip_tok:
	lda (ip)
	cmp #T_EXT
	beq @2
	cmp #$0C
	bcs @1
	tax
	lda toklen,x
	bne @n
	; float, string, comment, data: by their length bytes
	cpx #T_FLOAT
	bne @s
	ldy #6
	lda (ip),y
	clc
	adc #7
	bra @n
@s:	ldy #1
	lda (ip),y
	clc
	adc #2
@n:	clc
	adc ip
	sta ip
	bcc @r
	inc ip+1
@r:	rts
@1:	INCIP
	rts
@2:	ADDIP 2
	rts
toklen:	.byte 1, 3, 3, 3, 0, 0, 3, 6, 6, 0, 0, 3

; ip to the end of the statement (':' or the line's end; ELSE outside
; parentheses)
skip_stmt:
	stz t3
@l:	lda (ip)
	beq @r
	ldx t3
	bne @3
	cmp #':'
	beq @r
	cmp #TK_ELSE
	beq @r
@3:	cmp #'('
	bne @4
	inc t3
@4:	cmp #')'
	bne @5
	dec t3
@5:	jsr skip_tok
	bra @l
@r:	rts

; ip to the line's $00
skip_line:
@l:	lda (ip)
	beq @r
	jsr skip_tok
	bra @l
@r:	rts

; "," at ip: carry set and skipped
accept_comma:
	lda (ip)
	cmp #','
	beq acc_yes
	clc
	rts
acc_yes:
	INCIP
	sec
	rts

; the keyword a at ip: carry set and skipped
accept_kw:
	cmp (ip)
	beq acc_yes
	clc
	rts

; the character a must be at ip
expect:	cmp (ip)
	bne @e
	INCIP
	rts
@e:	ERR E_SYNTAX

expect_rp:
	lda #')'
	bra expect
expect_lp:
	lda #'('
	bra expect

; at the end of a statement? (zero flag set)
at_end:	lda (ip)
	beq @r
	cmp #':'
	beq @r
	cmp #$27
	beq @r
	cmp #TK_ELSE
@r:	rts

;---------------------------------------------------------------
; the BASIC stack: frames in sbank, [bytes][size lo, size hi, kind]
;---------------------------------------------------------------
; n1 = size: room for a frame of n1 bytes, p2 = its base (bsp); sbank mapped
frame_new:
	lda bsp
	sta p2
	clc
	adc n1
	tax
	lda bsp+1
	sta p2+1
	adc n1+1
	cmp #>STACKTOP
	bcc @ok
	bne @full
	cpx #<STACKTOP
	bcc @ok
	beq @ok
@full:	MAPP
	ERR E_STACK
@ok:	lda _sbank
	sta ram_bank
	rts

; the frame at p2 of n1 bytes and kind a: its trailer, bsp past it (sbank mapped)
frame_push:
	pha
	lda p2
	clc
	adc n1
	sta bsp
	lda p2+1
	adc n1+1
	sta bsp+1
	stz nc_ok
	ldy #$FD                ; bsp - 3 .. bsp - 1
	lda bsp
	sec
	sbc #3
	sta fq
	lda bsp+1
	sbc #0
	sta fq+1
	lda n1
	sta (fq)
	ldy #1
	lda n1+1
	sta (fq),y
	iny
	pla
	sta (fq),y
	MAPP
	rts

; the top frame: a = its kind (0: none), p2 = its base, n1 its size (sbank mapped)
frame_top:
	lda _sbank
	sta ram_bank
	lda bsp+1
	cmp #$A0
	bne @1
	lda bsp
	bne @1
	lda #0
	rts
@1:	lda bsp
	sec
	sbc #3
	sta fq
	lda bsp+1
	sbc #0
	sta fq+1
	lda (fq)
	sta n1
	ldy #1
	lda (fq),y
	sta n1+1
	lda bsp
	sec
	sbc n1
	sta p2
	lda bsp+1
	sbc n1+1
	sta p2+1
	iny
	lda (fq),y
	rts

; the frame under the one at p2: the same (from p2 as the top)
frame_below:
	lda p2+1
	cmp #$A0
	bne @1
	lda p2
	bne @1
	lda #0
	rts
@1:	lda p2
	sec
	sbc #3
	sta fq
	lda p2+1
	sbc #0
	sta fq+1
	lda (fq)
	sta n1
	ldy #1
	lda (fq),y
	sta n1+1
	lda p2
	sec
	sbc n1
	sta p2
	lda p2+1
	sbc n1+1
	sta p2+1
	iny
	lda (fq),y
	rts

; the top frame popped (a procedure's: as by its END): carry set if it
; was a CALL frame (then the procedure has been left)
frame_pop:
	jsr frame_top
	beq @none
	cmp #FK_CALL
	bne @1
	jsr leave
	sec
	rts
@1:	cmp #FK_SELECT
	bne @2
	ldy #0                  ; a string held by the frame: dead
	lda (p2),y
	cmp #TY_S
	bne @2
	lda p2
	clc
	adc #1
	sta p1
	lda p2+1
	adc #0
	sta p1+1
	lda _sbank
	jsr cell_dead
@2:	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	MAPP
	clc
	rts
@none:	MAPP
	clc
	rts

; the frames popped down to the one at p2, and it
pop_to_p2:
	lda p2
	sta pt_at
	lda p2+1
	sta pt_at+1
@p:	jsr frame_top
	lda p2
	cmp pt_at
	bne @pp
	lda p2+1
	cmp pt_at+1
	beq @last
@pp:	jsr frame_pop
	bra @p
@last:	jmp frame_pop
pt_at:	.word 0

; pop the FOR, SELECT and TRY frames whose statement lies between the
; offsets n1 (lo) and n0 (hi), down to any other frame (a block left)
pop_inside:
	lda n0
	sta lo_hi
	lda n0+1
	sta lo_hi+1
	lda n1
	sta lo_lo
	lda n1+1
	sta lo_lo+1
@l:	jsr frame_top
	cmp #FK_FOR
	beq @for
	cmp #FK_SELECT
	beq @sel
	cmp #FK_TRY
	beq @try
	bra @done
@for:	ldy #17
	bra @chk
@sel:	ldy #6
	bra @chk
@try:	ldy #5
@chk:	lda (p2),y
	sta t0
	iny
	lda (p2),y
	sta t1
	; lo <= pos <= hi ?
	lda t0
	cmp lo_lo
	lda t1
	sbc lo_lo+1
	bcc @done
	lda lo_hi
	cmp t0
	lda lo_hi+1
	sbc t1
	bcc @done
	jsr frame_pop
	bra @l
@done:	MAPP
	rts
lo_lo:	.word 0
lo_hi:	.word 0

; drop the frames above and including the first FOR frame whose FOR is at
; offset n0 (none such before a CALL frame: carry clear)
pop_for_at:
	jsr frame_top
@l:	cmp #FK_FOR
	bne @n
	ldy #17
	lda (p2),y
	cmp n0
	bne @n
	iny
	lda (p2),y
	cmp n0+1
	bne @n
	; pop down to it, then it
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	MAPP
	sec
	rts
@n:	cmp #FK_CALL
	beq @no
	cmp #0
	beq @no
	jsr frame_below
	bra @l
@no:	MAPP
	clc
	rts

;---------------------------------------------------------------
; errors
;---------------------------------------------------------------
err_syntax:
	lda #E_SYNTAX
	.byte $2C               ; (bit abs: the next lda skipped)
err_type:
	lda #E_TYPE
	.byte $2C
err_illq:
	lda #E_ILLQ
	.byte $2C
err_subs:
	lda #E_SUBS
	.byte $2C
err_notarr:
	lda #E_NOTARR
; a = the error: to the innermost TRY, ON ERROR, or the program stops
raise:	sta errno
	lda #<err_fetch         ; ERR$: its message (from overlay 1)
	ldx #>err_fetch
	jsr ovl_call
raise2:
.ifdef VB_IDE
	lda dbgtrap             ; (the debugger evaluating: back to it)
	beq @nt
	jmp dbg_trapped
@nt:	lda cproc
	sta _vb_eproc
.endif
	ldx sp0
	txs
	stz romkeep
	stz rom_bank
	cli
	stz inp_on
	stz _cwait
	MAPP
	lda kerr
	sta errfile
	stz kerr
	jsr find_erl
	lda errno
	cmp #E_STOP
	jeq @fatal
	; the innermost TRY
	jsr frame_top
@t:	cmp #0
	beq @notry
	cmp #FK_TRY
	beq @try
	jsr frame_below
	bra @t
@try:	; everything above it left (procedures as by their END), then it
	lda p2
	sta tryp
	lda p2+1
	sta tryp+1
@u:	jsr frame_top
	lda p2
	cmp tryp
	bne @pop
	lda p2+1
	cmp tryp+1
	beq @got
@pop:	jsr frame_pop
	bra @u
@got:	; p2: the TRY frame
	ldy #0
	lda (p2),y
	sta p1
	iny
	lda (p2),y
	sta p1+1
	iny
	lda (p2),y
	pha
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	pla
	sta pbank
	sta ram_bank
	lda p1
	sta ip
	lda p1+1
	sta ip+1
	lda vbase
	sta vsp
	jsr free_temps
	jmp next
@notry:	lda onerr+2
	beq @fatal
	lda inhandler
	bne @fatal
	; the FUNCTIONs being run are left (as the reference does)
	jsr unwind_functions
	lda #1
	sta inhandler
	lda sip
	sta errip
	lda sip+1
	sta errip+1
	lda sipb
	sta errip+2
	lda onerr
	sta ip
	lda onerr+1
	sta ip+1
	lda onerr+2
	sta pbank
	sta ram_bank
	lda vbase
	sta vsp
	jsr free_temps
	jmp next
@fatal:	jsr unwind_functions
	jsr con_message_err
	lda #1
	sta _vb_how
	jmp stop_program

tryp:	.word 0

; leave every FUNCTION frame (and what is above the lowest one), as the
; reference does when an error goes to ON ERROR or stops the program
unwind_functions:
	stz uf_at+1
	jsr frame_top
@l:	cmp #0
	beq @d
	cmp #FK_CALL
	bne @n
	jsr call_flags          ; a = the CALL frame's flags
	and #1
	beq @n
	lda p2
	sta uf_at
	lda p2+1
	sta uf_at+1
@n:	jsr frame_below
	bra @l
@d:	MAPP
	lda uf_at+1
	beq @r
@u:	jsr frame_top           ; pop until the frame at uf_at is gone
	beq @r
	lda p2
	pha
	lda p2+1
	pha
	jsr frame_pop
	pla
	cmp uf_at+1
	bne @nx
	pla
	cmp uf_at
	beq @r
	bra @u
@nx:	pla
	bra @u
@r:	MAPP
	rts
uf_at:	.word 0

; the CALL frame at p2 (n1 bytes): a = its flags (sbank mapped)
call_flags:
	lda p2
	clc
	adc n1
	sta p1
	lda p2+1
	adc n1+1
	sta p1+1
	ldy #$FF - 12 + 7 + 1   ; (p1 - 13 + 7 = p1 - 6)
	lda p1
	sec
	sbc #6
	sta p1
	bcs @1
	dec p1+1
@1:	lda (p1)
	rts

; a routine of overlay 1 (a/x its address) called with that bank mapped,
; the caller's back after (it may use main RAM's routines that do not map
; banks themselves)
ovl_call:
	sta @j+1
	stx @j+2
	lda ram_bank
	pha
	lda appBank
	sta ram_bank
@j:	jsr $FFFF
	pla
	sta ram_bank
	rts

; ERL: the line of the statement at sip (sipb): its number, or its source line
find_erl:
	lda ip
	pha
	lda ip+1
	pha
	lda pbank
	pha
	lda sipb
	sta pbank
	lda sip
	sta ip
	lda sip+1
	sta ip+1
	jsr ip_to_off
	lda n0
	sta fe_s
	lda n0+1
	sta fe_s+1              ; the statement's offset
	stz fe_r
	stz fe_r+1              ; a record's
	stz erl
	stz erl+1
.ifdef VB_IDE
	stz _vb_esrc
	stz _vb_esrc+1
.endif
@l:	lda fe_r
	sta n0
	lda fe_r+1
	sta n0+1
	jsr off_to_ip
	lda (ip)
	beq @d                  ; (not found)
	clc
	adc fe_r
	sta fe_e
	lda fe_r+1
	adc #0
	sta fe_e+1              ; its end
	lda fe_s                ; statement < end: this record
	cmp fe_e
	lda fe_s+1
	sbc fe_e+1
	bcc @found
	lda fe_e
	sta fe_r
	lda fe_e+1
	sta fe_r+1
	bra @l
@found:
.ifdef VB_IDE
	ldy #3                  ; (the editor: the source line, for its jump)
	lda (ip),y
	sta _vb_esrc
	iny
	lda (ip),y
	sta _vb_esrc+1
.endif
	ldy #1
	lda (ip),y
	sta erl
	iny
	lda (ip),y
	sta erl+1
	ora erl
	bne @d
	iny
	lda (ip),y
	sta erl
	iny
	lda (ip),y
	sta erl+1
@d:	lda erl
	sta _vb_erl
	lda erl+1
	sta _vb_erl+1
	lda errno
	sta _vb_errno
	pla
	sta pbank
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	rts
fe_s:	.word 0
fe_r:	.word 0
fe_e:	.word 0

; TRON: "VB TRON n" for the line record at ip (a record's first byte);
; VeraBASIC Run alone: "TRON n" by LogText (DECISIONS V97). The editor
; (VB_IDE): the debugger's line hook (vbdbg.s dbg_line: the trace pane,
; breakpoints, steps), the record's head copied for it first
.ifdef VB_IDE
trace:	ldy #5
@h:	lda (ip),y
	sta dlhdr,y
	dey
	bpl @h
	lda #<dbg_line
	ldx #>dbg_line
	ldy _vx_dbg
	jmp bcall

; an error while the debugger evaluates (raise2, dbgtrap): back to the
; debugger's call (vbdbg.s dtry), carry set
dbg_trapped:
	stz romkeep
	stz rom_bank
	cli
	stz dbgtrap
	ldx dbgsp
	txs
	lda _vx_dbg
	sta ram_bank
	sec
	rts
.else
trace:	ldy #1
	lda (ip),y
	sta t0
	iny
	lda (ip),y
	sta t1
	ora t0
	bne @n
	iny
	lda (ip),y
	sta t0
	iny
	lda (ip),y
	sta t1
@n:
.ifndef VB_TEST
	lda #<tron_log          ; (VeraBASIC Run: LogText, overlay 1)
	ldx #>tron_log
	jmp ovl_call
.else
	ldx #0
@m:	lda MTron,x
	beq @d
	sta EMU_STDOUT
	inx
	bra @m
@d:	lda t0
	ldx t1
	jsr int_to_text         ; numbuf (" 12")
	ldx #0
@o:	lda numbuf,x
	beq @e
	sta EMU_STDOUT
	inx
	bra @o
@e:	lda #10
	sta EMU_STDOUT
	rts
.endif

; "TRON n" (t0, t1) to LogText (the emulator's console; nothing on
; hardware): VeraBASIC Run's TRON (DECISIONS V97; the test build logs
; "VB TRON n" itself)
.ifndef VB_TEST
.segment "OVERLAY1"
tron_log:
	lda t0
	ldx t1
	jsr int_to_text
	ldx #0
@c:	lda MTron+3,x
	sta sbounce,x
	beq @c2
	inx
	bra @c
@c2:	ldy #0
@c3:	lda numbuf,y
	sta sbounce,x
	beq @c4
	inx
	iny
	bra @c3
@c4:	LoadW r0, sbounce
	jmp LogText
.segment "CODE"
.endif
.endif

; the program stops (END, an error, the end of its lines)
end_program:
	stz _vb_how
stop_program:
	ldx sp0
	txs
	stz inp_on
	stz _cwait
	lda #VS_END
	sta _vb_state
	jsr con_end
	lda appBank
	sta ram_bank
	rts                     ; (from vb_slice)

;---------------------------------------------------------------
; statements: ip is past their token; rts goes on with the end check,
; jmp jumped when ip was moved
;---------------------------------------------------------------
st_rem:	jsr skip_line
	jmp next

st_nameref:
	; a label's definition, or a SUB called by its name
	ldy #2
	lda (ip),y
	bmi @call
	ADDIP 6
	lda #':'
	jsr expect
	jmp next
@call:	dey
	lda (ip),y
	sta t0
	ADDIP 6
	lda t0
	jsr proc_ptr            ; p2 = the procedure's entry
	lda #0                  ; no parentheses of its own
	jsr call_args
	jsr need_end
	jsr enter_sub
	jmp jumped

st_call:
	lda (ip)
	cmp #T_NAMEREF
	beq @1
	ERR E_SYNTAX
@1:	ldy #2
	lda (ip),y
	bmi @2
	ERR E_SYNTAX
@2:	dey
	lda (ip),y
	sta t0
	ADDIP 6
	lda t0
	jsr proc_ptr
	lda #1                  ; parentheses if there are any
	jsr call_args
	jsr need_end
	jsr enter_sub
	jmp jumped

st_let:	lda (ip)
	cmp #T_VAR
	beq st_assign
	ERR E_SYNTAX

; variable = expression
st_assign:
	ldy #2                  ; (V107) the quick way: a global variable, not
	lda (ip),y              ; an array, a constant or a FUNCTION
	cmp #$08
	bcc @gen
	sta p0+1
	dey
	lda (ip),y
	sta p0
	ldy #7
	lda (p0),y
	cmp #TY_S + 1
	bcs @gen
	sta t0
	ldy #3
	lda (ip),y
	cmp #'='
	bne @gen
	stz xb
	ADDIP 3
	bra @go
@gen:	jsr lvalue              ; p0, xb, t0
@go:	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	lda (ip)
	cmp #'='
	bne @e
	INCIP
	jsr eval
	pla
	sta t0
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	jmp store
@e:	ERR E_SYNTAX

push_target:
	ply                     ; (the return address)
	plx
	lda p0
	pha
	lda p0+1
	pha
	lda xb
	pha
	lda t0
	pha
	phx
	phy
	rts

pull_target:
	ply
	plx
	pla
	sta t0
	pla
	sta xb
	pla
	sta p0+1
	pla
	sta p0
	phx
	phy
	rts

st_goto:
	jsr ref_target
	jsr goto_rec
	jmp jumped

st_gosub:
	lda ip                  ; the target
	pha
	lda ip+1
	pha
	jsr skip_tok
	jsr need_end
	lda #FR_GOSUB
	sta n1
	stz n1+1
	jsr frame_new
	ldy #0
	lda ip
	sta (p2),y
	iny
	lda ip+1
	sta (p2),y
	iny
	lda pbank
	sta (p2),y
	lda #FK_GOSUB
	jsr frame_push
	pla
	sta ip+1
	pla
	sta ip
	jsr ref_target
	jsr goto_rec
	jmp jumped

st_return:
	jsr at_end
	beq @gosub
	; RETURN value (in a FUNCTION)
	lda cproc
	cmp #$FF
	beq @syn
	jsr proc_ptr
	ldy #2
	lda (p2),y
	and #1
	beq @syn
	jsr eval
	jsr need_end
	jsr set_result
	jmp end_function
@syn:	ERR E_SYNTAX
@gosub:	jsr frame_top
	cmp #FK_GOSUB
	beq @g
	cmp #0
	beq @err
	cmp #FK_CALL
	beq @err
	jsr frame_pop
	bra @gosub
@err:	MAPP
	ERR E_RETURN
@g:	ldy #0
	lda (p2),y
	sta ip
	iny
	lda (p2),y
	sta ip+1
	iny
	lda (p2),y
	sta pbank
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	MAPP
	jmp jumped

st_on:	lda (ip)
	cmp #T_EXT
	bne @core
	lda #0                  ; ON event CALL procedure (vbui.s)
	jmp ext_stmt_a
@core:	lda #TK_ERROR
	jsr accept_kw
	bcc @n
	lda #TK_GOTO
	jsr accept_kw
	bcs @1
	ERR E_SYNTAX
@1:	jsr ref_target          ; p1, a: 0 for line 0
	pha
	jsr need_end
	pla
	sta onerr+2
	beq @off
	lda p1
	clc
	adc #6
	sta onerr
	lda p1+1
	adc #0
	sta onerr+1
@off:	rts
@n:	jsr eval
	jsr toint
	lda ac0
	pha
	lda ac1
	pha
	lda #TK_GOTO
	jsr accept_kw
	lda #0
	bcs @2
	lda #TK_GOSUB
	jsr accept_kw
	bcs @3
	ERR E_NOTYET
@3:	lda #1
@2:	sta on_sub              ; 1: GOSUB
	pla
	sta on_n+1
	pla
	sta on_n
	stz on_t+1              ; the target chosen (0: none)
	lda #1
	sta on_k
@t:	lda on_n+1
	bne @skip
	lda on_k
	cmp on_n
	bne @skip
	lda ip
	sta on_t
	lda ip+1
	sta on_t+1
@skip:	inc on_k
	jsr skip_tok
	jsr accept_comma
	bcs @t
	jsr need_end
	lda on_t+1
	bne @go
	rts                     ; out of range: nothing
@go:	lda on_sub
	beq @j
	lda #FR_GOSUB
	sta n1
	stz n1+1
	jsr frame_new
	ldy #0
	lda ip
	sta (p2),y
	iny
	lda ip+1
	sta (p2),y
	iny
	lda pbank
	sta (p2),y
	lda #FK_GOSUB
	jsr frame_push
@j:	lda on_t
	sta ip
	lda on_t+1
	sta ip+1
	jsr ref_target
	jsr goto_rec
	jmp jumped
on_sub:	.byte 0
on_n:	.word 0
on_t:	.word 0
on_k:	.byte 0

; IF condition THEN ...
st_if:	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr eval
	lda #TK_GOTO            ; V2's IF ... GOTO line
	jsr accept_kw
	bcc @th
	jsr truth
	bne @gt
	pla
	sta n0+1
	pla
	sta n0
	jmp if_false
@gt:	pla
	pla
	jsr ref_target
	jsr goto_rec
	jmp jumped
@th:	lda #TK_THEN
	jsr accept_kw
	bcs @1
	ERR E_SYNTAX
@1:	jsr truth
	bne @true
	pla
	sta n0+1
	pla
	sta n0
	jmp if_false
@true:	pla
	pla
	lda (ip)
	cmp #T_LINEREF
	bne @r
	jsr ref_target
	jsr goto_rec
@r:	jmp jumped

; the IF or ELSEIF was false: on at its partner n0
if_false:
	jsr tok_at
	cmp #TK_ELSEIF
	bne @n1
	jsr off_to_ip
	INCIP
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr ip_to_off_sip       ; (errors in this condition: its line)
	jsr eval
	lda #TK_THEN
	jsr accept_kw
	bcs @t
	ERR E_SYNTAX
@t:	jsr truth
	bne @yes
	pla
	sta n0+1
	pla
	sta n0
	bra if_false
@yes:	pla
	pla
	jmp jumped
@n1:	cmp #TK_ELSE
	bne @n2
	jsr off_to_ip
	INCIP
	jsr block
	lda (ip)
	cmp #T_LINEREF
	bne @j
	jsr ref_target
	jsr goto_rec
@j:	jmp jumped
@n2:	pha
	jsr off_to_ip
	pla
	cmp #TK_END_IF
	bne @j
	INCIP
	jmp jumped

; sip := ip - 1 (the ELSEIF being tested)
ip_to_off_sip:
	lda ip
	sec
	sbc #4
	sta sip
	lda ip+1
	sbc #0
	sta sip+1
	lda pbank
	sta sipb
	rts

; ELSE or ELSEIF met after the part before it: on past END IF
st_else:
st_elseif:
	jsr block
to_end_if:
	jsr tok_at
	cmp #TK_ELSEIF
	beq @p
	cmp #TK_ELSE
	beq @p
	jsr off_to_ip
	lda (ip)
	cmp #TK_END_IF
	bne @j
	INCIP
@j:	jmp jumped
@p:	jsr partner_of
	bra to_end_if

st_endif:
	rts

st_rem2:
	jmp st_rem

;---------------------------------------------------------------
; loops
;---------------------------------------------------------------
; FOR v = a TO b [STEP s]
st_for:	jsr block
	lda n0                  ; the NEXT
	pha
	lda n0+1
	pha
	lda (ip)
	cmp #T_VAR
	beq @v
	ERR E_SYNTAX
@v:	jsr lvalue
	lda t0
	and #CT_ARRAY | CT_FUNC
	bne @syn                ; (an element: lvalue says so with t0's bit 3)
	lda t1
	bne @syn
	lda t0
	and #CT_TYPE
	cmp #TY_S
	bne @ok
	ERR E_TYPE
@syn:	ERR E_SYNTAX
@ok:	jsr push_target
	lda #'='
	jsr expect
	jsr eval
	jsr pull_target
	jsr push_target
	jsr store               ; (keeps p0, xb, t0)
	lda #TK_TO
	jsr accept_kw
	bcs @to
	ERR E_SYNTAX
@to:	jsr eval
	jsr pull_target
	jsr push_target
	lda t0
	jsr convert             ; the limit, as the variable
	jsr vpush
	lda #TK_STEP
	jsr accept_kw
	bcc @one
	jsr eval
	jsr pull_target
	jsr push_target
	lda t0
	jsr convert
	bra @st
@one:	jsr pull_target
	jsr push_target
	lda t0
	and #CT_TYPE
	jsr one_of              ; acc = 1 of that type
@st:	jsr need_end
	jsr pull_target
	; acc = step, vstk top = limit; the old FOR of this variable goes,
	; with what is above it
	jsr for_drop_same
	; no pass at all?
	pla
	sta n0+1
	pla
	sta n0
	ora n0+1
	beq @push
	lda n0
	pha
	lda n0+1
	pha
	jsr for_test            ; carry set: on
	pla
	sta n0+1
	pla
	sta n0
	bcs @push
	; to the NEXT, past its first variable; NEXT j, i goes on with i
	lda vbase
	sta vsp
	jsr off_to_ip
	INCIP
	jsr block
	lda (ip)
	cmp #T_VAR
	bne @nv
	jsr lvalue
@nv:	jsr accept_comma
	bcc @ne
	stz n0
	stz n0+1
	jmp next_vars
@ne:	jsr need_end
	jmp jumped
@push:	; the frame: cell, type, limit, step, the body, the FOR's offset
	ldx #0                  ; (the body: past a ":")
	lda (ip)
	cmp #':'
	bne @nc
	inx
@nc:	stx fr_skip
	lda #FR_FOR
	sta n1
	stz n1+1
	jsr frame_new
	ldy #0
	lda p0
	sta (p2),y
	iny
	lda p0+1
	sta (p2),y
	iny
	lda xb
	sta (p2),y
	iny
	lda t0
	sta (p2),y
	ldx vsp
	ldy #4
@lim:	lda vstk-5,x
	sta (p2),y
	inx
	iny
	cpy #9
	bne @lim
	ldx #0
@stp:	lda ac0,x
	sta (p2),y
	inx
	iny
	cpy #14
	bne @stp
	lda ip
	clc
	adc fr_skip
	sta (p2),y
	iny
	lda ip+1
	adc #0
	sta (p2),y
	iny
	lda pbank
	sta (p2),y
	iny
	; the FOR's offset (sip)
	phy
	lda ip
	pha
	lda ip+1
	pha
	lda sip
	sta ip
	lda sip+1
	sta ip+1
	lda _sbank
	pha
	lda sipb
	sta pbank
	jsr ip_to_off
	pla
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	ply
	lda n0
	sta (p2),y
	iny
	lda n0+1
	sta (p2),y
	lda #FK_FOR
	jsr frame_push
	; the NEXT cache: a global variable's loop
	lda xb
	bne @r
	lda t0
	and #CT_TYPE
	sta nc_type
	cmp #TY_S
	beq @r
	ldx vsp                 ; (a float's limit and step, whole)
	ldy #0
@cf:	lda vstk-5,x
	sta nc_limf,y
	lda ac0,y
	sta nc_stepf,y
	inx
	iny
	cpy #5
	bne @cf
	lda n0
	sta nc_for
	lda n0+1
	sta nc_for+1
	lda p0
	sta nc_cell
	lda p0+1
	sta nc_cell+1
	ldx vsp
	lda vstk-5,x
	sta nc_lim
	lda vstk-4,x
	sta nc_lim+1
	lda ac0
	sta nc_step
	lda ac1
	sta nc_step+1
	lda ip
	clc
	adc fr_skip
	sta nc_body
	lda ip+1
	adc #0
	sta nc_body+1
	lda pbank
	sta nc_bank
	lda #1
	sta nc_ok
	sta nc_live
	lda bsp
	sta nc_bsp
	lda bsp+1
	sta nc_bsp+1
@r:	rts

; the BASIC stack lowered (V107): the NEXT cache's FOR gone if bsp is
; below its frame's end; on again if its frame is the top once more (a
; GOSUB, a SUB called inside the loop returned)
nc_pop:	lda bsp
	cmp nc_bsp
	lda bsp+1
	sbc nc_bsp+1
	bcc @gone
	lda bsp
	eor nc_bsp
	bne @r
	lda bsp+1
	eor nc_bsp+1
	bne @r
	lda nc_live
	sta nc_ok
@r:	rts
@gone:	stz nc_live
	stz nc_ok
	rts

; FOR's old frame of the same cell (p0, xb), and what is above it
for_drop_same:
	jsr frame_top
@l:	cmp #0
	beq @r
	cmp #FK_CALL
	beq @r
	cmp #FK_FOR
	bne @n
	ldy #0
	lda (p2),y
	cmp p0
	bne @n
	iny
	lda (p2),y
	cmp p0+1
	bne @n
	iny
	lda (p2),y
	cmp xb
	bne @n
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	bra @r
@n:	jsr frame_below
	bra @l
@r:	MAPP
	rts

; does the loop go on: the cell (p0, xb, type t0) against the limit (vstk
; top) with the step acc's sign; carry set if so
for_test:
	lda t0
	and #CT_TYPE
	cmp #TY_I
	bne @f
	jsr cell_get_int        ; n1 = the value
	ldx vsp
	; step >= 0: v <= limit; else v >= limit
	lda ac1
	bmi @down
	lda vstk-5,x            ; limit - v >= 0
	sec
	sbc n1
	lda vstk-4,x
	sbc n1+1
	bvc @1
	eor #$80
@1:	bmi @no
	sec
	rts
@down:	lda n1                  ; v - limit >= 0
	sec
	sbc vstk-5,x
	lda n1+1
	sbc vstk-4,x
	bvc @2
	eor #$80
@2:	bmi @no
	sec
	rts
@no:	clc
	rts
@f:	; float: c = cmp(v, limit); go on if (step < 0 ? c >= 0 : c <= 0)
	jsr cell_to_fpa         ; fpa = the value
	lda ac0
	pha
	lda ac1
	pha
	ldx vsp
	jsr fcmp_fpa_vstk       ; a = -1/0/1 (fpa vs the limit at vstk - 6)
	sta t2
	pla
	sta t3                  ; the step's sign byte
	pla
	ldx t2
	beq @yes
	tay                     ; step 0: as positive
	beq @pos
	lda t3
	bmi @neg
@pos:	cpx #1
	beq @no
@yes:	sec
	rts
@neg:	cpx #$FF
	beq @no
	sec
	rts

; NEXT [v [, v] ...]
st_next:
	; the fast way: the FOR the NEXT cache holds (the top frame, an
	; integer loop of a global variable: FOR filled it, nothing has moved
	; the BASIC stack since)
	lda nc_ok
	jeq nx_slow
	ldy #1
	lda (ip),y
	cmp nc_for
	jne nx_slow
	iny
	lda (ip),y
	cmp nc_for+1
	jne nx_slow
	iny
	lda (ip),y
	cmp #T_VAR
	bne @nv
	iny
	lda (ip),y
	cmp nc_cell
	jne nx_slow
	iny
	lda (ip),y
	cmp nc_cell+1
	jne nx_slow
	lda #6
	bra @n1
@nv:	lda #3
@n1:	sta nx_t
	lda nc_cell
	sta p0
	lda nc_cell+1
	sta p0+1
	lda nc_type
	cmp #TY_I
	jne nf_float
	lda (p0)
	clc
	adc nc_step
	sta n1
	ldy #1
	lda (p0),y
	adc nc_step+1
	bvs @end                ; past the integers: the loop ends, v stays
	sta n1+1
	bit nc_step+1
	bmi @dn
	lda nc_lim              ; v <= limit
	cmp n1
	lda nc_lim+1
	sbc n1+1
	bvc @c1
	eor #$80
@c1:	bmi @endst
	bra @again
@dn:	lda n1                  ; v >= limit
	cmp nc_lim
	lda n1+1
	sbc nc_lim+1
	bvc @c2
	eor #$80
@c2:	bmi @endst
@again:	lda n1
	sta (p0)
	lda n1+1
	sta (p0),y
	lda nc_body
	sta ip
	lda nc_body+1
	sta ip+1
	lda nc_bank
	cmp pbank
	beq @sb
	sta pbank
	sta ram_bank
@sb:	pla                     ; (this handler's return: on at the body)
	pla
	jmp next
@endst:	lda n1
	sta (p0)
	lda n1+1
	sta (p0),y
@end:	lda bsp                 ; the frame goes
	sec
	sbc #FR_FOR
	sta bsp
	lda bsp+1
	sbc #0
	sta bsp+1
	jsr nc_pop
	lda nx_t
	clc
	adc ip
	sta ip
	bcc @e1
	inc ip+1
@e1:	stz nx_first
	jsr accept_comma
	bcs @more
	rts
@more:	jmp nv_go

; the fast NEXT of a float loop: v = v + step (ARG = v, FAC = step, as the
; reference: the ROM's faddt), then v against the limit (its sign the step's)
nf_float:
	jsr rom_in
	lda p0
	ldy p0+1
	jsr FP_CONUPK
	lda #<nc_stepf
	ldy #>nc_stepf
	jsr FP_MOVFM
	lda FAC
	jsr FP_FADDT
	ldx p0
	ldy p0+1
	jsr FP_MOVMF
	jsr rom_out
	ldy #4
@c:	lda (p0),y
	sta fpa,y
	lda nc_limf,y
	sta fcb,y
	dey
	bpl @c
	jsr fcmp                ; a = v against the limit
	tax
	beq @go
	lda nc_stepf            ; a step of 0 counts as positive
	beq @pos
	lda nc_stepf+1
	bmi @neg
@pos:	cpx #1
	beq @end
	bra @go
@neg:	cpx #$FF
	beq @end
@go:	lda nc_body
	sta ip
	lda nc_body+1
	sta ip+1
	lda nc_bank
	cmp pbank
	beq @sb
	sta pbank
	sta ram_bank
@sb:	pla
	pla
	jmp next
@end:	lda bsp
	sec
	sbc #FR_FOR
	sta bsp
	lda bsp+1
	sbc #0
	sta bsp+1
	jsr nc_pop
	lda nx_t
	clc
	adc ip
	sta ip
	bcc @e1
	inc ip+1
@e1:	stz nx_first
	jsr accept_comma
	bcs @more
	rts
@more:	jmp nv_go
nx_slow:
	jsr block               ; n0: the FOR (0 inside a one-line IF)
	lda #1
	sta nx_first
	bra nv_go
next_vars:                      ; (FOR with no pass: the variables after the first)
	stz nx_first
nv_go:	stz t1                  ; no variable
	lda (ip)
	cmp #T_VAR
	bne @find
	jsr lvalue
	lda #1
	sta t1
@find:	; the frame: (first and n0) the FOR at n0 with this variable; else
	; the innermost FOR (with this variable)
	jsr frame_top
@l:	cmp #0
	beq @err
	cmp #FK_CALL
	beq @err
	cmp #FK_FOR
	bne @n
	lda nx_first
	beq @var
	lda n0
	ora n0+1
	beq @var
	ldy #17
	lda (p2),y
	cmp n0
	bne @n
	iny
	lda (p2),y
	cmp n0+1
	bne @n
@var:	lda t1
	beq @got
	ldy #0
	lda (p2),y
	cmp p0
	bne @n
	iny
	lda (p2),y
	cmp p0+1
	bne @n
	iny
	lda (p2),y
	cmp xb
	beq @got
@n:	jsr frame_below
	bra @l
@err:	MAPP
	ERR E_NEXT
@got:	; the frames above it go
	lda p2
	clc
	adc #FR_FOR
	sta bsp
	lda p2+1
	adc #0
	sta bsp+1
	jsr nc_pop
	; v = v + step
	ldy #3
	lda (p2),y
	sta t0
	and #CT_TYPE
	cmp #TY_I
	beq @int
	jmp nx_float
@int:	ldy #0
	lda (p2),y
	sta p0
	iny
	lda (p2),y
	sta p0+1
	iny
	lda (p2),y
	sta xb
	ldy #9                  ; the step
	lda (p2),y
	sta n1
	iny
	lda (p2),y
	sta n1+1
	ldy #4
	lda (p2),y              ; the limit
	sta b0
	iny
	lda (p2),y
	sta b1
	lda xb
	beq @m
	sta ram_bank
@m:	lda (p0)
	clc
	adc n1
	sta t2
	ldy #1
	lda (p0),y
	adc n1+1
	sta t3
	bvs @over               ; past the end of the integers: the loop ends
	lda t2
	sta (p0)
	lda t3
	sta (p0),y
	lda _sbank
	sta ram_bank
	; on? step >= 0: v <= limit
	lda n1+1
	bmi @dn
	lda b0
	sec
	sbc t2
	lda b1
	sbc t3
	bvc @c1
	eor #$80
@c1:	bmi @over
	bra @again
@dn:	lda t2
	sec
	sbc b0
	lda t3
	sbc b1
	bvc @c2
	eor #$80
@c2:	bmi @over
@again:	ldy #14
	lda (p2),y
	sta ip
	iny
	lda (p2),y
	sta ip+1
	iny
	lda (p2),y
	sta pbank
	sta ram_bank
	jmp jumped
@over:	; the loop's end: its frame goes
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	MAPP
nx_more:
	stz nx_first
	jsr accept_comma
	bcc @e
	jmp nv_go
@e:	rts
nx_first: .byte 0
; the NEXT cache: the top FOR frame's essentials (nc_ok: valid)
nc_ok:	.byte 0
nc_bsp:	.word 0                 ; bsp with the FOR's frame on top
nc_live: .byte 0                ; 1: that frame is still there
nc_for:	.word 0
nc_cell: .word 0
nc_lim:	.word 0
nc_step: .word 0
nc_body: .word 0
nc_bank: .byte 0
nc_type: .byte 0
nc_limf: .res 5
nc_stepf: .res 5
fr_skip: .byte 0
nx_v:	.word 0
nx_t:	.byte 0

nx_float:
	ldy #0
	lda (p2),y
	sta p0
	iny
	lda (p2),y
	sta p0+1
	iny
	lda (p2),y
	sta xb
	lda p2
	pha
	lda p2+1
	pha
	; acc = v + step (ARG = v, FAC = step)
	ldy #9
	ldx #0
@s:	lda (p2),y
	sta ac0,x
	iny
	inx
	cpx #5
	bne @s
	lda ac1                  ; the step's sign, for the test
	pha
	jsr cell_to_fpa
	MAPP
	jsr fp_add_fpa_acc      ; acc = fpa + acc
	; store into the cell
	lda xb
	beq @m
	sta ram_bank
@m:	ldy #4
@w:	lda ac0,y
	sta (p0),y
	dey
	bpl @w
	MAPP
	pla
	sta t3                  ; step sign
	pla
	sta p2+1
	pla
	sta p2
	; c = cmp(v, limit)
	ldx #4
@f:	lda ac0,x
	sta fpa,x
	dex
	bpl @f
	lda _sbank
	sta ram_bank
	ldy #4
	ldx #0
@l:	lda (p2),y
	sta b0,x
	iny
	inx
	cpx #5
	bne @l
	MAPP
	jsr fcmp_fpa_b          ; a = cmp(fpa, b)
	tax
	beq @go
	lda t3
	bmi @neg
	cpx #1
	beq @end
	bra @go
@neg:	cpx #$FF
	beq @end
@go:	lda _sbank
	sta ram_bank
	ldy #14
	lda (p2),y
	sta ip
	iny
	lda (p2),y
	sta ip+1
	iny
	lda (p2),y
	sta pbank
	sta ram_bank
	jmp jumped
@end:	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	MAPP
	jmp nx_more

; WHILE condition
st_while:
	jsr block
while_go:
	lda n0
	pha
	lda n0+1
	pha
	jsr eval
	jsr need_end
	jsr truth
	beq @no
	pla
	pla
	rts
@no:	pla
	sta n0+1
	pla
	sta n0
	jsr sip_off_n1          ; n1 = this statement's offset
	jsr pop_inside
	jsr off_to_ip           ; the WEND
	INCIP
	jsr block
	jmp jumped

; n1 = the offset of the statement running (sip)
sip_off_n1:
	lda n0
	pha
	lda n0+1
	pha
	lda ip
	pha
	lda ip+1
	pha
	lda pbank
	pha
	lda sip
	sta ip
	lda sip+1
	sta ip+1
	lda sipb
	sta pbank
	jsr ip_to_off
	lda n0
	sta n1
	lda n0+1
	sta n1+1
	pla
	sta pbank
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	pla
	sta n0+1
	pla
	sta n0
	rts

st_wend:
	jsr block               ; the WHILE: tested again
	jsr off_to_ip
	lda ip
	sta sip
	lda ip+1
	sta sip+1
	lda pbank
	sta sipb
	INCIP
	jsr block
	jmp while_go

st_repeat:
	jsr block
	rts

st_until:
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr eval
	jsr need_end
	jsr truth
	bne @done
	pla
	sta n0+1
	pla
	sta n0
	jsr off_to_ip
	INCIP
	jsr block
	jmp jumped
@done:	pla
	pla
	rts

; DO [WHILE|UNTIL c]
st_do:	jsr block
do_go:	lda n0
	pha
	lda n0+1
	pha
	jsr loop_cond           ; z clear: go on
	php
	jsr need_end
	plp
	bne @go
	pla
	sta n0+1
	pla
	sta n0
	jsr sip_off_n1
	jsr pop_inside
	jsr off_to_ip           ; the LOOP, past its condition
	INCIP
	jsr block
	jsr skip_stmt
	jmp jumped
@go:	pla
	pla
	rts

; [WHILE c | UNTIL c]: zero flag clear when the loop goes on
loop_cond:
	lda #TK_WHILE
	jsr accept_kw
	bcc @u
	jsr eval
	jmp truth
@u:	lda #TK_UNTIL
	jsr accept_kw
	bcc @none
	jsr eval
	jsr truth
	beq @t
	lda #0
	rts
@t:	lda #1
	rts
@none:	lda #1
	rts

st_loop:
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr loop_cond
	php
	jsr need_end
	plp
	bne @back
	pla
	pla
	rts
@back:	pla
	sta n0+1
	pla
	sta n0
	jsr off_to_ip           ; the DO: tested again
	lda ip
	sta sip
	lda ip+1
	sta sip+1
	lda pbank
	sta sipb
	INCIP
	jsr block
	jmp do_go

; EXIT FOR / WHILE / DO / REPEAT: past the loop's last word
st_exitloop:
	jsr block               ; n0: NEXT, WEND, LOOP or UNTIL
	lda n0
	pha
	lda n0+1
	pha
	jsr partner_of          ; n0: the loop's first word
	lda n0
	sta n1
	lda n0+1
	sta n1+1
	pla
	sta n0+1
	pla
	sta n0
	lda n0
	pha
	lda n0+1
	pha
	lda n1
	pha
	lda n1+1
	pha
	jsr pop_inside
	pla
	sta n1+1
	pla
	sta n1
	pla
	sta n0+1
	pla
	sta n0
	jsr tok_at
	sta t2
	cmp #TK_NEXT
	bne @go
	lda n0
	pha
	lda n0+1
	pha
	lda n1
	sta n0
	lda n1+1
	sta n0+1
	jsr pop_for_at
	pla
	sta n0+1
	pla
	sta n0
@go:	lda t2
	pha
	jsr off_to_ip
	INCIP
	jsr block
	pla
	cmp #TK_WEND
	beq @j
	jsr skip_stmt
@j:	jmp jumped

;---------------------------------------------------------------
; SELECT CASE
;---------------------------------------------------------------
st_select:
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr eval
	jsr need_end
	; the frame: the value (a string: held by the frame), the offset
	lda #FR_SELECT
	sta n1
	stz n1+1
	jsr frame_new
	lda p2
	pha
	lda p2+1
	pha
	lda aty
	cmp #TY_S
	bne @num
	; the string to the frame (bytes 1-4: its descriptor)
	lda p2
	clc
	adc #1
	sta p0
	lda p2+1
	adc #0
	sta p0+1
	lda _sbank
	sta xb
	stz t1
	lda #TY_S
	sta (p2)
	MAPP
	jsr sassign
	bra @st
@num:	ldy #0
	lda aty
	sta (p2),y
	ldx #0
@v:	lda ac0,x
	iny
	sta (p2),y
	inx
	cpx #5
	bne @v
	MAPP
@st:	pla
	sta p2+1
	pla
	sta p2
	jsr sip_off_n1
	lda _sbank
	sta ram_bank
	ldy #6
	lda n1
	sta (p2),y
	iny
	lda n1+1
	sta (p2),y
	lda #FR_SELECT
	sta n1
	stz n1+1
	lda #FK_SELECT
	jsr frame_push
	pla
	sta n0+1
	pla
	sta n0
select_from:
	jsr tok_at
	cmp #TK_CASE_ELSE
	bne @1
	jsr off_to_ip
	INCIP
	jsr block
	jmp jumped
@1:	cmp #TK_END_SELECT
	bne @2
	jsr off_to_ip
	INCIP
	jsr select_pop
	jmp jumped
@2:	jsr off_to_ip           ; a CASE: its values
	lda ip
	sta sip
	lda ip+1
	sta sip+1
	lda pbank
	sta sipb
	INCIP
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr case_matches        ; carry set: it matches
	pla
	sta n0+1
	pla
	sta n0
	bcc select_from
	jmp jumped

; CASE v [TO w] | IS op v [, ...]: carry set if the SELECT's value matches
case_matches:
	lda #0
	pha                     ; the hits (on the 6502 stack: a FUNCTION may run a SELECT)
@l:	lda #TK_IS
	jsr accept_kw
	bcc @val
	lda (ip)
	jsr tok_prec
	beq @syn
	tya
	cmp #OP_EQ
	bcc @syn
	cmp #OP_GE + 1
	bcs @syn
	pha
	INCIP
	jsr eval
	jsr sel_to_b
	pla
	jsr binop_b
	jsr truth
	beq @next
	jsr cm_inc
	bra @next
@syn:	ERR E_SYNTAX
@val:	jsr eval
	lda #TK_TO
	jsr accept_kw
	bcs @range
	jsr sel_to_b
	lda #OP_EQ
	jsr binop_b
	jsr truth
	beq @next
	jsr cm_inc
	bra @next
@range:	jsr vpush               ; v
	jsr eval                ; w
	jsr vpush
	; sel >= v
	ldx vsp
	jsr vpeek_x12           ; acc = v (vstk - 12)
	jsr sel_to_b
	lda #OP_GE
	jsr binop_b
	jsr truth
	beq @r0
	ldx vsp
	jsr vpeek_x6            ; acc = w
	jsr sel_to_b
	lda #OP_LE
	jsr binop_b
	jsr truth
	beq @r0
	jsr cm_inc
@r0:	lda vsp
	sec
	sbc #12
	sta vsp
@next:	jsr accept_comma
	jcs @l
	jsr need_end
	pla
	beq @no
	sec
	rts
@no:	clc
	rts
; the hits on the stack (under this call's return): one more
cm_inc:	tsx
	inc $0103,x
	rts

; b = the SELECT's value (the top SELECT frame)
sel_to_b:
	jsr frame_top
@l:	cmp #FK_SELECT
	beq @got
	cmp #0
	beq @err
	jsr frame_below
	bra @l
@err:	MAPP
	ERR E_SYNTAX
@got:	ldy #0
	lda (p2),y
	sta bty
	cmp #TY_S
	beq @s
	ldx #0
@v:	iny
	lda (p2),y
	sta b0,x
	inx
	cpx #5
	bne @v
	MAPP
	rts
@s:	lda p2                  ; a reference to the frame's descriptor
	clc
	adc #1
	sta b1
	lda p2+1
	adc #0
	sta b2
	lda _sbank
	sta b3
	lda #SK_VAR
	sta b4
	MAPP
	rts

; CASE met after the part before it: on to END SELECT
st_case:
	jsr block
@l:	jsr tok_at
	cmp #TK_END_SELECT
	beq @e
	jsr partner_of
	bra @l
@e:	jsr off_to_ip
	INCIP
	jsr select_pop
	jmp jumped

st_endselect:
	jsr select_pop
	rts

; the innermost SELECT frame popped, with those above it
select_pop:
	jsr frame_top
@l:	cmp #0
	beq @err
	cmp #FK_CALL
	beq @err
	cmp #FK_SELECT
	beq @got
	jsr frame_below
	bra @l
@err:	MAPP
	ERR E_SYNTAX
@got:	jmp pop_to_p2

;---------------------------------------------------------------
; TRY ... CATCH ... END TRY, ERROR, RESUME
;---------------------------------------------------------------
st_try:	jsr block               ; n0: CATCH or END TRY
	lda n0
	sta ty_t
	lda n0+1
	sta ty_t+1
	jsr sip_off_n1
	lda n1
	sta ty_s
	lda n1+1
	sta ty_s+1
	; where an error goes: past CATCH and its offset, or past END TRY
	lda ip
	pha
	lda ip+1
	pha
	lda pbank
	pha
	jsr off_to_ip
	lda (ip)
	pha
	INCIP
	pla
	cmp #TK_CATCH
	bne @et
	jsr block
@et:	lda ip
	sta ty_c
	lda ip+1
	sta ty_c+1
	lda pbank
	sta ty_c+2
	pla
	sta pbank
	sta ram_bank
	pla
	sta ip+1
	pla
	sta ip
	lda #FR_TRY
	sta n1
	stz n1+1
	jsr frame_new
	ldy #0
@w:	lda ty_c,y
	sta (p2),y
	iny
	cpy #7
	bne @w
	lda vsp
	sta (p2),y
	iny
	lda ttop
	sta (p2),y
	lda #FK_TRY
	jmp frame_push
ty_c:	.res 3
ty_t:	.word 0                 ; (ty_c + 3)
ty_s:	.word 0                 ; (ty_c + 5)

; CATCH met: the TRY part ended well, past END TRY
st_catch:
	jsr block
	lda n0
	pha
	lda n0+1
	pha
	jsr frame_top
@l:	cmp #0
	beq @d
	cmp #FK_CALL
	beq @d
	cmp #FK_TRY
	beq @got
	jsr frame_below
	bra @l
@got:	jsr pop_to_p2
@d:	MAPP
	pla
	sta n0+1
	pla
	sta n0
	jsr off_to_ip
	INCIP
	jmp jumped

; END TRY: the end of a TRY without CATCH: its frame
st_endtry:
	jsr frame_top
	cmp #FK_TRY
	bne @r
	; its target is this END TRY?
	lda ip
	pha
	lda ip+1
	pha
	lda ip
	bne @1
	dec ip+1
@1:	dec ip
	jsr ip_to_off
	pla
	sta ip+1
	pla
	sta ip
	lda _sbank
	sta ram_bank
	ldy #3
	lda (p2),y
	cmp n0
	bne @r
	iny
	lda (p2),y
	cmp n0+1
	bne @r
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
@r:	MAPP
	rts

st_error:
	jsr eval
	jsr toint
	lda ac0
	pha
	lda ac1
	pha
	lda #','
	jsr accept_kw
	bcc @nm
	jsr eval
	jsr str_to_buf          ; sbufa, t0 = length
	pla
	sta t1
	pla
	sta t2
	jsr need_end
	ldx t0
	cpx #63
	bcc @c
	ldx #63
@c:	stz errmsg,x
@m:	dex
	bmi @n
	lda sbufa,x
	sta errmsg,x
	bra @m
@n:	lda t1
	bne @ill
	lda t2
	beq @ill
	sta errno
	jmp raise2
@nm:	jsr need_end
	pla
	bne @ill
	pla
	beq @ill
	jmp raise
@ill:	ERR E_ILLQ

st_resume:
	lda inhandler
	bne @1
	ERR E_RESUME
@1:	stz inhandler
	lda #TK_NEXT
	jsr accept_kw
	bcc @2
	jsr need_end
	jsr to_errip
	; past the statement that failed (a whole IF line)
	lda (ip)
	cmp #TK_IF
	bne @s
	jsr skip_line
	jmp jumped
@s:	jsr skip_tok
	jsr skip_stmt
	jmp jumped
@2:	jsr at_end
	bne @3
	jsr to_errip
	jmp jumped
@3:	lda ip
	pha
	lda ip+1
	pha
	jsr skip_tok
	jsr need_end
	pla
	sta ip+1
	pla
	sta ip
	jsr ref_target
	jsr goto_rec
	jmp jumped

to_errip:
	lda errip
	sta ip
	lda errip+1
	sta ip+1
	lda errip+2
	sta pbank
	sta ram_bank
	rts

;---------------------------------------------------------------
; the rest of the simple statements
;---------------------------------------------------------------
st_end:	jmp end_program

st_stop:
.ifdef VB_IDE
	lda #<dbg_stop          ; (the editor: a break, DECISIONS V97)
	ldx #>dbg_stop
	ldy _vx_dbg
	jmp bcall
.endif
	ERR E_STOP

st_cont:
	rts

st_skip:			; LOCAL, SHARED, DATA, DEFINT: nothing at run time
	jsr skip_stmt
	rts

st_option:
	lda #TK_INTEGER
	jsr accept_kw
	bcs @r
	lda #TK_MEMORY
	jsr accept_kw
	bcs @m
	ERR E_SYNTAX
@m:	jsr eval
	jsr toint
	lda ac1
	bne @ill
	lda ac0
	beq @ill
	cmp #65
	bcs @ill
	cmp #24
	bcc @s
	lda #24
@s:	sta _limitb
@r:	rts
@ill:	ERR E_ILLQ

st_poke:
	jsr eval
	jsr to_address          ; n1
	lda n1
	pha
	lda n1+1
	pha
	lda #','
	jsr expect
	jsr eval
	jsr toint
	jsr need_end
	pla
	sta p1+1
	pla
	sta p1
	lda ac1
	bne @ill
	lda p1+1
	cmp #$A0
	bcs @ill
	lda ac0
	sta (p1)
	rts
@ill:	ERR E_ILLQ

st_sys:	jsr eval
	jsr to_address
	jsr need_end
	lda n1+1
	cmp #$A0
	bcc @1
	ERR E_ILLQ
@1:	lda n1
	sta @j+1
	lda n1+1
	sta @j+2
	stz ram_bank
@j:	jsr $FFFF
	MAPP
	rts

; (tron: bit 0 TRON; bit 1 the editor's debugger has breakpoints, a step
; or a pause armed: vbdbg.s; any bit set, each line entered calls trace)
st_tron:
	lda #1
	tsb tron
	rts

st_troff:
	lda #1
	trb tron
	rts

st_wait:
	lda #TK_EVENTS
	jsr accept_kw
	lda _vx_any
	bne @e
	jmp end_program
@e:	lda #<xwait
	ldx #>xwait
	jmp x6call              ; (dispatches a handler or yields)

st_doevents:
	jsr need_end
	lda _vx_any
	beq @y
	lda #<xdoev
	ldx #>xdoev
	jmp x6call              ; (dispatches a handler or yields)
@y:	jmp yield_after         ; the slice ends; on after this statement

; SLEEP frames: the statement is run again until the time has come
st_sleep:
	lda sleepto+2
	bne @wait
	jsr eval
	jsr toint
	jsr need_end
	lda ac1
	bmi @ill
	jsr K_RDTIM
	clc
	adc ac0
	sta sleepto
	txa
	adc ac1
	sta sleepto+1
	lda #1
	sta sleepto+2
	sta xnn                 ; (the first time: an event point)
	bra @w1
@wait:	stz xnn
@w1:	lda _vx_any
	beq @w2
	lda #<xsleep
	ldx #>xsleep
	jsr x6call              ; (dispatches a handler, or returns)
@w2:	jsr K_RDTIM
	sec
	sbc sleepto
	txa
	sbc sleepto+1
	bpl @done
	lda sip                 ; not yet: this statement again next slice
	sta ip
	lda sip+1
	sta ip+1
	lda sipb
	sta pbank
	jmp yield
@done:	stz sleepto+2
	lda sip                 ; past the statement
	sta ip
	lda sip+1
	sta ip+1
	INCIP
	jmp skip_stmt
@ill:	ERR E_ILLQ

; the slice ends here; the program goes on after the statement at ip
yield_after:
	jmp yield

;---------------------------------------------------------------
; procedures
;---------------------------------------------------------------
; a = a procedure's number -> p2 its entry (8 bytes)
proc_ptr:
	stz p2+1
	asl a
	rol p2+1
	asl a
	rol p2+1
	asl a
	rol p2+1
	clc
	adc _proctab
	sta p2
	lda p2+1
	adc _proctab+1
	sta p2+1
	rts

; SUB or FUNCTION met in the flow: on past its END
st_sub:	jsr block
	jsr off_to_ip
	INCIP
	jmp jumped

st_endsub:
	lda cproc
	cmp #$FF
	bne @1
	ERR E_NOSUB
@1:	jsr leave
	jmp jumped

; END FUNCTION, EXIT FUNCTION, RETURN value
st_endfunction:
end_function:
	lda cproc
	cmp #$FF
	bne @1
	ERR E_NOSUB
@1:	jsr proc_ptr
	ldy #2
	lda (p2),y
	and #1
	bne @f
	jsr leave               ; (EXIT in a SUB)
	jmp jumped
@f:	jsr leave_function      ; back into the expression that called it
	rts                     ; (not reached)

st_exitproc:
	jsr block
	bra end_function

; acc -> the FUNCTION's result (slot 0)
set_result:
	lda fp
	sta p0
	lda fp+1
	sta p0+1
	lda _sbank
	sta xb
	sta ram_bank
	ldy #7
	lda (p0),y
	sta t0
	stz t1
	MAPP
	jmp store

; a call's arguments into the value stack for the procedure at p2; a = 1:
; parentheses if any (CALL), 0: none (a SUB by its name; a ( there is an
; argument's), 2: a FUNCTION (parentheses if any, none: no arguments)
call_args:
	sta ca_mode
	lda p2
	pha
	lda p2+1
	pha
	stz ca_n
	stz ca_paren
	lda ca_mode
	beq @noparen
	lda (ip)
	cmp #'('
	bne @np
	INCIP
	lda #1
	sta ca_paren
	lda (ip)
	cmp #')'
	jeq @args_done
	bra @args
@np:	lda ca_mode
	cmp #2
	jeq @args_done          ; a FUNCTION named alone
@noparen:
	jsr at_end
	jeq @args_done
@args:	; argument ca_n: the slot of parameter ca_n
	pla
	sta p2+1
	pla
	sta p2
	lda p2
	pha
	lda p2+1
	pha
	lda ca_n
	ldy #0
	cmp (p2),y              ; more than its parameters
	bcc @ok
	ERR E_ARGS
@ok:	jsr param_type          ; a = the slot's type byte
	sta ca_ty
	; (an argument may call a FUNCTION, which makes calls of its own: the
	; state kept on the 6502 stack, which goes with the FUNCTION's frame)
	lda ca_n
	pha
	lda ca_mode
	pha
	lda ca_paren
	pha
	lda ca_ty
	pha
	and #$20
	bne @arr
	lda ca_ty
	bmi @ref
	; a value
	jsr eval
	jsr ca_back
	lda ca_ty
	and #CT_TYPE
	jsr convert
	jsr vpush
	bra @nx
@arr:	lda (ip)
	cmp #T_VAR
	beq @ac1
	ERR E_NOTARR
@ac1:	jsr cellref             ; p0, xb, t0 (the array's cell, a reference followed)
	jsr expect_lp
	jsr expect_rp
	lda t0
	and #CT_ARRAY
	bne @ac2
	ERR E_NOTARR
@ac2:	jsr ca_back
	bra @pushref
@ref:	lda (ip)
	cmp #T_VAR
	beq @r1
	ERR E_BYREF
@r1:	jsr lvalue
	jsr ca_back
	lda t0
	eor ca_ty
	and #CT_TYPE
	beq @pushref
	ERR E_TYPE
@pushref:
	lda #$80
	sta aty
	lda p0
	sta ac0
	lda p0+1
	sta ac1
	lda xb
	sta ac2
	jsr vpush
@nx:	inc ca_n
	jsr accept_comma
	bcc @args_done
	jmp @args
@args_done:
	lda ca_paren
	beq @c
	jsr expect_rp
@c:	pla
	sta p2+1
	pla
	sta p2
	lda ca_n
	ldy #0
	cmp (p2),y
	beq @r
	ERR E_ARGS
@r:	rts
; call_args's state back from the 6502 stack
ca_back:
	ply
	plx
	pla
	sta ca_ty
	pla
	sta ca_paren
	pla
	sta ca_mode
	pla
	sta ca_n
	phx
	phy
	rts
ca_mode: .byte 0
ca_n:	.byte 0
ca_paren: .byte 0
ca_ty:	.byte 0

; the type byte of parameter ca_n of the procedure at p2 (slot ca_n, + 1
; for a FUNCTION: slot 0 is its result)
param_type:
	ldy #6
	lda (p2),y
	sta p1
	iny
	lda (p2),y
	sta p1+1
	ldy #2
	lda (p2),y
	and #1
	clc
	adc ca_n
	tay
	lda (p1),y
	rts

; the procedure at p2 entered: its frame (its arguments from the value
; stack), the body at its start. ip is where it returns. A FUNCTION's
; call (fcall) leaves the evaluator's 6502 stack in place: fc_n bytes from
; $0101 + fc_sp, copied into the frame here (V107: no buffer between)
enter_sub:
	stz fc_n
enter_proc:
	lda p2
	sta ep_p
	sta p1
	lda p2+1
	sta ep_p+1
	sta p1+1                ; p1: the entry (main RAM), until the slots
	; the arguments' values: from vsp - parameters * 6
	lda (p1)
	sta ep_np
	asl a
	adc ep_np
	asl a
	sta t3
	lda vsp
	sec
	sbc t3
	sta ep_v
	; a FUNCTION keeps its caller's values (the value stack under its
	; arguments) in its frame: ep_fv bytes
	ldy #2
	lda (p1),y
	and #1
	sta ep_first            ; (slot 0 its result)
	beq @sb
	lda ep_v
@sb:	sta ep_fv
	; the frame's size: slots * 8 + FR_CALL + fc_n + ep_fv
	ldy #1
	lda (p1),y
	sta ep_ns
	stz n1+1
	asl a
	rol n1+1
	asl a
	rol n1+1
	asl a
	rol n1+1
	clc
	adc #FR_CALL
	bcc @1
	inc n1+1
@1:	clc
	adc fc_n
	bcc @1b
	inc n1+1
@1b:	clc
	adc ep_fv
	sta n1
	sta ep_size
	bcc @2
	inc n1+1
@2:	lda n1+1
	sta ep_size+1
	jsr frame_new           ; p2 = the frame's base (the slots); sbank mapped
	lda p2
	sta ep_fp
	sta p0
	lda p2+1
	sta ep_fp+1
	sta p0+1
	; the slots: zero, their type bytes (the table in main RAM)
	ldy #6
	lda (p1),y
	sta n0
	iny
	lda (p1),y
	sta n0+1
	ldx #0
@s:	cpx ep_ns
	beq @sd
	txa
	tay
	lda (n0),y
	bit #$20
	beq @nt
	ora #CT_REF             ; an array parameter: a reference
@nt:	and #CT_TYPE | CT_ARRAY | CT_REF
	ldy #7
	sta (p0),y
	lda #0
@z:	dey
	sta (p0),y
	bne @z
	jsr p0_8
	inx
	bra @s
@sd:	; the parameters from the value stack: slot k (+1 for a FUNCTION)
	lda ep_v
	sta vsp                 ; (popped)
	lda ep_first
	asl a
	asl a
	asl a
	adc ep_fp
	sta p0
	lda ep_fp+1
	adc #0
	sta p0+1
	stz t2
@pl:	lda t2
	cmp ep_np
	beq @pd
	ldx ep_v
	lda vstk,x
	ldy #3                  ; a reference: the caller's cell
	cmp #$80
	beq @cp
	ldy #2                  ; a number: as call_args converted it
	cmp #TY_I
	beq @cp
	ldy #5
	cmp #TY_F
	bne @str
@cp:	sty t3
	ldy #0
@c:	lda vstk+1,x
	sta (p0),y
	inx
	iny
	cpy t3
	bne @c
	bra @pn
@str:	sta aty                 ; a string: stored as by an assignment
	ldy #0
@sv:	lda vstk+1,x
	sta ac0,y
	inx
	iny
	cpy #5
	bne @sv
	ldy #7
	lda (p0),y
	sta t0
	lda _sbank
	sta xb
	stz t1
	lda p0
	pha
	lda p0+1
	pha
	jsr store
	pla
	sta p0+1
	pla
	sta p0
	lda _sbank
	sta ram_bank
@pn:	jsr p0_8
	lda ep_v
	clc
	adc #6
	sta ep_v
	inc t2
	bra @pl
@pd:	; the slots' end: the saved stack, the values, the header
	lda ep_ns
	stz t3
	asl a
	rol t3
	asl a
	rol t3
	asl a
	rol t3
	clc
	adc ep_fp
	sta p0
	lda t3
	adc ep_fp+1
	sta p0+1
	ldy #0
	ldx fc_sp
	lda fc_n
	beq @nf
@cf:	lda $0101,x
	sta (p0),y
	inx
	iny
	cpy fc_n
	bne @cf
	jsr p0_y
@nf:	ldy #0
	ldx ep_fv
	beq @nv
@cv:	lda vstk,y
	sta (p0),y
	iny
	dex
	bne @cv
	jsr p0_y
@nv:	; the header: ret ip, fp, cproc, fc_n, flags, tbase, vbase
	ldy #0
	lda ip
	sta (p0),y
	iny
	lda ip+1
	sta (p0),y
	iny
	lda pbank
	sta (p0),y
	iny
	lda fp
	sta (p0),y
	iny
	lda fp+1
	sta (p0),y
	iny
	lda cproc
	sta (p0),y
	iny
	lda fc_n
	sta (p0),y
	iny
	lda ep_first            ; flags: 1 a FUNCTION
	sta (p0),y
	iny
	lda tbase
	sta (p0),y
	iny
	lda vbase
	sta (p0),y
	iny
	lda ep_fv
	sta (p0),y
	; the trailer
	lda ep_fp
	sta p2
	sta fp
	lda ep_fp+1
	sta p2+1
	sta fp+1
	lda ep_size
	sta n1
	lda ep_size+1
	sta n1+1
	lda #FK_CALL
	jsr frame_push
	stz vsp                 ; (the caller's values are in the frame)
	lda ttop
	sta tbase
	; the procedure's number, its body
	lda ep_p
	sta p1
	sec
	sbc _proctab
	sta t3
	lda ep_p+1
	sta p1+1
	sbc _proctab+1
	lsr a
	ror t3
	lsr a
	ror t3
	lsr a
	ror t3
	lda t3
	sta cproc
	ldy #3
	lda (p1),y
	sta ip
	iny
	lda (p1),y
	sta ip+1
	iny
	lda (p1),y
	sta pbank
	sta ram_bank
	rts
; p0 += 8; p0 += y
p0_8:	ldy #8
p0_y:	tya
	clc
	adc p0
	sta p0
	bcc @r
	inc p0+1
@r:	rts
ep_p:	.word 0
ep_ns:	.byte 0
ep_np:	.byte 0
ep_fp:	.word 0
ep_first: .byte 0
ep_v:	.byte 0
ep_size: .word 0
ep_fv:	.byte 0
fc_n:	.byte 0
fc_sp:	.byte 0

; leave the innermost procedure (its frames above it popped first): its
; strings dead, the caller's fp, cproc, ip back (a FUNCTION's saved stack
; is in fc_buf, fc_n bytes)
leave:
@a:	jsr frame_top
	cmp #0
	bne @1
	MAPP
	ERR E_NOSUB
@1:	cmp #FK_CALL
	beq @call
	jsr frame_pop
	bra @a
@call:	; p2: the frame; the header at p2 + size - 12
	lda p2
	clc
	adc n1
	sta p0
	lda p2+1
	adc n1+1
	sta p0+1
	lda p0
	sec
	sbc #FR_CALL
	sta p0
	lda p0+1
	sbc #0
	sta p0+1
	; the caller's values back (before the header)
	ldy #10
	lda (p0),y
	sta lv_fv
	lda p0
	sec
	sbc lv_fv
	sta p1
	lda p0+1
	sbc #0
	sta p1+1
	ldy #0
	ldx lv_fv
	beq @nv
@vs:	lda (p1),y
	sta vstk,y
	iny
	dex
	bne @vs
@nv:	lda lv_fv
	sta vsp
	; the evaluator's saved stack (before them: leave_function pushes it
	; back from there, the frame gone but its bytes as they were)
	ldy #6
	lda (p0),y
	sta fc_n
	lda p1
	sec
	sbc fc_n
	sta p1
	lda p1+1
	sbc #0
	sta p1+1
	ldy #0
	lda (p0),y
	sta ip
	iny
	lda (p0),y
	sta ip+1
	iny
	lda (p0),y
	sta lv_pb
	iny
	lda (p0),y
	sta lv_fp
	iny
	lda (p0),y
	sta lv_fp+1
	iny
	lda (p0),y
	sta lv_cp
	iny
	iny
	lda (p0),y
	sta lv_fl
	iny
	lda (p0),y
	sta tbase
	iny
	lda (p0),y
	sta vbase
	; the slots' strings: dead (references and the result left alone)
	lda p2
	sta lv_base
	lda p2+1
	sta lv_base+1
	lda p1
	sta lv_end
	lda p1+1
	sta lv_end+1
@sl:	lda lv_base
	cmp lv_end
	lda lv_base+1
	sbc lv_end+1
	bcs @sd
	lda lv_base
	sta p1
	lda lv_base+1
	sta p1+1
	ldy #7
	lda (p1),y
	bmi @sn                 ; a reference
	and #CT_TYPE
	cmp #TY_S
	bne @sn
	lda lv_skip             ; the FUNCTION's result: kept
	beq @sk
	lda p1
	cmp fp
	bne @sk
	lda p1+1
	cmp fp+1
	beq @sn
@sk:	lda _sbank
	jsr cell_dead
	lda _sbank
	sta ram_bank
@sn:	lda lv_base
	clc
	adc #8
	sta lv_base
	bcc @sl
	inc lv_base+1
	bra @sl
@sd:	stz lv_skip
	lda p2
	sta bsp
	lda p2+1
	sta bsp+1
	jsr nc_pop
	lda lv_fp
	sta fp
	lda lv_fp+1
	sta fp+1
	lda lv_cp
	sta cproc
	lda lv_pb
	sta pbank
	sta ram_bank
	rts
lv_pb:	.byte 0
lv_fp:	.word 0
lv_cp:	.byte 0
lv_fl:	.byte 0
lv_base: .word 0
lv_end:	.word 0
lv_skip: .byte 0
lv_fv:	.byte 0

; a FUNCTION's end: its result into acc (a string: a temporary), the
; frame left, the evaluator's stack back, and on in the expression
leave_function:
	; the result: slot 0
	lda fp
	sta p1
	lda fp+1
	sta p1+1
	lda _sbank
	sta ram_bank
	ldy #7
	lda (p1),y
	and #CT_TYPE
	sta aty
	ldy #0
@r:	lda (p1),y
	sta ac0,y
	iny
	cpy #5
	bne @r
	MAPP
	lda aty
	cmp #TY_S
	bne @n
	jsr result_to_temp      ; (the result string: now a temporary's)
	lda #1
	sta lv_skip
@n:	lda aty
	pha
	ldx #4
@k:	lda ac0,x
	pha
	dex
	bpl @k
	jsr leave
	ldx #0
@u:	pla
	sta ac0,x
	inx
	cpx #5
	bne @u
	pla
	sta aty
	; the evaluator's stack back, and its return (from the frame left:
	; lv_end, in sbank)
	ldx sp0
	txs
	lda lv_end
	sta p1
	lda lv_end+1
	sta p1+1
	lda _sbank
	sta ram_bank
	ldy fc_n
	beq @x
@b:	dey
	lda (p1),y
	pha
	cpy #0
	bne @b
@x:	MAPP
	rts                     ; (into fcall_eval's caller)

; the result string in slot 0 (p1) becomes a temporary: acc SK_TMP
result_to_temp:
	lda ac0
	bne @1
	stz ac4                  ; ""
	lda #SK_LIT
	sta ac4
	rts
@1:	lda ac3                  ; a literal's: as it is
	tax
	lda bkind,x
	cmp #2
	beq @heap
	lda #SK_LIT
	sta ac4
	rts
@heap:	jsr temp_slot           ; x = a slot (4 * its number)
	lda ac0
	sta temps,x
	lda ac1
	sta temps+1,x
	lda ac2
	sta temps+2,x
	lda ac3
	sta temps+3,x
	; the heap entry's owner: the slot
	txa
	pha
	lda ac1
	sec
	sbc #3
	sta p1
	lda ac2
	sbc #0
	sta p1+1
	lda ac3
	sta ram_bank
	pla
	pha
	clc
	adc #<temps
	sta (p1)
	ldy #1
	lda #>temps
	adc #0
	sta (p1),y
	iny
	lda #0
	sta (p1),y
	MAPP
	pla
	lsr a
	lsr a
	sta ac1
	lda #SK_TMP
	sta ac4
	rts

; a FUNCTION called in an expression (primary): p2 its entry, ip at its
; arguments; the evaluator's stack goes into the frame and the body runs
; from the dispatcher; leave_function comes back here with the result
fcall:	lda #2
	jsr call_args
	jsr materialize         ; the caller's variables on the value stack: copied
	; the 6502 stack from here to sp0 (with this call's return)
	tsx
	stx t3
	lda sp0
	sec
	sbc t3
	sta fc_n
	cmp #161
	bcc @ok
	ERR E_COMPLEX
@ok:	stx fc_sp               ; (enter_proc copies it into the frame)
	jsr enter_proc
	jmp jumped

;---------------------------------------------------------------
; the start: the program's records are in place (main.c, vb_layout and
; vb_rewrite), its first line
;---------------------------------------------------------------
_vb_reset:			; before a program: the state at zero
	stz _vb_state
	stz _vb_how
	stz _vb_stopreq
	stz _vb_errno
	stz tron
	stz inhandler
	stz onerr+2
	stz errno
	stz errmsg
	stz errfile
	stz erl
	stz erl+1
	stz dataptr
	stz dataptr+1
	stz sleepto+2
	stz inp_on
	stz ttop
	stz tbase
	stz vsp
	stz vbase
	stz nhb
	stz nab
	stz hv
	stz _nbanks
	stz nc_ok
	stz nc_live
	stz atop
	stz atop+1
	stz atop+2
	stz hd_ok
	lda #4
	sta _limitb
	lda #$FF
	sta cproc
	lda #<$A000
	sta bsp
	sta fp
	sta hp                  ; the heap's top with hv: no bank yet, nothing in
	lda #>$A000             ; it (left as the program before had it, the
	sta bsp+1               ; first collection walked that program's bank)
	stz nc_ok
	sta fp+1
	sta hp+1
	ldx #0
@b:	stz bkind,x
	inx
	bne @b
	; the seed of RND: as tools/vbrom.py SEED
	ldx #4
@s:	lda seed,x
	sta RNDX,x
	dex
	bpl @s
	jsr K_RDTIM
	sta ti0
	stx ti0+1
	sty ti0+2
	rts
seed:	.byte $80, $4F, $C7, $52, $58

.ifdef VB_TEST
; the test build's "!fill n" (main.c): every free RAM bank filled with
; bytes at random (a 16-bit xorshift from n), and free again; so a gate
; has, whatever the machine's RAM held, the banks a program gets full of
; bytes it did not write (DECISIONS V88)
_vb_tfill:
	sta tf_s
	stx tf_s+1
	ora tf_s+1
	bne @s
	inc tf_s                ; (never 0)
@s:	lda ram_bank
	pha
	ldx #0
@a:	phx
	lda #1
	jsr BankAlloc
	plx
	cmp #0
	beq @all
	sta sbounce,x
	inx
	bne @a
@all:	stx tf_n
	ldx #0
@b:	cpx tf_n
	beq @free
	lda sbounce,x
	sta ram_bank
	stz bp2
	lda #$A0
	sta bp2+1
	ldy #0
@f:	lda tf_s+1              ; x ^= x << 7, x ^= x >> 9, x ^= x << 8
	lsr a
	lda tf_s
	ror a
	eor tf_s+1
	sta tf_s+1
	ror a
	eor tf_s
	sta tf_s
	eor tf_s+1
	sta tf_s+1
	sta (bp2),y
	iny
	bne @f
	inc bp2+1
	lda bp2+1
	cmp #$C0
	bne @f
	inx
	bra @b
@free:	ldx tf_n
	beq @r
	dec tf_n
	lda sbounce-1,x
	jsr BankFree
	bra @free
@r:	pla
	sta ram_bank
	rts
tf_s:	.word 0
tf_n:	.byte 0
.export _vb_tfill
.endif

; main.c's reading into a bank (it runs in overlay 1's): the record that
; PointRecord chose to $A000 of bank a (r2 = vb_fcount at most); x error,
; r7 its end
_vb_readrec:
	ldx ram_bank
	phx
	sta ram_bank
	lda #<$A000
	sta r7
	lda #>$A000
	sta r7+1
	lda _vb_fcount
	sta r2
	lda _vb_fcount+1
	sta r2+1
	jsr ReadRecord
	pla
	sta ram_bank
	txa
	ldx #0
	rts

; FRead(a, vb_faddr in vb_fbank, vb_fcount): the bytes read
_vb_fread:
	ldx ram_bank
	phx
	ldx _vb_fbank
	stx ram_bank
	ldx _vb_faddr
	stx r0
	ldx _vb_faddr+1
	stx r0+1
	ldx _vb_fcount
	stx r1
	ldx _vb_fcount+1
	stx r1+1
	jsr FRead
	pla
	sta ram_bank
	lda r1
	ldx r1+1
	rts
; main RAM from the BSS's end to the C stack: the procedures and the cells
_vb_dynsize: .word __STACKSTART__ - __STACKSIZE__ - __BSS_RUN__ - __BSS_SIZE__
_vb_fbank: .byte 0
_vb_faddr: .word 0
_vb_fcount: .word 0

; the program's banks given back (its program, stack, DATA index are main.c's)
_vb_free:
@h:	ldx nhb
	beq @a
	dex
	stx nhb
	lda hbanks,x
	tay
	lda #0
	sta bkind,y
	tya
	jsr BankFree
	bra @h
@a:	ldx nab
	beq @r
	dex
	stx nab
	lda abanks,x
	jsr BankFree
	bra @a
@r:	stz _nbanks
	rts

_vb_begin:
	lda _pbase
	sta pbank
	ldx _npb
@k:	dex
	bmi @k2
	txa
	clc
	adc _pbase
	tay
	lda #1
	sta bkind,y
	bra @k
@k2:	lda #<($A000 + 6)
	sta ip
	lda #>($A000 + 6)
	sta ip+1
	lda #VS_RUN
	sta _vb_state
	rts

; keyVector: a key into the queue; Ctrl+C or STOP: stop the program
_vb_key:
	lda keyData
	cmp #KEY_STOP
	beq @stop
	cmp #3
	bne @q
	lda keyDataMods
	and #2
	beq @q
@stop:	lda _vb_state
	cmp #VS_RUN
	bne @r
	lda #1
	sta _vb_stopreq
	rts
@q:	lda keyData
	jmp kq_put
@r:	rts

kq_put:	ldx _kqt
	sta _kq,x
	inx
	txa
	and #31
	cmp _kqh
	beq @full
	sta _kqt
@full:	rts

;---------------------------------------------------------------
; the tables
;---------------------------------------------------------------
.segment RO_SEG
mul31:
.repeat 9, I
	.byte I * 31
.endrepeat

.define STMT(t, h) .word h

; the statements' handlers, by token ($80-$FE)
stmttab:
	.word st_print          ; $80 PRINT
	.word st_input          ; $81 INPUT
	.word st_lineinput      ; $82 LINE INPUT
	.word st_get            ; $83 GET
	.word st_let            ; $84 LET
	.word st_goto           ; $85 GOTO
	.word st_gosub          ; $86 GOSUB
	.word st_return         ; $87 RETURN
	.word st_on             ; $88 ON
	.word st_skip           ; $89 DATA
	.word st_read           ; $8A READ
	.word st_restore        ; $8B RESTORE
	.word st_rem2           ; $8C REM
	.word st_end            ; $8D END
	.word st_stop           ; $8E STOP
	.word st_cont           ; $8F CONT
	.word st_if             ; $90 IF
	.word st_syn            ; $91 THEN
	.word st_else           ; $92 ELSE
	.word st_elseif         ; $93 ELSEIF
	.word st_endif          ; $94 END IF
	.word st_while          ; $95 WHILE
	.word st_wend           ; $96 WEND
	.word st_repeat         ; $97 REPEAT
	.word st_until          ; $98 UNTIL
	.word st_do             ; $99 DO
	.word st_loop           ; $9A LOOP
	.word st_for            ; $9B FOR
	.word st_syn            ; $9C TO
	.word st_syn            ; $9D STEP
	.word st_next           ; $9E NEXT
	.word st_syn            ; $9F SELECT
	.word st_select         ; $A0 SELECT CASE
	.word st_case           ; $A1 CASE
	.word st_case           ; $A2 CASE ELSE
	.word st_syn            ; $A3 IS
	.word st_endselect      ; $A4 END SELECT
	.word st_syn            ; $A5 EXIT
	.word st_exitloop       ; $A6 EXIT FOR
	.word st_exitloop       ; $A7 EXIT WHILE
	.word st_exitloop       ; $A8 EXIT DO
	.word st_exitloop       ; $A9 EXIT REPEAT
	.word st_exitproc       ; $AA EXIT SUB
	.word st_exitproc       ; $AB EXIT FUNCTION
	.word st_sub            ; $AC SUB
	.word st_endsub         ; $AD END SUB
	.word st_sub            ; $AE FUNCTION
	.word st_endfunction    ; $AF END FUNCTION
	.word st_call           ; $B0 CALL
	.word st_syn            ; $B1 BYREF
	.word st_skip           ; $B2 LOCAL
	.word st_skip           ; $B3 SHARED
	.word st_const          ; $B4 CONST
	.word st_dim            ; $B5 DIM
	.word st_redim          ; $B6 REDIM
	.word st_skip           ; $B7 DEFINT
	.word st_option         ; $B8 OPTION
	.word st_syn            ; $B9 INTEGER
	.word st_syn            ; $BA MEMORY
	.word st_try            ; $BB TRY
	.word st_catch          ; $BC CATCH
	.word st_endtry         ; $BD END TRY
	.word st_error          ; $BE ERROR
	.word st_resume         ; $BF RESUME
	.word st_poke           ; $C0 POKE
	.word st_sys            ; $C1 SYS
	.word st_tron           ; $C2 TRON
	.word st_troff          ; $C3 TROFF
	.word st_doevents       ; $C4 DOEVENTS
	.word st_wait           ; $C5 WAIT
	.word st_syn            ; $C6 EVENTS
	.word st_sleep          ; $C7 SLEEP
; ($C8-$FE: none, stmt says so)

MTron:	.byte "VB TRON", 0

.segment "CODE"
st_syn:	ERR E_SYNTAX

.include "vbexpr.s"
.include "vbstr.s"
.include "vbio.s"
.include "vbload.s"
.include "vbtok.s"
.include "vbprep.s"
.include "vbfloat.s"
.include "vbx.s"
.include "vbev.s"
.include "vbui.s"
.include "vbgfx.s"
.include "vbdlg.s"
.include "vbfile.s"
.ifdef VB_IDE
.include "vbdbg.s"
.endif
.segment "CODE"
.ifdef VB_IDE
; the editor's builds: this place (_ide_s0 .. _ide_s1) holds the editor's
; main RAM part (LOW) while no program runs; its size kept at V106's
; (the release build had the test build's logging, VB_LOG, as room: 296
; bytes of this CODE; the test build's LOW, with its player, needs V106's
; $5252), however small the code here is
.ifdef IDE_TEST
IDE_SPAN = $5252
.else
IDE_SPAN = $5239
.endif
.if (* - _ide_s0) < IDE_SPAN
	.res IDE_SPAN - (* - _ide_s0)
.endif
.endif
_ide_s1:                ; (the interpreter's code ends)
