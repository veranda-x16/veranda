; gate boot: BankCopy (DECISIONS V158), run as TEST.PRG
;
; Built twice: as it is the copies go through the kernel's BankCopy, with
; -D REF through RefCopy below, the kernel's BankCopy before V158 (byte by
; byte, the banks switched for every byte) as it was. Both runs draw the
; same NCASE random copies (from RAM below $A000 or a test bank, to RAM
; below $A000 or a test bank; 0 to 8191 bytes, into the next bank;
; overlapping ones forwards and backwards, in one bank and across two) on
; the same noise, and log after each the registers kept and a sum of the
; destination's bytes; at the end a sum of the whole test area. The gate
; compares the two consoles: they must be the same.
;
; Then the timings, interrupts off, 8192 bytes: TIME <name> <cycles, hex>
; (lo2bank, bank2lo, bank2bank, samebank; V187: 16 bytes, a page, 8 KB
; not on page boundaries, a bank to another into their next ones), the
; kernel's and RefCopy's.
; Console: BC <case> <a> <y> <bank> <r0-r4> <sum>, BC AREA <sum>, BC DONE.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

NCASE = 600
LO    = $3000                   ; the RAM below $A000: LO .. LOEND - 1
LOEND = $5000
NBANK = 4
kp    = $70                     ; (zero page)

.segment "CODE"

Start:
	lda #10                 ; (a line of its own)
	sta EMU_STDOUT
	lda #NBANK
	jsr BankAlloc
	cpx #0
	beq @ok
	LoadW r0, MsgNoBank
	jsr Log
	jmp Quit
@ok:	sta tb
	jsr Noise
	stz ncase
	stz ncase+1
@case:	jsr Pick
	jsr Rnd                 ; a and y in: kept or not
	sta vA
	jsr Rnd
	sta vY
	lda ram_bank
	sta inBank
	lda vA
	ldy vY
	jsr Copy
	sta outA
	sty outY
	lda ram_bank
	sta outBank
	; BC case a y bank r0 r1 r2 r3 r4 sum
	LoadW r15, MsgBC
	jsr Log15
	lda ncase+1
	jsr LogHex
	lda ncase
	jsr LogHex
	jsr Space
	lda outA
	jsr LogHex
	jsr Space
	lda outY
	jsr LogHex
	jsr Space
	lda outBank
	cmp inBank
	beq @b
	lda #'!'
	sta EMU_STDOUT
@b:	jsr Space
	ldx #0
@r:	lda r0+1,x
	jsr LogHex
	lda r0,x
	jsr LogHex
	jsr Space
	inx
	inx
	cpx #10
	bne @r
	jsr SumDest
	jsr LogSum
	lda #10
	sta EMU_STDOUT
	inc ncase
	bne @n
	inc ncase+1
@n:	lda ncase
	cmp #<NCASE
	bne @again
	lda ncase+1
	cmp #>NCASE
	beq @end
@again:	jmp @case
@end:
	; the whole area
	LoadW r15, MsgArea
	jsr Log15
	jsr SumArea
	jsr LogSum
	lda #10
	sta EMU_STDOUT
	jsr Timings
	LoadW r15, MsgDone
	jsr Log15
	lda #10
	sta EMU_STDOUT
Quit:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; the copy under test (or the reference)
Copy:
.ifdef REF
	jmp RefCopy
.else
	jmp BankCopy
.endif

;---------------------------------------------------------------
; a random case: r0, r1, r2, r3L, r3H (and r4 noise, kept)
;---------------------------------------------------------------
Pick:	jsr Rnd                 ; the count: 0 (1/16), 1-16, 17-1023,
	and #15                 ; 1024-8191
	sta cnt
	stz cnt+1
	beq @ce
	jsr Rnd
	and #3
	beq @c1
	cmp #3
	beq @c3
	jsr Rnd                 ; 17-1023
	sta cnt
	jsr Rnd
	and #3
	sta cnt+1
	bra @ce
