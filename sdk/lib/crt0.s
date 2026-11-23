; Veranda C start-up (cc65): the first bytes of a C application ($0801,
; its start address). The kernel has set up GEOS's state; this clears the
; BSS, sets the C stack (below $8800) and runs the constructors, calls
; main(); when main returns the application goes on in the main loop,
; with an empty stack, as the switcher needs to put the program aside
; (DECISIONS V86: a jmp there with StartAppl's return address still on
; the stack, and Alt+Tab never took a C program aside).

.export __STARTUP__ : absolute = 1
.export _exit
.import _main, initlib, donelib, zerobss
.import __STACKSTART__
.importzp c_sp

.include "veranda.inc"

.segment "STARTUP"

	jsr zerobss
	lda #<__STACKSTART__
	sta c_sp
	lda #>__STACKSTART__
	sta c_sp+1
	jsr initlib
	jsr _main
	ldx #$FF                ; (the stack empty, as StartAppl leaves it)
	txs
	jmp MainLoop

; exit(): the destructors, then back to the shell
_exit:	jsr donelib
	jmp EnterDeskTop
