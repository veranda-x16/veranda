; VeraBASIC Run: the resident part of the Veranda extensions (phase 3,
; DECISIONS V89). Everything else is banked: overlay 1 (vbev.s) the kernel's
; side of the events (the queue, the vectors, the menus' and processes'
; routines, the window chrome's calls), overlay 6 (vbui.s) the statements
; of events, windows, menus, mouse, keys and time, overlay 7 (vbgfx.s)
; graphics, text, colour and sound.
;
; The rule of the banked parts: overlay code never maps the program's bank
; itself (its own code would go); it reads tokens through fpeek and calls
; the evaluator and the rest through bcall with the program's bank, and it
; ends a statement that moved ip with "jmp mapp_jumped".
;
; MIT licence (LICENSE).

.segment "BSS"
_vx_ovl6: .res 1                ; overlay 6's bank, 7's
_vx_ovl7: .res 1
xnn:	.res 1                  ; the second-page token being run (SLEEP: 1 the first time)
_vx_any: .res 1                 ; 1: an event has a handler
_vx_hide: .res 1                ; 1: the console is hidden (the program draws its own screen)
_vx_used: .res 1                ; 1: the program's menus or windows were shown
_vx_wins: .res 4 * 7            ; the windows (struct vrwin)
_vx_ev:	.res 10                 ; the event running: kind, a, b, x (2), y (2), mods, procedure + 1
_vx_cellend: .res 2             ; the program's cells' end (main.c): main RAM above it is free
_vx_ox:	.res 2                  ; the origin (WINDOW USE): pixels
_vx_oy:	.res 2
_vx_ocx: .res 1                 ; and cards
_vx_ocy: .res 1
_vx_hbsp: .res 2                ; a handler runs while bsp is above this
_vx_hact: .res 1
_vx_dpc: .res 2                 ; event points passed (the gate's logs)
_vx_idle: .res 1                ; 1: waiting for events with none queued (the gate's scripts)
_vx_evn: .res 1                 ; handlers started, but the timers' (the gate's scripts)
_vx_clip: .res 9                ; WINDOW USE's clip: left, right, top, bottom; on
_vx_ovl8: .res 1                ; phase 4 (DECISIONS V90): overlay 8's bank (dialogs,
_vx_ovl9: .res 1                ; icons, pictures, sprites), 9's (files), the
_vx_ovla: .res 1                ; C overlays' A (records 10, 11: vbc.cfg) and B
_vx_ovlb: .res 1
_vx_dlg: .res 1                 ; the number of the dialog box up (0: none; the gate's scripts)

.segment "CODE"
.import _theme, _theme_rect, _theme_menus, _docname, _vb_font, pusha, _vb_fontload
.export _vx_ovl6, _vx_ovl7, _vx_any, _vx_hide, _vx_used, _vx_wins, _vx_ev, _vx_cellend
.export _vx_idle, _vx_evn, _vx_dpc, _vx_reset, _vx_irq
.export _vx_ovl8, _vx_ovl9, _vx_ovla, _vx_ovlb, _vx_dlg

; a second-page statement: ip at its $FF
ext_stmt:
	ldy #1
	lda (ip),y
	pha
	ADDIP 2
	pla
; a = the token (0: ON event, ip at the event's word)
ext_stmt_a:
	sta xnn
	lda #<xstmt
	ldx #>xstmt
	jsr x6call
	bcs mapp_jumped
	jmp endstmt
mapp_jumped:                    ; (overlay code: ip moved, its bank in pbank)
	MAPP
	jmp jumped

; a second-page function or word in an expression: ip at its $FF
ext_func:
	ldy #1
	lda (ip),y
	pha
	ADDIP 2
	pla
	sta xnn
	lda #<xfunc
	ldx #>xfunc
; overlay 6's routine a/x, the caller's bank back after
x6call:	ldy _vx_ovl6
	jmp bcall

; the main lines ended: a program with handlers waits for events
main_end:
	lda _vx_any
	bne @w
	jmp end_program
@w:	lda #<wait_stub
	sta ip
	lda #>wait_stub
	sta ip+1
	jmp next
wait_stub: .byte TK_WAIT, TK_EVENTS, 0

; a = t0: buf_to_temp for overlay code (bcall cannot pass a)
btt0:	lda t0
	jmp buf_to_temp
; parse_num with a = 1 (the whole field a number) for overlay code
pnum1:	lda #1
	jmp parse_num

; the interrupt (intTopVector, every frame): PLAY's sequencer in overlay 7
_vx_irq:
	lda ram_bank
	pha
	lda _vx_ovl7
	sta ram_bank
	jsr snd_tick
	pla
	sta ram_bank
.ifdef VB_TEST
	jmp _vb_wd
.else
	rts
.endif

; main.c: a program starts: the extensions' state reset (overlay 6)
_vx_reset:
	lda #<xreset
	ldx #>xreset
	jmp x6call

; main.c (overlay 1) calls the window chrome in overlay 7: the first
; argument is on the C stack already, the last one in a/x
vrw_a:	.res 2
_vrw_win:
	ldy #<f7_win
	bra vrw
_vrw_title:
	ldy #<f7_title
	bra vrw
_vrw_status:
	ldy #<f7_status
vrw:	sta vrw_a
	stx vrw_a+1
	tya
	ldx #>f7_win
	ldy _vx_ovl7
	jmp bcall
.assert >f7_win = >f7_status, error, "vbx.s: f7_win .. f7_status in one page"
.export _vrw_win, _vrw_title, _vrw_status
