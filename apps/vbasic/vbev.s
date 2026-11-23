; VeraBASIC Run: the kernel's side of the event model (phase 3, DECISIONS
; V89), in overlay 1: appBank, the bank mapped whenever the kernel calls the
; program. Kernel callbacks only queue an event (16 of them) and return;
; BASIC never runs inside one. The handlers' procedures, the menus' items,
; the timers and the windows' close glyphs are looked up here, from the
; table o1tab that overlay 6 fills through o1_set. The window chrome's
; calls (vrwin.c, also in this overlay) are wrapped here for overlay 6.
;
; MIT licence (LICENSE).


; the events' kinds (the gate's logs name them: vbui.s EvNames)
EV_MENU  = 1                    ; a: the item (flat number)
EV_CLICK = 2                    ; a: the buttons (bit 7: a release); x, y
EV_KEY   = 3                    ; a: the key, b: the modifiers
EV_WHEEL = 4                    ; a: the movement (signed)
EV_CLOSE = 5                    ; a: the window (1-4)
EV_TIMER = 6                    ; a: the timer (1-8)
EV_QUIT  = 7
EV_ICON  = 8                    ; a: the icon (1-8) (phase 4, DECISIONS V90)

; o1tab: procedure + 1 (0: none) of each event, then the items' keys and flags
OT_CLICK = 0
OT_KEY   = 1
OT_WHEEL = 2
OT_QUIT  = 3
OT_CLOSE = 4                    ; 4 windows
OT_TIMER = 8                    ; 8 timers
OT_ITEM  = 16                   ; MAXITEM items
MAXITEM  = 40
OT_IKEY  = OT_ITEM + MAXITEM    ; an item's shortcut (an upper-case letter, 0 none)
OT_IFLAG = OT_IKEY + MAXITEM    ; bit 0: the item is disabled
OT_MFIRST = OT_IFLAG + MAXITEM  ; each menu's first item
MAXMENU  = 8
OT_NITEM = OT_MFIRST + MAXMENU
OT_WOPEN = OT_NITEM + 1         ; 4: the window is open
OT_TFR   = OT_WOPEN + 4         ; 8 words: the timers' frames
OT_TON   = OT_TFR + 16          ; 8: 0 none, 1 running, 2 paused
OT_ICON  = OT_TON + 8           ; 8 icons: the procedure + 1
OT_SIZE  = OT_ICON + 8

QN = 16                         ; the queue: 16 events of 8 bytes

.segment "OVL1BSS"
o1tab:	.res OT_SIZE
evq:	.res QN * 8
evqh:	.res 1
evqt:	.res 1
evrec:	.res 8                  ; the event being queued
tpend:	.res 8                  ; a timer's event is queued
swallow: .res 1                 ; the release of a press on a close glyph
pressed: .res 1                 ; a press was queued: its release will be