@c3:	jsr Rnd                 ; up to 8191 (half of these)
	sta cnt
	jsr Rnd
	and #$1F
	sta cnt+1
	bra @ce
@c1:	inc cnt                 ; 1-16
@ce:	jsr Rnd                 ; the source: low or a bank
	and #1
	sta sKind
	jsr Rnd
	and #1
	sta dKind
	lda sKind
	jsr Side                ; the source
	MoveW sv, r0
	MoveB sb, r3L
	jsr Rnd                 ; an overlap (1/4): the destination near the source
	and #3
	beq @near
	jmp @far
@near:	lda sKind
	sta dKind
	jsr Rnd                 ; source + (-24 .. 23)
	and #$2F
	sec
	sbc #24
	sta dtmp
	ldx #0
	cmp #$80
	bcc @p
	dex
@p:	lda r0L
	clc
	adc dtmp
	sta r1L
	txa
	adc r0H
	sta r1H
	MoveB r3L, r3H
	lda dKind               ; in a bank: $A000 .. $BFFF, or the bank before
	beq @lo                 ; or after
	lda r1H
	cmp #$A0
	bcs @hi
	adc #$20
	sta r1H
	dec r3H
	lda r3H                 ; (before the first test bank: its start)
	cmp tb
	bcs @fit
	MoveB tb, r3H
	LoadW r1, $A000
	bra @fit
@hi:	cmp #$C0
	bcc @fit
	sbc #$20
	sta r1H
	inc r3H
	bra @fit
@lo:	CmpWI r1, LO            ; low: in the area
	bcs @lo2
	LoadW r1, LO
@lo2:	CmpWI r1, LOEND
	bcc @fit
	LoadW r1, LOEND - 1
	bra @fit
@far:	lda dKind
	jsr Side                ; the destination anywhere
	MoveW sv, r1
	MoveB sb, r3H
@fit:	; the count: low sides end at LOEND, banked ones in the last bank
	lda sKind
	ldx #r0
	ldy r3L
	jsr Clamp
	lda dKind
	ldx #r1
	ldy r3H
	jsr Clamp
	MoveW cnt, r2
	jsr Rnd
	sta r4L
	jsr Rnd
	sta r4H
	rts

; a side (kind in a: 0 low, 1 banked) -> sv, sb
Side:	beq @lo
	jsr Rnd
	sta sv
	jsr Rnd
	and #$1F
	ora #$A0
	sta sv+1
	jsr Rnd
	and #3
	cmp #NBANK - 1
	bcc @b
	lda #0
@b:	clc
	adc tb
	sta sb
	rts
@lo:	jsr Rnd
	sta sv
	jsr Rnd
	and #$1F
	clc
	adc #>LO
	sta sv+1
	jsr Rnd
	sta sb                  ; (the bank: any)
	rts

; cnt = at most the room after the side at zero page x (kind a, bank y)
Clamp:	cmp #0
	bne @bk
	lda #<LOEND             ; LOEND - address
	sec
	sbc 0,x
	sta dtmp
	lda #>LOEND
	sbc 1,x
	bra @m
@bk:	tya                     ; the room: (last bank + 1 - bank) * 8192
	eor #$FF                ; + $A000 - address
	sec
	adc tb
	clc
	adc #NBANK              ; (banks after this one, with it)
	asl
	asl
	asl
	asl
	asl
	sta dtmp+1
	lda #0
	sec
	sbc 0,x
	sta dtmp
	lda dtmp+1
	sbc 1,x
	clc
	adc #$A0
@m:	sta dtmp+1
	CmpW cnt, dtmp
	bcc @r
	MoveW dtmp, cnt
@r:	rts

;---------------------------------------------------------------
; the noise in the area: LO .. LOEND - 1 and the test banks
;---------------------------------------------------------------
Noise:	LoadW nseed, $6B3D
	LoadW kp, LO
