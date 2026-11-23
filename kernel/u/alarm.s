; Veranda bank U: the alarm's box (DECISIONS V56; kernel/s/prefs.s finds
; the alarm that is due, from ClockPoll in the main loop)
;
; AlarmBox: r0-r15 hold the alarm's entry (year, month, day, hour, minute,
; the state, the text). With a dialog box open already, or a menu's or an
; icon's flash running (V68): c set, nothing
; done (it comes again a second later). Else the alarm's sound (V69:
; SND_ALARM, even with the settings' sounds off), a line on the emulator's console
; ("ALARM hh:mm text"), and a small box over whatever runs: "Alarm hh:mm"
; in bold, the text, OK; DoDlgBox keeps the program's state and screen
; and gives them back. Its two lines go into the first 64 bytes of
; dbFileNames (the text drawing reads them below $A000, with bank G
; mapped), which are kept here and put back after it. c clear.

.include "kernel.inc"

.export AlarmBox
.import k_DoDlgBox, dlgOn, kSndReq, k_LogText, uiWake

LINE1   = dbFileNames           ; "Alarm  hh:mm" (bold)
LINE2   = dbFileNames + 16      ; the text (at most 24 characters and the 0)
KEEP    = 48
TPOS    = ABoxT - AlarmT        ; where the time goes in LINE1

.segment "BSS"

keep:	.res KEEP
logl:	.res 6 + 6 + 26

.segment "CODE"

AlarmBox:
	bit dlgOn
	bmi @w
	lda uiWake              ; a menu's or an icon's flash: after it (V68)
	beq @1
@w:	sec
	rts
@1:	ldx #KEEP - 1
@k:	lda dbFileNames,x
	sta keep,x
	dex
	bpl @k
	ldx #TPOS - 1           ; BOLDON "Alarm  "
@t:	lda AlarmT,x
	sta LINE1,x
	dex
	bpl @t
	ldx #TPOS
	lda r1H                 ; hh:mm
	jsr Dec2
	lda #':'
	sta LINE1,x
	inx
	lda r2L
	jsr Dec2
	lda #PLAINTEXT           ; (the text after it plain)
	sta LINE1,x
	stz LINE1 + 1,x
	ldx #0                  ; the text
@x:	lda r3L,x
	sta LINE2,x
	beq @x1
	inx
	cpx #24
	bne @x
	stz LINE2,x
@x1:	; the console: ALARM hh:mm text
	ldx #5
@l0:	lda LogT,x
	sta logl,x
	dex
	bpl @l0
	ldx #0
@l:	lda LINE1 + TPOS,x
	cmp #' '
	bcc @l1
	sta logl + 6,x
	inx
	bra @l
@l1:	lda #' '
	sta logl + 6,x
	inx
	ldy #0
@l2:	lda LINE2,y
	sta logl + 6,x
	beq @l3
	inx
	iny
	bra @l2
@l3:	LoadW r0, logl
	jsr k_LogText
	LoadB kSndReq, SND_ALARM
	LoadW r0, ABox
	jsr k_DoDlgBox
	ldx #KEEP - 1
@b:	lda keep,x
	sta dbFileNames,x
	dex
	bpl @b
	clc
	rts

; a (0-99) as two digits at LINE1 + x
Dec2:	ldy #'0'
@1:	cmp #10
	bcc @2
	sbc #10
	iny
	bra @1
@2:	pha
	tya
	sta LINE1,x
	inx
	pla
	ora #'0'
	sta LINE1,x
	inx
	rts

.segment "RODATA"

AlarmT:	.byte BOLDON, "Alarm  "
ABoxT:
LogT:	.byte "ALARM "
; the default box (192 x 96, in the middle of the screen), a shadow
ABox:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word LINE1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_4_Y - 4
	.word LINE2
	.byte OK, DBI_X_2, DBI_Y_2
	.byte 0
