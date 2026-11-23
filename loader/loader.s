; Veranda: VERANDA.PRG (docs/PLAN.md 4.6)
;
; A BASIC line (10 SYS 2061), this loader and the resident core's image.
; The loader copies the resident core to $8800, loads VERANDA.SYS (the
; kernel bank images, 8 KB each) into the top KERNEL_BANKS RAM banks with
; one LOAD (the X16 KERNAL continues into the next bank at $C000),
; copies the first KCOPY_BANKS into the banks below (their pristine copy,
; DECISIONS V50; bank C, the last, has none: V165), lowers MEMTOP below the copy and starts the kernel
; (bank S, Init).

.include "kernel.inc"

.import kBankBase, kMemBanks, kMemTopX, kMemTopY, k_BankCopy

.segment "LOADADDR"
	.word $0801

.segment "STUB"
	.word @next, 10         ; 10 SYS2061
	.byte $9E, "2061", 0
@next:	.word 0

.segment "CODE"

Start:
	ldx #BZP_LEN - 1        ; (V73) BASIC's zero page, for ToBASIC
@z:	lda BZP_START,x
	sta bzp,x
	dex
	bpl @z
	stz rom_bank            ; KERNAL ROM (Veranda runs with ROM bank 0)
	lda #0                  ; no LOAD messages on the text screen
	jsr k_setmsg
	sec
	jsr k_memtop            ; a = RAM banks (0: 256), x/y = MEMTOP
	; (V64) Veranda kept in memory (ToBASIC with TOBASIC_KEEP) left MEMTOP
	; at $8800 and RB: the banks it holds come back first (else each
	; start would lose 17)
	cpy #RB_TOPHI
	bne @m
	cpx #0
	bne @m
	clc
	adc #RB_BELOW + KERNEL_BANKS
	ldy #>$9F00
@m:	sta banks
	stx topX
	sty topY
	sec
	sbc #KERNEL_BANKS
	sta base
	; the resident core: clear $8800-$9EFF, copy the image
	.assert RESIDENT_SIZE = $1700, error, "the clear loop: 23 pages, up to $9EFF"
	LoadW kPtr, RESIDENT
	ldx #>RESIDENT_SIZE
	ldy #0
	tya
@clr:	sta (kPtr),y
	iny
	bne @clr
	inc kPtr+1
	dex
	bne @clr
	LoadW kPtr, Image
	LoadW kPtr2, RESIDENT
	ldx #>(ImageEnd - Image + 255)
	ldy #0
@cp:	lda (kPtr),y
	sta (kPtr2),y
	iny
	bne @cp
	inc kPtr+1
	inc kPtr2+1
	dex
	bne @cp
	lda base
	sta kBankBase
	lda banks
	sta kMemBanks
	lda topX
	sta kMemTopX
	lda topY
	sta kMemTopY
	; VERANDA.SYS into the kernel banks
	lda base
	sta ram_bank
	lda #SysNameEnd - SysName
	ldx #<SysName
	ldy #>SysName
	jsr k_setnam
	lda #1
	ldx #8
	ldy #0                  ; to x/y, not to the file's address
	jsr k_setlfs
	lda #0
	ldx #<$A000
	ldy #>$A000
	jsr k_load
	bcs @err
	lda base                ; BASIC's zero page into bank T (V73: before
	clc                     ; the copy, which keeps it)
	adc #BANK_T
	sta ram_bank
	ldx #BZP_LEN - 1
@b:	lda bzp,x
	sta RBI_BZP,x
	dex
	bpl @b
	; their pristine copy in the KCOPY_BANKS banks below them (the panic
	; box puts them back: DECISIONS V50)
	LoadW r0, $A000
	LoadW r1, $A000
	LoadW r2, KB_HALF * $2000   ; (in two parts: 9 banks are 72 KB, past r2)
	lda base
	sta r3L
	sec
	sbc #KCOPY_BANKS
	sta r3H
	jsr k_BankCopy
	lda r3L                 ; the second half
	clc
	adc #KCOPY_BANKS / 2
	sta r3L
	lda r3H
	clc
	adc #KCOPY_BANKS / 2
	sta r3H
	jsr k_BankCopy
	; BASIC must not use the kernel's banks or the copy
	lda base
	sec
	sbc #KCOPY_BANKS
	ldx topX
	ldy topY
	clc
	jsr k_memtop
	lda #0                  ; (not the resume from BASIC, V64)
	FARCALL k_Init          ; the kernel: does not return
@err:	ldx #0
@1:	lda MsgErr,x
	beq @2
	jsr k_chrout
	inx
	bne @1
@2:	rts

banks:	.byte 0
topX:	.byte 0
topY:	.byte 0
base:	.byte 0
bzp:	.res BZP_LEN

SysName:	.byte "VERANDA.SYS"
SysNameEnd:
MsgErr:		.byte "VERANDA.SYS NOT FOUND", 13, 0

.assert ImageEnd - Image <= RESIDENT_SIZE, error, "the resident core is too big"

.segment "IMAGE"
Image:
	.incbin "resident.bin"
ImageEnd:
