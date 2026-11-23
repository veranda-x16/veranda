; Veranda bank G2: the small classic calls that need no more (written from
; the GEOS programmer's reference; the maths calls are in bank S since
; DECISIONS V81: kernel/s/math.s)

.include "kernel.inc"

.export k_GetRandom, k_GetSerialNumber, k_InitForIO, k_DoneWithIO

; random: the next of a 16-bit xorshift (never 0)
k_GetRandom:
	lda random
	ora random+1
	bne @1
	inc random
@1:	lda random+1            ; x ^= x << 7
	lsr
	lda random
	ror
	eor random+1
	sta random+1
	ror
	eor random
	sta random              ; x ^= x >> 9
	lda random+1
	eor random              ; x ^= x << 8
	sta random+1
	rts

; GEOS's serial number: Veranda has none, a constant
k_GetSerialNumber:
	lda #<$5652
	sta r0L
	lda #>$5652
	sta r0H
	rts

; GEOS 64 switched the C64's I/O in and out around disk access
k_InitForIO:
k_DoneWithIO:
	rts
