; Veranda bank C: the way back to BASIC (ToBASIC; DECISIONS V64, V67, V73;
; from bank S in V165, where the canvas needed the room: bank S's
; k_ToBASIC comes here through GoC)

.include "kernel.inc"

.export ToBasic
KEYHDL = $032E                  ; the ROM's key number hook

.import kMemBanks, kMemTopX, kMemTopY, RemoveIrq, kSavedKeyHook, kSndReq, kBankBase, k_BankCopy

;---------------------------------------------------------------
; ToBASIC: the X16's text screen, palette, vectors and MEMTOP back, every
; file closed, the system folder the current one; Veranda's banks and the
; resident core freed (the descriptor in RB made invalid). With r1 =
; TOBASIC_KEEP (DECISIONS V64, the shell's BASIC (keep Veranda)): the same, but MEMTOP $8800 with the bank count RB:
; the resident core, the kernel banks, their copy and RB stay; the
; shell's folder kept in RB; a hint printed. r0 = a command for BASIC
; (typed into the keyboard queue, up to 10 characters: a 13 in it ends a
; line; RETURN after it) or 0
;---------------------------------------------------------------
.segment "CODE"

ToBasic:
	lda #0                  ; r1 = TOBASIC_KEEP: Veranda kept (V64)
	ldx r1L
	cpx #<TOBASIC_KEEP
	bne @f
	ldx r1H
	cpx #>TOBASIC_KEEP
	bne @f
	lda #$80
@f:	sta keep
	MoveW r0, cmd
	LoadB kSndReq, SND_EXIT  ; (V69: played to its end, by Veranda's
	cli                     ; interrupt, before the ROM's is back and
				; before cint resets the PSG, V67)
@snd:	lda kSndReq
	bne @snd
	FARCALL AudioReset      ; (V52: before the ROM's handler is back)
	ldx #SysDirEnd - SysDir - 1 ; the system folder (LOAD"RBOOT" finds it;
@sd:	lda SysDir,x            ; the name below $A000: fileHeader, unused now)
	sta fileHeader,x
	dex
	bpl @sd
	LoadW r0, fileHeader
	FARCALL k_ChDir
	beq @d
	stz fileHeader+1        ; "/"
	LoadW r0, fileHeader
	FARCALL k_ChDir
@d:	ldx #1                  ; every channel closed (the command channel last)
@cl:	phx
	txa
	jsr k_close
	plx
	inx
	cpx #16
	bne @cl
	jsr k_clrchn
	jsr RemoveIrq
	lda kBankBase           ; RB: under the kernel banks' copy
	sec
	sbc #RB_BELOW
	sta r3H
	sta rbank
	bit keep
	bmi @k1
	LoadW r1, RB_CRC        ; Veranda gone: the descriptor's CRC made
	LoadW r0, Zero          ; invalid (ReEntry and RBOOT refuse it)
	lda kBankBase
	clc
	adc #BANK_C
	sta r3L
	LoadW r2, 2
	jsr k_BankCopy
	jmp @re0
@k1:	; Veranda kept (DECISIONS V64): RB gets the resident core as it is
	; now, RCore, RLow, the shell's folder; then the descriptor (RLowSum)
	LoadW r0, RESIDENT
	LoadW r1, RB_IMAGE
	LoadW r2, RESIDENT_SIZE
	jsr k_BankCopy
	LoadW r0, curDirName
	LoadW r1, RB_DIR
	LoadW r2, 64
	jsr k_BankCopy
	lda kBankBase           ; (the images: in bank T, kernel/t/reentry.s)
	clc
	adc #BANK_T
	sta r3L
	LoadW r0, RBI_CORE
	LoadW r1, RB_CORE
	LoadW r2, RBI_CORELEN
	jsr k_BankCopy
	LoadW r0, RBI_LOW
	LoadW r1, RB_LOW
	LoadW r2, $100
	jsr k_BankCopy
	LoadW r0, RBI_SUM       ; RLowSum to $0400 (fileHeader, unused now)
	LoadW r1, RLOW_RUN
	jsr k_BankCopy
	lda kBankBase
	jsr RLOW_RUN            ; (RLowSum)
@re0:	; ReEntry over the second jump table: SYS 35328 (kernel/t/reentry.s)
	lda kBankBase
	clc
	adc #BANK_T
	sta r3L
	LoadW r0, RBI_ENTRY
	LoadW r1, RB_ENTRY
	LoadW r2, RBI_ENTRYLEN
	jsr k_BankCopy
	lda #$80                ; Quit (V73): "bra" to its message, so that
	ldx #RB_QUITBRA         ; it reads no bank (BASIC's now) and calls
	bit keep                ; nothing
	bpl @rq
	lda #$A9                ; kept: "lda #RB"
	ldx rbank
@rq:	sta RB_ENTRY + RB_QUITOFF
	stx RB_ENTRY + RB_QUITOFF + 1
	; the keyboard and the mouse as they were, sprites off
	php
	sei
	lda kSavedKeyHook+1
	beq @kh
	lda kSavedKeyHook
	sta KEYHDL
	lda kSavedKeyHook+1
	sta KEYHDL+1
@kh:	plp
	lda #0                  ; mouse off
	ldx #0
	ldy #0
	jsr k_mouse_config
	sei
	lda #$FF                ; ColorOff (kColorOn clear: the way back's ModeRegs)
	FARCALL k_ColorRect
	lda kMemBanks           ; MEMTOP as it was
	ldx kMemTopX
	ldy kMemTopY
	bit keep
	bpl @mt
	lda rbank               ; (kept: below RB and $8800)
	ldx #0
	ldy #RB_TOPHI
@mt:	clc
	jsr k_memtop
	cli
	; the ROM's own screen, as at a reset or RUN STOP/RESTORE (DECISIONS
	; V67): cint's screen_init (charset, all of the palette, layer 1 the
	; text map, layer 0 off, sprites cleared, PETSCII) and the NVRAM
	; profile's output, mode, scale and colours; nothing hand-restored
	jsr k_cint
	; BASIC's zero page as the loader found it (V73: programs use
	; $A9-$FF; CHRGET at $E7 is code, and the warm start does not set it)
	lda kBankBase
	clc
	adc #BANK_T
	sta r3L
	LoadW r0, RBI_BZP
	LoadW r1, BZP_START
	LoadW r2, BZP_LEN
	jsr k_BankCopy
	stz $0801               ; (no BASIC program: the shell's code was there)
	stz $0802
	bit keep
	bpl @cmd
	ldx #0
@h:	lda MsgKeep,x
	beq @cmd
	jsr k_chrout
	inx
	bne @h
@cmd:	MoveW cmd, r0
	lda r0L
	ora r0H
	beq @b
	ldy #0
@k:	lda (r0),y
	beq @ret
	phy
	jsr k_kbdbuf_put
	ply
	iny
	cpy #10
	bne @k
@ret:	lda #13
	jsr k_kbdbuf_put
@b:	clc                     ; warm start: the program stays
	jmp k_enter_basic

.segment "BSS"

keep:	.res 1
rbank:	.res 1
cmd:	.res 2

.segment "RODATA"

SysDir:	.byte VR_SYSDIR, 0
SysDirEnd:
Zero:	.word 0
MsgKeep:	.byte "VERANDA STAYS IN MEMORY. BACK TO IT: SYS 35328", 13
		.byte "OR ", $5E, "RBOOT (LOAD", $22, "RBOOT", $22, " AND RUN)", 13, 0
