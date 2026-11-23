; Veranda bank X: input and processes
;
; IrqWork (from the interrupt entry, after the ROM's handler): the mouse,
; the pointer sprite, the process timers, the double click counter,
; random, a tick for the clock once a second. The keyboard queue (filled
; by the main loop's GETIN), GetNextChar, the processes.
;
; The mouse: the X16 mouse's position is used *relatively* (the pointer
; moves by its change), the device position put back in the middle near
; the edges of its range (1016 x 504, see MSE_W): Veranda moves the
; pointer itself too (menus, dialogs, StartMouseMode), and an absolute
; position would undo that (the old project's D34 and D68, found on a real
; X16). mouseSource replaces the device (tests, other devices).

.include "kernel.inc"

.export k_IrqWork, MouseInit, MouseModeA, k_MouseUp, k_MouseOff, k_ClearMouseMode
.export k_TempHideMouse, k_HideOnlyMouse, k_IsMseInRegion, k_WIsMseInRegion
.export k_WStartMouseMode, k_WSetMouseRegion, k_GetMouse, k_GetKeyMods
.export KeyPut, KeyGet, k_GetNextChar, k_InitProcesses, k_RestartProcess, k_EnableProcess
.export k_BlockProcess, k_UnblockProcess, k_FreezeProcess, k_UnfreezeProcess, ProcNext
.export MouseRegionAll, ProcSave, ProcRestore, ProcOut, ProcIn
.import kClockTick, kMenuRect, PromptBlink, kBankBase, k_BankCopy, kPrefs

; the device's range: mouse_config multiplies x and y by 8 keeping only 10
; bits of x and 9 of y (x 255 gives 1015, y 255 gives 503: found on a real
; X16), and scales below x 41 and y 31; so x 127 and y 63: 0-1015, 0-503,
; and the device in the middle (507, 251) after it
MSE_W    = 127
MSE_H    = 63
MSE_EDGE = 128                  ; nearer an edge: back to the middle
PROCS     = 20
KQ        = 16                  ; key queue
P_FROZEN  = $80
P_BLOCKED = $40

.segment "BSS"

mseLastX:	.res 2
mseLastY:	.res 2
mseHide:	.res 1          ; $80: hidden until it moves (TempHideMouse)
frames:		.res 1
procN:		.res 1
procFlags:	.res PROCS
procPend:	.res PROCS
procRL:		.res PROCS      ; routine
procRH:		.res PROCS
procTL:		.res PROCS      ; timer reload
procTH:		.res PROCS
procCL:		.res PROCS      ; count
procCH:		.res PROCS
procEnd:
procBuf:	.res 1 + 8 * PROCS ; ProcSave's copy
kq:		.res KQ
kqm:		.res KQ         ; the modifiers latched with each key (keyDataMods)
kqMods:		.res 1
kqHead:		.res 1
kqTail:		.res 1
dx:		.res 2
dy:		.res 2
mseSrc:		.res 2          ; the source mseLast came from (0: the device)
mseAbs:		.res 1          ; bit 7: this frame's position is absolute

.segment "CODE"

;---------------------------------------------------------------
; the interrupt's work
;---------------------------------------------------------------
k_IrqWork:
	; random: a 16-bit LFSR step
	lda random+1
	lsr
	ror random
	bcc @r1
	eor #$B4
@r1:	sta random+1
	ora random
	bne @r2
	inc random              ; (never 0)
@r2:	lda dblClickCount
	beq @d1
	dec dblClickCount
@d1:	inc frames
	lda frames
	cmp #60
	bcc @c1
	stz frames
	LoadB kClockTick, $80
@c1:	jsr Mouse
	jsr Pointer
	jsr PromptBlink
	; process timers
	ldx procN
@p:	dex
	bmi @r
	lda procFlags,x
	bmi @p                  ; frozen
	lda procCL,x
	bne @p1
	lda procCH,x
	beq @p2                 ; (no timer)
	dec procCH,x
@p1:	dec procCL,x
	lda procCL,x
	ora procCH,x
	bne @p
@p2:	lda procTL,x            ; time: run it, start again
	sta procCL,x
	lda procTH,x
	sta procCH,x
	lda procTL,x
	ora procTH,x
	beq @p                  ; a timer of 0: never
	lda #1
	sta procPend,x
	bra @p
@r:	rts

;---------------------------------------------------------------
; the mouse
;---------------------------------------------------------------
MouseInit:
	php                     ; (the interrupt runs already: no change from
	sei                     ; the cleared state is reported)
	jsr Center
	jsr Read
	LoadB mouseData, $80    ; up
	stz mouseButtons
	stz mouseWheel
	stz faultData
	stz mseHide
	lda pressFlag
	and #<~SET_MOUSE
	sta pressFlag
	plp
MouseRegionAll:                 ; the region: the whole screen
	stz mouseLeft
	stz mouseLeft+1
	stz mouseTopW
	stz mouseTopW+1
	stz mouseTop
	lda screenWidth
	sec
	sbc #1
	sta mouseRight
	lda screenWidth+1
	sbc #0
	sta mouseRight+1
	lda screenHeight
	sec
	sbc #1
	sta mouseBottomW
	lda screenHeight+1
	sbc #0
	sta mouseBottomW+1
	beq @1
	lda #$FF
	bra @2
@1:	lda mouseBottomW
@2:	sta mouseBottom
	rts

; the device in the middle of a range larger than the screen
Center:	lda mouseSource
	ora mouseSource+1
	bne @r
	lda #$FF                ; on, the ROM's pointer picture left alone
	ldx #MSE_W
	ldy #MSE_H
	jsr k_mouse_config
@r:	rts

; kTmp = x, kTmp+2 = y, a = buttons; mseLast = the same
Read:	MoveW mouseSource, mseSrc
	jsr Source
	pha
	MoveW kTmp, mseLastX
	MoveW kTmp+2, mseLastY
	pla
	rts
Source:	lda mouseSource
	ora mouseSource+1
	beq @dev
	jsr @call               ; a routine: r0, r1, a
	pha
	MoveW r0, kTmp
	MoveW r1, kTmp+2
	pla
	rts
@call:	jmp (mouseSource)
@dev:	ldx #kTmp
	jsr k_mouse_get
	pha                     ; (a: the buttons)
	txa                     ; (ROMs with a wheel return it in x, cleared
	clc                     ; there: added up until GetMouse, held at the
	adc mouseWheel          ; ends; V68)
	bvs @w
	sta mouseWheel
@w:	pla
	clc                     ; relative
	rts

Mouse:	; a new source (a program set mouseSource): its first position is
	; where it starts, not a move
	lda mouseSource
	cmp mseSrc
	bne @new
	lda mouseSource+1
	cmp mseSrc+1
	beq @same
@new:	jsr Read
	bra @btn
@same:	jsr Source
@btn:	ror mseAbs              ; c: a source's absolute position
	sta mouseButtons
	; the left button: mouseData bit 7 = up; a change sets MOUSE
	and #1
	eor #1
	lsr
	lda #0
	ror
	cmp mouseData
	beq @m
	sta mouseData
	lda pressFlag
	ora #SET_MOUSE
	sta pressFlag
@m:	bit mseAbs
	bpl @rel
	; absolute: the change from where the pointer is
	lda kTmp
	sec
	sbc mouseXPos
	sta dx
	lda kTmp+1
	sbc mouseXPos+1
	sta dx+1
	lda kTmp+2
	sec
	sbc mouseYPosW
	sta dy
	lda kTmp+3
	sbc mouseYPosW+1
	sta dy+1
	MoveW kTmp, mseLastX
	MoveW kTmp+2, mseLastY
	bra @moved
@rel:	; the change of the device position
	lda kTmp
	sec
	sbc mseLastX
	sta dx
	lda kTmp+1
	sbc mseLastX+1
	sta dx+1
	lda kTmp+2
	sec
	sbc mseLastY
	sta dy
	lda kTmp+3
	sbc mseLastY+1
	sta dy+1
	MoveW kTmp, mseLastX
	MoveW kTmp+2, mseLastY
	lda kPrefs              ; (V56: the pointer's speed, the settings': a
	and #3                  ; move times 1, 2 or 4)
	beq @moved
	tax
@sp:	asl dx
	rol dx+1
	asl dy
	rol dy+1
	dex
	bne @sp
@moved:	lda dx
	ora dx+1
	ora dy
	ora dy+1
	beq @still
	stz mseHide             ; it moved: shown again
@still:	; x += dx, limited to the region
	lda mouseXPos
	clc
	adc dx
	sta mouseXPos
	lda mouseXPos+1
	adc dx+1
	sta mouseXPos+1
	bmi @xl                 ; < 0
	CmpW mouseXPos, mouseLeft
	bcs @x1
@xl:	MoveW mouseLeft, mouseXPos
	lda dx+1
	bpl @x2
	lda #SET_OFFLEFT
	tsb faultData
	bra @x2
@x1:	CmpW mouseRight, mouseXPos
	bcs @x2
	MoveW mouseRight, mouseXPos
	lda #SET_OFFRIGHT
	tsb faultData
@x2:	; y += dy, limited to the region
	lda mouseYPosW
	clc
	adc dy
	sta mouseYPosW
	lda mouseYPosW+1
	adc dy+1
	sta mouseYPosW+1
	bmi @yt
	CmpW mouseYPosW, mouseTopW
	bcs @y1
@yt:	MoveW mouseTopW, mouseYPosW
	lda dy+1
	bpl @y2
	lda #SET_OFFTOP
	tsb faultData
	bra @y2
@y1:	CmpW mouseBottomW, mouseYPosW
	bcs @y2
	MoveW mouseBottomW, mouseYPosW
	lda #SET_OFFBOTTOM
	tsb faultData
@y2:	jsr YByte
	; menus on: outside the current level's rectangle is a fault too
	lda mouseOn
	and #SET_MSE_ON | SET_MENUON
	cmp #SET_MSE_ON | SET_MENUON
	bne @nm
	CmpW mouseYPosW, kMenuRect
	bcc @om
	CmpW kMenuRect+2, mouseYPosW
	bcc @om
	CmpW mouseXPos, kMenuRect+4
	bcc @om
	CmpW kMenuRect+6, mouseXPos
	bcs @nm
@om:	lda #SET_OFFMENU
	tsb faultData
@nm:
	; near the edge of the device's range: back to the middle (only after
	; a move: a device that reports a fixed position, or none, costs nothing)
	lda mouseSource
	ora mouseSource+1
	bne @r
	lda dx
	ora dx+1
	ora dy
	ora dy+1
	beq @r
	CmpWI mseLastX, MSE_EDGE
	bcc @c
	CmpWI mseLastX, MSE_W * 8 - MSE_EDGE
	bcs @c
	CmpWI mseLastY, MSE_EDGE
	bcc @c
	CmpWI mseLastY, MSE_H * 8 - MSE_EDGE
	bcc @r
@c:	jsr Center
	jmp Read
@r:	rts

; the pointer: sprite 0 at the mouse (mouseOn bit 7, not TempHideMouse)
Pointer:
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_SPRATTR + 2)
	LoadB VERA_ADDR_M, >(VRAM_SPRATTR + 2)
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	lda mouseXPos
	sta VERA_DATA0
	lda mouseXPos+1
	sta VERA_DATA0
	lda mouseYPosW
	sta VERA_DATA0
	lda mouseYPosW+1
	sta VERA_DATA0
	lda #%00001100          ; in front of the layers
	bit mouseOn
	bpl @off
	bit mseHide
	bpl @on
