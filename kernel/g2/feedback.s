; Veranda bank G2: feedback (DECISIONS V51): the pointer's shapes, the
; system beep, blanking the screen
;
; FbIrq runs in every interrupt after bank X's work (the pointer's
; position is written by then):
;
; - The pointer's shape: pointerShape (SetPointer), the arrow while a sub
;   menu is open (dialog boxes set pointerShape to the arrow themselves),
;   PTR_BUSY while the main loop has not run for BUSY_AFTER frames
;   (kLoopF: the main loop clears it). The shapes are in sprite 0's slot
;   from PTR_SLOT_OFFSET (tools/mkpointers.py; PointerInit put them
;   there); a shape is shown by writing sprite 0's address and size, the
;   busy one animated by stepping the address; a hot spot moves the sprite
;   up and left of the pointer's position. PTR_OWN: the picture a program
;   drew into sprite 0 itself (DrawSprite: slot offset 0, 32x32).
; - The system sounds (SndStep, kernel/g2/sound.s; Beep is one of them).
; - Blanking: blankDelay seconds without a key (kKeyAct, the main loop's
;   KeyPoll), a pointer move or a button change turn VERA's video output
;   off (V184: DC_VIDEO's output mode, bits 0-1, made 0, the mode kept in
;   saveMode), so the monitor loses its signal and may go to power save;
;   VERA still raises the VSYNC and line interrupts. The next input puts
;   the mode back into bits 0-1 alone (read, modify, write), unless a mode
;   was set meanwhile. DC_VIDEO's layer and sprite bits are never touched
;   (V96): the ROM's mouse_scan turns the sprites on at every mouse packet
;   (sprite_set_position), and the kernel reads the layer bits as the
;   colour map's state. VRAM, the palette, the border and the display
;   window are left as they are. The key that wakes is dropped (KeyPoll
;   sees kBlanked); a button pressed to wake is taken away from the main
;   loop (SET_MOUSE cleared, mouseData up) until it is released.

.include "kernel.inc"

.export FbIrq, k_SetPointer, PtrShowInit, kPtrShown, PtrPics, PtrPal
.import kLoopF, kBlanked, kKeyAct, SndStep

SPR_PAL    = 1
BUSY_AFTER = 20                 ; frames (a third of a second)
BUSY_STEP  = 6                  ; frames a busy picture

.segment "BSS"

kPtrShown:	.res 1          ; the shape whose attributes sprite 0 has
bFrame:		.res 1          ; the busy picture shown
bTick:		.res 1
idleF:		.res 1          ; frames to the next second
idleS:		.res 2          ; seconds without input
last:		.res 5          ; mouseXPos, mouseYPosW, mouseButtons as last seen
swallow:	.res 1          ; $80: a button pressed to wake: hidden until released
saveMode:	.res 1          ; DC_VIDEO's output mode before blanking

.segment "CODE"

;---------------------------------------------------------------
; SetPointer: a = the shape -> a = the one before
;---------------------------------------------------------------
k_SetPointer:
	ldx pointerShape
	sta pointerShape
	txa
	rts

; PointerInit (bank G2, sprites.s) showed the arrow
PtrShowInit:
	stz kPtrShown
	rts

;---------------------------------------------------------------
; the interrupt's part
;---------------------------------------------------------------
FbIrq:
	jsr Idle
	jsr SndStep
	; the shape to show
	lda kLoopF
	cmp #BUSY_AFTER
	bcs @busy
	inc kLoopF
	lda pointerShape
	ldx menuNumber
	beq @1
	lda #PTR_ARROW          ; a sub menu
@1:	cmp #PTR_OWN
	beq @2
	and #$7F
	cmp #PTR_CROSS + 1
	bcc @2
	lda #PTR_ARROW
	bra @2
@busy:	lda #PTR_BUSY
@2:	cmp kPtrShown
	beq @same
	jsr Show
	bra @hot
@same:	cmp #PTR_BUSY           ; the busy picture's next step
	bne @hot
	dec bTick
	bne @hot
	lda bFrame
	ina
	and #PTR_BUSY_FRAMES - 1
	sta bFrame
	jsr BusyAddr
@hot:	; the hot spot: the sprite up and left of the pointer
	ldx kPtrShown
	bmi @r                  ; (PTR_OWN: 0, 0)
	ldy SlotOf,x
	lda PtrHotX,y
	ora PtrHotY,y
	beq @r
	stz VERA_CTRL
	LoadB VERA_ADDR_L, <(VRAM_SPRATTR + 2)
	LoadB VERA_ADDR_M, >(VRAM_SPRATTR + 2)
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	lda mouseXPos
	sec
	sbc PtrHotX,y
	sta VERA_DATA0
	lda mouseXPos+1
	sbc #0
	sta VERA_DATA0
	lda mouseYPosW
	sec
	sbc PtrHotY,y
	sta VERA_DATA0
	lda mouseYPosW+1
	sbc #0
	sta VERA_DATA0