@l:	jsr NRnd
	sta (kp)
	IncW kp
	CmpWI kp, LOEND
	bne @l
	lda ram_bank
	pha
	lda tb
	sta bk
@bk:	lda bk
	sta ram_bank
	LoadW kp, $A000
@b:	jsr NRnd
	sta (kp)
	IncW kp
	lda kp+1
	cmp #$C0
	bne @b
	inc bk
	lda bk
	sec
	sbc tb
	cmp #NBANK
	bne @bk
	pla
	sta ram_bank
	rts

; sum (s1, s2) of the destination's r2 bytes: r1, bank r3H as they were
; (BankCopy keeps them)
SumDest:
	stz s1
	stz s2
	MoveW r1, kp
	MoveW r2, kn
	lda r3H
	sta bk
	lda ram_bank
	pha
@l:	lda kn
	ora kn+1
	beq @r
	lda bk
	sta ram_bank
	lda (kp)
	jsr Add
	IncW kp
	lda kp+1
	cmp #$C0
	bne @n
	lda #$A0
	sta kp+1
	inc bk
@n:	lda kn
	bne @d
	dec kn+1
@d:	dec kn
	bra @l
@r:	pla
	sta ram_bank
	rts

SumArea:
	stz s1
	stz s2
	LoadW kp, LO
@l:	lda (kp)
	jsr Add
	IncW kp
	CmpWI kp, LOEND
	bne @l
	lda ram_bank
	pha
	lda tb
	sta bk
@bk:	lda bk
	sta ram_bank
	LoadW kp, $A000
@b:	lda (kp)
	jsr Add
	IncW kp
	lda kp+1
	cmp #$C0
	bne @b
	inc bk
	lda bk
	sec
	sbc tb
	cmp #NBANK
	bne @bk
	pla
	sta ram_bank
	rts

Add:	clc
	adc s1
	sta s1
	clc
	adc s2
	sta s2
	rts

LogSum:	lda s2
	jsr LogHex
	lda s1
	jmp LogHex

;---------------------------------------------------------------
; the timings: 8192 bytes each way, the kernel's and RefCopy's
;---------------------------------------------------------------
Timings:
	ldx #0
@t:	stx tn
	lda TDesc,x             ; source, destination, banks (+ tb)
	sta r0L
	lda TDesc+1,x
	sta r0H
	lda TDesc+2,x
	sta r1L
	lda TDesc+3,x
	sta r1H
	lda TDesc+4,x
	clc
	adc tb
	sta r3L
	lda TDesc+5,x
	clc
	adc tb
	sta r3H
	lda TDesc+6,x
	sta r2L
	lda TDesc+7,x
	sta r2H
	sei
	sta EMU_CLOCK
	jsr BankCopy
	jsr Latch
	cli
	jsr TNameX
	ldx #'k'
	jsr Report
	sei
	sta EMU_CLOCK
	jsr RefCopy
	jsr Latch
	cli
	jsr TNameX
	ldx #'r'
	jsr Report
	lda tn
	clc
	adc #8
	tax
	cpx #TDescEnd - TDesc
	bne @t
	rts

TNameX:	lda tn
	lsr
	lsr
	tax
	lda TName,x
	ldy TName+1,x
	rts

Latch:	lda EMU_CLOCK
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	rts

; "TIME <x>_<name at a/y> <cycles>"
Report:	sta r15L
	sty r15H
	phx
	LoadW r14, MsgTime
	jsr Log14
	pla
	sta EMU_STDOUT
	lda #'_'
	sta EMU_STDOUT
	jsr Log15
	jsr Space
	ldx #3
@c:	lda clk,x
	jsr LogHex
	dex
	bpl @c
	lda #10
	sta EMU_STDOUT
	rts

;---------------------------------------------------------------
; RefCopy: the kernel's BankCopy before V158, as it was
;---------------------------------------------------------------
RefCopy:
	lda ram_bank
	pha
	PushW r0
	PushW r1
	PushW r2
	lda r3L
	pha
	lda r3H
	pha
