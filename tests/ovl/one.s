; the overlay: runs at $4000
.include "veranda.inc"
.include "macros.inc"
.segment "CODE"
	LoadW r0, Msg
	jsr LogText
	rts
Msg:	.byte "OVL ONE", 0
	.res 600, $EE           ; (more than one block of 254)
