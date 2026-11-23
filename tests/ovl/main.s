; gate sdk: a VLIR application; record 1 an overlay assembled for $4000
.include "veranda.inc"
.include "macros.inc"

.segment "CODE"
	LoadW r0, MsgMain
	jsr LogText
	LoadW r7, $4000
	lda #1
	jsr LoadOverlay
	cpx #0
	bne @bad
	jsr $4000               ; it logs and returns
	LoadW r7, $4000         ; a record that is not there
	lda #9
	jsr LoadOverlay
	cpx #INV_RECORD
	bne @bad
	LoadW r0, MsgOk
	jsr LogText
	rts
@bad:	LoadW r0, MsgBad
	jsr LogText
	rts

.segment "RODATA"
MsgMain:	.byte "OVL MAIN", 0
MsgOk:		.byte "OVL OK", 0
MsgBad:		.byte "OVL BAD", 0
