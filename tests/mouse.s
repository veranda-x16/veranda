; gate input, the ROM's mouse (found on a real X16: the pointer reached
; only part of the screen). The device position is set past the corner of
; its range (extapi's mouse_set_position: the ROM limits it to 1015, 503);
; the kernel moves the pointer by the change, limited to the screen, and
; mouse_config puts the device back in the middle; two moves from there
; reach the opposite corner.
;
;   A<x> <y>   the pointer after the first move:  027F 01DF (639, 479)
;   B<x> <y>   the device after it:               01FB 00FB (507, 251)
;   C<x> <y>   the pointer after two more:        0000 0000
;   D<a> <b>   mouseYPos at once after WStartMouseMode placed the pointer
;              at y 300, then at y 200 (no interrupt in between): the
;              byte view current (DECISIONS V59):  00FF 00C8
;   E<a> <w>   BBMult 20 * 14: a on return and the word at x; a is the
;              low byte as GEOS 64 leaves it (geoWrite's geos menu
;              adds to it, DECISIONS V66):         0018 0118
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

k_extapi = $FEAB                ; (ROM r47 on: the test only)
pos = $50                       ; 4 bytes

.segment "CODE"

Start:
	LoadW r0, MsgStart
	jsr LogText
	jsr Go                  ; returns at once (Sleep); the rest later
	jmp MainLoop

Go:	LoadW r0, 10
	jsr Sleep
	LoadW pos, 2000         ; far right and down
	LoadW pos+2, 2000
	jsr SetPos
	LoadW r0, 10
	jsr Sleep
	lda #'A'
	jsr ShowP
	ldx #pos
	jsr k_mouse_get
	lda #'B'
	jsr Show
	jsr Zero                ; far left and up, twice (507 x 251 from the
	LoadW r0, 10            ; middle: then the middle again)
	jsr Sleep
	jsr Zero
	LoadW r0, 10
	jsr Sleep
	lda #'C'
	jsr ShowP
	php                     ; the kernel's own move of the pointer: the byte
	sei                     ; view before the interrupt recomputes it
	LoadW r11, 100
	LoadW r12, 300
	lda #1
	jsr WStartMouseMode
	lda mouseYPos
	sta pos
	LoadW r12, 200
	lda #1
	jsr WStartMouseMode
	lda mouseYPos
	sta pos+2
	plp
	stz pos+1
	stz pos+3
	lda #'D'
	jsr Show
	LoadB r1L, 20           ; (not the mouse: a classic call's a, found
	LoadB r2L, 14           ; with geoWrite's geos menu)
	lda #$A5
	ldx #r1
	ldy #r2
	jsr BBMult
	sta pos
	stz pos+1
	MoveW r1, pos+2
	lda #'E'
	jsr Show
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

Zero:	stz pos
	stz pos+1
	stz pos+2
	stz pos+3
SetPos:	ldx #pos
	lda #12
	jmp k_extapi

; a letter, the pointer
ShowP:	pha
	MoveW mouseXPos, pos
	MoveW mouseYPosW, pos+2
	pla
; a letter, pos and pos+2
Show:	jsr Put
	lda pos+1
	jsr Hex
	lda pos
	jsr Hex
	lda #' '
	jsr Put
	lda pos+3
	jsr Hex
	lda pos+2
	jsr Hex
NL:	lda #10
Put:	sta EMU_STDOUT
	rts
Hex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @n
	pla
	and #$0F
@n:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra Put

.segment "RODATA"

MsgStart:	.byte 10, "MOUSE START", 0
MsgDone:	.byte "MOUSE DONE", 0