@off:	lda #0
@on:	sta VERA_DATA0
	rts

;---------------------------------------------------------------
; mouse calls
;---------------------------------------------------------------
; a = 1: the pointer to r11 (x), kTmp+2 (y, 16 bits); then on
MouseModeA:
	cmp #0
	beq @1
	php                     ; (the interrupt sees both or neither)
	sei
	MoveW r11, mouseXPos
	MoveW kTmp+2, mouseYPosW
	jsr YByte
	plp
@1:	stz faultData
	lda mouseOn
	ora #SET_MSE_ON
	sta mouseOn
	stz mseHide
	rts

; mouseYPos, the classic byte view of mouseYPosW (255 below line 255),
; whenever the pointer moves: GEOS programs read it, and a port that
; follows its own writes to it (geoWrite's glue) must not take a stale one
; for a new position (V59)
YByte:	lda mouseYPosW+1
	beq @1
	lda #$FF
	bra @2
@1:	lda mouseYPosW
@2:	sta mouseYPos
	rts

; a <> 0: the pointer to r11, r12; then on
k_WStartMouseMode:
	cmp #0
	beq @1
	MoveW r12, kTmp+2
	lda #1
@1:	jmp MouseModeA

k_MouseUp:
	lda mouseOn
	ora #SET_MSE_ON
	sta mouseOn
	rts

k_MouseOff:
	lda mouseOn
	and #<~SET_MSE_ON
	sta mouseOn
	rts

k_ClearMouseMode:
	stz mouseOn
	stz faultData
	rts

k_TempHideMouse:
k_HideOnlyMouse:
	LoadB mseHide, $80
	rts

; r3 left, r11 top, r4 right, r12 bottom
k_WSetMouseRegion:
	php                     ; (the interrupt clamps the pointer to it: V68)
	sei
	MoveW r3, mouseLeft
	MoveW r4, mouseRight
	MoveW r11, mouseTopW
	MoveW r12, mouseBottomW
	lda r11H
	beq @1
	lda #$FF
	bra @2
@1:	lda r11L
@2:	sta mouseTop
	lda r12H
	beq @3
	lda #$FF
	bra @4
@3:	lda r12L
@4:	sta mouseBottom
	plp
	rts

; classic: r2L top, r2H bottom, r3, r4 -> a = $FF if the pointer is inside
k_IsMseInRegion:
	PushW r11
	PushW r12
	lda r2L
	sta r11L
	stz r11H
	lda r2H
	sta r12L
	stz r12H
	jsr k_WIsMseInRegion
	tax
	PopW r12
	PopW r11
	txa
	rts

k_WIsMseInRegion:
	php                     ; (the pointer's words read whole: V68)
	sei
	CmpW mouseXPos, r3
	bcc @no
	CmpW r4, mouseXPos
	bcc @no
	CmpW mouseYPosW, r11
	bcc @no
	CmpW r12, mouseYPosW
	bcc @no
	plp
	lda #$FF
	rts
@no:	plp
	lda #0
	rts

; a = mouseButtons, x = the wheel's movement since the last call
k_GetMouse:
	php
	sei
	ldx mouseWheel
	stz mouseWheel
	plp
	lda mouseButtons
	rts

; a = keyMods: bit 0 shift, 1 ctrl, 2 alt, 3 GUI
; (V142) right Alt is the ROM's Alt + Ctrl: with the settings' Polish
; keyboard (PREFS_POLISH) it types letters (the ROM's key map), so neither
; is reported then (the programs' Alt shortcuts never see them)
k_GetKeyMods:
	jsr k_kbdbuf_get_modifiers  ; the ROM: 1 shift, 2 alt, 4 ctrl, 8 GUI
	pha
	and #6
	lsr
	tax                     ; 0 none, 1 alt, 2 ctrl, 3 both
	cpx #3
	bne @1
	lda kPrefs
	and #PREFS_POLISH
	beq @1
	ldx #0
@1:	pla
	and #%00001001
	ora ModSwap,x
	sta keyMods
	rts
ModSwap: .byte 0, 4, 2, 6       ; alt, ctrl to keyMods' bits

;---------------------------------------------------------------
; the keyboard queue
;---------------------------------------------------------------
; a = ISO code from GETIN (the main loop): translated, queued with the
; modifiers held now (KeyGet gives them as keyDataMods). Alt + Tab is not
; queued: it asks the switcher for the dock (switchReq, V83)
KeyPut:	pha
	jsr k_GetKeyMods
	sta kqMods
	tax
	pla
	cmp #9                  ; (Tab)
	bne @k
	cpx #4                  ; (Alt alone)
	bne @k
	lda #SWITCH_ASIDE
	sta switchReq
	rts
@k:	jsr IsoToGeos
	beq @r
	ldx kqTail
	sta kq,x
	lda kqMods
	sta kqm,x
	inx
	cpx #KQ
	bcc @1
	ldx #0
@1:	cpx kqHead
	beq @r                  ; full: dropped
	stx kqTail
	lda #SET_KEYPRESS       ; (tsb, trb: the interrupt sets pressFlag's
	tsb pressFlag           ; other bits, V68)
@r:	rts

; keyData = the next key (KEYPRESS cleared when the queue is empty)
KeyGet:	jsr k_GetNextChar
	sta keyData
	rts

; a = the next key, 0 if none; keyDataMods = the modifiers held when it
; was typed
k_GetNextChar:
	ldx kqHead
	cpx kqTail
	beq @none
	lda kqm,x
	sta keyDataMods
	lda kq,x
	inx
	cpx #KQ
	bcc @1
	ldx #0
@1:	stx kqHead
	cpx kqTail
	bne @r
	pha
	lda #SET_KEYPRESS
	trb pressFlag
	pla
@r:	rts
@none:	lda #SET_KEYPRESS
	trb pressFlag
	stz keyDataMods
	lda #0
	rts

; a = ISO code -> a = GEOS key code, 0 = none. With Ctrl held (kqMods
; bit 1) the codes $01-$1A are Ctrl + A-Z and stay as they are: the X16
; gives PgDn, End, F9-F12 the same codes as Ctrl+B, D, P, U, V, W, so
; without Ctrl they are those keys (KEY_PGDN ...)
IsoToGeos:
	cmp #$20
	bcs @hi
	tax
	beq @same
	cmp #$1B
	bcs @ctrl
	lda kqMods
	and #2
	beq @tx
	txa
	rts                     ; Ctrl + a letter
@tx:	txa
	bra @ctrl
@hi:	cmp #$7F
	bcc @same               ; ASCII
	cmp #$A0
	bcs @same               ; shortcuts (KeyHook) and Latin-9
@ctrl:	ldx #CtrlEnd - CtrlIso - 1
@1:	cmp CtrlIso,x
	beq @2
	dex
	bpl @1
	cmp #$20                ; other control keys: as they are
	bcc @same
	lda #0
@same:	rts
@2:	cpx #7                  ; the four arrows: keyDataMods bit 4 (KEY_LEFT
	bcs @3                  ; is BACKSPACE's code)
	cpx #3
	bcc @3
	lda #KEYM_ARROW
	tsb kqMods
@3:	lda CtrlGeos,x
	rts

CtrlIso:
	.byte $0D, $14, $19, $11, $91, $1D, $9D, $13, $93, $09, $1B, $03, $94
	.byte $85, $86, $87, $88, $89, $8A, $8B, $8C
	.byte $82, $02, $04, $84, $10, $15, $16, $17
CtrlEnd:
CtrlGeos:
	.byte CR, BACKSPACE, KEY_DELETE, KEY_DOWN, KEY_UP, KEY_RIGHT, KEY_LEFT
	.byte KEY_HOME, KEY_CLEAR, KEY_TAB, KEY_ESC, KEY_STOP, KEY_INSERT
	.byte KEY_F1, KEY_F3, KEY_F5, KEY_F7, KEY_F2, KEY_F4, KEY_F6, KEY_F8
	.byte KEY_PGUP, KEY_PGDN, KEY_END, KEY_END, KEY_F9, KEY_F10, KEY_F11, KEY_F12

;---------------------------------------------------------------
; processes: a table of .word routine, .word timer (frames); all frozen
; at first (as GEOS)
;---------------------------------------------------------------
; r0 table, a count
k_InitProcesses:
	cmp #PROCS + 1
	bcc @1
	lda #PROCS
@1:	sta procN
	ldx #0
	ldy #0
@2:	cpx procN
	beq @r
	lda (r0),y
	sta procRL,x
	iny
	lda (r0),y
	sta procRH,x
	iny
	lda (r0),y
	sta procTL,x
	sta procCL,x
	iny
	lda (r0),y
	sta procTH,x
	sta procCH,x
	iny
	lda #P_FROZEN
	sta procFlags,x
	stz procPend,x
	inx
	bra @2
@r:	rts

; x = process: its timer from the start, unfrozen
k_RestartProcess:
	lda procTL,x
	sta procCL,x
	lda procTH,x
	sta procCH,x
	lda procFlags,x
	and #<~P_FROZEN
	sta procFlags,x
	rts

; x: run at the next main loop pass
k_EnableProcess:
	lda #1
	sta procPend,x
	rts

k_BlockProcess:
	lda #P_BLOCKED
	ora procFlags,x
	sta procFlags,x
	rts

k_UnblockProcess:
	lda procFlags,x
	and #<~P_BLOCKED
	sta procFlags,x
	rts

k_FreezeProcess:
	lda #P_FROZEN
	ora procFlags,x
	sta procFlags,x
	rts

k_UnfreezeProcess:
	lda procFlags,x
	and #<~P_FROZEN
	sta procFlags,x
	rts

; the main loop: a/x = a process due (and not blocked), c set; c clear if none
ProcNext:
	ldx #0
@1:	cpx procN
	beq @no
	lda procPend,x
	beq @n
	lda procFlags,x
	and #P_BLOCKED
	bne @n
	stz procPend,x
	lda procRL,x
	pha
	lda procRH,x
	tax
	pla
	sec
	rts
@n:	inx
	bra @1
@no:	clc
	rts

; a dialog box: the processes kept and stopped (ProcSave), back (ProcRestore)
ProcSave:
	ldx #procEnd - procN - 1
@1:	lda procN,x
	sta procBuf,x
	dex
	cpx #$FF
	bne @1
	stz procN
	rts

ProcRestore:
	ldx #procEnd - procN - 1
@1:	lda procBuf,x
	sta procN,x
	dex
	cpx #$FF
	bne @1
	rts

; desk accessories (bank S, kernel/s/desk.s) and the switcher (bank W,
; V83): the process table copied to r1 in the caller's bank (ProcOut), or
; back from r0 there (ProcIn); 161 bytes. (Reached through the bank gate
; only: the caller's bank is under FarGo's return address.)
.assert procEnd - procN <= 168, error, "input.s: desk.s's procImg"
ProcOut:
	LoadW r0, procN
	lda ram_bank
	sta r3L
	tsx
	lda $0103,x
	sta r3H
	bra ProcCopy
ProcIn:	LoadW r1, procN
	tsx
	lda $0103,x
	sta r3L
	lda ram_bank
	sta r3H
ProcCopy:
	LoadW r2, procEnd - procN
	jmp k_BankCopy
