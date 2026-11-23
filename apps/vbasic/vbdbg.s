; VeraBASIC, the debugger: the runtime's side (DECISIONS V97). Included
; by vb.s in VeraBASIC (VB_IDE) only: overlay 12, linked into the
; application as record 23 (main.c: _vx_dbg its bank). The editor's side is
; ide/dbg.c (bank B9); what the two share is in this overlay's own bank
; from DI_BASE (vbdbg.inc, ide/dbgshare.h).
;
;   dbg_line   trace's hook (vb.s, each line entered while tron is not 0):
;              TRON's entry in the trace ring (DI_RING, the last 200), then,
;              with tron's bit 1 (armed), a pause, a step or the line's
;              breakpoint (bit 0 of the record's flags) stops the program
;              before the line: vb_state VS_BRK, back to the main loop
;   dbg_stop   a STOP statement: the same, after it
;   dbg_svc    main.c's vb_dbg(n): D_MARK the breakpoints into the line
;              records, D_BREAK the break's state saved (the call stack
;              into DI, the program's screen, colours, palette, sprites, zero
;              page and main RAM's names into a bank of its own, DS),
;              D_RESUME all of it back and the step armed, D_EVAL the
;              editor's requests (values, arrays' bounds, assignments) with
;              errors caught (vb.s raise2: dbgtrap), D_QUOTE an error's
;              statement for the editor, D_END DS freed, D_PAUSE a pause at
;              the next line, D_FIRST a break before the first line,
;              D_TRON TRON from the start
;
; Code here runs with this overlay mapped at $A000: the interpreter's
; routines (main RAM) are called through dcall, which maps the bank they
; need and this one again after; another bank's bytes through fpeek and
; fpoke (vbtok.s), BankCopy. MIT licence (LICENSE).

.include "vbdbg.inc"
.import _ide_step

; the state's bank (DS)
DS_COL  = $A000                 ; 2400: the colour map, two cards a byte
DS_BAR  = $A960                 ; 1280: the bitmap's rows 0-15 (the menu bar)
DS_HDR  = $AE60                 ; 128: misc, the zero page $D4-$FF, the palette, sprites (H_*)
DS_DYN  = $AF00                 ; main RAM's room for names (vb_dynsize)

ZP0     = $D4                   ; (the interpreter's zero page: $D4-$FF)
ZPN     = $2C

; main RAM: dcall, the stubs the C side and the hooks reach
.segment "CODE"
; a/x = a routine, y = the bank mapped while it runs; this overlay mapped
; again after; a and the flags as it left them
dcall:	sta @j+1
	stx @j+2
	sty ram_bank
@j:	jsr $FFFF
	php
	pha
	lda _vx_dbg
	sta ram_bank
	pla
	plp
	rts

; void __fastcall__ vb_dbg(unsigned char service) (main.c, overlay 1)
_vb_dbg:
	sta dsvc
	lda #<dbg_svc
	ldx #>dbg_svc
	ldy _vx_dbg
	jmp bcall
.export _vb_dbg
dsvc:	.byte 0
_vb_dkept: .byte 0              ; D_BREAK: 1 the state kept (0: no bank for it)
.export _vb_dkept
.ifdef IDE_TEST
; (the test build) the emulator's clock to dclks + x (main.c's vb_dclks:
; ide_go puts Continue's start in its first 4 bytes)
.import _vb_dclks
dclks = _vb_dclks
dclk1 = _vb_dclks + 4
dclk2 = _vb_dclks + 8
clock:	lda EMU_CLOCK
	sta dclks,x
	lda EMU_CLOCK+1
	sta dclks+1,x
	lda EMU_CLOCK+2
	sta dclks+2,x
	lda EMU_CLOCK+3
	sta dclks+3,x
	rts
.endif

.segment "OVL12BSS"
dsb:	.res 1                  ; DS (0 none)
dstep:	.res 1                  ; 0 run, 1 step, 2 step over, 3 step out
dpause:	.res 1
dreason: .res 1
dsdep:	.res 1                  ; the step's calls (depth)
dzp:	.res ZPN
dbps:	.res DI_BPMAX * 2       ; the breakpoints (their source lines)
dbpn:	.res 1
dcur:	.res 1                  ; the procedure of the frames being walked
dn:	.res 1
dp2:	.res 2
dkeep:	.res 8                  ; erl, errno, errfile, kerr, sip, sipb
dmsg:	.res 64                 ; errmsg kept over D_EVAL
dreq:	.res 2                  ; the request read
dri:	.res 1                  ; its number
dk:	.res 1
dout:	.res DI_RESW            ; an answer being made
dol:	.res 1
dmisc:	.res 4
dtr:	.res 2

.segment "OVERLAY12"

; DI's bank (this overlay's own) -> xb
dibank:	lda _vx_dbg
	sta xb
	rts

; a into DI at p2 + y
diput:	pha
	jsr dibank
	pla
	jmp fpoke

; DI at p2 + y -> a
diget:	jsr dibank
	jmp fpeek

