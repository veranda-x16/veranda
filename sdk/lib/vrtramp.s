; Veranda SDK: vr_tramp (vr.h), a routine the kernel calls (a vector, a
; dialog box's DB_USR_ROUT) that may live in a banked overlay
; (DECISIONS V37, V79). The kernel calls an application's vectors with
; the application's own bank mapped (appBank), not an overlay's: the
; trampoline maps the RAM bank that was mapped when vr_tramp was called
; (the caller's: its overlay's), calls the routine and maps the bank it
; found again. Four slots. For code in main RAM it changes nothing.
;
;   void *__fastcall__ vr_tramp(unsigned char slot, void (*f)(void));
;
; MIT licence (see LICENSE).

.import popa
.export _vr_tramp

.segment "BSS"
tb:	.res 1                  ; the bank to map
tf:	.res 8                  ; the routines
tj:	.res 2
tt:	.res 2

.segment "CODE"

_vr_tramp:
	sta tt
	stx tt+1
	jsr popa                ; the slot
	and #3
	asl
	tay
	lda tt
	sta tf,y
	lda tt+1
	sta tf+1,y
	lda $00
	sta tb
	lda ta,y
	ldx ta+1,y
	rts

ta:	.word t0, t1, t2, t3

t0:	ldy #0
	bra go
t1:	ldy #2
	bra go
t2:	ldy #4
	bra go
t3:	ldy #6
go:	lda $00
	pha
	lda tb
	sta $00
	lda tf,y
	sta tj
	lda tf+1,y
	sta tj+1
	jsr call
	pla
	sta $00
	rts
call:	jmp (tj)
