; Veranda bank T: the way back from BASIC (DECISIONS V64, the RBOOT model)
;
; Code kept here as images at fixed addresses (segment RBIMG, $BC00-$BFFF:
; kernel.inc RBI_*) and copied where it runs by ToBASIC with TOBASIC_KEEP
; (bank S, kernel/s/init.s, with BankCopy: bank S is linked apart and
; cannot name these labels), which also copies the resident core as it
; is then and the working folder into bank RB:
;
; ReEntry, SYS 35328 ($8A00): written over the start of the second jump
; table (NEW_BASE: a fixed address; nothing calls the jump table while
; BASIC runs, and the way back puts the whole resident core back), so it
; costs the resident core nothing. It reads nothing of the resident core
; but its own bytes: RB's number is in its code (ToBASIC writes it). It
; checks the descriptor's CRC (the ROM's memory_crc) and calls RCore; if
; the descriptor or a copy is damaged (or Veranda quit: the descriptor's
; CRC zeroed) it comes back before anything changed: a message, and
; BASIC goes on.
;
; RCore (bank RB, $A040; RBOOT calls it too): the resident core's copy
; checked; RLow to $0400, where RLowCheck checks the kernel banks' copy
; (code in bank RB cannot map other banks); then the copy over
; $8800-$9EFF (ReEntry goes with it: it is not returned to) and RLowGo.
; c set: a copy is damaged, nothing but $0400-$04FF written.
;
; RLowSum ($0400, at the exit, called from bank S): the descriptor in
; RB, its CRCs (the kernel banks' copy is mapped bank by bank: code in a
; bank cannot); bank S mapped again.
;
; RLow ($0400, its image in RB at $A100): RLowCheck, RLowGo (the shell's
; folder from RB, MEMTOP as Veranda runs, the kernel banks from their
; copy, the ROM's vectors, Init's resume: ResumeInit, the desktop).

.include "kernel.inc"

.import kMemBanks, kMemTopX, kMemTopY, k_BankCopy
.segment "RBIMG"

;---------------------------------------------------------------
ReEntryImg:
.assert * = RBI_ENTRY, error, "ReEntry's image moved"
.org RB_ENTRY
ReEntry:
	lda rom_bank
	pha
	stz rom_bank            ; (BASIC's SYS: ROM bank 4)
	lda ram_bank
	pha
ReQuit:	lda #0                  ; RB (ToBASIC writes it; after Quit, V73:
ReBank = * - 1			; a bra to ReNo)
	sta ram_bank
	LoadW r0, RB_HEAD
	LoadW r1, RB_HEADEND - RB_HEAD
	jsr k_memory_crc
	lda r2L
	cmp RB_CRC
	bne ReNo
	lda r2H
	cmp RB_CRC+1
	bne ReNo
	jsr RB_CORE             ; (returns only if a copy is damaged)
ReNo:	pla
	sta ram_bank
	ldx #0
@m:	lda Msg,x
	beq @e
	jsr k_chrout
	inx
	bra @m
@e:	pla
	sta rom_bank
	rts

Msg:	.byte 13, "NO VERANDA IN RAM: ", $5E, "RBOOT", 13, 0
ReEnd:
.reloc
ReEntryLen = ReEnd - ReEntry
.assert ReBank - ReEntry = RB_BANKOFF, error, "ReEntry: RB's byte moved (kernel.inc RB_BANKOFF)"
.assert ReQuit - ReEntry = RB_QUITOFF, error, "ReEntry: kernel.inc RB_QUITOFF"
.assert ReNo - (ReQuit + 2) = RB_QUITBRA, error, "ReEntry: kernel.inc RB_QUITBRA"
.assert ReEntryLen <= RBI_ENTRYLEN, error, "ReEntry is too big"
	.res RBI_CORE - RBI_ENTRY - ReEntryLen

;---------------------------------------------------------------
RCoreImg:
.assert * = RBI_CORE, error, "RCore's image moved"
.org RB_CORE
RCore:
	LoadW r0, RB_IMAGE
	LoadW r1, RESIDENT_SIZE
	jsr k_memory_crc
	lda r2L
	cmp RB_IMGCRC
	bne @bad
	lda r2H
	cmp RB_IMGCRC+1
	bne @bad
	ldx #0
@l:	lda RB_LOW,x
	sta RLOW_RUN,x
	inx
	bne @l
	jsr RLowCheck
	bcs @bad
	sei
	LoadW r0, RB_IMAGE
	LoadW r1, RESIDENT
	ldx #>RESIDENT_SIZE
	ldy #0
@c:	lda (r0),y
	sta (r1),y
	iny
	bne @c
	inc r0H
	inc r1H
	dex
	bne @c
	jmp RLowGo
@bad:	sec
	rts
RCoreEnd:
.reloc
RCoreLen = RCoreEnd - RCore
.assert RCoreLen <= RBI_CORELEN, error, "RCore is too big"
.assert RBI_CORELEN <= RB_LOW - RB_CORE, error, "RCore's room in RB"
	.res RBI_SUM - RBI_CORE - RCoreLen

;---------------------------------------------------------------
RSumImg:
.assert * = RBI_SUM, error, "RLowSum's image moved"
.org RLOW_RUN

