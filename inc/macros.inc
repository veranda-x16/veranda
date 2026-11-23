; Veranda: assembly macros (kernel and SDK)

.ifndef MACROS_INC
MACROS_INC = 1

.macro LoadB dest, value
	lda #value
	sta dest
.endmacro

.macro LoadW dest, value
	lda #<(value)
	sta dest
	lda #>(value)
	sta dest+1
.endmacro

.macro MoveB source, dest
	lda source
	sta dest
.endmacro

.macro MoveW source, dest
	lda source
	sta dest
	lda source+1
	sta dest+1
.endmacro

.macro PushW source
	lda source+1
	pha
	lda source
	pha
.endmacro

.macro PopW dest
	pla
	sta dest
	pla
	sta dest+1
.endmacro

.macro AddW source, dest
	lda source
	clc
	adc dest
	sta dest
	lda source+1
	adc dest+1
	sta dest+1
.endmacro

.macro AddVW value, dest
	lda dest
	clc
	adc #<(value)
	sta dest
	lda dest+1
	adc #>(value)
	sta dest+1
.endmacro

.macro SubW source, dest
	lda dest
	sec
	sbc source
	sta dest
	lda dest+1
	sbc source+1
	sta dest+1
.endmacro

.macro IncW dest
	inc dest
	bne :+
	inc dest+1
:
.endmacro

; compare words: c set if a >= b, z set if equal
.macro CmpW left, right
	lda left+1
	cmp right+1
	bne :+
	lda left
	cmp right
:
.endmacro

.macro CmpWI left, value
	lda left+1
	cmp #>(value)
	bne :+
	lda left
	cmp #<(value)
:
.endmacro

.endif