.segment "OVERLAY1"
; the process table is installed (loaded 0 with the overlay: the first
; start's procs_off reads it before anything wrote it; V106)
procs_on: .byte 0

; everything cleared (a program starts)
o1_init:
	ldx #OT_SIZE - 1
@1:	stz o1tab,x
	dex
	bpl @1
	ldx #7
@2:	stz tpend,x
	dex
	bpl @2
	stz evqh
	stz evqt
	stz swallow
	stz pressed
; the process table taken away (no timers, no wheel's poll): at a start and
; at a program's end (_vx_end, DECISIONS V95). The kernel calls a process's
; routine in appBank, which is the editor's view bank once VeraBASIC's
; editor is back: a TIMER left running ran into its bytes there
procs_off:
	lda procs_on
	beq @r
	stz procs_on
	LoadW r0, sbufb
	lda #0
	jsr InitProcesses       ; no processes
@r:	rts

; the debugger's break (vbdbg.s, DECISIONS V97): a = procs_on, the
; process table taken away (o1_procs puts it back on Continue)
.ifdef VB_IDE
o1_brk:	lda procs_on
	pha
	jsr procs_off
	pla
	rts
.endif

; o1tab[t0] = t1; o1_get: x = o1tab[t0]
o1_set:	ldx t0
	lda t1
	sta o1tab,x
	rts
o1_get:	ldx t0
	lda o1tab,x
	tax
	rts

; c set if an event is queued
o1_any:	lda evqh
	cmp evqt
	beq @n
	sec
	rts
@n:	clc
	rts

; the next event into _vx_ev (its procedure + 1 at _vx_ev + 8); c clear if none
o1_take:
	ldx evqh
	cpx evqt
	bne @1
	clc
	rts
@1:	txa
	asl a
	asl a
	asl a
	tax
	ldy #0
@c:	lda evq,x
	sta _vx_ev,y
	inx
	iny
	cpy #8
	bne @c
	lda evqh
	inc a
	and #QN - 1
	sta evqh
	; its handler
	lda _vx_ev
	ldx #OT_CLICK
	cmp #EV_CLICK
	beq @p
	ldx #OT_KEY
	cmp #EV_KEY
	beq @p
	ldx #OT_WHEEL
	cmp #EV_WHEEL
	beq @p
	ldx #OT_QUIT
	cmp #EV_QUIT
	beq @p
	cmp #EV_MENU
	bne @2
	lda _vx_ev+1
	clc
	adc #OT_ITEM
	tax
	bra @p
@2:	cmp #EV_TIMER
	bne @3
	ldx _vx_ev+1
	stz tpend-1,x
	txa
	clc
	adc #OT_TIMER - 1
	tax
	bra @p
@3:	cmp #EV_ICON
	bne @4
	lda _vx_ev+1
	clc
	adc #OT_ICON - 1
	tax
	bra @p
@4:	lda _vx_ev+1           ; EV_CLOSE
	clc
	adc #OT_CLOSE - 1
	tax
@p:	lda o1tab,x
	sta _vx_ev+8
	sec
	rts

; evrec into the queue (dropped when it is full)
ev_put:	lda evqt
	inc a
	and #QN - 1
	cmp evqh
	beq @full
	pha
	lda evqt
	asl a
	asl a
	asl a
	tax
	ldy #0
@c:	lda evrec,y
	sta evq,x
	inx
	iny
	cpy #8
	bne @c
	pla
	sta evqt
@full:	rts

; evrec: kind a, the pointer's place, the modifiers
ev_new:	sta evrec
	stz evrec+1
	stz evrec+2
	lda mouseXPos
	sta evrec+3
	lda mouseXPos+1
	sta evrec+4
	lda mouseYPosW
	sta evrec+5
	lda mouseYPosW+1
	sta evrec+6
	lda keyDataMods
	and #$0F
	sta evrec+7
	rts

; main.c's Quit while the program runs: 1 if ON QUIT has a handler (queued)
_vx_quit:
	lda o1tab+OT_QUIT
	beq @n
	lda #EV_QUIT
	jsr ev_new
	jsr ev_put
	lda #1
	ldx #0
	rts
@n:	lda #0
	tax
	rts
.export _vx_quit, _ev_keyv, _ev_press
_ev_keyv = ev_keyv
_ev_press = ev_press

;---------------------------------------------------------------
; otherPressVec: a press or release not on a menu or an icon
;---------------------------------------------------------------
ev_press:
	jsr ev_icon             ; (phase 4: an icon's press and release)
	bcc @ni
	rts
@ni:	lda mouseData
	bmi @rel
	; a press on a window's close glyph, if ON CLOSE has a handler
	ldx #3
@w:	lda o1tab+OT_WOPEN,x
	beq @nw
	lda o1tab+OT_CLOSE,x
	beq @nw
	phx
	stx t0                  ; x = vr_win_hit(window x, the pointer): overlay 7
	lda #<o1_hitx
	ldx #>o1_hitx
	ldy _vx_ovl7
	jsr bcall
	txa
	plx
	cmp #2                  ; VW_XCLOSE
	bne @nw
	lda #EV_CLOSE
	phx
	jsr ev_new
	pla
	inc a
	sta evrec+1
	lda #1
	sta swallow
	jmp ev_put
@nw:	dex
	bpl @w
	lda mouseButtons
	ldx o1tab+OT_CLICK
	beq @r
	stx pressed
	bra @click
@rel:	stz swallow
	lda pressed             ; (a menu's press: its release is not the program's)
	beq @r
	stz pressed
	lda mouseButtons
	ora #$80
@click:
	pha
	lda #EV_CLICK
	jsr ev_new
	pla
	sta evrec+1
	jmp ev_put
@r:	rts

;---------------------------------------------------------------
; icons (phase 4): overlay 8 (vbdlg.s i8_icon) knows their places; a
; press on one inverts it, its release there queues an ICON event (the
; inverse back first); c set when an icon took it
;---------------------------------------------------------------
ev_icon:
	lda #<i8_icon
	ldx #>i8_icon
	ldy _vx_ovl8
	jsr bcall
	bcc @r
	txa
	beq @y
	pha
	lda #EV_ICON
	jsr ev_new
	pla
	sta evrec+1
	jsr ev_put
@y:	sec
@r:	rts
; icon t0 (0-7)'s procedure + 1: t2 (0: taken away)
o1_icon:
	ldx t0
	lda t2
	sta o1tab+OT_ICON,x
	beq @r
	lda #1
	sta _vx_any
@r:	rts

; the dialog boxes' routine, keys and presses (vbdlg.s): the kernel calls
; them with appBank mapped
dlg_rout:
	lda #<d_rout
	ldx #>d_rout
	bra dlg8
dlg_key:
	lda #<d_key
	ldx #>d_key
	bra dlg8
dlg_press:
	lda #<d_press
	ldx #>d_press
dlg8:	ldy _vx_ovl8
	jmp bcall

; main.c: a program ended (its processes gone, its files closed, its
; sprites off) or starts
_vx_end:
	jsr procs_off           ; its timers and the wheel's poll gone
	lda #<f9_closeall
	ldx #>f9_closeall
	ldy _vx_ovl9
	jsr bcall
	lda #<d_end
	ldx #>d_end
	ldy _vx_ovl8
	jmp bcall
.export _vx_end

;---------------------------------------------------------------
; keyVector: a menu's shortcut (Ctrl and its letter), ON KEY, else the
; console's queue (and Ctrl+C or STOP: vb.s _vb_key)
;---------------------------------------------------------------
ev_keyv:
	lda keyData
	cmp #KEY_STOP
	beq @vb
	lda keyDataMods
	and #2
	beq @nk
	lda keyData
	beq @nk
	cmp #27
	bcs @nk
	ora #$40                ; Ctrl + the letter
	ldx o1tab+OT_NITEM
@s:	dex
	bmi @nc
	cmp o1tab+OT_IKEY,x
	bne @s
	lda o1tab+OT_IFLAG,x
	and #1
	bne @r                  ; disabled
	phx
	lda #EV_MENU
	jsr ev_new
	pla
	sta evrec+1
	jmp ev_put
@nc:	lda keyData
	cmp #3
	beq @vb                 ; Ctrl+C: Stop
@nk:	lda o1tab+OT_KEY
	beq @vb
	lda #EV_KEY
	jsr ev_new
	lda keyData
	sta evrec+1
	lda keyDataMods
	sta evrec+2
	jmp ev_put
@vb:	jmp _vb_key
@r:	rts

;---------------------------------------------------------------
; the menus' items: menu k's routine, a = the item in it
;---------------------------------------------------------------
.macro MSTUB k
	ldx #k
	bra mpick
.endmacro
mstubs:
mstub0:	MSTUB 0
mstub1:	MSTUB 1
mstub2:	MSTUB 2
mstub3:	MSTUB 3
mstub4:	MSTUB 4
mstub5:	MSTUB 5
mstub6:	MSTUB 6
mstub7:	MSTUB 7
mpick:	clc
	adc o1tab+OT_MFIRST,x
	pha
	jsr GotoFirstMenu
	lda #<g_bart            ; (SCREEN FULL's title: the bar was drawn again)
	ldx #>g_bart
	ldy _vx_ovl7
	jsr bcall
	plx
	lda o1tab+OT_IFLAG,x
	and #1
	bne @r
	phx
	lda #EV_MENU
	jsr ev_new
	pla
	sta evrec+1
	jmp ev_put
@r:	rts

;---------------------------------------------------------------
; the processes: timers 1-8 (processes 0-7) and the wheel's poll (8)
;---------------------------------------------------------------
.macro PSTUB k
	ldx #k
	bra ptick
.endmacro
pstub0:	PSTUB 0
pstub1:	PSTUB 1
pstub2:	PSTUB 2
pstub3:	PSTUB 3
pstub4:	PSTUB 4
pstub5:	PSTUB 5
pstub6:	PSTUB 6
pstub7:	PSTUB 7
ptick:	lda tpend,x             ; one event of a timer queued at a time
	bne @r
	lda o1tab+OT_TIMER,x
	beq @r
	inc tpend,x
	phx
	lda #EV_TIMER
	jsr ev_new
	pla
	inc a
	sta evrec+1
	jmp ev_put
@r:	rts
pwheel:	jsr GetMouse
	txa
	beq @r
	ldy o1tab+OT_WHEEL
	beq @r
	pha
	lda #EV_WHEEL
	jsr ev_new
	pla
	sta evrec+1
	jmp ev_put
@r:	rts

PT_N = 9
ptabr:	.word pstub0, pstub1, pstub2, pstub3, pstub4, pstub5, pstub6, pstub7, pwheel

; the process table installed again from o1tab (InitProcesses freezes them
; all: the running timers restarted, the wheel's poll if ON WHEEL has one)
o1_procs:
	ldx #0
	ldy #0
@t:	lda ptabr,x
	sta sbufb,y
	lda ptabr+1,x
	sta sbufb+1,y
	cpx #16
	bcs @wh
	lda o1tab+OT_TFR,x
	sta sbufb+2,y
	lda o1tab+OT_TFR+1,x
	sta sbufb+3,y
	bra @n
@wh:	lda #2                  ; the wheel: every 2 frames
	sta sbufb+2,y
	lda #0
	sta sbufb+3,y
@n:	iny
	iny
	iny
	iny
	inx
	inx
	cpx #PT_N * 2
	bne @t
	LoadW r0, sbufb
	lda #PT_N
	jsr InitProcesses
	lda #1
	sta procs_on
	ldx #7
@r:	lda o1tab+OT_TON,x
	cmp #1
	bne @nr
	phx
	jsr RestartProcess
	plx
@nr:	dex
	bpl @r
	lda o1tab+OT_WHEEL
	beq @nw
	ldx #8
	jsr RestartProcess
@nw:	rts

; timer t1 (0-7): t0 = 0 ON (where it was), 1 OFF, 2 STOP
o1_tctl:
	lda procs_on
	beq @r
	ldx t1
	lda t0
	beq @on
	cmp #1
	beq @off
	stz o1tab+OT_TON,x      ; STOP
	stz o1tab+OT_TIMER,x
	stz tpend,x
	jmp FreezeProcess
@off:	lda o1tab+OT_TON,x
	beq @r
	lda #2
	sta o1tab+OT_TON,x
	jmp FreezeProcess
@on:	lda o1tab+OT_TON,x
	beq @r
	lda #1
	sta o1tab+OT_TON,x
	jmp UnfreezeProcess
@r:	rts

