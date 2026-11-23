; Veranda: RBOOT, back to Veranda from BASIC (DECISIONS V64, the RBOOT
; model after GEOS's RBOOT, which restarted GEOS from its copy in a RAM
; expansion). A .PRG without the extension, so that LOAD"RBOOT" finds it.
;
; LOAD"RBOOT" and RUN, or ^RBOOT. ToBASIC with TOBASIC_KEEP left Veranda in memory:
; the resident core, the kernel banks, their copy and bank RB with the
; resident core's copy and a descriptor, all above MEMTOP. RBOOT finds RB
; (MEMTOP's bank count first, then every bank from 255 down: its
; signature), checks the descriptor's CRC and calls RCore there, which
; checks and puts back the resident core and the kernel banks from their
; copies and goes on to the desktop in the folder the shell showed;
; nothing is read from the card for it. Only when no intact copy is found
; does RBOOT load VERANDA.PRG from the card (the current folder, then
; /VERANDA, then the root) and start it, or say that it cannot.

.include "kernel.inc"

.import __LOW_LOAD__, __LOW_SIZE__

.segment "LOADADDR"
	.word $0801

.segment "STUB"
	.word @next, 10         ; 10 SYS2061
	.byte $9E, "2061", 0
@next:	.word 0

.segment "CODE"

Start:
	lda rom_bank
	sta RomSave
	stz rom_bank
	sec
	jsr k_memtop            ; a = MEMTOP's bank count: RB if Veranda is kept
	jsr Try
	lda #255                ; else every bank
@s:	pha
	jsr Try
	pla
	dec a
	bne @s
	; no intact copy: VERANDA.PRG from the card
	ldx #<MsgCard
	ldy #>MsgCard
	jsr Print
	.assert __LOW_SIZE__ <= 256, error, "RBOOT's low part is too big"
	ldx #0
@l:	lda __LOW_LOAD__,x
	sta Low,x
	inx
	bne @l
	jmp Low

; a = a bank: if it holds Veranda's descriptor (its signature and CRC),
; RCore there (which returns only if the copy is damaged)
Try:	sta ram_bank
	ldx #7
@1:	lda RB_SIG,x
	cmp Sig,x
	bne @r
	dex
	bpl @1
	LoadW r0, RB_HEAD
	LoadW r1, RB_HEADEND - RB_HEAD
	jsr k_memory_crc
	lda r2L
	cmp RB_CRC
	bne @r
	lda r2H
	cmp RB_CRC+1
	bne @r
	ldx #<MsgRam
	ldy #>MsgRam
	jsr Print
	jsr RB_CORE
@r:	rts

Print:	stx r0L
	sty r0H
	ldy #0
@1:	lda (r0),y
	beq @2
	jsr k_chrout
	iny
	bne @1
@2:	rts

Sig:	.byte "VERANDA", RB_VERSION
MsgRam:	.byte 13, "VERANDA IS IN MEMORY: STARTING IT", 13, 0
RomSave: .byte 0
MsgCard: .byte 13, "NO INTACT COPY OF VERANDA IN MEMORY:", 13, "LOADING VERANDA.PRG", 13, 0

;---------------------------------------------------------------
; at $0700 (VERANDA.PRG loads over $0801): VERANDA.PRG from the current
; folder, /VERANDA or the root, then its loader (SYS 2061)
;---------------------------------------------------------------
.segment "LOW"

Low:	stz Step
@try:	ldx Step
	lda CmdN,x
	beq @load
	pha                     ; the DOS command: CD to the next folder
	lda CmdL,x
	tax
	pla
	ldy #>Low
	jsr k_setnam
	lda #15
	ldx #8
	ldy #15
	jsr k_setlfs
	jsr k_open
	lda #15
	jsr k_close
	jsr k_clrchn
@load:	lda #PrgEnd - Prg
	ldx #<Prg
	ldy #>Prg
	jsr k_setnam
	lda #1
	ldx #8
	ldy #1                  ; to its own address
	jsr k_setlfs
	lda #0
	jsr k_load
	bcs @next
	jmp 2061                ; VERANDA.PRG's loader
@next:	inc Step
	lda Step
	cmp #3
	bne @try
	ldx #0
@m:	lda MsgNone,x
	beq @e
	jsr k_chrout
	inx
	bne @m
@e:	lda RomSave
	sta rom_bank
	rts

Step:	.byte 0
CmdL:	.byte 0, <CmdV, <CmdR
CmdN:	.byte 0, CmdVEnd - CmdV, CmdREnd - CmdR
CmdV:	.byte "CD:", VR_SYSDIR
CmdVEnd:
CmdR:	.byte "CD:/"
CmdREnd:
Prg:	.byte "VERANDA.PRG"
PrgEnd:
MsgNone: .byte "VERANDA.PRG NOT FOUND", 13, 0
