; Veranda bank S: start-up, video mode, colours, the way back to BASIC
;
; Init (FarCall from the loader, does not return): system variables, the
; 640x480 mode, then the first program. Phase 1 has no application loader
; yet: it loads TEST.PRG (a plain .PRG for $0801, entry at its first byte)
; if the card has one, else it returns to BASIC.

.include "kernel.inc"

.import kStride, kMemBanks, kMemTopX, kMemTopY, LogStr, LogNL, IsEmu, kNotEmu, InstallIrq, RemoveIrq
.import KeyHook, kSavedKeyHook, kClockTick, SleepN, kFx, ColorOff, daOn
.import kAppName, kCrashing, k_ClearRam, k_BankCopy, kSndReq, AppJsr, kAppVec

.export k_Init, k_SetVideoMode, k_SetColors, k_ToBASIC, ClockPoll, k_SetClock, AppReset, StateReset, ModeVars, DefColors
.export SysInit, ModeRegs, SetName, ClockRead, ClearVars, Low, Root
.import kBankBase
.global S_k_ChDir, S_k_EnterDeskTop, S_k_GetFile, S_k_TaskCtl
.export k_EnterDeskTop
.import SysLoad, AlarmCheck, prBlock, prMode
.export AudioOff, AudioReset, GoC
.import gA, gT, FarGo, E_ToBasic

KEYHDL = $032E                  ; the ROM's key number hook

.segment "CODE"

k_Init:
	ldx #$FF
	txs
	cmp #1                  ; (V64: RLow, back from BASIC)
	bne @boot
	jmp ResumeInit
@boot:
	jsr EmuCheck
	; the system variables ($0400-$07FF) and GEOS's zero page ($22-$3E)
	LoadW kPtr, $0400
	ldx #4
	ldy #0
	tya
@z:	sta (kPtr),y
	iny
	bne @z
	inc kPtr+1
	dex
	bne @z
	ldx #$3E - $22
@z2:	stz $22,x
	dex
	bpl @z2
	FARCALL BanksInit
	jsr InstallIrq
	LoadW blankDelay, 600   ; (V51)
	lda #MODE_640x480
	clc
	jsr SysInit
	; the first program
	lda #TestNameEnd - TestName
	ldx #<TestName
	ldy #>TestName
	jsr k_setnam
	lda #1
	ldx #8
	ldy #1                  ; to its own address
	jsr k_setlfs
	lda #0
	jsr k_load
	bcs @none
	ldx #$FF
	txs
	jmp $0801
@none:	LoadB sndBoot, $80       ; (V69: the start-up chime, with the first program)
	jsr Settings
	jsr Boot                ; AUTOSTART, the shell (or BASIC)
	ldx #<MsgNoTest
	ldy #>MsgNoTest
	jsr IsEmu
	bne @1
	jsr LogStr
	jsr LogNL
@1:	LoadW r0, 0
	jmp k_ToBASIC

; start-up (after TEST.PRG, which the gates use): AUTOSTART, or the shell
; (from bank F since V82: room there for long names)
Boot:	lda #<Auto
	ldx #>Auto
	jsr Low
	stz r0L
	FARCALL k_GetFile
; the shell, from the system folder /VERANDA (or the root without one; the
; shell goes back to its own folder: SysPrefs DESK_GET, V63), or BASIC
k_EnterDeskTop:
	lda #<SysDir
	ldx #>SysDir
	jsr Low
	FARCALL k_ChDir
	beq @1
	lda #<Root
	ldx #>Root
	jsr Low
	FARCALL k_ChDir
@1:	lda #<Desk              ; (DECISIONS V46) another desktop, if there is one
	ldx #>Desk
	jsr Low
	stz r0L
	FARCALL k_GetFile
	lda #<Shell
	ldx #>Shell
	jsr Low
	stz r0L
	FARCALL k_GetFile
	LoadW r0, 0
	jmp k_ToBASIC
; the name at a/x (in this bank, which bank F cannot see) copied below
; $A000, to fileHeader's last 64 bytes (GetFile reads it before it fills
; fileHeader); r0 and r6 point to it
LOWNAME = fileHeader + 192
Low:	sta kPtr
	stx kPtr+1
	ldy #$FF
