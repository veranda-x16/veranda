; Veranda C: FOpen with its error (lib/veranda.lib; vr.h)
;
;   unsigned char vr_fopen(const char *name, unsigned char mode);
;
; The binding FOpen (veranda.h) returns the handle in a and drops x, the
; error: vr_fopen returns the handle, or 0 when x is not 0 (the error is
; then in vr_ferr).

.include "veranda.inc"
.import popax
.export _vr_fopen, _vr_ferr

.segment "BSS"
_vr_ferr: .res 1
mode:	.res 1

.segment "CODE"

_vr_fopen:
	sta mode
	jsr popax
	sta r0
	stx r0+1
	lda mode
	jsr FOpen
	stx _vr_ferr
	cpx #0
	beq @ok
	lda #0
@ok:	ldx #0
	rts