; RLowSum (ToBASIC, bank S mapped, a = kBankBase; RB filled but the
; descriptor): the descriptor in RB and its CRCs; bank S mapped again
RLowSum:
	ldx ram_bank            ; (a = kBankBase)
	phx
	jsr SBanks
	ldx #7
@sg:	lda Sig,x
	sta RB_SIG,x
	dex
	bpl @sg
	lda kTmp
	sta RB_BASE
	lda kTmp+2
	sta RB_SELF
	lda kMemBanks
	sta RB_BANKS
	lda kMemTopX
	sta RB_BANKS+1
	lda kMemTopY
	sta RB_BANKS+2
	LoadW r0, RB_IMAGE
	LoadW r1, RESIDENT_SIZE
	jsr k_memory_crc
	MoveW r2, RB_IMGCRC
	ldx #0
@k:	jsr SCrc                 ; each copied kernel bank's
	lda r2L
	sta RB_KCRC,y
	lda r2H
	sta RB_KCRC+1,y
	inx
	cpx #KCOPY_BANKS
	bne @k
	LoadW r0, RB_HEAD
	LoadW r1, RB_HEADEND - RB_HEAD
	jsr k_memory_crc
	MoveW r2, RB_CRC
	pla
	sta ram_bank
	rts

; a = kBankBase: kTmp = it, kTmp+1 the copy's first bank, kTmp+2 RB
; (mapped)
SBanks:	sta kTmp
	sec
	sbc #KCOPY_BANKS
	sta kTmp+1
	sbc #1
	sta kTmp+2
	sta ram_bank
	rts

; x = n: r2 = the CRC of the copy's bank n, y = 2n, RB mapped
SCrc:	txa
	clc
	adc kTmp+1
	sta ram_bank
	LoadW r0, $A000
	LoadW r1, $2000
	phx
	jsr k_memory_crc
	plx
	lda kTmp+2
	sta ram_bank
	txa
	asl
	tay
	rts

Sig:	.byte "VERANDA", RB_VERSION
RSumEnd:
.reloc
RSumLen = RSumEnd - RLowSum
.assert RSumLen <= 256, error, "RLowSum is too big"
	.res RBI_LOW - RBI_SUM - RSumLen

;---------------------------------------------------------------
RLowImg:
.assert * = RBI_LOW, error, "RLow's image moved"
.org RLOW_RUN

; RLowCheck (RCore, RB mapped): c set if a copied kernel bank's CRC differs
RLowCheck:
	lda RB_BASE
	jsr Banks
	ldx #0
@k:	jsr Crc
	lda r2L
	cmp RB_KCRC,y
	bne @bad
	lda r2H
	cmp RB_KCRC+1,y
	bne @bad
	inx
	cpx #KCOPY_BANKS
	bne @k
	clc
	rts
@bad:	sec
	rts

; a = kBankBase: kTmp = it, kTmp+1 the copy's first bank, kTmp+2 RB
; (mapped)
Banks:	sta kTmp
	sec
	sbc #KCOPY_BANKS
	sta kTmp+1
	sbc #1
	sta kTmp+2
	sta ram_bank
	rts

; x = n: r2 = the CRC of the copy's bank n, y = 2n, RB mapped
Crc:	txa
	clc
	adc kTmp+1
	sta ram_bank
	LoadW r0, $A000
	LoadW r1, $2000
	phx
	jsr k_memory_crc
	plx
	lda kTmp+2
	sta ram_bank
	txa
	asl
	tay
	rts

RLowGo:
	ldx #63                 ; the shell's folder (curDirName)
@d:	lda RB_DIR,x
	sta curDirName,x
	dex
	bpl @d
	lda kTmp+1              ; MEMTOP as Veranda runs: below the copy
	ldx RB_BANKS+1
	ldy RB_BANKS+2
	clc
	jsr k_memtop
	sei
	LoadW r0, $A000         ; the kernel banks from their copy (in two
	LoadW r1, $A000         ; parts: 9 banks are 72 KB, past r2)
	LoadW r2, KB_HALF * $2000
	lda kTmp+1
	sta r3L
	lda kTmp
	sta r3H
	jsr k_BankCopy
	lda r3L
	clc
	adc #KCOPY_BANKS / 2
	sta r3L
	lda r3H
	clc
	adc #KCOPY_BANKS / 2
	sta r3H
	jsr k_BankCopy
	jsr k_restor            ; the ROM's vectors (a BASIC program's own)
	sei
	lda #1                  ; VERA: VSYNC only
	sta VERA_IEN
	ldx #$FF
	txs
	lda #1                  ; Init: the resume
	FARCALL k_Init

RLowEnd:
.reloc
RLowLen = RLowEnd - RLowCheck
.assert RLowLen <= 256, error, "RLow is too big"
.assert RLowLen <= RB_HEADEND - RB_LOW, error, "RLow is too big for RB"
	.res RBI_BZP - RBI_LOW - RLowLen

;---------------------------------------------------------------
; (V73) BASIC's zero page $A9-$FF as the loader found it (loader/loader.s
; writes it here before the kernel banks' pristine copy is made, so the
; copy keeps it); ToBASIC puts it back: programs use $A9-$FF, and BASIC's
; warm start does not set CHRGET ($E7) or TXTTAB again
.assert * = RBI_BZP, error, "BASIC's zero page moved"
	.res BZP_LEN