@loop:	lda r2L
	ora r2H
	beq @done
	lda r3L
	sta ram_bank
	lda (r0)
	ldx r3H
	stx ram_bank
	sta (r1)
	inc r0L                 ; source + 1
	bne @s
	inc r0H
	lda r0H
	cmp #$C0
	bne @s
	lda #$A0
	sta r0H
	inc r3L
@s:	inc r1L                 ; destination + 1
	bne @d
	inc r1H
	lda r1H
	cmp #$C0
	bne @d
	lda #$A0
	sta r1H
	inc r3H
@d:	lda r2L                 ; count - 1
	bne @c
	dec r2H
@c:	dec r2L
	bra @loop
@done:	pla
	sta r3H
	pla
	sta r3L
	PopW r2
	PopW r1
	PopW r0
	pla
	sta ram_bank
	rts

;---------------------------------------------------------------
; the generators and the console
;---------------------------------------------------------------
Rnd:	lda rs
	asl
	rol rs+1
	bcc @1
	eor #$2D
@1:	sta rs
	eor rs+1
	rts
NRnd:	lda nseed
	asl
	rol nseed+1
	bcc @1
	eor #$39
@1:	sta nseed
	adc nseed+1
	rts

Log:	MoveW r0, r15
Log15:	ldy #0
@1:	lda (r15),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts
Log14:	ldy #0
@1:	lda (r14),y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	rts
Space:	lda #' '
	sta EMU_STDOUT
	rts
LogHex:	pha
	lsr
	lsr
	lsr
	lsr
	jsr @d
	pla
	and #$0F
@d:	cmp #10
	bcc @1
	adc #'A' - '0' - 10 - 1
@1:	adc #'0'
	sta EMU_STDOUT
	rts

.segment "RODATA"

; source, destination, banks (from tb), count
TDesc:	.word LO, $A000
	.byte 0, 0
	.word 8192
	.word $A000, LO
	.byte 0, 0
	.word 8192
	.word $A000, $A000
	.byte 0, 1
	.word 8192
	.word $A000, $B000
	.byte 2, 2
	.word 4096
	.word LO, $A000         ; (V187) 16 bytes
	.byte 0, 0
	.word 16
	.word LO, $A000         ; a page
	.byte 0, 0
	.word 256
	.word LO + 3, $A005     ; 8 KB, not on page boundaries
	.byte 0, 0
	.word 8192
	.word $B100, $B800      ; from a bank to another, both into their next
	.byte 0, 1
	.word 8192
TDescEnd:
TName:	.word N1, N2, N3, N4, N5, N6, N7, N8
N1:	.byte "lo2bank", 0
N2:	.byte "bank2lo", 0
N3:	.byte "bank2bank", 0
N4:	.byte "samebank4k", 0
N5:	.byte "lo2bank16", 0
N6:	.byte "lo2bank256", 0
N7:	.byte "odd8k", 0
N8:	.byte "bank2bankx", 0
MsgBC:	.byte "BC ", 0
MsgArea: .byte "BC AREA ", 0
MsgDone: .byte "BC DONE", 0
MsgTime: .byte "TIME ", 0
MsgNoBank: .byte "BC NO BANKS", 10, 0

.segment "DATA"

rs:	.word $ACE1

.segment "BSS"

tb:	.res 1
ncase:	.res 2
cnt:	.res 2
sKind:	.res 1
dKind:	.res 1
sv:	.res 2
sb:	.res 1
dtmp:	.res 2
nseed:	.res 2
kn:	.res 2
bk:	.res 1
s1:	.res 1
s2:	.res 1
vA:	.res 1
vY:	.res 1
inBank:	.res 1
outA:	.res 1
outY:	.res 1
outBank: .res 1
tn:	.res 1
clk:	.res 4
