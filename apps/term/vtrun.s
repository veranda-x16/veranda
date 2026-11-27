; Veranda Term: the printable run at the start of what came in, in
; assembly (DECISIONS V212; net.c's net_rx takes such a run at once, vt.c's
; vt_text puts it into the model). MIT licence (see LICENSE).
;
;   unsigned char __fastcall__ net_run(const unsigned char *p, unsigned int n)
;       the printable characters (32-126) at p's start, at most n and 255

.export _net_run
.import popax
.importzp ptr1, tmp1

.segment "CODE"

_net_run:
	cpx #0                  ; n > 255: 255
	beq @1
	lda #255
@1:	sta tmp1
	jsr popax
	sta ptr1
	stx ptr1+1
	ldy #0
@l:	cpy tmp1
	beq @r
	lda (ptr1),y
	cmp #32
	bcc @r
	cmp #127
	bcs @r
	iny
	bne @l
@r:	tya
	ldx #0
	rts

