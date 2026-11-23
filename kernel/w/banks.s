; Veranda bank W: RAM banks for applications and the kernel's own data
; (record files, overlays); in bank S until the switcher (DECISIONS V83)
;
; Banks 2 .. kBankBase - KCOPY_BANKS - 1 are handed out (bank 0 is the
; KERNAL's, bank 1 the application's own: appBank; the kernel banks'
; pristine copy is under them, DECISIONS V50); a bitmap, and the runs given out (their
; first bank and count) so that BankFree needs only the first. The banks
; of the applications put aside (tb, kernel/w/task.s) stay used across
; programs, as the fonts' do, and are never spare.

.include "kernel.inc"

.export k_BankAlloc, k_BankFree, BanksInit, used, runF, runN, keep, spare, tb, FontBanks
.export TakeBank, FreeCount, BankBit, GiveSpare
.import kBankBase, Roomy, EvictAny, CardOff, CardOn, daOn

RUNS = 24

.segment "BSS"

used:	.res 32                 ; bit per bank
runF:	.res RUNS               ; a run's first bank (0: free entry)
runN:	.res RUNS
want:	.res 1
first:	.res 1
; the font service's banks (bank T, DECISIONS V62): kept across programs
; (BanksInit leaves them used); spare: those no program has asked for
; since the current one started, given up when an allocation fails
keep:	.res 32
spare:	.res 32
fcnt:	.res 1
tmpOp:	.res 1
noRes	= tmpOp                 ; (V145) $80: BankAlloc's try without Leave2
				; (FontBanks sets tmpOp after BankAlloc)
tb:	.res 32                 ; the banks of the tasks put aside (V83)


.segment "CODE"

BanksInit:
	ldx #31
@1:	lda tb,x                ; (the tasks' banks: kept, and their fonts not
	eor #$FF                ; spare, V83)
	and keep,x
	sta spare,x
	lda keep,x
	ora tb,x
	sta used,x
	dex
	bpl @1
	ldx #RUNS - 1
@2:	stz runF,x
	dex
	bpl @2
	rts

; x = bank -> a = its bit, y = its byte
BankBit:	txa
	lsr
	lsr
	lsr
	tay
	txa
	and #7
	tax
	lda #$80
@1:	dex
	bmi @2
	lsr
	bra @1
@2:	rts

; a count -> a first bank, x 0; or x NO_BANKS. When none are free, the
; fonts no program asked for since the current one started are given up
; (spare), once, and the search starts again.
k_BankAlloc:
	sta want
	cmp #0
	bne @n0
	ldx #NO_BANKS           ; (a = 0)
	rts
@n0:	sta fcnt
	stz noRes
@alloc:	jsr Leave2              ; (V145) Roomy: two banks left free if it can
	bcs @none
	ldx #2
@try:	stx first
	ldy want
@chk:	txa
	clc
	adc #KCOPY_BANKS
	cmp kBankBase
	bcs @none               ; up to the kernel banks' copy (V50)
	phx
	phy
	jsr BankBit
	and used,y
	ply
	plx
	cmp #0                  ; (the pulls changed the flags)
	bne @next
	inx
	dey
	bne @chk
	; found: a run entry, then mark
	ldy #RUNS - 1
@e:	lda runF,y
	beq @take
	dey
	bpl @e
	bra @none
@take:	lda first
	sta runF,y
	lda want
	sta runN,y
	ldx first
@m:	phx
	jsr BankBit
	ora used,y
	sta used,y
	plx
	inx
	dec want
	bne @m
	lda first
	ldx #0
	rts
@next:	inx                     ; past the used bank
	bra @try
@none:	jsr GiveSpare           ; spare fonts: given up, then again
	bcc @again
	jsr Roomy               ; (V145) Roomy: a program aside in RAM goes
	bcc @no                 ; to the card, then again
	jsr EvictAny
	bcc @again
	bit noRes               ; nothing else: the switcher's two banks too
	bmi @no                 ; (a program that takes them is asked to quit
	bit daOn                ; at Alt+Tab, as before V145); never a font's
	bvs @no                 ; (V183: a task on the card needs them back)
	dec noRes
@again:	lda fcnt
	sta want
	jmp @alloc
@no:	ldx #NO_BANKS
	lda #0
	rts

; (V145) c set when the switcher is Roomy and fewer than fcnt + 2 banks
; are free: Roomy puts a program aside onto the card through two banks of
; its own (the context and the data that streams), which a program takes
; only when nothing else is left (noRes: BankAlloc's last try)
Leave2:	bit noRes
	bmi @ok
	jsr Roomy
	bcc @r
	jsr FreeCount
	sbc #2                  ; (c set)
	bcc @no
	cmp fcnt
	bcs @ok
@no:	sec
	rts
@ok:	clc
@r:	rts

; the spare fonts given up (their banks free, no longer kept): c clear,
; or c set if there were none (V145: also the switcher's, before it
; counts the free banks)
GiveSpare:
	ldx #31
	lda #0
@sp:	ora spare,x
	dex
	bpl @sp
	cmp #0
	beq @no
	ldx #31
@sf:	lda spare,x
	eor #$FF
	tay
	and used,x
	sta used,x
	tya
	and keep,x
	sta keep,x
	stz spare,x
	dex
	bpl @sf
	clc
	rts
@no:	sec
	rts

; the font service's banks (bank T): x = 0: a banks kept (as BankAlloc:
; a first, x 0 or NO_BANKS; no run entry: BankFree and the next program's
; start leave them); x = 1: banks a .. a + y - 1 freed; x = 2: they are in
; use by the current program (not spare); x = 3: a <> 0 if bank a is kept;
; x = 4: a <> 0 if bank a is spare (no program asked for it since the
; current one started: V68)
FontBanks:
	cpx #0
	bne @op
	sta fcnt
	jsr CardOff             ; (V183) not in a task's banks on the card
	lda fcnt
	jsr k_BankAlloc
	jsr CardOn
	cpx #0
	bne @r
	sta first
	ldy #RUNS - 1           ; its run entry goes
@e:	cmp runF,y
	beq @d
	dey
	bpl @e
@d:	lda #0
	sta runF,y
	lda fcnt
	tay
	lda first
	ldx #0                  ; keep: set
@op:	sta want
	sty fcnt
	stx tmpOp
	cpx #3
	bcs @kept               ; 3 kept, 4 spare
@m:	ldx want
	jsr BankBit             ; a bit, y byte
	ldx tmpOp
	beq @keep
	dex
	beq @free
	eor #$FF                ; 2: not spare
	and spare,y
	sta spare,y
	bra @nx
@free:	eor #$FF
	pha
	and used,y
	sta used,y
	pla
	pha
	and keep,y
	sta keep,y
	pla
	and spare,y
	sta spare,y
	bra @nx
@keep:	pha
	ora keep,y
	sta keep,y
	pla
	eor #$FF
	and spare,y
	sta spare,y
@nx:	inc want
	dec fcnt
	bne @m
	lda first
	ldx #0
@r:	rts
@kept:	tax
	jsr BankBit
	ldx tmpOp
	cpx #4
	beq @spare
	and keep,y
	rts
@spare:	and spare,y
	rts

; a first bank (as BankAlloc gave it)
k_BankFree:
	ldy #RUNS - 1
@e:	cmp runF,y
	beq @f
	dey
	bpl @e
	rts
@f:	tax
	lda #0
	sta runF,y
	lda runN,y
	sta want
@c:	phx
	jsr BankBit
	eor #$FF
	and used,y
	sta used,y
	plx
	inx
	dec want
	bne @c
	rts

; TakeBank (the switcher's packed data, V83): a free bank, no run entry
; (the task's own list frees it), as long as more than a stay free:
; a = the bank, x = 0; else x = NO_BANKS
TakeBank:
	sta want
	jsr FreeCount
	cmp want
	beq @no
	bcc @no
	ldx #2
@t:	txa
	clc
	adc #KCOPY_BANKS
	cmp kBankBase
	bcs @no
	phx
	jsr BankBit
	and used,y
	plx
	cmp #0
	beq @got
	inx
	bra @t
@got:	phx
	jsr BankBit
	ora used,y
	sta used,y
	pla
	ldx #0
	rts
@no:	ldx #NO_BANKS
	rts

; FreeCount: a = the free banks, y = the banks there are for programs
FreeCount:
	stz first
	ldy #0
	ldx #2
@c:	txa
	clc
	adc #KCOPY_BANKS
	cmp kBankBase
	bcs @r
	iny
	phx
	phy
	jsr BankBit
	and used,y
	ply
	plx
	cmp #0
	bne @n
	inc first
@n:	inx
	bra @c
@r:	lda first
	rts