@1:	iny
	lda (kPtr),y
	sta LOWNAME,y
	bne @1
	LoadW r0, LOWNAME
	MoveW r0, r6
	rts
Desk = DeskNames + 6
Shell = DeskNames
Auto:	.byte "AUTOSTART", 0
Root:	.byte "/", 0

; the settings and the alarms (V56), the settings' video mode
Settings:
	jsr SysLoad
	lda prMode
	cmp #3
	bcs @r
	cmp graphMode
	beq @r
	jmp k_SetVideoMode
@r:	rts

;---------------------------------------------------------------
; ResumeInit (Init with a = 1, from RLow: back from BASIC, DECISIONS
; V64; the resident core and the kernel banks are their copies again,
; the ROM's vectors set, curDirName the shell's folder): as Init, then
; the desktop in that folder
;---------------------------------------------------------------
ResumeInit:
	jsr EmuCheck
	jsr AudioReset
	jsr ClearVars
	FARCALL BanksInit
	jsr InstallIrq
	LoadW blankDelay, 600
	lda #MODE_640x480
	clc
	jsr SysInit
	cli
	ldx #<MsgBack
	ldy #>MsgBack
	jsr IsEmu
	bne @1
	jsr LogStr
	jsr LogNL
@1:	LoadB sndBoot, $80
	jsr Settings
	FARCALL k_EnterDeskTop

