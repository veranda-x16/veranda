; Veranda shell: the overlays' trampoline (shell.h, XCALL).
;
; ovl_go is called as the function itself would be (cc65's arguments on
; its stack and in a/x are not touched): it maps ovl_bk at $A000, makes it
; appBank (the kernel's callbacks during the call find that overlay),
; calls ovl_fn there, and puts the caller's bank and appBank back; the
; result (a/x, sreg) comes back as it was.
.include "veranda.inc"

.export _ovl_go, _ovl_bk, _ovl_fn

.segment "BSS"
_ovl_bk: .res 1
_ovl_fn: .res 2
ta:	.res 1

.segment "CODE"
_ovl_go:
	sta ta
	lda $00
	pha
	lda appBank
	pha
	lda _ovl_bk
	sta appBank
	sta $00
	lda ta
	jsr @jump
	sta ta
	pla
	sta appBank
	pla
	sta $00
	lda ta
	rts
@jump:	jmp (_ovl_fn)
