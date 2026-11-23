; A Veranda application in assembly (ca65): a title, a box, a menu with
; "quit". The start address is the first byte ($0801); the routine sets
; things up and returns: the kernel's main loop runs the rest.

.include "veranda.inc"
.include "macros.inc"

.segment "CODE"

Start:
	lda #2
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 16
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	lda #0
	jsr SetPattern
	jsr Box
	jsr WRectangle
	jsr Box
	lda #$FF
	jsr WFrameRectangle
	LoadW r0, Title
	LoadW r11, 240
	LoadW r12, 244
	jsr WPutString
	LoadW r0, Menu
	lda #0
	jsr DoMenu
	LoadW r0, Running
	jsr LogText
	rts                     ; to the main loop

Box:	LoadW r3, 200
	LoadW r11, 180
	LoadW r4, 440
	LoadW r12, 300
	rts

Quit:	LoadW r0, 0
	jmp ToBASIC

.segment "RODATA"

Menu:	.byte 0, 14
	.word 0, 40
	.byte HORIZONTAL | UN_CONSTRAINED | 1
	.word TQuit
	.byte MENU_ACTION
	.word Quit

Title:	.byte "Hello from assembly on Veranda", 0
TQuit:	.byte "quit", 0
Running: .byte "TEMPLATE ASM RUNNING", 0
