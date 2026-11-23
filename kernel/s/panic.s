; Veranda bank S: the panic box (DECISIONS V50)
;
; CrashInit (kernel/res/crash.s, after the kernel banks were copied back
; from their pristine copy; does not return): a clean system as Init
; leaves it, but the screen as the crash left it (the colour map hidden,
; black on white) and the shell's path (curDirName) kept; then the beep,
; the panic box over the screen (the program's name, why and where, OK),
; and the shell (EnterDeskTop: the program's RAM banks were freed). The
; box and its text are built in the application's RAM, which the program
; that crashed no longer needs.

.include "kernel.inc"

.export CrashInit
.import ClearVars, k_BankCopy, kBankBase, SysLoad, SysInit, StateReset, InstallIrq, uiTimer, uiWake, AudioReset
.import kCrashPC, kCrashBank, kCrashWhy, kAppName, k_Beep, LogStr, LogNL, IsEmu
.global S_k_DoDlgBox, S_k_EnterDeskTop

BOX     = $0801                 ; the dialog box's table
TXT1    = $0840                 ; its three lines
TXT2    = $0880
TXT3    = $08C0
BOX_H   = 96

.segment "CODE"

CrashInit:
	LoadW r0, $A000         ; the last two kernel banks (T, W) from their
	LoadW r1, $A000         ; copy: the resident core copied the others
	LoadW r2, 2 * $2000     ; (V62, V83)
	lda kBankBase
	clc
	adc #KCOPY_BANKS - 2
	sta r3H
	sec
	sbc #KCOPY_BANKS
	sta r3L
	jsr k_BankCopy
	jsr AudioReset          ; (V52: the PCM stopped, the FIFO emptied; Crash
				; left only VSYNC in IEN)
	lda graphMode           ; the mode (as the crash left it, if it is one)
	cmp #3
	bcc @m
	lda #MODE_640x480
@m:	pha
	jsr ClearVars           ; the system variables but the shell's path
	FARCALL BanksInit
	jsr InstallIrq
	LoadW blankDelay, 600
	pla
	sec                     ; the screens kept
	jsr SysInit
	jsr StateReset
	stz uiTimer
	stz uiWake
	cli
	jsr SysLoad             ; (V56: the settings and the alarms again)
	jsr k_Beep
	; the box: the program's name, then why and where
	LoadW kPtr2, TXT1
	lda #BOLDON
	jsr Put
	lda kAppName
	bne @n
	LoadW r0, SProgram
	jsr Str
	bra @n1
@n:	LoadW r0, kAppName
	jsr Str
@n1:	LoadW r0, SStopped
	jsr Str
	jsr PutEnd
	LoadW kPtr2, TXT2
	ldx kCrashWhy
	lda WhyL,x
	sta r0L
	lda WhyH,x
	sta r0H
	jsr Str
	lda kCrashPC+1
	jsr Hex
	lda kCrashPC
	jsr Hex
	LoadW r0, SBank
	jsr Str
	lda kCrashBank
	jsr PutDec
	lda #')'
	jsr Put
	jsr PutEnd
	; the emulator's console: PANIC, the name, the second line (x16emu
	; only, V106: on hardware $9FB0-$9FBF is an expansion card's)
	jsr IsEmu
	bne @nolog
	ldx #<SLog
	ldy #>SLog
	jsr LogStr
	ldx #<kAppName
	ldy #>kAppName
	jsr LogStr
	lda #' '
	sta EMU_STDOUT
	ldx #<TXT2
	ldy #>TXT2
	jsr LogStr
	jsr LogNL
@nolog:	LoadW kPtr2, TXT3
	LoadW r0, SBack
	jsr Str
	jsr PutEnd
	; the table: centred, 352 (640 modes) or 304 pixels wide, 96 high
	ldx #BoxEnd - BoxTab - 1
@t:	lda BoxTab,x
	sta BOX,x
	dex
	bpl @t
	lda screenHeight        ; top = (height - 96) / 2
	sec
	sbc #BOX_H
	sta kTmp
	lda screenHeight+1
	sbc #0
	lsr
	ror kTmp
	sta BOX+2
	lda kTmp
	sta BOX+1
	clc
	adc #BOX_H - 1
	sta BOX+3
	lda BOX+2
	adc #0
	sta BOX+4
	ldx #0                  ; the width: x = 0 the 640 modes, 1 the 320 one
	lda screenWidth+1
	bne @w
	inx
@w:	lda Lefts,x
	sta BOX+5
	stz BOX+6
	lda RightsL,x
	sta BOX+7
	lda RightsH,x
	sta BOX+8
	lda OkX,x
	sta BOX + OKPOS
.ifdef PANIC_SHOT
	; a test build (gate crash): the screen dumped once the box is drawn
	ldx #ShotEnd - Shot - 1
@s:	lda Shot,x
	sta SHOT,x
	dex
	bpl @s
	LoadW mouseSource, SHOT
.endif
	LoadW r0, BOX
	FARCALL k_DoDlgBox
	FARCALL k_EnterDeskTop  ; (does not return)

; byte a to kPtr2
Put:	sta (kPtr2)
	inc kPtr2
	bne @r
	inc kPtr2+1
@r:	rts
PutEnd:	lda #0
	bra Put
; the string at r0 (0-terminated) to kPtr2
Str:	ldy #0
@1:	lda (r0),y
	beq @r
	phy
	jsr Put
	ply
	iny
	bne @1
@r:	rts
; a as two hex digits
Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra Put
; a as a decimal number (0-255)
PutDec:	ldx #0                  ; hundreds
@h:	cmp #100
	bcc @h1
	sbc #100
	inx
	bra @h
@h1:	pha
	txa
	beq @t0
	ora #'0'
	jsr Put
@t0:	pla
	ldy #0                  ; tens
@t:	cmp #10
	bcc @t1
	sbc #10
	iny
	bra @t
@t1:	pha
	tya
	bne @t2
	cpx #0
	beq @u
@t2:	ora #'0'
	jsr Put
@u:	pla
	ora #'0'
	bra Put

.segment "RODATA"

BoxTab:	.byte SET_DB_POS | WIDE_DB | 1
	.word 0, 0, 0, 0                        ; top, bottom, left, right
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y
	.word TXT1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word TXT2
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_3_Y
	.word TXT3
	.byte OK
OKPOS = * - BoxTab
	.byte 0, DBI_Y_2
	.byte 0
BoxEnd:
.assert BOX + BoxEnd - BoxTab <= TXT1, error, "panic.s: the box's table"
Lefts:	.byte (640 - 352) / 2, (320 - 304) / 2
RightsL: .byte <((640 + 352) / 2 - 1), <((320 + 304) / 2 - 1)
RightsH: .byte >((640 + 352) / 2 - 1), >((320 + 304) / 2 - 1)
OkX:	.byte 352 / 16 - 3, 304 / 16 - 3       ; the OK icon in the middle (cards)

WhyL:	.byte <SBrk, <SPanic, <SStack
WhyH:	.byte >SBrk, >SPanic, >SStack
SProgram: .byte "The program", 0
SStopped: .byte " stopped.", PLAINTEXT, 0
SBrk:	.byte "It ran into a BRK at $", 0
SPanic:	.byte "It called Panic at $", 0
SStack:	.byte "Its stack was full at $", 0
SBank:	.byte " (RAM bank ", 0
SBack:	.byte "OK goes back to the shell.", 0
SLog:	.byte 10, "PANIC ", 0

.ifdef PANIC_SHOT
; mouseSource (called by the interrupt, bank X mapped; relative, no
; move): after 30 frames the emulator writes its dump and stops
SHOT    = $0A00
Shot:	inc SHOT + ShotN - Shot
	lda SHOT + ShotN - Shot
	cmp #30
	bne @1
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
@1:	stz r0L
	stz r0H
	stz r1L
	stz r1H
	lda #0
	clc
	rts
ShotN:	.byte 0
ShotEnd:
.endif
