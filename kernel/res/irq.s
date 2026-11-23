; Veranda resident core: the interrupt entry
;
; Hooked into $0314 (Init; ToBASIC puts the ROM's back). The ROM's handler
; (keyboard, mouse, clock, the screen editor's cursor, the VSYNC
; acknowledge) moves VERA's address registers, and the kernel may be in
; the middle of a VRAM stream or of a bank call: this entry saves VERA's
; CTRL and both ports' addresses and the bank gate's state, runs the ROM's
; handler through a fake interrupt frame, and restores them.
;
; Phase 3 adds Veranda's own work (pointer, processes, sleep) here.

.include "kernel.inc"

.import GATE_STATE, GATE_STATE_SIZE, SleepTick, BrkEntry, CrashStack, kRomBrk, kBankBase, E_FbIrq

STACK_LOW = $28                 ; the stack pointer below this here: the stack is
				; nearly full (this interrupt needs about 30 bytes)

.export IrqEntry, kRomIrq, InstallIrq, RemoveIrq

.segment "DATA"

kRomIrq:	.word 0         ; the ROM's handler
sCtrl:		.byte 0
sAddr:		.res 6          ; port 0 L M H, port 1 L M H
sGate:		.res 8
sBank:		.byte 0
iVec:		.word 0
sZp:		.res 32 + $50 - $3F ; r0-r15 and the kernel's zero page (not GEOS's
				; $22-$3E: the interrupt sets pressFlag and the mouse there)

.segment "CODE"

; the ROM pushed a, x, y (and the CPU p and pc) and jumped here
IrqEntry:
	; intFirstVector (DECISIONS V41): a device's own routine, first and
	; with nothing saved; c set: its sources are served, so if VERA has
	; nothing pending either, the interrupt ends here
	lda intFirstVector+1
	beq @full
	jsr @first
	bcc @full
	lda VERA_ISR
	and VERA_IEN
	and #$0F
	bne @full
	ply
	plx
	pla
	rti
@first:	jmp (intFirstVector)
@full:	tsx                     ; a stack overflow (DECISIONS V50): the panic box
	cpx #STACK_LOW
	bcs @sp
	jmp CrashStack
@sp:	lda ram_bank
	sta sBank
	ldx #31                 ; the interrupted code's r0-r15 and kernel zero page
@zs:	lda r0,x
	sta sZp,x
	dex
	bpl @zs
	ldx #$50 - $3F - 1
@zk:	lda $3F,x
	sta sZp+32,x
	dex
	bpl @zk
	; (NO_VERA_RESTORE: gate input's control build, which must fail)
.ifndef NO_VERA_RESTORE
	lda VERA_CTRL
	sta sCtrl
	stz VERA_CTRL
	lda VERA_ADDR_L
	sta sAddr
	lda VERA_ADDR_M
	sta sAddr+1
	lda VERA_ADDR_H
	sta sAddr+2
	lda #1
	sta VERA_CTRL
	lda VERA_ADDR_L
	sta sAddr+3
	lda VERA_ADDR_M
	sta sAddr+4
	lda VERA_ADDR_H
	sta sAddr+5
	stz VERA_CTRL
.endif
	ldx #<(GATE_STATE_SIZE - 1)
@g:	lda GATE_STATE,x
	sta sGate,x
	dex
	bpl @g
	; the ROM's handler, returning here: pc, p (i set), a, x, y
	lda #>@back
	pha
	lda #<@back
	pha
	lda #%00100100          ; i set
	pha
	pha
	pha
	pha
	jmp (kRomIrq)
@back:	; Veranda's own work: intTopVector, input and timers, Sleep, intBotVector
	lda intTopVector
	ldx intTopVector+1
	jsr IrqApp
	FARCALL k_IrqWork
	lda kBankBase           ; the pointer's shape, the beep, blanking (bank G2,
	ina                     ; mapped here: the gate costs 100 cycles a frame;
	sta ram_bank            ; sBank puts the bank back)
	jsr E_FbIrq
.assert BANK_G2 = 1, error, "irq.s: ina gives bank G2"
	jsr SleepTick
	lda intBotVector
	ldx intBotVector+1
	jsr IrqApp
	ldx #<(GATE_STATE_SIZE - 1)
@h:	lda sGate,x
	sta GATE_STATE,x
	dex
	bpl @h
.ifndef NO_VERA_RESTORE
	lda #1
	sta VERA_CTRL
	lda sAddr+3
	sta VERA_ADDR_L
	lda sAddr+4
	sta VERA_ADDR_M
	lda sAddr+5
	sta VERA_ADDR_H
	stz VERA_CTRL
	lda sAddr
	sta VERA_ADDR_L
	lda sAddr+1
	sta VERA_ADDR_M
	lda sAddr+2
	sta VERA_ADDR_H
	lda sCtrl
	sta VERA_CTRL
.endif
	ldx #31
@zr:	lda sZp,x
	sta r0,x
	dex
	bpl @zr
	ldx #$50 - $3F - 1
@zq:	lda sZp+32,x
	sta $3F,x
	dex
	bpl @zq
	lda sBank
	sta ram_bank
	ply
	plx
	pla
	rti

; an application's interrupt routine (a/x, nothing if 0), its bank mapped:
; the main loop's CallApp has its own vector (an interrupt between its
; store and its jump would otherwise send the main loop here)
IrqApp:	sta iVec
	stx iVec+1
	ora iVec+1
	beq @r
	lda appBank
	sta ram_bank
	jmp (iVec)
@r:	rts

InstallIrq:
	php
	sei
	lda irqvec
	cmp #<IrqEntry
	bne @1
	lda irqvec+1
	cmp #>IrqEntry
	beq @2                  ; (already)
@1:	lda irqvec
	sta kRomIrq
	lda irqvec+1
	sta kRomIrq+1
	lda #<IrqEntry
	sta irqvec
	lda #>IrqEntry
	sta irqvec+1
	lda brkvec              ; a BRK: the panic box (kernel/res/crash.s)
	sta kRomBrk
	lda brkvec+1
	sta kRomBrk+1
	lda #<BrkEntry
	sta brkvec
	lda #>BrkEntry
	sta brkvec+1
@2:	plp
	rts

RemoveIrq:
	php
	sei
	lda kRomIrq+1
	beq @1
	lda kRomIrq
	sta irqvec
	lda kRomIrq+1
	sta irqvec+1
	lda kRomBrk
	sta brkvec
	lda kRomBrk+1
	sta brkvec+1
@1:	plp
	rts
