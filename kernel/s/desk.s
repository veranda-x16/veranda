; Veranda bank S: desk accessories (docs/PLAN.md 4.6, DECISIONS V31)
;
; GetFile on a file of type DESK_ACC (bank F) comes here (DaRun). The
; running application is put aside whole, the accessory is loaded and
; started like an application, but over the screen as it is (no video
; mode change, nothing cleared); RstrAppl (from the accessory) puts the
; application back exactly as it was and returns from its GetFile with
; x = 0.
;
; Put aside (V83: packed by bank W's packer, kernel/w/pack.s, as the
; switcher puts a program aside; 22 raw banks until then):
;   $0800-$87FF the application's RAM, VRAM $00000-$1EFFF (both screens,
;   the save-under stack, the sprite pictures, the colour map), bank 1,
;   bank U whole (menus, icons, dialog boxes, GetString)
; and one bank, the accessory's own (appBank while it runs)
; and here (bank S's variables; low memory is read directly):
;   zero page $22-$3E (GEOS's), $50-$7F and $A9-$FF (the application's);
;   the stack page and the stack pointer; $0400-$07FF (the system
;   variables, vectors, file names); the sleeping routines, the menu
;   rectangle, the font flag and bank U's timer (resident); the processes
;   (bank X: ProcOut); the bank table (bank W keeps it: TC_DAKEEP); the
;   sprite attributes,
;   palette entries 0-15, the layers and the colour map's state.
; Not put aside: what is live (the pointer's position, the button and the
; key queue, the clock, random), r0-r15, and bank F's state: an open
; record file and the overlays stay the application's (an accessory must
; not open a record file while the application has one open).

.include "kernel.inc"

.export DaRun, k_RstrAppl, daOn, BarDesk
.import Low, Root
.import kBankBase, k_BankCopy, k_StartAppl, SleepN
.import kMenuRect, sysFont, uiTimer, uiWake
.import kColorOn, kCov, ColorHide, StateReset, ModeVars, DefColors, kAppName, SetName, AudioOff, kSndReq
.global S_k_ChDir, S_k_GetFile, S_k_GetFHdrInfo, S_k_LdFile, S_ProcOut, S_ProcIn, S_k_FClose, S_k_BankAlloc, S_k_BankFree, S_k_TaskCtl

