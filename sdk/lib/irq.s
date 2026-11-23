; Veranda C: a C function in the interrupt (intTopVector)
;
;   void vr_set_irq(void (*f)(void));   f each frame; 0: none
;
; The kernel saves r0-r15 around the application's interrupt routines, not
; cc65's zero page. The trampoline here keeps cc65's 26 bytes of zero page
; (from c_sp: c_sp, sreg, regsave, ptr1-4, tmp1-4, regbank), gives the
; function its own small C stack, and puts both back. Main loop callbacks
; (vectors, menu actions, icons, processes) need none of this: they run
; between the application's own C code, not inside it.

.export _vr_set_irq
.importzp c_sp

.include "veranda.inc"

ZPSIZE = 26
STACK  = 128

.segment "BSS"

handler: .res 2
save:	.res ZPSIZE
stack:	.res STACK

.segment "CODE"

_vr_set_irq:
	php
	sei
	sta handler
	stx handler+1
	ora handler+1
	beq @off
	lda #<Tramp
	sta intTopVector
	lda #>Tramp
	sta intTopVector+1
	plp
	rts
@off:	stz intTopVector
	stz intTopVector+1
	plp
	rts

Tramp:	ldx #ZPSIZE - 1
@s:	lda c_sp,x
	sta save,x
	dex
	bpl @s
	lda #<(stack + STACK)
	sta c_sp
	lda #>(stack + STACK)
	sta c_sp+1
	jsr @call
	ldx #ZPSIZE - 1
@r:	lda save,x
	sta c_sp,x
	dex
	bpl @r
	rts
@call:	jmp (handler)
