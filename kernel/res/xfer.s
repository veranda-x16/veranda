; Veranda resident core: block transfers with CMDR-DOS
;
; XferIn / XferOut move kXN bytes between the current input / output
; channel (CHKIN / CHKOUT done by the caller) and kXA, through MACPTR /
; MCIOUT (byte by byte where a device has no block transfer). At or above
; $A000 the address is in RAM bank kXB, and the transfer goes on into the
; next bank at $C000. Resident because the destination may be any bank:
; bank F, which calls these, cannot map another bank under itself.
;
; XferOut goes byte by byte when bit 7 of kXSlow is set (FWrite sets it
; for an 'm' or seeked stream; XferOut clears it): the ROM's MCIOUT (R49,
; CMDR-DOS's fat32_write) overwriting inside a file copies one source byte
; over the rest of the call once it crosses a 512-byte sector (V55).
;
; Return: kXN = the bytes not moved (0 unless the file ended or failed);
;         a = READST's status ($40: the end of the file)

.include "kernel.inc"

.export XferIn, XferOut, kXA, kXN, kXB, kXSlow, kName, kVolume

.segment "DATA"

kXA:	.word 0
kXN:	.word 0
kXB:	.byte 0
kXSlow:	.byte 0                 ; bit 7: XferOut byte by byte (V55)
xBank:	.byte 0                 ; the caller's bank
xSt:	.byte 0
xN:	.byte 0
kVolume: .byte "SD", 0           ; GetPtrCurDkNm's volume name
kName:	.res 80                 ; file names and DOS commands (bank F; 80 since V82: "@:", a long name, ".cvt,S,W"; "R:" a long name "=VRTEMP.tmp")

.segment "CODE"

; n = the bytes for this step: at most 255, the rest, and (in banked RAM)
; up to $C000; banked addresses map kXB. z set when nothing is left
Step:	lda kXN+1
	bne @255
	lda kXN
	beq @r
	bra @n
@255:	lda #255
@n:	sta xN
	lda kXA+1
	cmp #$A0
	bcc @ok
	lda kXB
	sta ram_bank
	lda kXA+1               ; up to $C000
	cmp #$BF
	bne @ok
	lda kXA
	eor #$FF
	ina                     ; $C000 - address (1 .. 256; 256 does not occur
	beq @ok                 ; here: the address would be $BF00 -> 0: keep)
	cmp xN
	bcs @ok
	sta xN
@ok:	lda #1                  ; z clear
@r:	rts

; after moving x/y bytes: the address and the count
Moved:	txa
	clc
	adc kXA
	sta kXA
	tya
	adc kXA+1
	sta kXA+1
	cmp #$C0
	bne @1
	lda #$A0                ; on into the next bank
	sta kXA+1
	inc kXB
@1:	stx xN
	lda kXN
	sec
	sbc xN
	sta kXN
	lda kXN+1
	sbc #0
	sta kXN+1
	rts

XferIn:	lda ram_bank
	sta xBank
@step:	jsr Step
	beq @done
	lda xN
	ldx kXA
	ldy kXA+1
	clc
	jsr k_macptr
	bcs @slow
	cpx #0
	bne @got
	cpy #0
	beq @st                 ; nothing: the end
@got:	jsr Moved
	jsr k_readst
	sta xSt
	and #$40
	beq @step
	bra @done1
@slow:	; byte by byte
	lda kXA
	sta kTmp
	lda kXA+1
	sta kTmp+1
	ldy #0
@b:	phy
	jsr k_chrin
	ply
	sta (kTmp),y
	phy
	jsr k_readst
	ply
	sta xSt
	and #$02                ; a time-out: no byte (past the end)
	bne @bend
	iny
	lda xSt
	and #$40
	bne @bend
	cpy xN
	bne @b
@bend:	tya
	tax
	ldy #0
	jsr Moved
	lda xSt
	and #$42
	beq @step
	bra @done1
@st:	jsr k_readst
	sta xSt
	bra @done1
@done:	stz xSt
@done1:	lda xBank
	sta ram_bank
	lda xSt
	rts

XferOut:
	lda ram_bank
	sta xBank
@step:	jsr Step
	beq @done
.ifndef NORMW                   ; (-D NORMW: gate disk shows the ROM's fault)
	bit kXSlow              ; an overwrite: never MCIOUT (DECISIONS V55)
	bmi @slow
.endif
	lda xN
	ldx kXA
	ldy kXA+1
	clc
	jsr k_mciout
	bcs @slow
	cpx #0
	bne @got
	cpy #0
	beq @st
@got:	jsr Moved
	jsr k_readst
	sta xSt
	and #%10000011          ; device gone, a time-out
	beq @step
	bra @done1
@slow:	lda kXA
	sta kTmp
	lda kXA+1
	sta kTmp+1
	ldy #0
@b:	lda (kTmp),y
	phy
	jsr k_chrout
	ply
	iny
	cpy xN
	bne @b
	tya
	tax
	ldy #0
	bra @got                ; (its status too: a write error stops, V68)
@st:	jsr k_readst
	sta xSt
	bra @done1
@done:	stz xSt
@done1:	stz kXSlow              ; (only FWrite sets it)
	lda xBank
	sta ram_bank
	lda xSt
	rts