@r:	rts

; sprite 0's address and size for shape a
Show:	sta kPtrShown
	cmp #PTR_OWN
	bne @v
	jsr Attr0
	lda #<(VRAM_SPRITES >> 5)
	sta VERA_DATA0
	lda #>(VRAM_SPRITES >> 5)
	sta VERA_DATA0
	lda #%10100000 | SPR_PAL ; 32x32
	bra Size
@v:	cmp #PTR_BUSY
	bne ShowN
	stz bFrame
BusyAddr:
	LoadB bTick, BUSY_STEP
	lda bFrame
	clc
	adc #3                  ; (the busy pictures follow the arrow, I-beam, crosshair)
	bra Addr
ShowN:	tax
	lda SlotOf,x
Addr:	; picture a of the slot: VRAM_SPRITES + PTR_SLOT_OFFSET + 128 a, >> 5
	asl
	asl
	clc
	adc #<((VRAM_SPRITES + PTR_SLOT_OFFSET) >> 5)
	pha
	jsr Attr0
	pla
	sta VERA_DATA0
	lda #>((VRAM_SPRITES + PTR_SLOT_OFFSET) >> 5)
	sta VERA_DATA0
	lda #%01010000 | SPR_PAL ; 16x16
Size:	pha
	LoadB VERA_ADDR_L, <(VRAM_SPRATTR + 7)
	pla
	sta VERA_DATA0
	rts

Attr0:	stz VERA_CTRL
	LoadB VERA_ADDR_L, <VRAM_SPRATTR
	LoadB VERA_ADDR_M, >VRAM_SPRATTR
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	rts

.assert <((VRAM_SPRITES + PTR_SLOT_OFFSET) >> 5) + 4 * (PTR_SHAPES - 1) < 256, error, "feedback.s: Addr's low byte"

;---------------------------------------------------------------
; idle time and blanking
;---------------------------------------------------------------
Idle:	; a button pressed to wake stays the screen's until it is let go
	bit swallow
	bpl @in
	lda mouseButtons
	bne @hide
	stz swallow
@hide:	LoadB mouseData, $80
	lda pressFlag
	and #<~SET_MOUSE
	sta pressFlag
@in:	; input: a key, the pointer moved, a button changed
	ldy #0
	bit kKeyAct
	bpl @k
	stz kKeyAct
	iny
@k:	lda mouseXPos
	cmp last
	beq @c1
	sta last
	iny
@c1:	lda mouseXPos+1
	cmp last+1
	beq @c2
	sta last+1
	iny
@c2:	lda mouseYPosW
	cmp last+2
	beq @c3
	sta last+2
	iny
@c3:	lda mouseYPosW+1
	cmp last+3
	beq @c4
	sta last+3
	iny
@c4:	lda mouseButtons
	cmp last+4
	beq @c5
	sta last+4
	iny
@c5:
	tya
	beq @still
	stz idleS
	stz idleS+1
	LoadB idleF, 60
	bit kBlanked
	bpl @r
	; it wakes: a press is not passed on
	lda mouseButtons
	beq @w
	LoadB swallow, $80
	LoadB mouseData, $80
	lda pressFlag
	and #<~SET_MOUSE
	sta pressFlag
@w:	stz faultData
	bra Wake
@still:	lda blankDelay
	ora blankDelay+1
	beq @r                  ; never
	dec idleF
	bne @r
	LoadB idleF, 60
	inc idleS
	bne @s
	inc idleS+1
@s:	bit kBlanked
	bmi @r
	lda idleS               ; idleS >= blankDelay: blank
	cmp blankDelay
	lda idleS+1
	sbc blankDelay+1
	bcs Blank
@r:	rts

Blank:	stz VERA_CTRL           ; DCSEL 0
	lda VERA_DC_VIDEO
	tax
	and #%00000011          ; the output mode
	sta saveMode
	txa
	and #%01111100          ; mode 0: video off (V184)
	sta VERA_DC_VIDEO
	LoadB kBlanked, $80
	rts

; the output mode back, the other bits as they are now (the ROM's
; mouse_scan sets bit 6 at every packet, V96); a mode set meanwhile kept
Wake:	stz VERA_CTRL
	lda VERA_DC_VIDEO
	bit #%00000011
	bne @k
	ora saveMode
	sta VERA_DC_VIDEO
@k:	stz kBlanked
	rts

.segment "RODATA"

; a shape's picture in the slot (tools/mkpointers.py's order)
SlotOf:	.byte 0, 3, 1, 2        ; PTR_ARROW, PTR_BUSY (its first), PTR_IBEAM, PTR_CROSS

PTR_DATA = 1
.include "pointers.inc"
