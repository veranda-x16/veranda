; Veranda resident core: crash recovery (DECISIONS V50)
;
; A BRK (the ROM jumps through CBINV, $0316, which InstallIrq points
; here), Panic, or the interrupt finding the stack nearly full all come
; to Crash: interrupts off, a fresh stack, ROM bank 0, VERA's FX off and
; only the VSYNC interrupt, every channel closed, then the kernel banks
; copied back from their pristine copy (the loader put it in the
; KCOPY_BANKS RAM banks under them) and CrashInit (bank S): a clean
; state, the panic box over the screen as it was, then the shell. A
; second crash before the shell runs again goes to the ROM's own BRK
; handler (its monitor).
;
; The ROM's interrupt stub leaves on the stack (from S+1): y, x, a, p (its
; php), its return address (2), the ROM bank, a, then the CPU's p and pc
; (the address after the BRK and its signature byte).

.include "kernel.inc"

.export BrkEntry, CrashStack, k_Panic, k_Beep, k_PlaySound, kRomBrk, kCrashing, kCrashPC, kCrashBank
.export kCrashWhy, kAppName, kSndReq, kSndAtt, kLoopF, kBlanked, kKeyAct, kPrefs
.import k_BankCopy, kFx, kBankBase

.segment "DATA"

kRomBrk:	.word 0         ; the ROM's BRK handler (InstallIrq)
kCrashing:	.byte 0         ; $FF from a crash until the shell starts again
kCrashPC:	.word 0         ; where it happened
kCrashBank:	.byte 0         ; the RAM bank mapped then
kCrashWhy:	.byte 0         ; CR_BRK, CR_PANIC, CR_STACK (kernel.inc)
kAppName:	.res 17         ; the running program's name (AppReset, DaRun), 0-terminated
kSndReq:	.byte 0         ; a sound asked for (its id), $80 one playing, 0 none
				; (V69: kernel/g2/sound.s plays it)
kSndAtt:	.byte 0         ; the sounds' attenuation, 0-63 (the settings', V72)
kPrefs:		.byte 0         ; the settings' flags (V56, kernel/s/prefs.s): bit 7
				; the sounds off, bit 6 menu ticks, bits 0-1 the
				; pointer's speed
kLoopF:		.byte 0         ; frames since the main loop last ran (FbIrq: the busy pointer)
kBlanked:	.byte 0         ; $80: the screen is blanked (FbIrq)
kKeyAct:	.byte 0         ; $80: a key came (KeyPoll; FbIrq: idle, wake)

.segment "CODE"

; CBINV: a BRK
BrkEntry:
	tsx
	lda $10A,x              ; pc - 2: the BRK
	sec
	sbc #2
	sta kCrashPC
	lda $10B,x
	sbc #0
	sta kCrashPC+1
	lda #CR_BRK
	bra Bank

; the interrupt (kernel/res/irq.s): x = its stack pointer, the frame as a
; BRK's; the interrupted pc
CrashStack:
	lda $10A,x
	sta kCrashPC
	lda $10B,x
	sta kCrashPC+1
	lda #CR_STACK
	bra Bank

; Panic (GEOS): the address of the jsr
k_Panic:
	sei
	pla
	sec
	sbc #2
	sta kCrashPC
	pla
	sbc #0
	sta kCrashPC+1
	lda #CR_PANIC
Bank:	ldx ram_bank
	stx kCrashBank
	; (a = why)
Crash:	sei
	cld
	bit kCrashing
	bmi @again
	sta kCrashWhy
	dec kCrashing
	ldx #$FF
	txs
	stz rom_bank
	bit kFx                 ; FX cache writes off
	bpl @fx
	lda #2 << 1
	sta VERA_CTRL
	stz VERA_FX_CTRL
@fx:	stz VERA_CTRL
	lda #1                  ; VSYNC only (an application's line interrupt off)
	sta VERA_IEN
	; every channel closed (the command channel last: CMDR-DOS closes the rest with it)
	ldx #1
@c:	phx
	txa
	jsr k_close
	plx
	inx
	cpx #16
	bne @c
	jsr k_clrchn
	; the kernel banks from their copy (the KCOPY_BANKS banks below them)
	LoadW r0, $A000
	LoadW r1, $A000
	LoadW r2, (KCOPY_BANKS - 2) * $2000    ; (all but the last two, T and W:
	lda kBankBase                           ; 72 KB would not fit r2; CrashInit,
	sta r3H                                 ; in bank S, copies them)
	sec
	sbc #KCOPY_BANKS
	sta r3L
	jsr k_BankCopy
	FARCALL CrashInit       ; (bank S: does not return)
@again:	jmp (kRomBrk)

; Beep: PlaySound(SND_ERROR); PlaySound: a = the id; the interrupt plays
; it from the next frame (bank G2, kernel/g2/sound.s: the settings there)
k_Beep:
	lda #SND_ERROR
k_PlaySound:
	sta kSndReq
	rts
