; gate gfx (phase 2), Veranda's side: tests/scene.s in the 320x240 mode,
; then a VRAM dump (tests/check_gfx2.py compares it with GEOS 64's)
;
; -D MOVING (gate input): the scene 20 times, each on a cleared screen,
; while a scripted mouse moves the pointer every frame: the interrupt (the
; ROM's handler, the pointer sprite) runs in the middle of the drawing's
; VRAM streams, and the result must still equal GEOS 64's

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.import GfxScene

.segment "CODE"

.ifdef MOVING
Start:
	LoadW mouseSource, Wander
	LoadB passes, 20
@pass:	lda #MODE_320x240
	jsr SetVideoMode
	jsr GfxScene
	dec passes
	bne @pass
.else
Start:
	lda #MODE_320x240
	jsr SetVideoMode
	jsr GfxScene
.endif
	LoadW r0, MsgDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

.ifdef MOVING
; mouseSource: (in the interrupt) 5 pixels right and 3 down every frame,
; the left button never pressed; the region keeps the pointer on screen
Wander:	AddVW 5, wx
	AddVW 3, wy
	MoveW wx, r0
	MoveW wy, r1
	lda #0
	clc                     ; relative
	rts

.segment "DATA"

passes:	.byte 0
wx:	.word 0
wy:	.word 0
.endif

.segment "RODATA"

MsgDone:	.byte "GFX2 DONE", 0