; the system variables ($0400-$07FF) but the shell's path (curDirName),
; GEOS's zero page (ResumeInit; CrashInit)
; IsEmu's answer (resident kNotEmu, 1 in its image): 0 if the emulator's
; detection bytes say x16emu. The only access to $9FB0-$9FBF on hardware,
; once a start (V106: the X16's documented detection, two reads)
EmuCheck:
	lda EMU_DETECT1
	cmp #'1'
	bne @r
	lda EMU_DETECT2
	cmp #'6'
	bne @r
	stz kNotEmu
@r:	rts

ClearVars:
	LoadW kPtr, $0400
	ldy #0
@z:	lda kPtr+1
	cmp #>curDirName
	bne @z1
	cpy #<curDirName
	bcc @z1
	cpy #<curDirName + 64
	bcc @z2
@z1:	lda #0
	sta (kPtr),y
@z2:	iny
	bne @z
	inc kPtr+1
	lda kPtr+1
	cmp #$08
	bne @z
	ldx #$3E - $22
@z3:	stz $22,x
	dex
	bpl @z3
	rts

;---------------------------------------------------------------
; SysInit (Init; CrashInit): a = the video mode, c set: the screens kept
;---------------------------------------------------------------
SysInit:
	pha
	php
	LoadB appBank, 1
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	lda #0
	FARCALL k_SetPattern
	FARCALL k_UseSystemFont
	stz currentMode
	stz StringFaultVec
	stz StringFaultVec+1
	LoadB curDrive, 8
	plp
	pla
	bcs @keep
	jsr k_SetVideoMode
	bra @m
@keep:	jsr ModeRegs
@m:	jsr DefColors
	jsr FxCheck
	; the keyboard: ISO mode, the Alt shortcut hook
	lda #$0F
	jsr k_chrout
	php
	sei
	lda KEYHDL
	cmp #<KeyHook
	bne @h
	lda KEYHDL+1
	cmp #>KeyHook
	beq @h1                 ; (already: CrashInit)
@h:	lda KEYHDL
	sta kSavedKeyHook
	lda KEYHDL+1
	sta kSavedKeyHook+1
	LoadW KEYHDL, KeyHook
@h1:	plp
	; the pointer, in the middle, on
	FARCALL PointerInit
	FARCALL MouseInit
	lda screenWidth+1
	lsr
	sta mouseXPos+1
	lda screenWidth
	ror
	sta mouseXPos
	lda screenHeight+1
	lsr
	sta mouseYPosW+1
	lda screenHeight
	ror
	sta mouseYPosW
	LoadB mouseOn, SET_MSE_ON
	LoadB selectionFlash, 10  ; GEOS's defaults
	LoadB iconSelFlg, ST_FLASH
	rts

;---------------------------------------------------------------
; SetVideoMode: a = MODE_640x480, MODE_640x240 or MODE_320x240;
; clears both screens. x = 0, or UNSUPPORTED for another a
;---------------------------------------------------------------
k_SetVideoMode:
	jsr ModeRegs
	bcs @r
	bit isDesk              ; (V177) the desktop's: its mode when it comes
	bpl @c                  ; back ("keep" with no mode in the settings)
	ldx graphMode
	inx
	stx deskMode
@c:	jmp ModeClear
@r:	rts

; the mode's variables and VERA's registers, the screens as they are
; (CrashInit: the panic box over them); c set: no such mode
ModeRegs:
	cmp #3
	bcc @1
	ldx #UNSUPPORTED
	sec
	rts
@1:	pha
	jsr ColorOff            ; (the bitmap back on layer 0)
	pla
	sta graphMode
	tax
	lda ModeW,x
	sta screenWidth
	lda ModeWH,x
	sta screenWidth+1
	lda ModeH,x
	sta screenHeight
	lda ModeHH,x
	sta screenHeight+1
	lda ModeStride,x
	sta kStride
	jsr ModeVars
	ldx graphMode           ; (the calls change x)
	php
	sei
	stz VERA_CTRL
	lda #%00000100          ; layer 0: bitmap, 1 bpp
	sta VERA_L0_CONFIG
	lda ModeTile,x          ; bitmap at VRAM_FG, TILEW = 640
	sta VERA_L0_TILEBASE
	stz VERA_L0_HSCROLL_H   ; palette offset 0: paper = entry 0, ink = 1
	lda ModeHScale,x
	sta VERA_DC_HSCALE
	lda ModeVScale,x
	sta VERA_DC_VSCALE
	stz VERA_DC_BORDER
	lda VERA_DC_VIDEO
	and #%00001111          ; keep the output mode
	ora #%01010000          ; sprites and layer 0
	sta VERA_DC_VIDEO
	plp
	; sprites 8-127 off (their attributes are random after power-up;
	; 0-7 are the kernel's: the pointer, the prompt, the application's)
	LoadB VERA_ADDR_L, <(VRAM_SPRATTR + 64)
	LoadB VERA_ADDR_M, >(VRAM_SPRATTR + 64)
	LoadB VERA_ADDR_H, (^VRAM_SPRATTR) | VERA_INC1
	ldx #240                ; 240 x 4 = 960 bytes
@3:	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	dex
	bne @3
	clc
	rts

ModeClear:
	; both screens to paper: $00000 .. VRAM_BG + 38400
	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	lda #VERA_INC1
	sta VERA_ADDR_H
	.assert VRAM_BG + 38400 - VRAM_FG = 75 * 1024, error, "both screens: 75 KB"
	ldy #75                 ; 75 x 1024 bytes
	ldx #0
@2:	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	dex
	bne @2
	dey
	bne @2
	ldx #0
	clc
	rts

ModeW:		.byte <640, <640, <320
ModeWH:		.byte >640, >640, >320
ModeH:		.byte <480, <240, <240
ModeHH:		.byte >480, >240, >240
ModeStride:	.byte 80, 80, 40
ModeTile:	.byte ((VRAM_FG >> 11) << 2) | 1, ((VRAM_FG >> 11) << 2) | 1, (VRAM_FG >> 11) << 2
ModeHScale:	.byte 128, 128, 64
ModeVScale:	.byte 128, 64, 64

;---------------------------------------------------------------
; SetColors: r0 paper, r1 ink ($0RGB): palette entries 0 and 1; one
; with bit 15 set ($FFFF) is left as it is (the ink alone: r0 = $FFFF)
;---------------------------------------------------------------
k_SetColors:
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldx #0
@1:	lda r0H,x               ; GGGGBBBB, then 0000RRRR
	bmi @k
	lda r0L,x
	sta VERA_DATA0
	lda r0H,x
	sta VERA_DATA0
	bra @2
@k:	bit VERA_DATA0          ; (kept: the reads step over it)
	bit VERA_DATA0
@2:	inx
	inx
	cpx #4
	bne @1
	rts

; Veranda's colours: paper white, ink black (Init; an application's
; start, AppReset; a desk accessory's); palette entries 2-15 the X16's
; (V65: a program that softened some, the shell's theme, leaves none to
; the next)
DefColors:
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_PALETTE + 4)
	LoadB VERA_ADDR_M, >(VRAM_PALETTE + 4)
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	ldy #4
@p:	lda DefaultPal,y
	sta VERA_DATA0
	iny
	cpy #32
	bne @p
	MoveW prBlock, r0       ; (V56: the settings' paper and ink; white and
	MoveW prBlock + 2, r1   ; black unless the control panel changed them)
	bra k_SetColors

