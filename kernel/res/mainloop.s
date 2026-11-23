; Veranda resident core: the main loop, calls into the application, Sleep,
; the keyboard hook
;
; Everything here may call application code, which runs with appBank
; mapped (CallApp). The loop, in GEOS's order: a key (GetString, then
; keyVector), a button change (mouseVector, or the menus and icons in bank
; U, then otherPressVec), inputVector, mouseFaultVec (after the menus),
; processes, sleeping routines, the clock, appMain.

.include "kernel.inc"

.export k_MainLoop, k_CallRoutine, CallApp, k_Sleep, SleepTick, KeyHook, kSavedKeyHook
.export k_StartMouseMode, SleepN, kClockTick
.import kLoopF, kKeyAct, kBlanked, kPrefs
.export k_StartAppl, SleepSave, SleepRestore, sysFont, fontBank, fontPage, kMenuRect, uiTimer, uiWake, AppJsr, kAppVec

SLEEPS  = 8                     ; sleeping routines at a time
KEYHDL  = $032E                 ; the ROM's key number hook
MOD_SHIFT = 1
MOD_ALT   = 2
MOD_CTRL  = 4

.segment "DATA"

kSavedKeyHook:	.word 0
kVec:		.word 0
SleepN:		.byte 0                 ; entries in use
SleepAt:	.res SLEEPS * 2         ; the routine (its return address - 1 when it slept)
SleepCnt:	.res SLEEPS * 2         ; frames left
kbdTmp:		.byte 0
kClockTick:	.byte 0                 ; $80: a second has passed (the interrupt; ClockPoll)
sysFont:	.byte 0                 ; $FF: the system font is current (text's fast path)
fontBank:	.byte 0                 ; a font in RAM banks is current: its first bank (V62), else 0
fontPage:	.byte 0                 ; and the page of its header there ($A000 + 256 * page)
kMenuRect:	.res 8                  ; the current menu level: top, bottom, left, right
				; (words; the interrupt's SET_OFFMENU)
uiTimer:	.byte 0                 ; frames until bank U's next step (the interrupt counts)
uiWake:		.byte 0                 ; <> 0: bank U waits for uiTimer (UiWake)
kAppVec:	.word 0
sleepBuf:	.res 1 + SLEEPS * 4    ; SleepSave's copy
kSaveA:		.byte 0

.segment "CODE"

;---------------------------------------------------------------
; CallRoutine: a = low, x = high; nothing if 0. CallApp: the same with
; appBank mapped (the caller's bank afterwards is the routine's).
;---------------------------------------------------------------
k_CallRoutine:
CallApp:
	sta kVec
	stx kVec+1
	ora kVec+1
	beq @r
	lda appBank
	sta ram_bank
	jmp (kVec)
@r:	rts

;---------------------------------------------------------------
; StartAppl: r7 = the start: an empty stack whose return address is
; MainLoop, the application's bank mapped
;---------------------------------------------------------------
k_StartAppl:
	ldx #$FF
	txs
	lda #>(k_MainLoop - 1)
	pha
	lda #<(k_MainLoop - 1)
	pha
	lda appBank
	sta ram_bank
	cli
	jmp (r7)

;---------------------------------------------------------------
; AppJsr: kernel banks call application code here (kAppVec; a, x, y and
; the registers passed both ways): appBank mapped for the call, the
; caller's bank back afterwards
;---------------------------------------------------------------
AppJsr:
	sta kSaveA
	lda ram_bank
	pha
	lda appBank
	sta ram_bank
	lda kSaveA
	jsr @go
	sta kSaveA
	pla
	sta ram_bank
	lda kSaveA
	rts
@go:	jmp (kAppVec)

;---------------------------------------------------------------
; MainLoop (does not return)
;---------------------------------------------------------------
k_MainLoop:
	stz kLoopF              ; (the busy pointer: FbIrq, bank G2)
	jsr KeyPoll
	; a key: keyData = the next one, keyVector
	lda pressFlag
	and #SET_KEYPRESS
	beq @mouse
	FARCALL KeyGet          ; keyData; KEYPRESS stays while keys are queued
	FARCALL UiKey           ; GetString's text input (bank U), c set if taken
	bcs @mouse
	lda keyVector
	ldx keyVector+1
	jsr CallApp
@mouse:	; a button change: the program's mouseVector if it has one; else the
	; menus and icons (bank U), then otherPressVec (presses and releases,
	; mouseData bit 7 tells them apart)
	lda pressFlag
	and #SET_MOUSE
	beq @input
	lda #SET_MOUSE          ; (trb: the interrupt sets the others, V68)
	trb pressFlag
	lda mouseVector
	ora mouseVector+1
	beq @mdef
	lda mouseVector
	ldx mouseVector+1
	jsr CallApp
	bra @input
@mdef:	FARCALL UiClick         ; c set if taken
	bcs @input
	lda otherPressVec
	ldx otherPressVec+1
	jsr CallApp
@input:	lda pressFlag
	and #SET_INPUTCHG
	beq @fault
	lda #SET_INPUTCHG
	trb pressFlag
	lda inputVector
	ldx inputVector+1
	jsr CallApp
@fault:	lda faultData
	beq @proc
	FARCALL UiFault         ; menus first (bank U); c set if taken
	bcs @f1
	lda mouseFaultVec
	ldx mouseFaultVec+1
	jsr CallApp
@f1:	stz faultData
@proc:	; processes whose time came
	FARCALL ProcNext        ; a/x = a routine, c set; else c clear
	bcc @sleep
	jsr CallApp
	bra @proc
@sleep:	; sleeping routines whose time came: they continue after their Sleep
	ldx SleepN
@s1:	dex
	bmi @clock
	lda SleepCnt,x
	ora SleepCnt+SLEEPS,x
	bne @s1
	lda SleepAt,x           ; (the return address - 1)
	clc
	adc #1
	sta kTmp
	lda SleepAt+SLEEPS,x
	adc #0
	sta kTmp+1
	jsr SleepRemove
	lda kTmp
	ldx kTmp+1
	jsr CallApp
	bra @sleep
@clock:	; bank U's timed step (a menu's or an icon's flash)
	lda uiWake
	beq @clk
	lda uiTimer
	bne @clk
	FARCALL UiWake
@clk:	FARCALL ClockPoll       ; the date and time, once a second (bank S)
	lda appMain
	ldx appMain+1
	jsr CallApp
	jmp k_MainLoop

; remove sleeping entry x (the last one takes its place)
SleepRemove:
	php
	sei
	dec SleepN
	ldy SleepN
	lda SleepAt,y
	sta SleepAt,x
	lda SleepAt+SLEEPS,y
	sta SleepAt+SLEEPS,x
	lda SleepCnt,y
	sta SleepCnt,x
	lda SleepCnt+SLEEPS,y
	sta SleepCnt+SLEEPS,x
	plp
	rts

;---------------------------------------------------------------
; Sleep: r0 = frames. The caller continues after r0 frames, from the main
; loop; Sleep itself returns to the caller's caller (GEOS's semantics).
;---------------------------------------------------------------
k_Sleep:
	php
	sei
	ldx SleepN
	cpx #SLEEPS
	bcs @full
	pla                     ; (p)
	tay
	pla                     ; the caller's return address
	sta SleepAt,x
	pla
	sta SleepAt+SLEEPS,x
	lda r0L
	sta SleepCnt,x
	lda r0H
	sta SleepCnt+SLEEPS,x
	inc SleepN
	phy
	plp
	rts                     ; to the caller's caller
@full:	plp                     ; no room: return at once
	rts

; a dialog box: the sleeping routines kept and suspended, and back
SleepSave:
	php
	sei
	ldx #SLEEPS * 4
@1:	lda SleepN,x
	sta sleepBuf,x
	dex
	bpl @1
	stz SleepN
	plp
	rts
SleepRestore:
	php
	sei
	ldx #SLEEPS * 4
@1:	lda sleepBuf,x
	sta SleepN,x
	dex
	bpl @1
	plp
	rts

; interrupt: count the sleeping routines down (to 0, where they wait), and
; bank U's timer
SleepTick:
	lda uiTimer
	beq @0
	dec uiTimer
@0:	ldx SleepN
@1:	dex
	bmi @r
	lda SleepCnt,x
	bne @2
	lda SleepCnt+SLEEPS,x
	beq @1
	dec SleepCnt+SLEEPS,x
@2:	dec SleepCnt,x
	bra @1
@r:	rts

;---------------------------------------------------------------
; StartMouseMode: c set: the pointer to r11, y; then on. The flag would not
; survive the bank gate: a = 1 to place it.
;---------------------------------------------------------------
k_StartMouseMode:
	lda #0
	rol
	sty kTmp+2
	stz kTmp+3
	FARCALL MouseModeA
	rts

;---------------------------------------------------------------
; the keyboard: GETIN from the main loop (in the interrupt it would read
; whatever channel the program has open), ISO mode while Veranda runs
;---------------------------------------------------------------
KeyPoll:
	jsr k_getin
	beq @r
	ldx #$80                ; input: not idle (FbIrq)
	stx kKeyAct
	bit kBlanked
	bmi @r                  ; the key that wakes the screen is not passed on
	FARCALL KeyPut          ; translate, queue, KEYPRESS
@r:	rts

; the ROM's key number hook (in its interrupt, any bank): Alt + a letter or
; a digit becomes a shortcut (the code OR $80) before the ISO key map
; would turn it into a Latin-9 character; Ctrl + Home and Ctrl + End (key
; numbers $50, $51), which the ROM's Ctrl map leaves out, become the codes
; of PgUp ($82) and Shift + End ($84): KEY_PGUP and KEY_END with Ctrl in
; keyDataMods (KEY_HOME with Ctrl would be Ctrl + R's code, 18). Alt +
; Tab (key number $10) is put as Tab (9): the ROM's Alt map has none, so
; KeyPut's Alt + Tab (V83) never came under R49 (V117). Right Alt is the
; ROM's Alt + Ctrl: with the settings' Polish keyboard (PREFS_POLISH, V142)
; it goes on to the ROM's key map (PL-PL: the ISO-8859-16 letters; the
; shell and Preferences select it), else it is Alt. Keeps x.
.assert PREFS_POLISH = MOD_CTRL, error, "KeyHook: PREFS_POLISH is the ROM's Ctrl bit"
KeyHook:
	pha
	and #$FF
	bmi @pass               ; key up
	cmp #$50
	beq @he
	cmp #$51
	beq @he
	cmp #KeynumEnd - KeynumChar
	bcs @pass
	tay                     ; (y: the ROM's caller sets it again)
	lda KeynumChar,y
	beq @pass
	sta kbdTmp
	jsr k_kbdbuf_get_modifiers
	sta kTmp                ; (the interrupt keeps the kernel's zero page)
	lda kPrefs
	and #PREFS_POLISH       ; (Ctrl too with the Polish keyboard: V142)
	ora #MOD_ALT | MOD_SHIFT
	and kTmp
	cmp #MOD_ALT
	beq @short
	cmp #MOD_ALT | MOD_SHIFT
	bne @pass
	lda kbdTmp              ; Shift + Alt + a letter: upper case
	cmp #'a'
	bcc @short
	and #%11011111
	sta kbdTmp
@short:	lda kbdTmp
	cmp #9                  ; Alt + Tab: Tab itself, for KeyPut (V117)
	beq @put
	ora #SHORTCUT
@put:	phx
	jsr k_kbdbuf_put
	plx
	pla
	lda #0                  ; the key is taken
	rts
@pass:	pla
	jmp (kSavedKeyHook)
@he:	sta kbdTmp
	jsr k_kbdbuf_get_modifiers
	and #MOD_CTRL
	beq @pass
	lda kbdTmp
	lsr                     ; c: End
	lda #$82
	bcc @put
	lda #$84
	bra @put

; key numbers (the X16 ROM's keycode.inc) -> characters, US layout
KeynumChar:
	.byte 0, 0                              ; $00-$01
	.byte "1234567890"                      ; $02-$0B
	.byte 0, 0, 0, 0, 9                     ; $0C-$10 (Tab: Alt + Tab, V117)
	.byte "qwertyuiop"                      ; $11-$1A
	.byte 0, 0, 0, 0                        ; $1B-$1E
	.byte "asdfghjkl"                       ; $1F-$27
	.byte 0, 0, 0, 0, 0, 0                  ; $28-$2D
	.byte "zxcvbnm"                         ; $2E-$34
KeynumEnd:
