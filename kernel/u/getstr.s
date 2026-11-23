; Veranda bank U: GetString (text input), as GEOS 64 behaves
;
; GetString shows the buffer's text at (r11, y + baselineOffset), keeps its
; length and the end x (stringX), puts its own key handler in keyVector
; (the old one is called on Return, x = the length) and the prompt on.
; Keys: Return ends; 8, 28, 29, 30 erase the last
; character (its cell cleared, its real width); $20-$7F are added while the
; length is below the maximum and the character fits (else, with r1L bit 7
; clear, the maximum becomes the length: typing stops at the margin);
; others are ignored. After each key the text is 0-terminated (V39: a dialog
; box closed by its OK icon, not by Return, still gets the whole text). With
; ST_WRGS_FORE in dispBufferOn the characters go
; to the foreground only.

.include "kernel.inc"

.export k_GetString, k_WGetString, StrKey, StrFault, strState, strStateEnd
.import AppJsr, kAppVec, k_Beep
.global S_k_WPutString, S_k_WPutChar, S_k_GetRealSize, S_k_SetPattern, S_k_WRectangle
.global S_k_InitTextPrompt, S_k_PromptOn, S_k_PromptOff, S_StrKey, S_StrFault

.segment "BSS"

strState:
strBuf:	.res 2
strLen:	.res 1
strMax:	.res 1
strCtrl: .res 1                 ; r1L: bit 7, r4 is the fault routine
strFault: .res 2
tmpKey:	.res 2
strStateEnd:
patSave: .res 2
dbKeep:	.res 1

.segment "CODE"

; classic: r1H the line's top
k_GetString:
	lda r1H
	sta r12
	stz r12+1
; r0 buffer, r2L maximum, r11 x, r12 the line's top, r1L flags, r4 fault
k_WGetString:
	MoveW r0, strBuf
	MoveW r0, string
	MoveB r1L, strCtrl
	MoveB r2L, strMax
	MoveW r4, strFault
	MoveW r12, stringYW
	lda r12+1
	beq @y
	lda #$FF
	bra @y1
@y:	lda r12
@y1:	sta stringY
	; the text there already
	lda r12
	clc
	adc baselineOffset
	sta r12
	bcc @1
	inc r12+1
@1:	FARCALL k_WPutString    ; (r0 past the 0 afterwards)
	lda r0
	clc                     ; length = r0 - 1 - buffer
	sbc strBuf
	sta strLen
	MoveW r11, stringX
	MoveW keyVector, tmpKey
	LoadW keyVector, S_StrKey
	stz StringFaultVec
	stz StringFaultVec+1
	bit strCtrl
	bpl @2
	MoveW strFault, StringFaultVec
@2:	lda curHeight
	FARCALL k_InitTextPrompt
	FARCALL k_PromptOn
	rts

; keyVector during GetString (keyData)
StrKey:	FARCALL k_PromptOff
	MoveW stringX, r11
	lda stringYW
	clc
	adc baselineOffset
	sta r12
	lda stringYW+1
	adc #0
	sta r12+1
	lda keyData
	bmi @r                  ; ignored: the prompt stays off
	cmp #CR
	bne @nc
	jmp Done
@nc:	cmp #8
	beq @bs
	cmp #28
	bcc @ctl
	cmp #31
	bcc @bs                 ; 28, 29, 30
@ctl:	cmp #$20
	bcc @r
	; a character
	ldx strLen
	cpx strMax
	beq @full
	ldy strLen
	pha
	MoveW strBuf, kPtr      ; (kPtr: zero page)
	pla
	sta (kPtr),y
	pha
	lda strCtrl             ; our fault routine unless the caller gave one
	bmi @f
	LoadW StringFaultVec, S_StrFault
@f:	jsr Fore
	pla
	FARCALL k_WPutChar
	jsr Back
	bit strCtrl
	bmi @f1
	stz StringFaultVec
	stz StringFaultVec+1
@f1:	inc strLen
	MoveW r11, stringX
	bra @on
@full:	jsr k_Beep              ; (V51: a character refused)
@on:	MoveW strBuf, kPtr      ; the text 0-terminated as it stands, so a
	ldy strLen              ; dialog box closed by a button (OK), not by
	lda #0                  ; Return, gives it whole (V39)
	sta (kPtr),y
	FARCALL k_PromptOn
@r:	rts
@bs:	lda strLen
	beq @on
	dec strLen
	MoveW strBuf, kPtr
	ldy strLen
	lda (kPtr),y
	ldx currentMode
	FARCALL k_GetRealSize   ; y = its width
	sty r3
	lda stringX             ; the cell: stringX - width .. stringX - 1
	sec
	sbc r3
	sta r3
	lda stringX+1
	sbc #0
	sta r3+1
	lda stringX
	sec
	sbc #1
	sta r4
	lda stringX+1
	sbc #0
	sta r4+1
	MoveW stringYW, r11
	lda curHeight
	clc
	adc stringYW
	sta r12
	lda stringYW+1
	adc #0
	sta r12+1
	lda r12
	bne @d
	dec r12+1
@d:	dec r12
	PushW r3
	MoveW curPattern, patSave
	lda #0
	FARCALL k_SetPattern
	jsr Fore
	FARCALL k_WRectangle
	jsr Back
	MoveW patSave, curPattern
	PopW stringX
	jmp @on

; Return: the text ended, the prompt off and stopped, the old keyVector
Done:	php
	sei
	FARCALL k_PromptOff
	lda alphaFlag
	and #$7F
	sta alphaFlag
	plp
	MoveW strBuf, kPtr
	ldy strLen
	lda #0
	sta (kPtr),y
	stz keyVector
	stz keyVector+1
	stz StringFaultVec
	stz StringFaultVec+1
	MoveW tmpKey, kAppVec
	lda tmpKey
	ora tmpKey+1
	beq @r
	ldx strLen
	jmp AppJsr
@r:	rts

; the character does not fit (PutChar, through StringFaultVec): no more
StrFault:
	MoveB strLen, strMax
	dec strLen
	jmp k_Beep

; ST_WRGS_FORE: the foreground only, for one character
Fore:	lda dispBufferOn
	sta dbKeep
	and #ST_WRGS_FORE
	beq @r
	LoadB dispBufferOn, ST_WR_FORE | ST_WRGS_FORE
@r:	rts
Back:	lda dbKeep
	sta dispBufferOn
	rts
