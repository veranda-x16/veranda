; Calculator: the X16 ROM's maths library (ROM bank 4, its jump table at
; $FE00; x16-rom math/jumptab.s), as VeraBASIC Run calls it (DECISIONS
; V86, sdk/docs/GUIDE.md): the bank mapped with the interrupt off (it has
; no interrupt vectors), its errors through BASIC's error vector ($0300)
; to fp_err here, which takes the stack back and returns the error. The
; library's zero page is $A9-$D3 (calc.cfg keeps cc65's out of it); what
; it keeps in main RAM ($0300-$0301 the vector, $03CA-$03CE its
; variables) is put back after every call, so the application under the
; accessory finds them as they were.
;
;   unsigned char __fastcall__ fp_run(unsigned int op);
;       op: the routine's low byte ($FE00 + op), the high byte the kind:
;       0 fa = f(fa); 1 fa = fa op fb (ARG = fa, FAC = fb: faddt, fsubt
;       a - b, fmultt, fdivt a / b, fpwrt a ^ b). Returns 0, or the
;       library's error (14 illegal quantity, 15 overflow, 20 division by
;       zero).
;
; fa, fb: 5-byte packed floats (the exponent + 128, then the mantissa,
; its top bit the sign). Numbers as text are calc.c's (exact; not fout).
; MIT licence (see LICENSE).

	.export _fp_run, _fa, _fb

ROM_BANK = $01
IERROR   = $0300
FPVARS   = $03CA                ; integr, tansgn, (pad), bits, rndx
FACEXP   = $C3
MATHBANK = 4
CONUPK   = $FE5A
MOVFM    = $FE63
MOVMF    = $FE66

	.segment "BSS"
_fa:	.res 5
_fb:	.res 5
keep_rom: .res 1
keep_ie:  .res 2
keep_v:   .res 5
keep_sp:  .res 1
kind:	.res 1
result:	.res 1

	.segment "CODE"

_fp_run:
	sta call+1
	stx kind
	php
	sei
	lda ROM_BANK
	sta keep_rom
	lda IERROR
	sta keep_ie
	lda IERROR+1
	sta keep_ie+1
	ldx #4
@k:	lda FPVARS,x
	sta keep_v,x
	dex
	bpl @k
	lda #<fp_err
	sta IERROR
	lda #>fp_err
	sta IERROR+1
	tsx
	stx keep_sp
	lda #MATHBANK
	sta ROM_BANK
	lda kind
	beq @un
	lda #<_fa                       ; ARG = a
	ldy #>_fa
	jsr CONUPK
	lda #<_fb                       ; FAC = b
	ldy #>_fb
	jsr MOVFM
	lda FACEXP                      ; (the fixed entries want a = the exponent, its flags)
	bra @go
@un:	lda #<_fa
	ldy #>_fa
	jsr MOVFM
@go:	jsr call
	ldx #<_fa
	ldy #>_fa
	jsr MOVMF
	lda #0
done:	sta result
	lda keep_rom
	sta ROM_BANK
	lda keep_ie
	sta IERROR
	lda keep_ie+1
	sta IERROR+1
	ldx #4
@r:	lda keep_v,x
	sta FPVARS,x
	dex
	bpl @r
	plp
	lda result
	ldx #0
	rts

call:	jmp $FE00                       ; (its low byte set above)

; the library's error: x its number; the stack as it was at the call
fp_err:	txa
	ldx keep_sp
	txs
	bra done
