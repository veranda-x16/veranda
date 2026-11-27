; vrnet's CRC-8 (Dallas/Maxim, vrnet.c's table) over a packet's payload,
; in assembly (DECISIONS V210: every byte of a download goes through it;
; the C loop took some 60 cycles a byte, this one some 17). MIT licence
; (see LICENSE).
;
;   unsigned char __fastcall__ net_crc8(unsigned char n)
;       over STAGE's first n bytes ($A100) with the table CRCTAB ($A000),
;       vrnet's bank mapped (its step); 0 for none

.export _net_crc8
.importzp tmp1

CRCTAB = $A000
STAGE  = $A100

.segment "CODE"

_net_crc8:
	sta tmp1
	tay
	beq @r                  ; (A 0)
	lda #0
	ldy #0
@l:	eor STAGE,y
	tax
	lda CRCTAB,x
	iny
	cpy tmp1
	bne @l
@r:	ldx #0
	rts