; ToBASIC (V165: bank C's, kernel/c/basic.s)
k_ToBASIC:                      ; (V165: in bank C, kernel/c/basic.s)
	ldy #<E_ToBasic
	jmp GoC

; GoC: FARCALL bank C's entry y (3 x its index; a as given) without a
; resident stub (V165: the core is full; bank C's entries have none)
GoC:	sta gA
	sty gT
	lda #BANK_C
	jmp FarGo

; the main loop: once a second (the interrupt's tick) the date and time
; from the X16's clock (it uses r0-r3: kept)
;---------------------------------------------------------------
; SetClock (DECISIONS V42): the RTC through the ROM (r0-r3 as its
; clock_set_date_time; jiffies 0), then Veranda's variables from it now
;---------------------------------------------------------------
k_SetClock:
	stz r3L
	jsr k_clock_set_date_time
	jmp ClockRead           ; (the alarms at the next tick, from the main loop)

ClockPoll:
	bit switchReq           ; (V83) the switcher: at the main loop's top
	bpl @t                  ; level (MainLoop's FARCALL ClockPoll is all
	tsx                     ; the stack holds), not under an accessory,
	cpx #$FF - FAR_STACK + 1 ; not for the desktop itself
	bne @t
	bit daOn
	bmi @no
	bit isDesk
	bmi @no
	lda asideVector         ; (V91) the program first: it turns off what
	ora asideVector+1       ; interrupts through intFirstVector
	beq @tc
	MoveW asideVector, kAppVec
	jsr AppJsr
@tc:	lda #TC_POLL            ; (bank W: returns if the program stays)
	FARCALL k_TaskCtl
@no:	stz switchReq
@t:	bit kClockTick
	bpl ClockR
	stz kClockTick
	jsr ClockRead
	jmp AlarmCheck          ; (V56: the alarms, kernel/s/prefs.s)

; the date and time from the ROM's clock into year .. seconds
ClockRead:
	ldx #7
@s:	lda r0,x
	pha
	dex
	bpl @s
	jsr k_clock_get_date_time
	lda r0L                 ; years since 1900 -> 0-99
@y:	cmp #100
	bcc @y1
	sbc #100
	bra @y
@y1:	sta year
	MoveB r0H, month
	MoveB r1L, day
	MoveB r1H, hour
	MoveB r2L, minutes
	MoveB r2H, seconds
	ldx #0
@l:	pla
	sta r0,x
	inx
	cpx #8
	bne @l
ClockR:	rts

;---------------------------------------------------------------
; ModeVars: the margins, the clip window and the pointer's region the
; whole screen; no menus, icons or saved areas (SetVideoMode; a desk
; accessory's start, kernel/s/desk.s)
;---------------------------------------------------------------
ModeVars:
	; text margins and the clip window: the whole screen
	stz leftMargin
	stz leftMargin+1
	stz windowTopW
	stz windowTopW+1
	stz windowTop
	lda screenWidth
	sec
	sbc #1
	sta rightMargin
	lda screenWidth+1
	sbc #0
	sta rightMargin+1
	lda screenHeight
	sec
	sbc #1
	sta windowBottomW
	lda screenHeight+1
	sbc #0
	sta windowBottomW+1
	beq @1
	lda #$FF                ; the classic byte view: at most 255
	bra @2
@1:	lda windowBottomW
@2:	sta windowBottom
	FARCALL MouseRegionAll
	FARCALL UiInit           ; no menus, icons or saved areas
	rts

;---------------------------------------------------------------
; FxCheck: kFx bit 7 if VERA has FX cache writes (firmware 0.3.1 or later:
; DCSEL 63 reads "V", major, minor, patch); never with -D NOFX
;---------------------------------------------------------------
FxCheck:
	stz kFx
.ifndef NOFX
	lda #63 << 1
	sta VERA_CTRL
	lda VERA_VERSION
	cmp #'V'
	bne @no
	lda VERA_VERSION+1      ; major
	bne @yes
	lda VERA_VERSION+2      ; minor
	cmp #3
	bcc @no
	bne @yes
	lda VERA_VERSION+3      ; patch
	beq @no
@yes:	lda #2 << 1             ; FX off, the multiplier off
	sta VERA_CTRL
	stz VERA_FX_CTRL
	stz VERA_FX_MULT
	LoadB kFx, $80
@no:	stz VERA_CTRL
.endif
	rts

;---------------------------------------------------------------
; AppReset (the loader, before an application starts): GEOS's start-up
; state; a = the video mode ($FF: the one there is), the screens cleared
;---------------------------------------------------------------
AppReset:
	pha
	FARCALL PrReset         ; a PDF document left open (bank P)
	jsr StateReset
	jsr SetName
	jsr AppSound
	ldx fileHeader + 143    ; (V83: the switcher learns of it: its flags,
	ldy isDesk              ; the desktop or not)
	lda #TC_START
	FARCALL k_TaskCtl
	stz kCrashing           ; (V50: a crash from here on gets the panic box)
	jsr ClearRest
	pla
	cmp #$FF
	bne @m
	lda prMode              ; (V56: "keep" is the settings' mode, if any)
	cmp #3
	bcc @m
	lda graphMode           ; (V177: none: the desktop gets its own back,
	bit isDesk              ; not the last program's, such as Colour
	bpl @m                  ; Paint's 320 x 240)
	ldx deskMode
	beq @m
	dex
	txa
@m:	jsr k_SetVideoMode     ; (the colour map hidden)
	jsr DefColors
	LoadB mouseOn, SET_MSE_ON
	rts

; the sound of a program's start (V69): the start-up chime for the first
; after boot (or BASIC), SND_APP for an application but the desktop
; (SHELL or DESKTOP, V46: a return to it is quiet); isDesk $80 for the
; desktop (V83: the switcher does not put it aside)
AppSound:
	stz isDesk
	ldy #0
@d:	ldx DeskNames,y         ; the name against each (letters: case ignored)
	beq @app
	phy
	ldx #0
@c:	lda kAppName,x
	beq @e
	and #$DF
	cmp DeskNames,y
	bne @n
	inx
	iny
	bra @c
@e:	lda DeskNames,y         ; (both end here: the desktop)
	ply
	cmp #0
	bne @d1
	dec isDesk
	bra @app
@n:	ply
@d1:	lda DeskNames,y         ; the next name
	iny
	cmp #0
	bne @d1
	bra @d
@app:	lda #SND_STARTUP
	bit sndBoot
	bmi @p
	bit isDesk
	bmi @r
	lda #SND_APP
@p:	sta kSndReq
	stz sndBoot
@r:	rts

; GEOS's start-up state without the video mode (AppReset; a desk
; accessory's start)
StateReset:
	stz daOn                ; (an application started from an accessory
				; ends it: kernel/s/desk.s)
	php                     ; (the interrupt's vectors whole: V68)
	sei
	ldx #$0539 - $0523 - 1  ; appMain .. BRKVector
@v:	stz $0523,x
	dex
	bpl @v
	stz RecoverVector
	stz RecoverVector+1
	stz mouseSource
	stz mouseSource+1
	plp
	jsr AudioOff            ; (V52: AFLOW off before its routine goes)
	stz intFirstVector+1    ; (V41: the high byte first; the entry tests it)
	stz intFirstVector
	stz asideVector         ; (V91)
	stz asideVector+1
	stz faultData
	stz pressFlag
	stz pointerShape        ; (V51: the arrow)
	stz uiFont              ; (V62: menus and dialog boxes in the system font)
	stz uiLook              ; (V74: menus in GEOS 64's look)
	stz longNames           ; (V82: GEOS's names)
	LoadB selectionFlash, 10
	LoadB iconSelFlg, ST_FLASH
	stz SleepN
	lda #0
	FARCALL k_InitProcesses
	FARCALL k_PromptOff
	stz alphaFlag
	ldx #1                  ; sprites 1-7 off
@s:	stx r3L
	phx
	FARCALL k_DisablSprite
	plx
	inx
	cpx #8
	bne @s
	stz currentMode
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	FARCALL k_UseSystemFont
	LoadB appBank, 1
	rts

;---------------------------------------------------------------
; SetName: kAppName = the name in dirEntryBuf (the program starting:
; AppReset; an accessory: DaRun), 0-terminated
;---------------------------------------------------------------
SetName:
	ldx #0
@1:	lda dirEntryBuf + OFF_FNAME,x
	cmp #$A0
	beq @2
	sta kAppName,x
	inx
	cpx #16
	bne @1
@2:	stz kAppName,x
	rts

; the application's RAM after its program ($0801-$87FF, fileHeader's end
; address on) to 0: a jump past the program is a BRK, the panic box (V50)
ClearRest:
	lda fileHeader + O_GHEND_ADDR
	sta r1L
	lda fileHeader + O_GHEND_ADDR + 1
	sta r1H
	cmp #>$0801
	bcc @r
	cmp #>$8800
	bcs @r
	lda #<$8800
	sec
	sbc r1L
	sta r0L
	lda #>$8800
	sbc r1H
	sta r0H
	jmp k_ClearRam
@r:	rts

;---------------------------------------------------------------
; AudioOff (DECISIONS V52): VERA's PCM stopped where a program's audio
; interrupt routine is about to go away (an accessory's start, StateReset):
; AFLOW off in IEN (else, with nobody to refill the FIFO, AFLOW stays
; asserted: an interrupt storm through the ROM's handler), the DAC held
; (AUDIO_RATE 0). The FIFO is kept: an application resumes after GetFile.
; The PSG is not touched. AudioReset (an application's load, ToBASIC):
; that, intFirstVector cleared (the routine is in RAM about to be
; overwritten) and the FIFO emptied. a, x, y kept.
;---------------------------------------------------------------
AudioReset:
.ifndef NO_AUDIO_GUARD          ; (gate audio's control kernel, which must fail)
	php
	sei
	jsr AudioOff
	stz intFirstVector+1
	stz intFirstVector
	pha
	lda #$80                ; FIFO reset (8-bit mono, volume 0)
	sta AUDIO_CTRL
	pla
	plp
.endif
	rts

AudioOff:
.ifndef NO_AUDIO_GUARD
	php
	sei
	pha
	lda VERA_IEN
	and #<~(VERA_AFLOW | VERA_LINEIRQ) ; (V91: a line interrupt too: nobody
	sta VERA_IEN            ; would acknowledge it, the ROM's handler does not)
	stz AUDIO_RATE
	pla
	plp
.endif
	rts

.segment "BSS"

sndBoot: .res 1                 ; $80: the next program's start is the first (V69)
.export isDesk
isDesk:	.res 1                  ; $80: the program running is the desktop (V83)
deskMode: .res 1                ; (V177) the desktop's last mode + 1 (0: none yet)

.segment "RODATA"

SysDir:	.byte VR_SYSDIR, 0
SysDirEnd:
MsgBack:	.byte "VERANDA BACK FROM BASIC", 0
DefaultPal:	.byte $00, $00, $FF, $0F, $00, $08, $FE, $0A, $4C, $0C, $C5, $00, $0A, $00, $E7, $0E ; the X16's 0-15
		.byte $85, $0D, $40, $06, $77, $0F, $33, $03, $77, $07, $F6, $0A, $8F, $00, $BB, $0B
DeskNames:	.byte "SHELL", 0, "DESKTOP", 0, 0
TestName:	.byte "TEST.PRG"
TestNameEnd:
MsgNoTest:	.byte "VERANDA: NO TEST.PRG", 0
