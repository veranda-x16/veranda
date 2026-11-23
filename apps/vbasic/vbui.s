; VeraBASIC Run: overlay 6, the Veranda extensions' statements and functions
; (phase 3, DECISIONS V89): the dispatch of every second-page token, the
; arguments, the event model (ON ... CALL, TIMER, WAIT EVENTS, DOEVENTS,
; SLEEP's events), windows, menus, the mouse, the keys, the time; the
; graphics, text, colour and sound statements are parsed here and run in
; overlay 7 (vbgfx.s).
;
; Arguments: each is evaluated (bcall: the program's bank) and pushed on
; the value stack; only when all are there are they converted (xi: integers,
; the strings in sbufb and sbufa) and, in the test build, logged
; ("VB> @nn args", the reference's tools/vbasic.py run --replay logs the
; same). A FUNCTION in an argument may run any statement meanwhile, even
; this one: nothing of a statement is kept here across an evaluation.
;
; MIT licence (LICENSE).

xi	= numbuf                ; the arguments as integers (20 at most)
xi_n	= numbuf + 38           ; how many

.macro PCALL addr               ; a resident routine with the program's bank
	lda #<addr
	ldx #>addr
	ldy pbank
	jsr bcall
.endmacro
.macro O1CALL addr              ; a routine of overlay 1 (vbev.s)
	lda #<addr
	ldx #>addr
	ldy appBank
	jsr bcall
.endmacro
.macro G7 addr                  ; overlay 7's routine, then back here
	lda #<addr
	ldx #>addr
	ldy _vx_ovl7
	jsr bcall
.endmacro
.macro G8 addr                  ; overlay 8's routine, then back here
	lda #<addr
	ldx #>addr
	ldy _vx_ovl8
	jsr bcall
.endmacro
.macro G9 addr                  ; overlay 9's
	lda #<addr
	ldx #>addr
	ldy _vx_ovl9
	jsr bcall
.endmacro
.macro O1SET slot, val          ; o1tab[slot] = val (a)
	ldx #slot
	stx t0
	sta t1
	O1CALL o1_set
.endmacro

.segment "OVL6BSS"
xs_nn:	.res 1                  ; the statement running: its token, its second word (the log)
lgsub:	.res 1
xs_fn:	.res 1                  ; the function running
xa_v:	.res 1
xa_s:	.res 1
wtitle:	.res 4 * 64
waitf:	.res 1                  ; WAIT EVENTS counted as an event point
curw:	.res 1                  ; the window in use (0: the screen)
mw:	.res 2
mx:	.res 2
mk:	.res 1
mj:	.res 1
mi:	.res 1
fdt:	.res 4                  ; (vbui4.s)

.segment "OVERLAY6"

;---------------------------------------------------------------
; tokens: through fpeek (the program's bank)
;---------------------------------------------------------------
; a = the byte at ip + y
tpk:	lda ip
	sta p2
	lda ip+1
	sta p2+1
	lda pbank
	sta xb
	jmp fpeek

tadv:	clc
	adc ip
	sta ip
	bcc @r
	inc ip+1
@r:	rts

; the character a at ip: carry set, past it
tacc:	sta t0
	ldy #0
	jsr tpk
	cmp t0
	bne tno
	lda #1
	jsr tadv
	sec
	rts
tno:	clc
	rts

; the character a must be at ip
texp:	jsr tacc
	bcs tyes
syn:	ERR E_SYNTAX
tyes:	rts

; the second-page word a at ip: carry set, past it
tword:	sta t0
	ldy #0
	jsr tpk
	cmp #T_EXT
	bne tno
	ldy #1
	jsr tpk
	cmp t0
	bne tno
	lda #2
	jsr tadv
	sec
	rts

;---------------------------------------------------------------
; the arguments: each pushed on the value stack
;---------------------------------------------------------------
; a number
xan:	PCALL eval
	lda aty
	cmp #TY_S
	beq tyerr
	jmp vpush
tyerr:	ERR E_TYPE
; a string
xs:	PCALL eval
	lda aty
	cmp #TY_S
	bne tyerr
	jmp vpush
; ',' then a number, a string
xcn:	lda #','
	jsr texp
	bra xan
xcs:	lda #','
	jsr texp
	bra xs
; [#] a number (a window)
xh:	lda #'#'
	jsr tacc
	bra xan
; a word (a = its second-page byte) as an argument
xw:	sta ac0
	lda #$40
xwp:	sta aty
	stz ac1
	jmp vpush
; a procedure (a SUB by its name)
xap:	ldy #0
	jsr tpk
	cmp #T_NAMEREF
	bne syn
	ldy #2
	jsr tpk
	bpl syn                 ; (a label)
	ldy #1
	jsr tpk
	sta ac0
	lda #6
	jsr tadv
	lda #$41
	bra xwp

; the statement's end, then the arguments converted and logged; a = the
; value stack's height before them (xa_func: no end, no log)
xa_done:
	pha
	PCALL need_end
	pla
	sec
	bra xa_c
xa_func:
	clc
xa_c:	php
	sta xa_v                ; (no evaluation from here on)
	stz xa_s              ; the strings so far
	stz xi_n
.ifdef VB_TEST
	plp
	php
	bcc @nl
	jsr lg_stmt
@nl:
.endif
@l:	lda xa_v
	cmp vsp
	jcs @d
	pha
	clc
	adc #6
	sta xa_v
	pla
	jsr vpk                 ; acc = the value
	lda xi_n
	asl a
	tay
	lda aty
	cmp #$40
	bcc @v
	cmp #$42
	jeq @u24
	; a word or a procedure
	lda ac0
	sta xi,y
	lda #0
	sta xi+1,y
.ifdef VB_TEST
	plp
	php
	jcc @n
	lda aty
	cmp #$41
	beq @lp
	lda #' '
	jsr lg_c
	lda #'@'
	jsr lg_c
	lda ac0
	jsr lg_hex
	jmp @n
@lp:	lda #' '
	jsr lg_c
	lda #'P'
	jsr lg_c
	lda ac0
	sta mw
	stz mw+1
	jsr lg_dec0
.endif
	jmp @n
@u24:	lda ac0                 ; 24 bits (SEEK): the high byte in the next slot
	sta xi,y
	lda ac1
	sta xi+1,y
	lda ac2
	sta xi+2,y
.ifdef VB_TEST
	plp
	php
	jcc @n
	lda #' '
	jsr lg_c
	jsr lg_d24
.endif
	jmp @n
@v:	cmp #TY_S
	beq @s
	phy
	PCALL toint
	ply
	lda ac0
	sta xi,y
	lda ac1
	sta xi+1,y
.ifdef VB_TEST
	plp
	php
	bcc @n
	lda ac0
	ldx ac1
	jsr lg_dec
.endif
	bra @n
@s:	phy
	PCALL str_to_buf        ; sbufa, t0 its length
	ply
	lda t0
	sta xi,y
	lda #0
	sta xi+1,y
	ldx t0
	stz sbufa,x
	lda xa_s
	bne @s2
	inc xa_s              ; the first string: to sbufb (all its bytes, a 0 after)
	ldx #0
@cp:	cpx t0
	beq @c0
	lda sbufa,x
	sta sbufb,x
	inx
	bra @cp
@c0:	stz sbufb,x
@s2:
.ifdef VB_TEST
	plp
	php
	bcc @n
	lda #' '
	jsr lg_c
	lda #'"'
	jsr lg_c
	ldx #0
@ls:	cpx t0
	beq @le
	lda sbufa,x
	jsr lg_sc
	inx
	bra @ls
@le:	lda #'"'
	jsr lg_c
.endif
@n:	inc xi_n
	jmp @l
@d:	plp
.ifdef VB_TEST
	bcc @r
	lda #10
	jsr lg_c
.endif
@r:	lda xi_n
	asl a
	asl a
	adc xi_n
	adc xi_n                ; * 6
	sta t0
	lda vsp
	sec
	sbc t0
	sta vsp                 ; popped
	rts

; an inline spec after the jsr: "n" a number, "s" a string, "," a comma,
; "[" the rest only after a comma, "(" ")"; then the routine of overlay 7
; it runs (a statement: after the end and the log). The spec's place is
; kept on the 6502 stack across the evaluations.
xspec:	ldx #0
	bra xsp
xspec8:	ldx #1
	bra xsp
xspec9:	ldx #2
	bra xsp
xfspec:	ldx #$80
	bra xsp
xfspec8: ldx #$81
	bra xsp
xfspec9: ldx #$82
; x: bit 7 a function, bits 0-1 the overlay (7, 8, 9); a function's spec
; may start with '$' (its result a string: sbufa, t0) or '%' (24 bits:
; ac0-ac2)
xsp:	pla                     ; the spec - 1
	sta p1
	pla
	sta p1+1
	ldy #1
	lda (p1),y
	cmp #'$'
	bne @k1
	txa
	ora #$40
	bra @k2
@k1:	cmp #'%'
	bne @k3
	txa
	ora #$20
@k2:	tax
	inc p1
	bne @k3
	inc p1+1
@k3:	phx                     ; the flags
	lda vsp
	pha                     ; the height before
	lda p1+1
	pha
	lda p1
	pha
@l:	pla                     ; the next spec byte
	clc
	adc #1
	sta p1
	pla
	adc #0
	sta p1+1
	pha
	lda p1
	pha
	lda (p1)
	beq @end
	cmp #'n'
	bne @1
	jsr xan
	bra @l
@1:	cmp #'s'
	bne @2
	jsr xs
	bra @l
@2:	cmp #'['
	bne @3
	lda #','
	jsr tacc
	bcs @l
@sk:	pla                     ; no more: past the spec
	clc
	adc #1
	sta p1
	pla
	adc #0
	sta p1+1
	pha
	lda p1
	pha
	lda (p1)
	bne @sk
	bra @end
@3:	jsr texp                ; , ( )
	bra @l
@end:	pla
	sta p1
	pla
	sta p1+1
	ldy #1                  ; the routine after the 0
	lda (p1),y
	sta mx
	iny
	lda (p1),y
	sta mx+1
	pla                     ; the height
	plx                     ; bit 7: a function
	phx
	cpx #$80
	bcs @f
	jsr xa_done
	bra @g
@f:	jsr xa_func
@g:	lda mx                  ; the overlay's routine (7, 8: with WINDOW USE's clip)
	sta r14
	lda mx+1
	sta r14+1
	pla
	pha
	and #3
	beq @o7
	cmp #1
	beq @o8
	lda #<g9run
	ldx #>g9run
	ldy _vx_ovl9
	bra @go
@o8:	lda #<g8run
	ldx #>g8run
	ldy _vx_ovl8
	bra @go
@o7:	lda #<g7run
	ldx #>g7run
	ldy _vx_ovl7
@go:	jsr bcall
	pla
	bmi @fr
	clc
	rts
@fr:	asl a
	bmi @frs
	asl a
	bmi @f24
	lda ac0                 ; a function: its integer, logged
	ldx ac1
	jmp fr_int
@frs:	jmp fr_str
@f24:	jmp fr_u24

;---------------------------------------------------------------
; the dispatch: xnn the token (0: ON event)
;---------------------------------------------------------------
xstmt:	lda xs_nn               ; (a statement may run inside another's arguments)
	pha
	lda lgsub
	pha
	lda xnn
	sta xs_nn
	stz lgsub
	jsr @go
	pla
	sta lgsub
	pla
	sta xs_nn
	rts
@go:	lda xnn
	bne @1
	jmp s_on
@1:	sec
	sbc #$80
	bcc @no
	cmp #XS_N
	bcs @no
	asl a
	tax
	lda xstab+1,x
	beq @no
	jmp (xstab,x)
@no:	ERR E_NOTYET

xfunc:	lda xs_fn
	pha
	lda xnn
	sta xs_fn
	jsr @go
	pla
	sta xs_fn
	rts
@go:	lda xnn
	sec
	sbc #$80
	bcc @no
	cmp #XS_N
	bcs @no
	asl a
	tax
	lda xftab+1,x
	beq @no
	jmp (xftab,x)
@no:	ERR E_NOTYET

;---------------------------------------------------------------
; the logs (the test build): "VB> @nn ...", "VB= @nn value", "VB EVENT"
;---------------------------------------------------------------
.ifdef VB_TEST
lg_c:	sta EMU_STDOUT
	rts
; a string's byte: a control character or "\" as "\" and two hex digits
; (the reference reads them back: tools/vbveranda.py)
lg_sc:	cmp #' '
	bcc @e
	cmp #$7F
	bcs @e
	cmp #$5C
	bne lg_c
@e:	pha
	lda #$5C
	jsr lg_c
	pla
	jmp lg_hex
lg_stmt:
	ldx #0
@l:	lda MStmt,x
	beq @t
	jsr lg_c
	inx
	bra @l
@t:	lda xs_nn
	bne @h
	lda #'O'
	jsr lg_c
	lda #'N'
	jmp lg_c
@h:	pha
	lda #'@'
	jsr lg_c
	pla
	jsr lg_hex
	lda lgsub
	beq @r
	lda #' '
	jsr lg_c
	lda #'@'
	jsr lg_c
	lda lgsub
	jmp lg_hex
@r:	rts
lg_fn:	ldx #0
@l:	lda MFn,x
	beq @t
	jsr lg_c
	inx
	bra @l
@t:	lda #'@'
	jsr lg_c
	lda xs_fn
	jsr lg_hex
	lda #' '
	jmp lg_c
lg_hex:	pha
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
	jmp lg_c
; " " and the signed number a/x
lg_dec:	sta mw
	stx mw+1
	lda #' '
	jsr lg_c
lg_dec0:
	lda mw+1
	bpl @p
	lda #'-'
	jsr lg_c
	lda #0
	sec
	sbc mw
	sta mw
	lda #0
	sbc mw+1
	sta mw+1
@p:	ldy #0
@dv:	ldx #16                 ; mw / 10, the remainder in a
	lda #0
@b:	asl mw
	rol mw+1
	rol a
	cmp #10
	bcc @n
	sbc #10
	inc mw
@n:	dex
	bne @b
	pha
	iny
	lda mw
	ora mw+1
	bne @dv
@o:	pla
	ora #'0'
	jsr lg_c
	dey
	bne @o
	rts
MStmt:	.byte "VB> ", 0
MFn:	.byte "VB= ", 0
MEv:	.byte "VB EVENT", 0
.endif

;---------------------------------------------------------------
; function results
;---------------------------------------------------------------
; acc = the integer a/x (logged)
fr_int:	sta ac0
	stx ac1
	lda #TY_I
	sta aty
.ifdef VB_TEST
	jsr lg_fn
	lda ac0
	sta mw
	lda ac1
	sta mw+1
	jsr lg_dec0
	lda #10
	jsr lg_c
.endif
	rts
; a value (not logged)
fr_val:	sta ac0
	stx ac1
	lda #TY_I
	sta aty
	rts
; acc = sbufa's t0 bytes (logged)
fr_str:
.ifdef VB_TEST
	jsr lg_fn
	lda #'"'
	jsr lg_c
	ldx #0
@l:	cpx t0
	beq @e
	lda sbufa,x
	jsr lg_sc
	inx
	bra @l
@e:	lda #'"'
	jsr lg_c
	lda #10
	jsr lg_c
.endif
	PCALL btt0
	rts

;---------------------------------------------------------------
; the event model
;---------------------------------------------------------------
; carry set while a handler runs (its frame still on the BASIC stack)
inhand:
	lda _vx_hact
	beq @no
	lda _vx_hbsp
	cmp bsp
	lda _vx_hbsp+1
	sbc bsp+1
	bcc @yes                ; bsp above the handler's base
	stz _vx_hact
@no:	clc
	rts
@yes:	sec
	rts

dpc_inc:
	inc _vx_dpc
	bne @r
	inc _vx_dpc+1
@r:	rts

; ip at the statement again (it runs again after a handler or a slice)
setret:	lda sip
	sta ip
	lda sip+1
	sta ip+1
	lda sipb
	sta pbank
	rts
saveip:	ply                     ; (the caller's ip under its return)
	plx
	lda pbank
	pha
	lda ip+1
	pha
	lda ip
	pha
	phx
	phy
	rts
restip:	ply
	plx
	pla
	sta ip
	pla
	sta ip+1
	pla
	sta pbank
	phx
	phy
	rts

; the next queued event's handler entered (returning to ip, pbank): it
; does not come back; returns with carry clear when no event has a handler
disp:	O1CALL o1_take
	bcc @r
	lda _vx_ev+8
	beq disp                ; nobody's: dropped
.ifdef VB_TEST
	jsr lg_event
.endif
	lda _vx_ev+8
	dec a
	jsr proc_ptr            ; p2
	ldy #0
	lda (p2),y
	beq @1
	ERR E_ARGS              ; a handler takes no arguments
@1:	ldy #2
	lda (p2),y
	and #1
	beq @2
	jmp syn                 ; a FUNCTION
@2:	stz vsp
	stz waitf
	stz _vx_idle
	lda _vx_ev
	cmp #EV_TIMER
	beq @3
	inc _vx_evn             ; (the gate's scripts count the other events)
@3:
	lda bsp
	sta _vx_hbsp
	lda bsp+1
	sta _vx_hbsp+1
	lda #1
	sta _vx_hact
	PCALL enter_sub
	jmp mapp_jumped
@r:	rts

.ifdef VB_TEST
; "VB EVENT n KIND a ..." (the reference dispatches it at its n-th event point)
lg_event:
	ldx #0
@m:	lda MEv,x
	beq @1
	jsr lg_c
	inx
	bra @m
@1:	lda _vx_dpc
	ldx _vx_dpc+1
	jsr lg_dec
	lda #' '
	jsr lg_c
	lda _vx_ev
	asl a
	asl a
	asl a
	tax
@n:	lda EvNames-8,x
	beq @2
	jsr lg_c
	inx
	bra @n
@2:	lda _vx_ev
	cmp #EV_CLICK
	bne @3
	lda _vx_ev+3
	ldx _vx_ev+4
	jsr lg_dec
	lda _vx_ev+5
	ldx _vx_ev+6
	jsr lg_dec
	lda _vx_ev+1
	ldx #0
	jsr lg_dec
	bra @e
@3:	cmp #EV_QUIT
	beq @e
	cmp #EV_WHEEL
	bne @4
	lda _vx_ev+1
	ldx #0
	cmp #$80
	bcc @w
	dex
@w:	jsr lg_dec
	bra @e
@4:	lda _vx_ev+1
	ldx #0
	jsr lg_dec
	lda _vx_ev
	cmp #EV_KEY
	bne @e
	lda _vx_ev+2
	and #$0F
	ldx #0
	jsr lg_dec
@e:	lda #10
	jmp lg_c
EvNames:
	.byte "MENU", 0, 0, 0, 0
	.byte "CLICK", 0, 0, 0
	.byte "KEY", 0, 0, 0, 0, 0
	.byte "WHEEL", 0, 0, 0
	.byte "CLOSE", 0, 0, 0
	.byte "TIMER", 0, 0, 0
	.byte "QUIT", 0, 0, 0, 0
	.byte "ICON", 0, 0, 0, 0
.endif

; WAIT EVENTS (the main lines' end too): a handler, or the slice ends
xwait:	jsr inhand
	bcc @1
	ERR E_ILLQ              ; not inside a handler
@1:	lda waitf
	bne @2
	inc waitf
	jsr dpc_inc
@2:	jsr setret
	jsr disp
	lda #1
	sta _vx_idle
	jmp yield

; DOEVENTS: the handlers of the events queued, then on
xdoev:	jsr inhand
	bcs @y
	jsr dpc_inc
	jsr saveip
	jsr setret
	jsr disp
	jsr restip
@y:	jmp yield

; SLEEP, each time it runs (xnn = 1 the first time): an event's handler
xsleep:	jsr inhand
	bcs @r
	lda xnn
	beq @1
	jsr dpc_inc
@1:	jsr saveip
	jsr setret
	jsr disp
	jsr restip
@r:	rts

; ON CLICK | KEY | WHEEL | QUIT | CLOSE #w CALL procedure
s_on:	lda vsp
	pha
	lda #<TX_CLICK
	jsr tword
	ldx #OT_CLICK
	bcs @w
	lda #<TX_KEY
	jsr tword
	ldx #OT_KEY
	bcs @w
	lda #<TX_WHEEL
	jsr tword
	ldx #OT_WHEEL
	bcs @w
	lda #<TX_QUIT
	jsr tword
	ldx #OT_QUIT
	bcs @w
	lda #<TX_CLOSE
	jsr tword
	bcs @c
	jmp syn
@c:	lda #<TX_CLOSE
	jsr xw
	jsr xh
	ldx #OT_CLOSE - 1
	bra @call
@w:	phx
	lda t0
	jsr xw
	plx
@call:	phx
	lda #TK_CALL
	jsr texp
	jsr xap
	plx
	pla
	phx
	jsr xa_done
	plx
	lda xi_n
	cmp #3
	bcc @1
	txa                     ; CLOSE #w: the window
	clc
	adc xi+2
	tax
	lda xi+3
	bne @ill
	lda xi+2
	beq @ill
	cmp #5
	bcs @ill
	lda xi+4                ; the procedure
	bra @set
@1:	lda xi+2
@set:	inc a
	stx t0
	sta t1
	O1CALL o1_set
	lda #1
	sta _vx_any
	lda t0
	cmp #OT_WHEEL
	bne @r
	O1CALL o1_procs         ; the wheel's poll
@r:	clc
	rts
@ill:	ERR E_ILLQ

; TIMER n, frames CALL procedure | TIMER n ON | OFF | STOP
s_timer:
	lda vsp
	pha
	jsr xan
	lda #','
	jsr tacc
	bcs @set
	lda #TK_ON
	jsr tacc
	lda #0
	bcs @op
	lda #TK_STOP
	jsr tacc
	lda #2
	bcs @op
	lda #<TX_OFF
	jsr tword
	bcs @off
	jmp syn
@off:	lda #1
@op:	pha
	jsr xw                  ; (logged as the word's byte: 0 ON, 1 OFF, 2 STOP)
	pla
	tax
	pla
	phx
	jsr xa_done
	jsr tnum
	pla
	sta t0
	stx t1
	O1CALL o1_tctl
	clc
	rts
@set:	jsr xan
	lda #TK_CALL
	jsr texp
	jsr xap
	pla
	jsr xa_done
	jsr tnum
	stx mk
	lda xi+2
	ora xi+3
	beq @ill
	txa
	asl a
	clc
	adc #OT_TFR
	tax
	lda xi+2
	stx t0
	sta t1
	O1CALL o1_set
	inc t0
	lda xi+3
	sta t1
	O1CALL o1_set
	lda mk
	clc
	adc #OT_TON
	sta t0
	lda #1
	sta t1
	O1CALL o1_set
	lda mk
	clc
	adc #OT_TIMER
	sta t0
	lda xi+4
	inc a
	sta t1
	O1CALL o1_set
	lda #1
	sta _vx_any
	O1CALL o1_procs
	clc
	rts
@ill:	ERR E_ILLQ
; x = the timer (xi 0: 1-8) - 1
tnum:	lda xi+1
	bne @ill
	ldx xi
	beq @ill
	cpx #9
	bcs @ill
	dex
	rts
@ill:	ERR E_ILLQ

;---------------------------------------------------------------
; APP: NAME kept for the menu bar, CLASSIC; the rest is for Make application
;---------------------------------------------------------------
s_app:	lda #<TX_NAME
	jsr tword
	bcc @c
	lda vsp
	pha
	jsr xs
	pla
	jsr xa_func             ; (not logged: the reference skips APP too)
	G7 g_appname
	bra @sk
@c:	lda #<TX_CLASSIC
	jsr tword
	bcc @sk
	G7 g_classic
@sk:	PCALL skip_stmt
	clc
	rts

;---------------------------------------------------------------
; windows
;---------------------------------------------------------------
; the console hidden: the screen under the menu bar cleared to the desk
ui_on:	lda _vx_hide
	bne @r
	inc _vx_hide
	stz clipOn
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	lda #0
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 16
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	lda #0                  ; theme_rect(0, 80, 2, 58, the desk)
	jsr pusha
	lda #80
	jsr pusha
	lda #2
	jsr pusha
	lda #58
	jsr pusha
	lda _theme+1
	jsr _theme_rect
@r:	rts

; p0 = window xi[0]'s struct (1-4), a = its index 0-3
wptr:	lda xi+1
	bne @ill
	lda xi
	beq @ill
	cmp #5
	bcs @ill
	dec a
	pha
	sta t0
	asl a
	asl a
	asl a
	sec
	sbc t0
	clc
	adc #<_vx_wins
	sta p0
	lda #>_vx_wins
	adc #0
	sta p0+1
	pla
	rts
@ill:	ERR E_ILLQ
; ... and it must be open
wopen:	jsr wptr
	pha
	sta t0
	clc
	adc #OT_WOPEN
	sta t0
	O1CALL o1_get
	txa
	bne @ok
	ERR E_NOWIN
@ok:	pla
	rts

; window a's title into sbufb
wtitle_b:
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	tax
	ldy #0
@c:	lda wtitle,x
	sta sbufb,y
	beq @r
	inx
	iny
	cpy #63
	bcc @c
	lda #0
	sta sbufb,y
@r:	rts

s_window:
	lda vsp
	pha
	lda #<TX_TITLE
	jsr tword
	jcs w_title
	lda #<TX_STATUS
	jsr tword
	jcs w_status
	lda #<TX_USE
	jsr tword
	jcs w_use
	lda #<TX_BACK
	jsr tword
	jcs w_back
	lda #<TX_FRONT
	jsr tword
	jcs w_front
	lda #<TX_CLOSE
	jsr tword
	jcs w_close
	; WINDOW #w, x, y, wc, hc, title$ [, options]
	jsr xh
	jsr xcn
	jsr xcn
	jsr xcn
	jsr xcn
	jsr xcs
@o:	lda #','
	jsr tacc
	bcc @d
	lda #<TX_TOOL
	jsr tword
	bcs @wn
	lda #<TX_STATUS
	jsr tword
	bcs @wn
	lda #<TX_CLOSE
	jsr tword
	bcs @ww
	lda #<TX_FRAME
	jsr tword
	bcs @ww
	lda #<TX_SHADOW
	jsr tword
	bcs @ww
	jmp syn
@wn:	lda t0
	jsr xw
	jsr xan
	bra @o
@ww:	lda t0
	jsr xw
	bra @o
@d:	pla
	jsr xa_done
	jsr wptr
	sta mk
	; x, y, w, h: on the screen, at least 6 x 4 cards, under the menu bar
	lda xi+3
	ora xi+5
	ora xi+7
	ora xi+9
	jne @ill
	lda xi+2
	clc
	adc xi+6
	cmp #81
	bcs @ill
	lda xi+4
	cmp #2
	bcc @ill
	clc
	adc xi+8
	cmp #61
	bcs @ill
	lda xi+6
	cmp #6
	bcc @ill
	lda xi+8
	cmp #4
	bcc @ill
	ldy #0
	lda xi+2
	sta (p0),y
	iny
	lda xi+4
	sta (p0),y
	iny
	lda xi+6
	sta (p0),y
	iny
	lda xi+8
	sta (p0),y
	iny
	lda #0
	sta (p0),y              ; tool
	iny
	sta (p0),y              ; status
	iny
	sta (p0),y              ; flags
	; the options from argument 6 on
	ldx #12
@op:	txa
	lsr a
	cmp xi_n
	bcs @dr
	lda xi,x
	ldy #4
	cmp #<TX_TOOL
	beq @n
	iny
	cmp #<TX_STATUS
	beq @n
	ldy xi,x
	lda #1                  ; VW_CLOSE
	cpy #<TX_CLOSE
	beq @f
	lda #2                  ; VW_FRAME
	cpy #<TX_FRAME
	beq @f
	lda #4                  ; VW_SHADOW
@f:	ldy #6
	ora (p0),y
	sta (p0),y
	inx
	inx
	bra @op
@n:	lda xi+2,x
	sta (p0),y
	inx
	inx
	inx
	inx
	bra @op
@ill:	ERR E_ILLQ
@dr:	; the title kept, the window drawn
	lda mk
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	tax
	ldy #0
@t:	lda sbufb,y
	sta wtitle,x
	beq @t2
	inx
	iny
	cpy #63
	bcc @t
	lda #0
	sta wtitle,x
	sta sbufb,y
@t2:	jsr ui_on
	lda mk
	sta t0
	G7 o1_win
	lda mk
	clc
	adc #OT_WOPEN
	sta t0
	lda #1
	sta t1
	sta _vx_used
	O1CALL o1_set
	clc
	rts

w_title:
	lda t0
	sta lgsub
	jsr xh
	jsr xcs
	pla
	jsr xa_done
	jsr wptr
	sta mk
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	tax
	ldy #0
@t:	lda sbufb,y
	sta wtitle,x
	beq @t2
	inx
	iny
	cpy #63
	bcc @t
	lda #0
	sta wtitle,x
	sta sbufb,y
@t2:	jsr wisopen
	bcc @r
	lda mk
	sta t0
	G7 o1_wtitle
@r:	clc
	rts
; carry set if window mk is open
wisopen:
	lda mk
	clc
	adc #OT_WOPEN
	sta t0
	O1CALL o1_get
	cpx #1
	rts

w_status:
	lda t0
	sta lgsub
	jsr xh
	jsr xcs
	jsr xcs
	pla
	jsr xa_done
	jsr wopen
	sta t0
	G7 o1_wstatus
	clc
	rts

w_back:	lda t0
	sta lgsub
	lda #8
	bra wbf
w_front:
	lda t0
	sta lgsub
	lda #0
wbf:	sta mj
	jsr xh
	pla
	jsr xa_done
	jsr wopen
	sta mk
	ldy #6
	lda (p0),y
	and #<~8
	ora mj
	sta (p0),y
	lda mk
	jsr wtitle_b
	lda mk
	sta t0
	G7 o1_wtitle
	clc
	rts

; WINDOW USE #w: the origin at its body's corner, the clip its body
w_use:	lda t0
	sta lgsub
	jsr xh
	pla
	jsr xa_done
	lda xi
	ora xi+1
	bne @w
	stz curw                ; #0: the screen
	jmp origin0
@w:	jsr wopen
	inc a
	sta curw
	jmp use_body

origin0:
	stz _vx_ox
	stz _vx_ox+1
	stz _vx_oy
	stz _vx_oy+1
	stz _vx_ocx
	stz _vx_ocy
	stz _vx_clip+8
	clc
	rts

; the origin and the clip: window curw's body (p0 its struct)
use_body:
	ldy #6
	lda (p0),y
	and #2                  ; VW_FRAME: the frame's pixel inside
	lsr a
	sta mj
	lda (p0)                ; x
	sta _vx_ocx
	sta r3L
	stz r3H
	ldx #3
@x8:	asl r3L
	rol r3H
	dex
	bne @x8
	lda r3L
	clc
	adc mj
	sta _vx_clip
	sta _vx_ox
	lda r3H
	adc #0
	sta _vx_clip+1
	sta _vx_ox+1
	ldy #2                  ; right: (x + w) * 8 - 1 - frame
	lda (p0)
	clc
	adc (p0),y
	sta r3L
	stz r3H
	ldx #3
@r8:	asl r3L
	rol r3H
	dex
	bne @r8
	lda r3L
	sec
	sbc #1
	sbc mj
	sta _vx_clip+2
	lda r3H
	sbc #0
	sta _vx_clip+3
	jsr body_top            ; a/x
	sta _vx_clip+4
	stx _vx_clip+5
	sta _vx_oy
	stx _vx_oy+1
	ldy #1
	lda (p0),y
	clc
	adc #2
	ldy #4
	adc (p0),y
	sta _vx_ocy
	jsr body_bot
	sta _vx_clip+6
	stx _vx_clip+7
	ldy #5
	lda (p0),y              ; no status band: the frame's line is the last
	bne @s
	lda _vx_clip+6
	sec
	sbc mj
	sta _vx_clip+6
	bcs @s
	dec _vx_clip+7
@s:	lda #1
	sta _vx_clip+8          ; (overlay 7 sets the kernel's clip around each drawing)
	clc
	rts

; a/x = the body's first line (p0's window): (y + 2 + tool) * 8
body_top:
	ldy #1
	lda (p0),y
	clc
	adc #2
	ldy #4
	adc (p0),y
	bra x8
; a/x = the body's last line: (y + h - status) * 8 - 1
body_bot:
	ldy #1
	lda (p0),y
	ldy #3
	clc
	adc (p0),y
	ldy #5
	sec
	sbc (p0),y
	jsr x8
	sec
	sbc #1
	bcs @r
	dex
@r:	rts
x8:	stz mw+1
	asl a
	rol mw+1
	asl a
	rol mw+1
	asl a
	rol mw+1
	ldx mw+1
	rts

; WINDOW CLOSE #w: erased to the desk
w_close:
	lda t0
	sta lgsub
	jsr xh
	pla
	jsr xa_done
	jsr wopen
	sta mk
	stz clipOn
	lda #0
	jsr SetPattern
	lda (p0)
	jsr x8
	sta r3
	stx r3+1
	ldy #1
	lda (p0),y
	jsr x8
	sta r11
	stx r11+1
	lda (p0)
	ldy #2
	clc
	adc (p0),y
	sta mi                  ; the right card
	jsr x8
	sta r4
	stx r4+1
	ldy #1
	lda (p0),y
	ldy #3
	clc
	adc (p0),y
	sta mj                  ; the bottom card row
	jsr x8
	sta r12
	stx r12+1
	ldy #6
	lda (p0),y
	and #4                  ; a shadow: 4 pixels more, a card more
	beq @ns
	inc mi
	inc mj
	lda r4
	clc
	adc #4
	sta r4
	bcc @1
	inc r4+1
@1:	lda r12
	clc
	adc #4
	sta r12
	bcc @ns
	inc r12+1
@ns:	lda r4                  ; (the last pixel)
	bne @2
	dec r4+1
@2:	dec r4
	lda r12
	bne @3
	dec r12+1
@3:	dec r12
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	jsr WRectangle
	lda (p0)                ; theme_rect(x, w', y, h', desk)
	jsr pusha
	lda mi
	sec
	sbc (p0)
	cmp #81
	bcc @4
	lda #80
@4:	jsr pusha
	ldy #1
	lda (p0),y
	jsr pusha
	lda mj
	ldy #1
	sec
	sbc (p0),y
	jsr pusha
	lda _theme+1
	jsr _theme_rect
	lda mk
	clc
	adc #OT_WOPEN
	sta t0
	stz t1
	O1CALL o1_set
	lda mk
	inc a
	cmp curw
	bne @r
	stz curw
	jmp origin0
@r:	clc
	rts

; SCREEN FULL [title$]
s_screen:
	lda vsp
	pha
	lda #<TX_FULL
	jsr tword
	bcs @1
	jmp syn
@1:	lda t0
	sta lgsub
	stz sbufb
	jsr tend
	bcs @2
	jsr xs
@2:	pla
	jsr xa_done
	jsr ui_on
	lda #1
	sta _vx_used
	stz curw
	jsr origin0
	G7 g_screen
	clc
	rts
; carry set at the statement's end
tend:	ldy #0
	jsr tpk
	cmp #0
	beq @y
	cmp #':'
	beq @y
	cmp #$27
	beq @y
	cmp #TK_ELSE
	beq @y
	clc
	rts
@y:	sec
	rts

; HIT(#w, x, y): where the point is in window w
f_hit:	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xh
	jsr xcn
	jsr xcn
	lda #')'
	jsr texp
	pla
	jsr xa_func
	jsr wptr
	sta t0
	jsr wisopen1
	ldx #0
	bcc @r
	lda xi+2
	clc
	adc _vx_ox
	sta n0
	lda xi+3
	adc _vx_ox+1
	sta n0+1
	lda xi+4
	clc
	adc _vx_oy
	sta n1
	lda xi+5
	adc _vx_oy+1
	sta n1+1
	G7 o1_whit
@r:	txa
	ldx #0
	jmp fr_int
; carry set if window t0 is open (t0 kept)
wisopen1:
	lda t0
	pha
	clc
	adc #OT_WOPEN
	sta t0
	O1CALL o1_get
	pla
	sta t0
	cpx #1
	rts

; BODYTOP(#w), BODYBOTTOM(#w): in the current coordinates
f_bodytop:
	jsr fwin
	jsr body_top
	bra fbody
f_bodybottom:
	jsr fwin
	jsr body_bot
fbody:	sec
	sbc _vx_oy
	pha
	txa
	sbc _vx_oy+1
	tax
	pla
	jmp fr_int
fwin:	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xh
	lda #')'
	jsr texp
	pla
	jsr xa_func
	jmp wptr

; menus: parsed here, run in overlay 7 (vbgfx.s)
;---------------------------------------------------------------
s_menu:	lda vsp
	pha
	lda #<TX_SHOW
	jsr tword
	bcs @show
	lda #<TX_ENABLE
	jsr tword
	bcs @en
	stz t0
	jsr xs
	pla
	jsr xa_done
	G7 g_menu
	clc
	rts
@show:	lda t0
	sta lgsub
	pla
	jsr xa_done
	G7 g_show
	clc
	rts
@en:	lda t0
	sta lgsub
	jsr xs
	jsr xcs
	jsr xcn
	pla
	jsr xa_done
	G7 g_enable
	clc
	rts
s_endmenu:
	G7 g_endmenu
	clc
	rts
; ITEM text$ [, procedure [, key$]]
s_item:	lda vsp
	pha
	jsr xs
	lda #','
	jsr tacc
	bcc @d
	jsr xap
	lda #','
	jsr tacc
	bcc @d
	jsr xs
@d:	pla
	jsr xa_done
	G7 g_item
	clc
	rts
; CHECK item$, on
s_check:
	lda vsp
	pha
	jsr xs
	jsr xcn
	pla
	jsr xa_done
	G7 g_check
	clc
	rts

;---------------------------------------------------------------
; the mouse and the keys
;---------------------------------------------------------------
; carry set if the event running is of kind a (inside its handler)
evis:	cmp _vx_ev
	bne @n
	jsr inhand
	rts
@n:	clc
	rts

f_mousex:
	lda #EV_CLICK
	jsr evis
	bcc @l
	lda _vx_ev+3
	ldx _vx_ev+4
	bra @o
@l:	lda mouseXPos
	ldx mouseXPos+1
@o:	sec
	sbc _vx_ox
	pha
	txa
	sbc _vx_ox+1
	tax
	pla
	jmp fr_int
f_mousey:
	lda #EV_CLICK
	jsr evis
	bcc @l
	lda _vx_ev+5
	ldx _vx_ev+6
	bra @o
@l:	lda mouseYPosW
	ldx mouseYPosW+1
@o:	sec
	sbc _vx_oy
	pha
	txa
	sbc _vx_oy+1
	tax
	pla
	jmp fr_int
f_mouseb:
	lda #EV_CLICK
	jsr evis
	bcc @l
	lda _vx_ev+1
	bra @o
@l:	lda mouseButtons
	and #7
@o:	ldx #0
	jmp fr_int
f_wheel:
	lda #EV_WHEEL
	jsr evis
	bcc @l
	lda _vx_ev+1
	bra @o
@l:	jsr GetMouse
	txa
@o:	ldx #0
	cmp #$80
	bcc @p
	dex
@p:	jmp fr_int

; MOUSEIN(x1, y1, x2, y2)
f_mousein:
	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xan
	jsr xcn
	jsr xcn
	jsr xcn
	lda #')'
	jsr texp
	pla
	jsr xa_func
	jsr rect_regs
	jsr WIsMseInRegion
	ldx #0
	cmp #0
	beq @r
	lda #1
@r:	jmp fr_int
; r3, r11, r4, r12 = xi[0..3] + the origin
rect_regs:
	ldx #0
	ldy #0
@l:	lda xi,y
	clc
	adc _vx_ox
	sta r3,x
	lda xi+1,y
	adc _vx_ox+1
	sta r3+1,x
	lda xi+2,y
	clc
	adc _vx_oy
	sta r11,x
	lda xi+3,y
	adc _vx_oy+1
	sta r11+1,x
	cpx #0
	bne @r
	ldx #r4 - r3
	ldy #4
	bra @l
@r:	rts

; MOUSE LIMIT x1, y1, x2, y2
s_mouse:
	lda #<TX_LIMIT
	jsr tword
	bcs @1
	jmp syn
@1:	lda t0
	sta lgsub
	lda vsp
	pha
	jsr xan
	jsr xcn
	jsr xcn
	jsr xcn
	pla
	jsr xa_done
	jsr rect_regs
	jsr WSetMouseRegion
	clc
	rts

f_inkey:
	PCALL fn_inkey
	rts
f_keys:	lda #EV_KEY             ; KEY$
	jsr evis
	stz t0
	bcc @r
	lda _vx_ev+1
	cmp #32
	bcc @r
	cmp #$7F
	bcc @k
	cmp #$A0
	bcc @r
@k:	sta sbufa
	inc t0
@r:	jmp fr_str
f_keycode:
	lda #EV_KEY
	jsr evis
	lda #0
	bcc @r
	lda _vx_ev+1
@r:	ldx #0
	jmp fr_int
f_keymods:
	lda #EV_KEY
	jsr evis
	lda #0
	bcc @r
	lda _vx_ev+2
	and #$0F
@r:	ldx #0
	jmp fr_int

;---------------------------------------------------------------
; the time, the switcher
;---------------------------------------------------------------
f_time:	lda hour
	ldx #0
	jsr dd
	lda #':'
	sta sbufa,x
	inx
	lda minutes
	jsr dd
	lda #':'
	sta sbufa,x
	inx
	lda seconds
	jsr dd
	stx t0
	jmp fr_str
f_date:	lda #'2'
	sta sbufa
	lda #'0'
	sta sbufa+1
	ldx #2
	lda year
	jsr dd
	lda #'-'
	sta sbufa,x
	inx
	lda month
	jsr dd
	lda #'-'
	sta sbufa,x
	inx
	lda day
	jsr dd
	stx t0
	jmp fr_str
; two digits of a (0-99) at sbufa + x
dd:	ldy #'0'
@t:	cmp #10
	bcc @o
	sbc #10
	iny
	bra @t
@o:	pha
	tya
	sta sbufa,x
	inx
	pla
	ora #'0'
	sta sbufa,x
	inx
	rts

s_aside:
	PCALL need_end
	lda #TASK_ASIDE
	ldx #0
	jsr TaskCtl
	jmp yield               ; (put aside at the main loop's next pass)
f_tasks:
	LoadW r0, sbufb
	lda #TASK_INFO
	ldx #$FF
	jsr TaskCtl
	lda sbufb + TS_COUNT
	ldx #0
	jmp fr_int
f_tasks_s:
	lda vsp
	pha
	lda #'('
	jsr texp
	jsr xan
	lda #')'
	jsr texp
	pla
	jsr xa_func
	stz t0
	lda xi+1
	bne @no
	lda xi
	beq @no
	sta mi
	ldx #0
@l:	cpx #TASK_MAX
	bcs @no
	phx
	LoadW r0, sbufb
	lda #TASK_INFO
	jsr TaskCtl
	plx
	lda sbufb + TR_STATE
	cmp #TASK_ASIDE
	bne @n
	dec mi
	beq @f
@n:	inx
	bra @l
@f:	ldx #0
@c:	lda sbufb + TR_NAME,x
	sta sbufa,x
	beq @e
	inx
	cpx #16
	bcc @c
@e:	stx t0
@no:	jmp fr_str

;---------------------------------------------------------------
; words that are values in an expression
;---------------------------------------------------------------
v_paper: lda #0
	bra vv
v_ink:	lda #1
	bra vv
v_title: lda #5
vv:	ldx #0
	jmp fr_val

;---------------------------------------------------------------
; the statements and functions run in overlay 7, their arguments
;---------------------------------------------------------------
s_cls:	jsr xspec
	.byte 0
	.addr g_cls
s_pattern:
	jsr xspec
	.byte "n", 0
	.addr g_pattern
s_box:	jsr xspec
	.byte "n,n,n,n", 0
	.addr g_box
s_frame:
	jsr xspec
	.byte "n,n,n,n", 0
	.addr g_frame
s_invert:
	jsr xspec
	.byte "n,n,n,n", 0
	.addr g_invert
s_line:	jsr xspec
	.byte "n,n,n,n[n", 0
	.addr g_line
s_plot:	jsr xspec
	.byte "n,n[n", 0
	.addr g_plot
s_scroll:
	jsr xspec
	.byte "n,n,n,n,n", 0
	.addr g_scroll
s_pointer:
	jsr xspec
	.byte "n", 0
	.addr g_pointer
s_text:	jsr xspec
	.byte "n,n,s", 0
	.addr g_text
s_style:
	jsr xspec
	.byte "n", 0
	.addr g_style
s_cards:
	jsr xspec
	.byte "n,n,s[n", 0
	.addr g_cards
s_paper:
	jsr xspec
	.byte "n,n,n,n,n", 0
	.addr g_paper
s_ink:	jsr xspec
	.byte "n", 0
	.addr g_ink
s_palette:
	jsr xspec
	.byte "n,n", 0
	.addr g_palette
s_beep:	jsr xspec
	.byte 0
	.addr g_beep
s_voice:
	jsr xspec
	.byte "n,n,n[n[n", 0
	.addr g_voice
s_play:	jsr xspec
	.byte "n,s", 0
	.addr g_play
; COPY x, y, w, h TO x2, y2
s_copy:	lda vsp
	pha
	jsr xan
	jsr xcn
	jsr xcn
	jsr xcn
	lda #TK_TO
	jsr texp
	jsr xan
	jsr xcn
	pla
	jsr xa_done
	G7 g_copy
	clc
	rts
; FONT name$, size | FONT n (UI, SYSTEM)
s_font:	lda vsp
	pha
	PCALL eval
	lda aty
	cmp #TY_S
	beq @s
	jsr vpush
	pla
	jsr xa_done
	G7 g_fontn
	clc
	rts
@s:	jsr vpush
	jsr xcn
	pla
	jsr xa_done
	G7 g_font
	clc
	rts
; SOUND id | SOUND OFF
s_sound:
	lda vsp
	pha
	lda #<TX_OFF
	jsr tword
	bcs @off
	jsr xan
	pla
	jsr xa_done
	G7 g_sound
	clc
	rts
@off:	lda #<TX_OFF
	jsr xw
	pla
	jsr xa_done
	G7 g_soundoff
	clc
	rts
f_point:
	jsr xfspec
	.byte "(n,n)", 0
	.addr gf_point
f_textwidth:
	jsr xfspec
	.byte "(s)", 0
	.addr gf_textwidth
f_fontheight:
	jsr xfspec
	.byte 0
	.addr gf_fontheight
f_cardcolor:
	jsr xfspec
	.byte "(n,n)", 0
	.addr gf_cardcolor

;---------------------------------------------------------------
; a program starts (main.c): everything back as at the start
;---------------------------------------------------------------
xreset:	O1CALL o1_init
	G8 d_reset
	G9 f9_closeall
	stz _vx_any
	stz _vx_hide
	stz _vx_used
	stz _vx_hact
	stz _vx_dpc
	stz _vx_dpc+1
	stz _vx_idle
	stz _vx_evn
	stz waitf
	stz curw
	jsr origin0
	G7 g_reset
	rts

.include "vbui4.s"

;---------------------------------------------------------------
; the tables: second-page tokens $80 .. $80 + XS_N - 1
;---------------------------------------------------------------
XS_N = $76                      ; (to $F5: XP_GET)
.macro XT base, nn, addr
	.res (nn - $80) * 2 - (* - base), 0
	.addr addr
.endmacro
xstab:
	XT xstab, $84, s_timer
	XT xstab, $85, s_app
	XT xstab, $86, s_name
	XT xstab, $8E, s_window
	XT xstab, $96, s_close
	XT xstab, $9A, s_screen
	XT xstab, $9C, s_menu
	XT xstab, $9D, s_item
	XT xstab, $9E, s_check
	XT xstab, $9F, s_endmenu
	XT xstab, $A2, s_msgbox
	XT xstab, $A7, s_dialog
	XT xstab, $A8, s_enddialog
	XT xstab, $AB, s_label
	XT xstab, $AC, s_field
	XT xstab, $AD, s_button
	XT xstab, $B0, s_icon
	XT xstab, $B1, s_icons
	XT xstab, $B4, s_tile
	XT xstab, $B5, s_bitmap
	XT xstab, $B8, s_cls
	XT xstab, $B9, s_pattern
	XT xstab, $BA, s_box
	XT xstab, $BB, s_frame
	XT xstab, $BC, s_invert
	XT xstab, $BD, s_line
	XT xstab, $BE, s_plot
	XT xstab, $C0, s_copy
	XT xstab, $C1, s_scroll
	XT xstab, $C2, s_pointer
	XT xstab, $C3, s_text
	XT xstab, $C4, s_font
	XT xstab, $C5, s_style
	XT xstab, $C8, s_cards
	XT xstab, $C9, s_paper
	XT xstab, $CB, s_ink
	XT xstab, $CC, s_palette
	XT xstab, $D1, s_mouse
	XT xstab, $D7, s_sound
	XT xstab, $D8, s_beep
	XT xstab, $D9, s_voice
	XT xstab, $DA, s_play
	XT xstab, $DB, s_open
	XT xstab, $DC, s_put
	XT xstab, $DD, s_seek
	XT xstab, $E1, s_kill
	XT xstab, $E3, s_mkdir
	XT xstab, $E4, s_rmdir
	XT xstab, $E5, s_chdir
	XT xstab, $EB, s_clipboard
	XT xstab, $EE, s_sprite
	XT xstab, $F0, s_aside
	XT xstab, XP_PRINT, s_printh
	XT xstab, XP_INPUT, s_inputh
	XT xstab, XP_GET, s_geth
	.res XS_N * 2 - (* - xstab), 0
xftab:
	XT xftab, $82, f_wheel
	XT xftab, $8F, v_title
	XT xftab, $97, f_hit
	XT xftab, $98, f_bodytop
	XT xftab, $99, f_bodybottom
	XT xftab, $A3, f_ask
	XT xftab, $A4, f_inputbox
	XT xftab, $A5, f_fileopen
	XT xftab, $A6, f_filesave
	XT xftab, $AA, f_dresult
	XT xftab, $B6, f_picture
	XT xftab, $BF, f_point
	XT xftab, $C6, f_textwidth
	XT xftab, $C7, f_fontheight
	XT xftab, $C9, v_paper
	XT xftab, $CA, f_cardcolor
	XT xftab, $CB, v_ink
	XT xftab, $CD, f_mousex
	XT xftab, $CE, f_mousey
	XT xftab, $CF, f_mouseb
	XT xftab, $D0, f_mousein
	XT xftab, $D3, f_inkey
	XT xftab, $D4, f_keys
	XT xftab, $D5, f_keycode
	XT xftab, $D6, f_keymods
	XT xftab, $DE, f_lof
	XT xftab, $DF, f_loc
	XT xftab, $E0, f_eof
	XT xftab, $E6, f_curdir
	XT xftab, $E7, f_dir
	XT xftab, $E8, f_folder
	XT xftab, $E9, f_document
	XT xftab, $EA, f_clipget
	XT xftab, $EC, f_time
	XT xftab, $ED, f_date
	XT xftab, $F1, f_tasks
	XT xftab, $F2, f_tasks_s
	.res XS_N * 2 - (* - xftab), 0
