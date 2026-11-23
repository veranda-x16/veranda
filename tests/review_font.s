; gate review (DECISIONS V68): the font table (finding 4) and LoadFont's
; banks (finding 5c); the fonts from tests/review_fixture.py fonts.
;
;   BIG e g        Rev Big 9 (a record of 8200 bytes: two banks) loaded with
;                  a guard bank right after a free one: e its error, g the
;                  guard's first 256 bytes intact (00) or not (FF)
;   TY e           Rev Tiny 9 (211 bytes): its error
;   LF s h e       20 sizes loaded (Rev A 10-19, Rev B 20-29): size,
;                  handle, error
;   FI s h z       then FontInfo of each handle given: the size it reports
;   UF e           UseFont of the first again
; -D APP (AUTOSTART.cvt): then the program again (dataFileName "1"): Rev C
; 10-19 loaded over the first run's fonts, spare now ("LC s h e"), and
; FontInfo of each ("FC s h z e")

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

.ifdef APP
Start:	lda dataFileName        ; the second run: Rev C over the spare ones
	cmp #'1'
	bne First
	jmp Run2
First:
.else
Start:
.endif
	; the guard: g1 free, g2 right after it, filled
	lda #1
	jsr BankAlloc
	sta g1
	lda #1
	jsr BankAlloc
	sta g2
	jsr Guard
	lda g1
	jsr BankFree
	LoadW r0, NBig
	lda #9
	jsr LoadFont
	stx e
	jsr NL
	lda #'B'
	jsr Put
	lda #'I'
	jsr Put
	lda #'G'
	jsr Put
	lda e
	jsr Hex
	ldx #0                  ; the guard still $5A?
	php
	sei
	lda g2
	sta ram_bank
	lda #0
@g:	ldy $A000,x
	cpy #$5A
	beq @g1
	lda #$FF
@g1:	inx
	bne @g
	ldy #1
	sty ram_bank
	plp
	jsr Hex
	jsr NL
	; a record under 256 bytes (one bank, not none)
	LoadW r0, NTiny
	lda #9
	jsr LoadFont
	stx e
	jsr NL
	lda #'T'
	jsr Put
	lda #'Y'
	jsr Put
	lda e
	jsr Hex
	jsr NL

	; 20 sizes
	stz i
@l:	lda i
	clc
	adc #10
	sta s
	LoadW r0, NA
	lda i
	cmp #10
	bcc @a
	LoadW r0, NB
@a:	lda s
	jsr LoadFont
	ldy i
	sta hs,y
	stx e
	jsr NL
	lda #'L'
	jsr Put
	lda #'F'
	jsr Put
	lda s
	jsr Hex
	ldy i
	lda hs,y
	jsr Hex
	lda e
	jsr Hex
	jsr NL                  ; (the DOS's seek is echoed after it)
	inc i
	lda i
	cmp #20
	bne @l
	; what each handle is now
	stz i
@f:	ldy i
	lda hs,y
	cmp #FONT_NONE
	beq @fn
	LoadW r0, 0
	ldy i
	lda hs,y
	jsr FontInfo
	sta s
	stx e
	jsr NL
	lda #'F'
	jsr Put
	lda #'I'
	jsr Put
	lda i
	clc
	adc #10
	jsr Hex
	ldy i
	lda hs,y
	jsr Hex
	lda s
	jsr Hex
	lda e
	jsr Hex
@fn:	inc i
	lda i
	cmp #20
	bne @f
	jsr NL
	lda #'U'
	jsr Put
	lda #'F'
	jsr Put
	lda hs
	jsr UseFont
	txa
	jsr Hex
	jsr UseSystemFont
	jsr NL
.ifdef APP
	LoadW r6, NAuto         ; again, as the next program
	LoadW r3, Doc
	LoadB r0L, ST_LD_DATA
	jsr GetFile
	jmp Stop

; the fonts of the first run are spare now: Rev C 10-19 loaded
; ("LC s h e"), then what each handle is ("FC s h z e")
Run2:	stz i
@l:	lda i
	clc
	adc #10
	sta s
	LoadW r0, NCc
	lda s
	jsr LoadFont
	ldy i
	sta hs,y
	stx e
	jsr NL
	lda #'L'
	jsr Put
	lda #'C'
	jsr Put
	lda s
	jsr Hex
	ldy i
	lda hs,y
	jsr Hex
	lda e
	jsr Hex
	jsr NL
	inc i
	lda i
	cmp #10
	bne @l
	stz i
@f:	LoadW r0, 0
	ldy i
	lda hs,y
	jsr FontInfo
	sta s
	stx e
	jsr NL
	lda #'F'
	jsr Put
	lda #'C'
	jsr Put
	lda i
	clc
	adc #10
	jsr Hex
	ldy i
	lda hs,y
	jsr Hex
	lda s
	jsr Hex
	lda e
	jsr Hex
	inc i
	lda i
	cmp #10
	bne @f
	jsr NL
.endif
	LoadW r0, TDone
	jsr LogText
Stop:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; bank g2's first 256 bytes = $5A
Guard:	php
	sei
	lda g2
	sta ram_bank
	ldx #0
	lda #$5A
@1:	sta $A000,x
	inx
	bne @1
	lda #1
	sta ram_bank
	plp
	rts

Put:	sta EMU_STDOUT
	rts
NL:	lda #10
	bra Put
Hex:	pha
	lda #' '
	jsr Put
	pla
	pha
	lsr
	lsr
	lsr
	lsr
	jsr @n
	pla
	and #$0F
@n:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	bra Put

.segment "DATA"

g1:	.byte 0
g2:	.byte 0
e:	.byte 0
i:	.byte 0
s:	.byte 0
hs:	.res 20

.segment "RODATA"

NA:	.byte "Rev A", 0
NB:	.byte "Rev B", 0
NBig:	.byte "Rev Big", 0
NTiny:	.byte "Rev Tiny", 0
NCc:	.byte "Rev C", 0
NAuto:	.byte "AUTOSTART", 0
Doc:	.byte "1", 0
TDone:	.byte "FONT DONE", 0