DA_BANKS = 1                    ; the accessory's own (V83: the rest packed)
DA_ROOM  = 2                    ; (V168) banks left for the accessory after the packing
				; (Note Pad's record file): else NO_BANKS, and the shell
				; lends its desktop's banks and tries again (V78)
B_APP   = 0
ZP1     = $3F - $22             ; $22-$3E
ZP2     = $80 - $50             ; $50-$7F
ZP3     = $100 - $A9            ; $A9-$FF
SLEEPBUF_SIZE = 1 + 8 * 4       ; SleepN, SleepAt, SleepCnt (kernel/res/mainloop.s:
				; SLEEPS = 8; SleepSave copies the same bytes)

.segment "BSS"

daOn:	.res 1                  ; $80: an accessory runs
daB:	.res 1                  ; the first bank
daRoom:	.res 1
daOpt:	.res 1                  ; (V168) DA_ROOM banks held while the application is packed
daSP:	.res 1                  ; the stack pointer at DaRun's entry
daErr:	.res 1
zpImg:	.res ZP1 + ZP2 + ZP3
stkImg:	.res 256
varImg:	.res 1024
slImg:	.res 40
rcImg:	.res 8
fontImg: .res FONT_STATE        ; sysFont, fontBank, fontPage
uiImg:	.res 2
procImg: .res 168
colImg:	.res 2                  ; kColorOn, kCov
vidImg:	.res 1                  ; DC_VIDEO
layImg:	.res 14
sprImg:	.res 64                 ; sprites 0-7's attributes
palImg:	.res 32                 ; palette entries 0-15
live:	.res 18
nameImg: .res 17                ; the application's name (kAppName)

.segment "CODE"


;---------------------------------------------------------------
; DaRun (GetFile, bank F): the accessory in dirEntryBuf; returns only on
; an error (x), else from RstrAppl with x = 0
;---------------------------------------------------------------
DaRun:
	sta daOpt               ; (V168) GetFile's options: ST_DA_ROOM
	tsx
	stx daSP
	ldx #INCOMPATIBLE       ; one at a time
	bit daOn
	bmi @r
	LoadW r9, dirEntryBuf
	FARCALL k_GetFHdrInfo
	cpx #0
	bne @r
	ldx #INCOMPATIBLE
	lda fileHeader + O_GHGEOS_TYPE
	cmp #DESK_ACC
	bne @r
	ldx #STRUCT_MISMAT
	lda fileHeader + O_GHSTR_TYPE
	bne @r
	ldx #NOT_VERANDA
	ldy #3
@v:	lda fileHeader + 137,y
	cmp Vrnd,y
	bne @r
	dey
	bpl @v
	ldx #TOO_NEW
	lda fileHeader + 141
	cmp #API_LEVEL + 1
	bcs @r
	lda #DA_BANKS
	FARCALL k_BankAlloc
	cpx #0
	beq @1
@r:	rts
@1:	sta daB
	jsr Keep                ; (the variables first: the packer uses some)
	jsr IrqOff              ; (V91) the application's interrupt routines
				; stop here: what they would change while it
				; is packed (its zero page, its RAM) would be
				; lost or half kept; their vectors are in varImg
	stz daRoom
	lda daOpt               ; (V168) ST_DA_ROOM: room for the accessory,
	and #ST_DA_ROOM         ; held while the application is packed (after
	beq @p                  ; Keep: the bank table kept for RstrAppl has
	lda #DA_ROOM            ; it free)
	FARCALL k_BankAlloc
	cpx #0
	bne @f
	sta daRoom
@p:
	lda #TC_DAPACK          ; RAM, VRAM, banks 1 and U packed (bank W, V83)
	FARCALL k_TaskCtl
	cpx #0
	beq @2
	jsr Room
@f:	jsr VarsBack            ; not enough banks: nothing changed
	jsr VecBack
	lda daB
	FARCALL k_BankFree
	ldx #NO_BANKS
	rts
@2:	jsr Room                ; (V168: the room given to the accessory)
	lda #1                  ; the application's open streams marked: they
	FARCALL k_FClose        ; stay open, the accessory's go at RstrAppl (V68)
	jsr AudioOff            ; (V52: before the application is put aside)
	ldx #16                 ; the name: the accessory's (the panic box)
@nm:	lda kAppName,x
	sta nameImg,x
	dex
	bpl @nm
	jsr SetName
	; the accessory: GEOS's start-up state, the screen as it is, in
	; Veranda's colours (the map hidden, its VRAM put aside above)
	jsr ColorHide           ; (V101: the shell's picture rows stay)
	jsr DefColors
	jsr StateReset
	LoadB daOn, $80
	LoadB kSndReq, SND_OPEN  ; (V69)
	lda daB
	clc
	adc #B_APP
	sta appBank
	jsr ModeVars
	LoadB mouseOn, SET_MSE_ON
	LoadW r9, dirEntryBuf
	FARCALL k_LdFile
	cpx #0
	bne @fail
	MoveW fileHeader + O_GHST_VEC, r7
	jmp k_StartAppl
@fail:	stx daErr
	jmp Back

Vrnd:	.byte "VRND"

Room:	lda daRoom
	beq @r
	FARCALL k_BankFree
@r:	rts

;---------------------------------------------------------------
; RstrAppl (from the accessory): the application back; its GetFile
; returns with x = 0. Nothing if no accessory runs.
;---------------------------------------------------------------
k_RstrAppl:
	bit daOn
	bmi @1
	rts
@1:	stz daErr
	LoadB kSndReq, SND_CLOSE ; (V69)
Back:	; the interrupt calls nothing of the accessory's from now on (each
	; vector whole: interrupts off, V68)
	jsr IrqOff
	lda #0                  ; the accessory's streams closed, the
	FARCALL k_FClose        ; application's kept (V68)
	; the application's RAM, VRAM, banks 1 and U (bank W unpacks them),
	; the processes
	lda #TC_DAUNPACK
	FARCALL k_TaskCtl
	LoadW r0, procImg
	FARCALL ProcIn          ; (bank X copies them back)
	ldx daB                 ; the bank table (the accessory's banks are
	lda #TC_DABACK          ; free again, the fonts' kept: bank W, V83)
	FARCALL k_TaskCtl
	; the rest with the interrupt off
	sei
	jsr VeraBack
	ldx #SLEEPBUF_SIZE - 1
@sl:	lda slImg,x
	sta SleepN,x
	dex
	bpl @sl
	ldx #7
@rc:	lda rcImg,x
	sta kMenuRect,x
	dex
	bpl @rc
	ldx #FONT_STATE - 1
@fi:	lda fontImg,x
	sta sysFont,x
	dex
	bpl @fi
	MoveB uiImg, uiTimer
	MoveB uiImg+1, uiWake
	ldx #16
@nm:	lda nameImg,x
	sta kAppName,x
	dex
	bpl @nm
	; the system variables, but what is live stays
	ldx #LiveN - 1
@l1:	ldy Live,x
	lda $0500,y
	sta live,x
	dex
	bpl @l1
	LoadW kPtr, $0400
	LoadW kPtr2, varImg
	ldx #4
	ldy #0
@v:	lda (kPtr2),y
	sta (kPtr),y
	iny
	bne @v
	inc kPtr+1
	inc kPtr2+1
	dex
	bne @v
	ldx #LiveN - 1
@l2:	ldy Live,x
	lda live,x
	sta $0500,y
	dex
	bpl @l2
	; zero page (not pressFlag and the pointer: $39-$3C)
	ldx #ZP1 - 1
@z1:	cpx #$39 - $22
	bcc @z1a
	cpx #$3D - $22
	bcc @z1b
@z1a:	lda zpImg,x
	sta $22,x
@z1b:	dex
	bpl @z1
	ldx #ZP2 - 1
@z2:	lda zpImg + ZP1,x
	sta $50,x
	dex
	bpl @z2
	ldx #ZP3 - 1
@z3:	lda zpImg + ZP1 + ZP2,x
	sta $A9,x
	dex
	bpl @z3
	lda #0                  ; the program's banked font: its index table
	FARCALL FontSel         ; again, if the accessory used another one
	stz daOn
	; the stack as it was at DaRun: its rts goes back to GetFile
	ldx #0
@s:	lda stkImg,x
	sta $0100,x
	inx
	bne @s
	ldx daSP
	txs
	ldx daErr
	cli
	rts

; the live system variables (offsets from $0500): mouseData, random,
; dblClickCount, the clock, mouseYPosW, mouseButtons, mouseWheel, keyMods
Live:	.byte <mouseData, <random, <(random + 1), <dblClickCount, <year, <month, <day
	.byte <hour, <minutes, <seconds, <mouseYPosW, <(mouseYPosW + 1), <mouseButtons
	.byte <mouseWheel, <keyMods, <blankDelay, <(blankDelay + 1)
LiveN = * - Live

;---------------------------------------------------------------
; Keep: everything put aside (see the top)
;---------------------------------------------------------------
Keep:	ldx #ZP1 - 1
@z1:	lda $22,x
	sta zpImg,x
	dex
	bpl @z1
	ldx #ZP2 - 1
@z2:	lda $50,x
	sta zpImg + ZP1,x
	dex
	bpl @z2
	ldx #ZP3 - 1
@z3:	lda $A9,x
	sta zpImg + ZP1 + ZP2,x
	dex
	bpl @z3
	ldx #0
@s:	lda $0100,x
	sta stkImg,x
	inx
	bne @s
	LoadW kPtr, $0400
	LoadW kPtr2, varImg
	ldx #4
	ldy #0
@v:	lda (kPtr),y
	sta (kPtr2),y
	iny
	bne @v
	inc kPtr+1
	inc kPtr2+1
	dex
	bne @v
	ldx #SLEEPBUF_SIZE - 1
@sl:	lda SleepN,x
	sta slImg,x
	dex
	bpl @sl
	ldx #7
@rc:	lda kMenuRect,x
	sta rcImg,x
	dex
	bpl @rc
	ldx #FONT_STATE - 1
@fo:	lda sysFont,x
	sta fontImg,x
	dex
	bpl @fo
	MoveB uiTimer, uiImg
	MoveB uiWake, uiImg+1
	lda #TC_DAKEEP          ; the bank table, with the banks taken above
	FARCALL k_TaskCtl       ; (bank W keeps it, V83)
	jsr VeraKeep
	LoadW r1, procImg
	FARCALL ProcOut
	rts

; the interrupt calls nothing of the program's (each vector whole:
; interrupts off, V68), and VERA's line interrupt and AFLOW are off, the
; DAC held (V91: nobody would acknowledge them; a program that used them
; arms them again; V52's AudioOff); IEN and the rate kept for VecBack
IrqOff:	php
	sei
	lda VERA_IEN
	sta ienKeep
	lda AUDIO_RATE
	sta rateKeep
.ifndef NO_AUDIO_GUARD          ; (gate audio's control kernel)
	stz AUDIO_RATE
.endif
	stz intFirstVector+1
	stz intFirstVector
	stz intTopVector
	stz intTopVector+1
	stz intBotVector
	stz intBotVector+1
	stz mouseSource
	stz mouseSource+1
	lda VERA_IEN
.ifndef NO_AUDIO_GUARD
	and #<~(VERA_LINEIRQ | VERA_AFLOW)
.else
	and #<~VERA_LINEIRQ
.endif
	sta VERA_IEN
	plp
	rts

; the interrupt's vectors back from varImg (V91: the packer gave up)
VecBack:
	php
	sei
	ldx #VecN - 1
@1:	ldy Vec,x
	lda varImg + $100,y
	sta $0500,y
	dex
	bpl @1
	lda rateKeep
	sta AUDIO_RATE
	lda ienKeep
	sta VERA_IEN
	plp
	rts

.segment "BSS"
ienKeep: .res 1
rateKeep: .res 1
.segment "CODE"
Vec:	.byte <intFirstVector, <(intFirstVector + 1), <intTopVector, <(intTopVector + 1)
	.byte <intBotVector, <(intBotVector + 1), <mouseSource, <(mouseSource + 1)
VecN = * - Vec
.assert >intFirstVector = $05 && >intTopVector = $05 && >intBotVector = $05 && >mouseSource = $05, error, "desk.s: the vectors in page 5"

; $0400-$04FF and $0600-$07FF back (the packer's, when it gave up)
VarsBack:
	ldx #0
@1:	lda varImg,x
	sta $0400,x
	lda varImg + $200,x
	sta $0600,x
	lda varImg + $300,x
	sta $0700,x
	inx
	bne @1
	rts

; the colour map's state, the layers, the sprites' attributes, the palette
VeraKeep:
	MoveB kColorOn, colImg
	MoveB kCov, colImg+1
	stz VERA_CTRL
	MoveB VERA_DC_VIDEO, vidImg
	ldx #13
@l:	lda VERA_L0_CONFIG,x
	sta layImg,x
	dex
	bpl @l
	jsr SprAt
	ldx #0
@s:	lda VERA_DATA0
	sta sprImg,x
	inx
	cpx #64
	bne @s
	jsr PalAt
	ldx #0
@p:	lda VERA_DATA0
	sta palImg,x
	inx
	cpx #32
	bne @p
	rts

VeraBack:
	MoveB colImg, kColorOn
	MoveB colImg+1, kCov
	stz VERA_CTRL
	ldx #13
@l:	lda layImg,x
	sta VERA_L0_CONFIG,x
	dex
	bpl @l
	lda VERA_DC_VIDEO
	and #%10001111
	sta kTmp
	lda vidImg
	and #%01110000          ; the layers and sprites as they were
	ora kTmp
	sta VERA_DC_VIDEO
	jsr SprAt
	ldx #0
@s:	lda sprImg,x
	sta VERA_DATA0
	inx
	cpx #64
	bne @s
	jsr PalAt
	ldx #0
@p:	lda palImg,x
	sta VERA_DATA0
	inx
	cpx #32
	bne @p
	rts

SprAt:	LoadB VERA_ADDR_L, <VRAM_SPRATTR
	LoadB VERA_ADDR_M, >VRAM_SPRATTR
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	rts
PalAt:	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	rts

;---------------------------------------------------------------
; BarDesk (V120; SysPrefs SP_BAR from bank T's LookClick, deskNote set):
; Preferences over the running program from the applications' folder, as a
; program's GetFile opens an accessory (x its error: 0 once it closed);
; then back to the program's folder (curDirName, as the accessories'
; sys_leave: the root without one). The names go below $A000 (init.s's
; Low: fileHeader's end, which the accessory's start fills anyway)
;---------------------------------------------------------------
; (gate crash's PANIC_SHOT kernel, panic.s's shot taking bank S's last
; bytes: none there)
.ifdef PANIC_SHOT
BarDesk:
	ldx #INCOMPATIBLE
	rts
.else
BarDesk:
	lda #<BdApps
	ldx #>BdApps
	jsr Low
	FARCALL k_ChDir
	lda #<BdName
	ldx #>BdName
	jsr Low
	stz r0L
	FARCALL k_GetFile
	phx
	lda #<Root
	ldx #>Root
	jsr Low
	lda curDirName
	cmp #'/'
	bne @d
	LoadW r0, curDirName
@d:	FARCALL k_ChDir
	plx
	rts

.segment "RODATA"

BdApps:	.byte VR_APPSDIR, 0
BdName:	.byte "Preferences", 0
.endif