;---------------------------------------------------------------
; the line hook (trace: the record's head in dlhdr; ip at the record)
;---------------------------------------------------------------
dbg_line:
	lda tron
	lsr a
	bcc @nt
	jsr ring_add
@nt:	lda tron
	and #2
	beq @r
	lda dpause
	bne @pause
	lda dstep
	beq @bp
	cmp #1
	beq @step
	; over, out: the calls (procedures, GOSUBs) on the BASIC stack against
	; the step's: deeper goes on; over stops at as deep, out shallower
	jsr calls
	ldx dstep
	cpx #2
	bne @out
	cmp dsdep
	bcc @step
	beq @step
	bra @bp
@out:	cmp dsdep
	bcc @step
@bp:	lda dlhdr+5
	lsr a
	bcs @isbp
@r:	rts
@isbp:	lda #DW_BP
	bra @brk
@pause:	lda #DW_PAUSE
	bra @brk
@step:	lda #DW_STEP
@brk:	sta dreason
	ADDIP 6                 ; (the line's first statement: it runs on Continue)
brk_now:
	stz dstep
	stz dpause
	lda #2
	trb tron
	lda #VS_BRK
	sta _vb_state
	jmp yield

; a STOP statement: the break after it
dbg_stop:
	lda #DW_STOP
	sta dreason
	bra brk_now

; the trace ring: the line's number (or its source line) and source line
ring_add:
	lda #<DI_RHEAD
	sta p2
	lda #>DI_RHEAD
	sta p2+1
	ldy #0
	jsr diget
	sta dk                  ; the entry
	asl a
	asl a
	sta p2
	lda dk
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc #>DI_RING
	sta p2+1
	lda dlhdr+1
	ora dlhdr+2
	bne @num
	lda dlhdr+3
	ldx dlhdr+4
	bra @put
@num:	lda dlhdr+1
	ldx dlhdr+2
@put:	phx
	pha
	ldy #0
	jsr diput
	pla
	sta dmisc
	pla
	sta dmisc+1
	iny
	jsr diput
	iny
	lda dlhdr+3
	jsr diput
	iny
	lda dlhdr+4
	jsr diput
	lda #<DI_RHEAD          ; the head on, the count up to 200
	sta p2
	lda #>DI_RHEAD
	sta p2+1
	ldx dk
	inx
	cpx #DI_RN
	bcc @h
	ldx #0
@h:	txa
	ldy #0
	jsr diput
	iny
	jsr diget
	cmp #DI_RN
	bcs @t
	inc a
	jsr diput
@t:
.ifdef VB_LOG
	lda _vb_test            ; (the test build: as VeraBASIC Run's TRON)
	beq @x
	ldx #0
@m:	lda MTron,x
	beq @d
	sta EMU_STDOUT
	inx
	bra @m
@d:	lda dmisc
	ldx dmisc+1
	jsr int_to_text
	ldx #0
@o:	lda numbuf,x
	beq @e
	sta EMU_STDOUT
	inx
	bra @o
@e:	lda #10
	sta EMU_STDOUT
.endif
@x:	rts

; a = the calls on the BASIC stack: procedures' frames and GOSUBs' (a
; procedure's frame pointer cannot tell: the first one's is the main
; lines' too, the stack's start)
calls:	stz dn
	lda #<frame_top
	ldx #>frame_top
@l:	ldy _sbank              ; (frame_below reads the stack's bank: mapped)
	jsr dcall
	beq @d
	cmp #FK_GOSUB
	beq @c
	cmp #FK_CALL
	bne @n
@c:	inc dn
@n:	lda #<frame_below
	ldx #>frame_below
	bra @l
@d:	lda dn
	rts

;---------------------------------------------------------------
; the services (vb_dbg)
;---------------------------------------------------------------
dbg_svc:
	lda dsvc
	asl a
	tax
	jmp (dsvtab,x)
dsvtab:	.word d_mark, d_break, d_resume, d_eval, d_quote, d_fin, d_pause, d_first, d_tron, d_init

; the start (main.c init): this overlay's variables cleared (an overlay's
; BSS is not: a bank's old bytes; dsb's would be freed at a program's end)
.import __OVL12BSS_RUN__, __OVL12BSS_SIZE__
d_init:	ldx #0
@c:	stz __OVL12BSS_RUN__,x
	inx
	cpx #<__OVL12BSS_SIZE__
	bne @c
	rts
.assert __OVL12BSS_SIZE__ < 256, error, "vbdbg.s: d_init clears 255 bytes at most"

d_pause:
	lda #1
	sta dpause
	lda #2
	tsb tron
	rts

d_tron:	lda #1
	tsb tron
	rts

; the break before the first line (Run > Step with no program running)
d_first:
	lda #DW_START
	sta dreason
	stz dstep
	stz dpause
	lda #VS_BRK
	sta _vb_state
	rts

d_fin:	lda dsb
	beq @r
	jsr BankFree
	stz dsb
@r:	stz dstep
	stz dpause
	rts

; the breakpoints (DI_BP) into the line records' flags (bit 0); tron's
; bit 1 armed if there are any (or a step, a pause)
d_mark:	lda #<DI_BPN
	sta p2
	lda #>DI_BPN
	sta p2+1
	ldy #0
	jsr diget
	cmp #DI_BPMAX + 1
	bcc @n
	lda #DI_BPMAX
@n:	sta dbpn
	asl a
	tax
	ldy #2                  ; (DI_BP = DI_BPN + 2)
@c:	cpx #0
	beq @w
	jsr diget
	sta dbps-2,y
	iny
	dex
	bra @c
@w:	lda _pbase              ; every record
	sta xb
	lda #<$A000
	sta p2
	lda #>$A000
	sta p2+1
@rec:	ldy #0
	jsr fpeek
	jeq @done
	sta dk                  ; its length
	ldy #3
	jsr fpeek
	sta dmisc
	iny
	jsr fpeek
	sta dmisc+1
	ldx #0                  ; a breakpoint's line?
@s:	cpx dbpn
	beq @no
	txa
	asl a
	tay
	lda dbps,y
	cmp dmisc
	bne @s1
	lda dbps+1,y
	cmp dmisc+1
	beq @yes
@s1:	inx
	bra @s
@yes:	lda #1
	bra @f
@no:	lda #0
@f:	sta dmisc+2
	ldy #5
	jsr fpeek
	and #$FE
	ora dmisc+2
	jsr fpoke
	lda p2                  ; the flag byte in the bank's last 256 bytes
	clc                     ; (p2 + 5 from $BF00): the next bank's copy too
	adc #5
	lda p2+1
	adc #0
	cmp #$A0 + PSTRIDE
	bcc @nm
	lda p2+1
	sec
	sbc #PSTRIDE
	sta p2+1
	inc xb
	ldy #5
	jsr fpeek
	and #$FE
	ora dmisc+2
	jsr fpoke
	dec xb
	lda p2+1
	clc
	adc #PSTRIDE
	sta p2+1
@nm:	lda p2                  ; the next record (its bank as eol finds it)
	clc
	adc dk
	sta p2
	bcc @p
	inc p2+1
@p:	lda p2+1
	cmp #$A0 + PSTRIDE
	jcc @rec
	sbc #PSTRIDE
	sta p2+1
	inc xb
	jmp @rec
@done:	lda dbpn
	ora dstep
	ora dpause
	beq @off
	lda #2
	tsb tron
	rts
@off:	lda #2
	trb tron
	rts

;---------------------------------------------------------------
; D_BREAK: the program stopped (vb_state VS_BRK, ip at what runs next)
;---------------------------------------------------------------
d_break:
	ldx #ZPN - 1            ; the zero page first (as the break left it)
@z:	lda ZP0,x
	sta dzp,x
	dex
	bpl @z
	jsr keep_err
	; the line: sip = ip (find_erl: _vb_esrc, erl)
	lda ip
	sta sip
	lda ip+1
	sta sip+1
	lda pbank
	sta sipb
	jsr line_of
	lda #<DI_INFO
	sta p2
	lda #>DI_INFO
	sta p2+1
	ldy #DB_REASON
	lda dreason
	jsr diput
	ldy #DB_SRC
	lda _vb_esrc
	jsr diput
	iny
	lda _vb_esrc+1
	jsr diput
	iny
	lda erl
	jsr diput
	iny
	lda erl+1
	jsr diput
	iny
	lda cproc
	jsr diput
	jsr stack_walk
	jsr give_err
	; the program's screen, colours, palette, sprites, names
	lda dsb
	bne @have
	lda #1
	jsr BankAlloc
	sta dsb
	cmp #0
	bne @have
	stz _vb_dkept           ; (no bank: main.c ends the program)
	rts
@have:	jsr pic_load
	lda dispBufferOn        ; misc: dispBufferOn, clipOn, the colour map
	sta hdr + H_MISC        ; shown (layer 0), procs_on
	lda clipOn
	sta hdr + H_MISC + 1
	sei
	lda VERA_CTRL
	pha
	stz VERA_CTRL
	lda VERA_DC_VIDEO
	and #$10
	sta hdr + H_MISC + 2
	pla
	sta VERA_CTRL
	cli
	ldy appBank             ; its timers frozen: the process table gone
	lda #<o1_brk
	ldx #>o1_brk
	jsr dcall
	sta hdr + H_MISC + 3
	ldx #ZPN - 1
@zc:	lda dzp,x
	sta hdr + H_ZP,x
	dex
	bpl @zc
	jsr pal_out             ; (the sprites hidden)
	jsr hdr_out
	jsr dyn_out
	jsr bar_out
	jsr col_out
	; the bitmap onto the back screen (the editor draws on the foreground
	; only; the menu bar, which it draws on both, is in DS)
	stz r0
	stz r0+1
	lda #>VRAM_BG
	sta r1
	stz r1+1
	jsr vcopy
	lda #1
	sta _vb_dkept
	rts


; the BASIC stack walked: the break's line, then each frame's
stack_walk:
	stz dn
	lda cproc
	sta dcur
	lda #0
	jsr st_entry            ; (the break's line: _vb_esrc, erl as found)
	lda #<frame_top
	ldx #>frame_top
@l:	ldy _sbank              ; (frame_below reads the stack's bank: mapped)
	jsr dcall
	jeq @d
	cmp #FK_CALL
	beq @call
	cmp #FK_GOSUB
	jne @nx
	; GOSUB: its return place (0-2)
	lda p2
	sta dp2
	lda p2+1
	sta dp2+1
	lda _sbank
	sta xb
	ldy #0
	jsr fpeek
	sta sip
	iny
	jsr fpeek
	sta sip+1
	iny
	jsr fpeek
	sta sipb
	jsr line_of
	lda #2
	jsr st_entry
	bra @back
@call:	; a procedure's frame: its header (base + size - 14): return ip, pbank, fp, cproc
	lda p2
	sta dp2
	lda p2+1
	sta dp2+1
	clc
	lda p2
	adc n1
	sta p2
	lda p2+1
	adc n1+1
	sta p2+1
	lda p2
	sec
	sbc #14
	sta p2
	bcs @h
	dec p2+1
@h:	lda _sbank
	sta xb
	ldy #0
	jsr fpeek
	sta sip
	iny
	jsr fpeek
	sta sip+1
	iny
	jsr fpeek
	sta sipb
	ldy #5
	jsr fpeek
	sta dcur                ; (the caller's procedure)
	jsr line_of
	lda #1
	jsr st_entry
@back:	lda dp2
	sta p2
	lda dp2+1
	sta p2+1
@nx:	lda dn
	cmp #DI_STKN
	bcs @deep
	lda #<frame_below
	ldx #>frame_below
	jmp @l
@deep:	lda #1
	bra @dd
@d:	lda #0
@dd:	pha
	lda #<DI_INFO
	sta p2
	lda #>DI_INFO
	sta p2+1
	ldy #DB_DEEP
	pla
	jsr diput
	ldy #DB_NSTK
	lda dn
	jmp diput

; an entry of the call stack: a its kind, dcur, _vb_esrc, erl
st_entry:
	pha
	lda dn
	cmp #DI_STKN
	bcc @1
	pla
	rts
@1:	lda p2
	pha
	lda p2+1
	pha
	lda dn
	asl a
	adc dn
	asl a                   ; * 6
	adc #<DI_STACK
	sta p2
	lda #>DI_STACK
	adc #0
	sta p2+1
	tsx
	lda $0103,x             ; the kind
	ldy #0                  ; (kind, procedure, line, label)
	jsr diput
	iny
	lda dcur
	jsr diput
	iny
	lda _vb_esrc
	jsr diput
	iny
	lda _vb_esrc+1
	jsr diput
	iny
	lda erl
	jsr diput
	iny
	lda erl+1
	jsr diput
	inc dn
	pla
	sta p2+1
	pla
	sta p2
	pla
	rts

; the line of the statement at sip, sipb: _vb_esrc, erl (find_erl)
line_of:
	lda p2
	pha
	lda p2+1
	pha
	lda #<find_erl
	ldx #>find_erl
	ldy pbank
	jsr dcall
	pla
	sta p2+1
	pla
	sta p2
	rts

; erl, errno, errfile, kerr, sip, sipb kept (keep_err) and given back
keep_err:
	lda erl
	sta dkeep
	lda erl+1
	sta dkeep+1
	lda errno
	sta dkeep+2
	lda errfile
	sta dkeep+3
	lda kerr
	sta dkeep+4
	lda sip
	sta dkeep+5
	lda sip+1
	sta dkeep+6
	lda sipb
	sta dkeep+7
	ldx #63
@m:	lda errmsg,x
	sta dmsg,x
	dex
	bpl @m
	rts
give_err:
	lda dkeep
	sta erl
	lda dkeep+1
	sta erl+1
	lda dkeep+2
	sta errno
	lda dkeep+3
	sta errfile
	lda dkeep+4
	sta kerr
	lda dkeep+5
	sta sip
	lda dkeep+6
	sta sip+1
	lda dkeep+7
	sta sipb
	ldx #63
@m:	lda dmsg,x
	sta errmsg,x
	dex
	bpl @m
	rts

; the whole screen: r3 0, r11 0, r4 639, r12 479
whole:	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	rts

;---------------------------------------------------------------
; the state's copies (DS <-> main RAM, VERA): fast, since Continue gives
; the screen back in about 60 ms. A bank and main RAM are copied by pic,
; a position-independent routine this overlay copies into main RAM
; (inbuf, the INPUT line's buffer, idle between statements) and calls
; there with the bank mapped at $A000; VERA's bytes go through its data
; ports, the interrupt off for each piece (its handler moves the pointer
; through the same ports)
;---------------------------------------------------------------
; pic, at inbuf: +0 exchange, +PCOPY copy; r0 the one place, r1 the
; other (main RAM or $A000-$BFFF of bank a), r2 bytes; r3H changed.
; main.c's ide_swap uses the exchange (the editor's part and the
; interpreter's code change places: 8 times BankCopy's speed)
pic0:
	ldx ram_bank            ; +0: exchange (r0) and (r1)
	phx
	sta ram_bank
	ldy #0
	lda r2+1
	sta r3H
@xp:	lda r3H
	beq @xr
@xb:	lda (r0),y
	tax
	lda (r1),y
	sta (r0),y
	txa
	sta (r1),y
	iny
	bne @xb
	inc r0+1
	inc r1+1
	dec r3H
	bra @xp
@xr:	cpy r2
	beq @xd
	lda (r0),y
	tax
	lda (r1),y
	sta (r0),y
	txa
	sta (r1),y
	iny
	bra @xr
@xd:	pla
	sta ram_bank
	rts
PCOPY = * - pic0
	ldx ram_bank            ; +PCOPY: (r0) to (r1)
	phx
	sta ram_bank
	ldy #0
	lda r2+1
	sta r3H
@cp:	lda r3H
	beq @cr
@cb:	lda (r0),y
	sta (r1),y
	iny
	bne @cb
	inc r0+1
	inc r1+1
	dec r3H
	bra @cp
@cr:	cpy r2
	beq @cd
	lda (r0),y
	sta (r1),y
	iny
	bra @cr
@cd:	pla
	sta ram_bank
	rts
PICN = * - pic0
.assert PICN <= 256, error, "vbdbg.s: pic is more than inbuf"
_vb_pic = pic0
_vb_picn = PICN
.export _vb_pic, _vb_picn

; pic into inbuf
pic_load:
	ldx #PICN - 1
@c:	lda pic0,x
	sta inbuf,x
	dex
	cpx #$FF
	bne @c
	rts

; r2 bytes from r0 to r1, DS mapped meanwhile (one of them in DS)
ds_copy:
	lda dsb
	jmp inbuf + PCOPY

; main RAM's names (dynbase .. + vb_dynsize) <-> DS_DYN
dyn_out:
	lda _dynbase
	sta r0
	lda _dynbase+1
	sta r0+1
	LoadW r1, DS_DYN
	bra dyn_n
dyn_in:	LoadW r0, DS_DYN
	lda _dynbase
	sta r1
	lda _dynbase+1
	sta r1+1
dyn_n:	lda _vb_dynsize
	sta r2
	lda _vb_dynsize+1
	sta r2+1
	bra ds_copy

; DS_HDR (128 bytes: misc, zero page, palette, sprites) <-> hdr (main RAM)
hdr	= sbounce
H_MISC	= 0                     ; dispBufferOn, clipOn, the colour map shown, procs_on
H_ZP	= 4                     ; $D4-$FF
H_PAL	= 48                    ; palette entries 0-15
H_SPR	= 80                    ; sprites 2-7's attributes
hdr_out:
	LoadW r0, hdr
	LoadW r1, DS_HDR
	bra hdr_n
hdr_in:	LoadW r0, DS_HDR
	LoadW r1, hdr
hdr_n:	LoadW r2, 128
	bra ds_copy

; the zero page back from DS (DS_HDR)
zp_in:	jsr hdr_in
	ldx #ZPN - 1
@z:	lda hdr + H_ZP,x
	sta ZP0,x
	dex
	bpl @z
	rts

; VERA's port 0 address kept and given back (the interrupt off meanwhile)
vera_keep:
	sei
	lda VERA_CTRL
	sta dvk
	stz VERA_CTRL
	lda VERA_ADDR_L
	sta dvk+1
	lda VERA_ADDR_M
	sta dvk+2
	lda VERA_ADDR_H
	sta dvk+3
	rts
vera_give:
	stz VERA_CTRL
	lda dvk+1
	sta VERA_ADDR_L
	lda dvk+2
	sta VERA_ADDR_M
	lda dvk+3
	sta VERA_ADDR_H
	lda dvk
	sta VERA_CTRL
	cli
	rts
; VERA's port 0 at r0 (its low 16 bits), a its high byte and increment
vera_at:
	sta VERA_ADDR_H
	lda r0
	sta VERA_ADDR_L
	lda r0+1
	sta VERA_ADDR_M
	rts
dvk:	.res 4

; the bitmap: 38,400 bytes from VRAM page r0 (16 bits: the address / 256)
; to page r1, through VERA's two ports (8 cycles a byte), a page with the
; interrupt off at a time (the back screen runs past $FFFF)
vcopy:	ldx #150
@pg:	phx
	jsr vera_keep
	lda #1                  ; port 1: from
	sta VERA_CTRL
	stz VERA_ADDR_L
	lda r0
	sta VERA_ADDR_M
	lda r0+1
	ora #$10
	sta VERA_ADDR_H
	stz VERA_CTRL           ; port 0: to
	stz VERA_ADDR_L
	lda r1
	sta VERA_ADDR_M
	lda r1+1
	ora #$10
	sta VERA_ADDR_H
	ldy #32
@b:	.repeat 8
	lda VERA_DATA1
	sta VERA_DATA0
	.endrepeat
	dey
	bne @b
	jsr vera_give
	inc r0
	bne @1
	inc r0+1
@1:	inc r1
	bne @2
	inc r1+1
@2:	plx
	dex
	bne @pg
	rts

; the bar's rows (0-15: 1,280 bytes from VRAM 0) <-> DS_BAR, 256 at a time
; through sbufa; to VRAM: the foreground's and the back screen's
bar_out:
	stz dk
@p:	jsr vera_keep
	stz r0
	lda dk
	sta r0+1
	lda #$10
	jsr vera_at
	ldy #0
@r:	lda VERA_DATA0
	sta sbufa,y
	iny
	bne @r
	jsr vera_give
	jsr bar_ptr
	LoadW r0, sbufa
	jsr ds_copy
	inc dk
	lda dk
	cmp #5
	bne @p
	rts
bar_in:	stz dk
@p:	jsr bar_ptr
	MoveW r1, r0
	LoadW r1, sbufa
	jsr ds_copy
	lda #<VRAM_BG           ; the back screen, then the foreground
	sta r0
	lda dk
	clc
	adc #>VRAM_BG
	sta r0+1
	jsr @w
	stz r0
	lda dk
	sta r0+1
	jsr @w
	inc dk
	lda dk
	cmp #5
	bne @p
	rts
@w:	jsr vera_keep
	lda #$10
	jsr vera_at
	ldy #0
@r:	lda sbufa,y
	sta VERA_DATA0
	iny
	bne @r
	jmp vera_give
; r1 = DS_BAR + 256 * dk, r2 = 256
bar_ptr:
	lda #<DS_BAR
	sta r1
	lda dk
	clc
	adc #>DS_BAR
	sta r1+1
	LoadW r2, 256
	rts

; the colour map: 60 rows of 80 cards, two a byte, 6 rows (240 bytes) at a
; time through sbufa. A card's colour is its attribute's high nibble (a
; card under a menu or a box: its tile index's, V33)
col_out:
	stz dk                  ; the first row of the piece
@p:	jsr vera_keep
	ldx #0
@row:	lda #<VRAM_FREE         ; (the row in the piece: x; its bytes from x * 40)
	sta VERA_ADDR_L
	txa
	clc
	adc dk
	adc #>VRAM_FREE
	sta VERA_ADDR_M
	lda #^VRAM_FREE | $10
	sta VERA_ADDR_H
	jsr mul40
	tay
	lda #40
	sta dm16
@c:	jsr card
	asl a
	asl a
	asl a
	asl a
	sta dm16+1
	jsr card
	ora dm16+1
	sta sbufa,y
	iny
	dec dm16
	bne @c
	inx
	cpx #6
	bne @row
	jsr vera_give
	jsr col_ptr
	LoadW r0, sbufa
	jsr ds_copy
	lda dk
	clc
	adc #6
	sta dk
	cmp #60
	bne @p
	rts
; a card's colour from VERA's map (port 0: its tile index, its attribute)
card:	lda VERA_DATA0
	phx
	tax
	lda VERA_DATA0
	bne @a
	txa
@a:	plx
	lsr a
	lsr a
	lsr a
	lsr a
	rts
; a = x * 40
mul40:	txa
	asl a
	asl a
	asl a                   ; * 8
	sta dm80
	asl a
	asl a                   ; * 32
	clc
	adc dm80
	rts
; r1 = DS_COL + 40 * dk (dk a multiple of 6: 240 a piece), r2 = 240
col_ptr:
	lda dk
	sta r1
	stz r1+1
	asl r1                  ; * 8 ...
	rol r1+1
	asl r1
	rol r1+1
	asl r1
	rol r1+1
	lda r1
	ldx r1+1
	asl r1                  ; ... + * 32 = * 40
	rol r1+1
	asl r1
	rol r1+1
	clc
	adc r1
	sta r1
	txa
	adc r1+1
	adc #>DS_COL
	sta r1+1
	LoadW r2, 240
	rts
col_in:	lda dmisc + 2
	bne @on
	lda #$FF                ; (the program had it hidden)
	jmp ColorRect
@on:	stz VERA_CTRL           ; shown, but hidden now (the Classic theme):
	lda VERA_DC_VIDEO       ; the kernel shows it (card 0, 0 first; its
	and #$10                ; colour comes below)
	bne @sh
	stz r3L
	lda #1
	sta r3H
	stz r11L
	sta r11H
	lda #0
	jsr ColorRect
@sh:	stz dk
@p:	jsr col_ptr
	MoveW r1, r0
	LoadW r1, sbufa
	jsr ds_copy
	jsr vera_keep
	ldx #0
@row:	lda #<(VRAM_FREE + 1)   ; the attributes: every other byte
	sta VERA_ADDR_L
	txa
	clc
	adc dk
	adc #>VRAM_FREE
	sta VERA_ADDR_M
	lda #^VRAM_FREE | $20
	sta VERA_ADDR_H
	jsr mul40
	tay
	lda #40
	sta dm16
@c:	lda sbufa,y
	and #$F0
	sta VERA_DATA0
	lda sbufa,y
	asl a
	asl a
	asl a
	asl a
	sta VERA_DATA0
	iny
	dec dm16
	bne @c
	inx
	cpx #6
	bne @row
	jsr vera_give
	lda dk
	clc
	adc #6
	sta dk
	cmp #60
	bne @p
	rts
dm16:	.res 2
dm80:	.res 1

; the palette's entries 0-15 and sprites 2-7's attributes <-> hdr; hidden
; (their z-depth 0) when kept
pal_out:
	jsr vera_keep
	LoadW r0, $FA00
	lda #^VRAM_PALETTE | $10
	jsr vera_at
	ldx #0
@pl:	lda VERA_DATA0
	sta hdr + H_PAL,x
	inx
	cpx #32
	bne @pl
	LoadW r0, $FC10         ; sprite 2's attributes
	jsr vera_at
	ldx #0
@sp:	lda VERA_DATA0
	sta hdr + H_SPR,x
	inx
	cpx #48
	bne @sp
	LoadW r0, $FC10
	jsr vera_at
	ldx #0
@sh:	lda hdr + H_SPR,x
	cpx #6                  ; (byte 6 of each: z-depth 0)
	beq @z
	cpx #14
	beq @z
	cpx #22
	beq @z
	cpx #30
	beq @z
	cpx #38
	beq @z
	cpx #46
	bne @w
@z:	and #$F3
@w:	sta VERA_DATA0
	inx
	cpx #48
	bne @sh
	jmp vera_give
pal_in:	jsr vera_keep
	LoadW r0, $FA00
	lda #^VRAM_PALETTE | $10
	jsr vera_at
	ldx #0
@pl:	lda hdr + H_PAL,x
	sta VERA_DATA0
	inx
	cpx #32
	bne @pl
	LoadW r0, $FC10
	jsr vera_at
	ldx #0
@sp:	lda hdr + H_SPR,x
	sta VERA_DATA0
	inx
	cpx #48
	bne @sp
	jmp vera_give

;---------------------------------------------------------------
; D_RESUME: everything back; the step (ide_step) armed; running again
;---------------------------------------------------------------
d_resume:
.ifdef IDE_TEST
	ldx #dclk1 - dclks
	jsr clock               ; (the test build: how long the screen takes)
.endif
	lda dsb
	jeq @go
	jsr pic_load
	jsr zp_in               ; (hdr: the misc, the palette, the sprites)
	jsr dyn_in
	ldx #3
@mc:	lda hdr + H_MISC,x
	sta dmisc,x
	dex
	bpl @mc
	jsr pal_in
	; the bitmap from the back screen
	lda #>VRAM_BG
	sta r0
	stz r0+1
	stz r1
	stz r1+1
	jsr vcopy
	; the program's menus again (its MENU SHOW), then the bar's rows
	lda #<g_reshow
	ldx #>g_reshow
	ldy _vx_ovl7
	jsr dcall
	jsr bar_in
	jsr col_in
	lda dmisc
	sta dispBufferOn
	lda dmisc+1
	sta clipOn
	lda dmisc+3             ; the timers again
	beq @go
	lda #<o1_procs
	ldx #>o1_procs
	ldy appBank
	jsr dcall
@go:	lda _ide_step
	sta dstep
	jsr calls
	sta dsdep
	jsr d_mark
	lda #VS_RUN
	sta _vb_state
.ifdef IDE_TEST
	ldx #dclk2 - dclks
	jsr clock
	ldx #0
@m:	lda MResume,x
	beq @d
	sta EMU_STDOUT
	inx
	bra @m
@d:	ldx #0                  ; the whole Continue (from ide_go), then the screen's part
	jsr clk_out
	lda #' '
	sta EMU_STDOUT
	ldx #dclk1 - dclks
	jsr clk_out
	lda #10
	sta EMU_STDOUT
.endif
	rts

.ifdef IDE_TEST
; dclk2 - (dclks + x) in hex, 4 bytes
clk_out:
	sec
	lda dclk2
	sbc dclks,x
	sta dclkd
	lda dclk2+1
	sbc dclks+1,x
	sta dclkd+1
	lda dclk2+2
	sbc dclks+2,x
	sta dclkd+2
	lda dclk2+3
	sbc dclks+3,x
	sta dclkd+3
	ldy #3
@h:	lda dclkd,y
	jsr hex2
	dey
	bpl @h
	rts
hex2:	pha
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
MResume: .byte "VB RESUME ", 0
dclkd:	.res 4
.endif


;---------------------------------------------------------------
; D_EVAL: the editor's requests (DI_REQ), each answer into DI_RES
;---------------------------------------------------------------
d_eval:	lda dsb
	bne @1
	rts
@1:	jsr pic_load
	jsr zp_in
	jsr dyn_in
	jsr keep_err
	lda #<DI_REQN
	sta p2
	lda #>DI_REQN
	sta p2+1
	ldy #0
	jsr diget
	sta dn
	lda #<DI_REQ
	sta dreq
	lda #>DI_REQ
	sta dreq+1
	stz dri
@req:	lda dri
	cmp dn
	jeq @end
	cmp #DI_RESN
	jcs @end
	stz dol
	lda dreq                ; its kind
	sta p2
	lda dreq+1
	sta p2+1
	ldy #0
	jsr diget
	sta dk
	inc dreq                ; its tokens
	bne @2
	inc dreq+1
@2:	jsr fix_floats
	lda dk
	cmp #DR_DIMS
	beq @dims
	jsr at_req
	lda dk
	cmp #DR_SET
	beq @set
	lda #<eval
	ldx #>eval
	jsr dtry
	bcs @err
	jsr at_end_req
	bne @syn
	jsr put_value
	bra @next
@set:	lda #<st_assign
	ldx #>st_assign
	jsr dtry
	bcs @err
	jsr at_end_req
	beq @next
@syn:	lda #E_SYNTAX
	sta errno
	lda #<err_fetch
	ldx #>err_fetch
	ldy appBank
	jsr dcall
@err:	jsr put_err
	bra @next
@dims:	jsr put_dims
@next:	jsr out_res
	lda #<free_temps
	ldx #>free_temps
	ldy pbank
	jsr dcall
	inc dri
	; past the request's tokens: to its 0 (skip_tok)
	jsr at_req
@sk:	jsr req_peek
	beq @sd
	lda #<skip_tok
	ldx #>skip_tok
	ldy pbank
	jsr dcall
	bra @sk
@sd:	lda ip
	clc
	adc #1
	sta dreq
	lda ip+1
	adc #0
	sta dreq+1
	jmp @req
@end:	jsr give_err
	jsr pic_load            ; (inbuf: a C overlay's arguments meanwhile)
	jsr dyn_out             ; (an assignment changed a global's cell)
	jsr zp_in
	rts

; ip, pbank: the request's tokens in DI
at_req:	lda dreq
	sta ip
	lda dreq+1
	sta ip+1
	lda _vx_dbg
	sta pbank
	stz vsp
	rts

; the byte at ip (DI) -> a, z set if 0
req_peek:
	lda ip
	sta p2
	lda ip+1
	sta p2+1
	ldy #0
	jsr diget
	cmp #0
	rts

; z set if ip is at the request's end (its 0)
at_end_req:
	jmp req_peek

; T_FLOAT literals the editor wrote with their spelling only: their
; values (parse_num, as VAL)
fix_floats:
	jsr at_req
@l:	jsr req_peek
	beq @r
	cmp #T_FLOAT
	bne @n
	ldy #6                  ; the spelling: length, bytes
	jsr diget
	sta t0
	ldx #0
@c:	cpx t0
	beq @cd
	iny
	phx
	jsr diget
	plx
	sta sbufa,x
	inx
	bra @c
@cd:	lda ip
	pha
	lda ip+1
	pha
	lda #1
	jsr parse_num
	pla
	sta ip+1
	pla
	sta ip
	bcs @n                  ; (not a number: eval's syntax error later)
	lda #<toflt
	ldx #>toflt
	ldy pbank
	jsr dcall
	lda ip
	sta p2
	lda ip+1
	sta p2+1
	ldx #0
	ldy #1
@w:	lda ac0,x
	jsr diput
	inx
	iny
	cpy #6
	bne @w
@n:	lda #<skip_tok
	ldx #>skip_tok
	ldy pbank
	jsr dcall
	bra @l
@r:	rts

; a/x = an interpreter routine run at ip (pbank) with errors caught
; (vb.s raise2 -> dbg_trapped: carry set, errmsg its text)
dtry:	sta dtr
	stx dtr+1
	tsx
	stx dbgsp
	lda #1
	sta dbgtrap
	lda dtr
	ldx dtr+1
	ldy pbank
	jsr dcall
	stz dbgtrap
	clc                     ; (its temporaries freed after the answer is made)
	rts

; the answer: "?" and the error's message
put_err:
	lda #'?'
	jsr out_c
	ldx #0
@m:	lda errmsg,x
	beq @r
	phx
	jsr out_c
	plx
	inx
	bne @m
@r:	rts

; acc's value as the answer (a string quoted)
put_value:
	lda aty
	cmp #TY_S
	beq @s
	lda #<num_text
	ldx #>num_text
	ldy pbank
	jsr dcall
	ldx #0
	lda numbuf
	cmp #' '
	bne @n
	inx
@n:	lda numbuf,x
	beq @r
	phx
	jsr out_c
	plx
	inx
	bra @n
@r:	rts
@s:	lda #<str_to_buf
	ldx #>str_to_buf
	ldy pbank
	jsr dcall
	lda #'"'
	jsr out_c
	ldx #0
@c:	cpx t0
	beq @q
	lda dol
	cmp #DI_RESW - 4
	bcs @long
	lda sbufa,x
	phx
	jsr out_c
	plx
	inx
	bra @c
@q:	lda #'"'
	jmp out_c
@long:	lda #'.'
	jsr out_c
	lda #'.'
	jmp out_c

; DR_DIMS: UBOUND(a, k) for k = 1, 2, 3 (as many as there are): "10, 5"
put_dims:
	lda dreq                ; the array's T_VAR operand
	sta p2
	lda dreq+1
	sta p2+1
	ldy #1
	jsr diget
	sta dmisc
	iny
	jsr diget
	sta dmisc+1
	lda #1
	sta dmisc+2
@k:	lda #<DI_SCR            ; UBOUND ( T_VAR lo hi , $01 k 0 ) 0
	sta p2
	lda #>DI_SCR
	sta p2+1
	ldy #0
@w:	lda dimtok,y
	cpy #3
	bne @w1
	lda dmisc
@w1:	cpy #4
	bne @w2
	lda dmisc+1
@w2:	cpy #7
	bne @w3
	lda dmisc+2
@w3:	jsr diput
	iny
	cpy #11
	bne @w
	lda #<DI_SCR
	sta ip
	lda #>DI_SCR
	sta ip+1
	lda _vx_dbg
	sta pbank
	stz vsp
	lda #<eval
	ldx #>eval
	jsr dtry
	bcs @end
	lda dmisc+2
	cmp #1
	beq @1
	lda #','
	jsr out_c
	lda #' '
	jsr out_c
@1:	lda ac0
	ldx ac1
	jsr int_to_text
	ldx #1
@n:	lda numbuf,x
	beq @nd
	phx
	jsr out_c
	plx
	inx
	bra @n
@nd:	inc dmisc+2
	lda dmisc+2
	cmp #4
	jcc @k
	rts
@end:	lda #<free_temps
	ldx #>free_temps
	ldy pbank
	jsr dcall
	lda dmisc+2
	cmp #1
	bne @r
	lda #'-'                ; (no DIM yet)
	jmp out_c
@r:	rts
dimtok:	.byte TK_UBOUND, '(', T_VAR, 0, 0, ',', T_INTDEC, 0, 0, ')', 0

; a character onto the answer (DI_RESW - 1 at most)
out_c:	ldx dol
	cpx #DI_RESW - 1
	bcs @r
	sta dout,x
	inc dol
@r:	rts

; the answer into DI_RES + 32 * dri
out_res:
	ldx dol
	stz dout,x
	lda dri                 ; DI_RES + 24 * dri (dri * 8 * 3)
	sta p2
	stz p2+1
	asl p2
	rol p2+1
	asl p2
	rol p2+1
	asl p2
	rol p2+1
	lda p2
	ldx p2+1
	asl p2
	rol p2+1
	clc
	adc p2
	sta p2
	txa
	adc p2+1
	sta p2+1
	clc
	lda p2
	adc #<DI_RES
	sta p2
	lda p2+1
	adc #>DI_RES
	sta p2+1
	ldy #0
@c:	lda dout,y
	jsr diput
	iny
	cpy #DI_RESW
	bne @c
	rts

;---------------------------------------------------------------
; D_QUOTE: the error that stopped the program, for the editor's message
; (the statement's tokens from sip to its line's end, in the runtime's form)
;---------------------------------------------------------------
d_quote:
	jsr line_of             ; (find_erl: fe_s, fe_e, _vb_esrc, erl)
	lda #<DI_QUOTE
	sta p2
	lda #>DI_QUOTE
	sta p2+1
	ldy #DQ_ERRNO
	lda errno
	jsr diput
	iny
	lda errfile
	jsr diput
	iny
	lda _vb_eproc
	jsr diput
	iny
	lda _vb_esrc
	jsr diput
	iny
	lda _vb_esrc+1
	jsr diput
	iny
	lda erl
	jsr diput
	iny
	lda erl+1
	jsr diput
	iny
	lda fe_s
	jsr diput
	iny
	lda fe_s+1
	jsr diput
	iny
	lda _pbase
	jsr diput
	iny
	lda _cellbase
	jsr diput
	iny
	lda _cellbase+1
	jsr diput
	lda fe_e                ; the bytes to the line's end
	sec
	sbc fe_s
	sta r2
	lda fe_e+1
	sbc fe_s+1
	beq @n
	lda #240
	sta r2
@n:	lda r2
	cmp #241
	bcc @n2
	lda #240
	sta r2
@n2:	ldy #DQ_N
	lda r2
	jsr diput
	stz r2+1
	lda sip
	sta r0
	lda sip+1
	sta r0+1
	LoadW r1, DI_QUOTE + DQ_TOK
	lda sipb
	sta r3L
	lda _vx_dbg
	sta r3H
	jmp BankCopy
.assert * < DI_BASE, error, "vbdbg.s: overlay 12's code runs into DI"
