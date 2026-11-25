; Veranda bank W: the switcher (DECISIONS V83)
;
; One full-screen application at a time, the others put aside whole into
; RAM banks, Switcher-style. switchReq (Alt + Tab: bank X's KeyPut;
; TaskCtl TASK_ASIDE) is seen by ClockPoll (bank S) at the main loop's
; top level, where nothing of the application is on the stack, the C
; stack is empty and r0-r15 are dead: TC_POLL puts the application aside
; and starts the desktop (EnterDeskTop), whose dock shows it; TaskCtl
; TASK_RESUME (the dock) ends the caller as GetFile would and brings the
; task back to the top of its main loop.
;
; A task's RAM banks: a chain (the first is its context bank) and its own
; banks, which it keeps (overlays, its open record file, what it asked
; for, the fonts it uses); tb (kernel/w/banks.s) has them all, so that
; BanksInit keeps them used and their fonts never spare.
;
; The context bank:
;   $A000 "VTSK", $A004 the chain's count, $A005 its banks (CHAIN_MAX)
;   CTX   the context (Ctx: zero page, $0400-$07FF, the sleeping routines,
;         the menu rectangle, the font, bank U's timer, the processes, the
;         VERA registers, sprites 0-7, palette entries 0-15, the colour
;         map's state, the name, the bank table)
;   FREC  bank F's record file and the program's overlays (RecVars,
;         LdVars: kgen/kvars.inc)
;   STREAM, and on into the chain's banks: the packed pages (bank C's pack.s, V189): the
;         application's RAM, VRAM, bank 1, bank U
; Not kept: what is live (the pointer, the buttons and keys, the clock,
; random), r0-r15, open streams or a listing (such a program is asked to
; quit instead), the PSG, the PCM's FIFO.
;
; (V145) The system variables ($0400-$07FF) go straight into the context
; bank (VARS), not through bank W. Roomy mode (the settings' PREFS_SWITCH;
; by default below 2 MB): a program that does not fit in the free banks
; with the desktop's reserve goes to the card instead, one file a task,
; /VERANDA/.SYSTEM/TASKS/T<slot>: its own banks but the fonts (in order),
; then its context bank and its packed pages, which stream through one
; rolling bank (TC_TAKE writes a full bank, TC_NEXT reads the next); then
; all those banks are free. Bringing it back reads the own banks into the
; same banks (the programs aside in RAM that hold one go to the card
; first, the fonts nobody holds are given up), the context bank into any
; free bank (the chain's list is only the context bank there), and the
; pages stream back; the file is deleted. Its fonts stay in RAM while it
; is on the card (tb). BankAlloc (Roomy) leaves two banks free for that
; and puts programs aside in RAM onto the card when it runs out. Stale
; files are deleted at the first start (Start).

.include "kernel.inc"
.include "kvars.inc"

.export k_TaskCtl, Roomy, EvictAny, CardOff, CardOn, daOn
.import used, runF, runN, keep, spare, tb, TakeBank, FreeCount, k_BankFree, BankBit, GiveSpare
.import XferIn, XferOut, kXA, kXN, kXB, kName, VramBank, kPrefs
.import kBankBase, k_BankCopy, kMenuRect, sysFont, uiTimer, uiWake, SleepN, kAppName
.import k_MainLoop, k_CallRoutine, LogStr, LogNL, IsEmu, kSndReq
.global S_ProcOut, S_ProcIn, S_k_DoDlgBox, S_k_EnterDeskTop, S_k_SetVideoMode, S_FontSel
.global S_k_ChDir, S_AudioReset, S_k_CloseRecordFile, S_k_FClose, S_PrReset
.global S_k_FOpen, S_k_FDelete, S_k_MkDir, S_k_UseSystemFont, S_k_WPutString, S_k_WPutDecimal

SLOTS   = TASK_MAX
RESERVE = 18                    ; banks left free for the desktop (the shell
				; needs 17, its picture 5 more that it lends)
ZP1     = $3F - $22             ; $22-$3E
ZP2     = $80 - $50             ; $50-$7F
ZP3     = $100 - $A9            ; $A9-$FF
SLEEPBUF_SIZE = 1 + 8 * 4       ; (kernel/res/mainloop.s: SleepN ...)
CH_N    = $A004
CH_LIST = $A005
CTX     = $A030
REC_LEN = F_RecVarsEnd - F_RecVars
LD_LEN  = F_LdVarsEnd - F_LdVars
TXT     = $0770                 ; (V145) the progress line's text (dbFileNames:
TXT_KB  = TXT + 52              ; the system variables are in the context bank)
BAND_N  = 5                     ; the progress band: the screen's first pages
				; (rows 0-15 at 80 bytes a row, 0-31 at 40)

; a task's record (TaskCtl TASK_INFO gives its first TASK_REC bytes)
R_STATE = TR_STATE
R_BANKS = TR_BANKS
R_NAME  = TR_NAME
R_NOTE  = TR_NOTE
R_CTX   = TASK_REC              ; the context bank
R_OWN   = R_CTX + 1             ; its own banks (32: a bit a bank)
R_CARD  = R_OWN + 32            ; (V145) $80: on the card (its fonts held)
REC     = R_CARD + 1
.assert TR_NOTE + TASK_NOTE_LEN = TASK_REC, error, "TASK_REC"

.segment "BSS"

recs:	.res SLOTS * REC
sl:	.res 1                  ; the task
curFlags: .res 1                ; the running application's info block flags
curDesk: .res 1                 ; $80: it is the desktop
curNote: .res TASK_NOTE_LEN     ; its note
pend:	.res TASK_NOTE_LEN      ; the next one's
lastErr: .res 1                 ; the last start that failed
lastName: .res 17
daImg:	.res 32 + 24 + 24       ; the bank table while an accessory runs
askB:	.res 1                  ; (V145) dbFileNames under the question's box: its bank
why:	.res 1
resv:	.res 1                  ; TakeBank's reserve: RESERVE, or 0 (an accessory)
daChain: .res 1 + CHAIN_MAX     ; an accessory's: PK_N, PK_LIST
own:	.res 32
cnt:	.res 1
tmp:	.res 4
keepP:	.res 3                  ; TbAll: kPtr2, sl
t0:	.res 4                  ; the emulator's cycle counter at the start
card:	.res 1                  ; (V145) $80: the chain goes to / comes from the card
fh:	.res 1                  ; the task's file (0: none open)
fslot:	.res 1                  ; its task (the name's digit)
ctxB:	.res 1                  ; the context bank
rollB:	.res 1                  ; the card's rolling bank
cb:	.res 1                  ; Each: the bank
dir:	.res 1                  ; Each: $80 in from the card, 0 out
pOn:	.res 1                  ; Each: $80 the progress line
kbN:	.res 2                  ; its KB
msk:	.res 32                 ; Each's banks
cardT:	.res 1
hitOnly: .res 1                 ; EvictAny: $80 only a task holding one of msk
booted:	.res 1                  ; $80 after the first start's clean-up
daOn:	.res 1                  ; $80 while an accessory runs
vecK:	.res 8                  ; the interrupt's vectors as CtxOut found them
evI:	.res 1                  ; Evict: the chain's bank
evN:	.res 1                  ; its banks
nmP:	.res 2                  ; Log: the name
slK:	.res 1                  ; CardIn: its task
abuf:	.res 32                 ; AllOf: a task's banks
zpK	= abuf                  ; r4-r12 (Take, Next: no AllOf while the images run)
chbuf	= daChain               ; a context bank's CH_N, CH_LIST (AllOf: never
				; while an accessory runs, whose chain that is)
colK:	.res 2                  ; kColorOn, kCov (bank S: Tidy's)
.segment "CODE"
; (V145) the context, as it goes into the context bank at CTX: staged in
; main RAM, in fileHeader and dbFileNames, once the system variables are
; in the context bank (VARS); the pack images run over the second part
; later (PK_RUN), so it goes to the context bank before them
CTXA    = $0400
cZp     = CTXA
cSleep  = cZp + ZP1 + ZP2 + ZP3
cRect   = cSleep + SLEEPBUF_SIZE
cFont   = cRect + 8
cUi     = cFont + FONT_STATE
cName   = cUi + 2
cFlags  = cName + 17            ; its info block's flags
CTXA_LEN = cFlags + 1 - CTXA
.assert CTXA_LEN <= 256, error, "the context's first part"
CTXB    = $0600
cProc   = CTXB
cCol    = cProc + 168           ; kColorOn, kCov (bank S)
cVid    = cCol + 2              ; DC_VIDEO
cLay    = cVid + 1              ; the layers
cSpr    = cLay + 14             ; sprites 0-7's attributes
cPal    = cSpr + 64             ; palette entries 0-15
cUsed   = cPal + 32             ; the bank table
cRunF   = cUsed + 32
cRunN   = cRunF + 24
CTXB_LEN = cRunN + 24 - CTXB
.assert CTXB + CTXB_LEN <= TXT, error, "the context's second part"
CTX_LEN = CTXA_LEN + CTXB_LEN
.segment "BSS"

FREC    = CTX + CTX_LEN
FLD     = FREC + REC_LEN
VARS    = (FLD + LD_LEN + 255) & $FF00  ; $0400-$07FF (V145)
STREAM  = VARS + $400
.assert STREAM < $B800, error, "the context bank has too little room for the packed data"

.segment "CODE"

;---------------------------------------------------------------
; TaskCtl: a = the operation (veranda.api; >= $80 the kernel's own)
;---------------------------------------------------------------
k_TaskCtl:
	cmp #TC_NEXT + 1
	bcs @bad
	cmp #TC_POLL
	bcs @k
	cmp #TASK_ROOM + 1
	bcs @bad
	asl
	tay
	lda Ops + 1,y
	pha
	lda Ops,y
	pha
	rts
@k:	and #$7F
	asl
	tay
	lda KOps + 1,y
	pha
	lda KOps,y
	pha
	rts
@bad:	ldx #INV_RECORD
	rts

Ops:	.word Info - 1, Resume - 1, End - 1, Note - 1, Aside - 1, Room - 1
KOps:	.word Poll - 1, Start - 1, DaKeep - 1, DaBack - 1, Fail - 1, Take - 1, DaPack - 1, DaUnpack - 1
	.word Next - 1

; x = the task -> kPtr2 its record, sl; c set if there is no such task
Slot:	cpx #SLOTS
	bcs @r
	stx sl
	LoadW kPtr2, recs
@1:	dex
	bmi @c
	AddVW REC, kPtr2
	bra @1
@c:	clc
@r:	rts

; the task (Slot) put aside? x = 0; else INV_RECORD, z clear
Used:	jsr Slot
	bcs @no
	lda (kPtr2)
	beq @no
	ldx #0
	rts
@no:	ldx #INV_RECORD
	rts

;---------------------------------------------------------------
; TASK_INFO: task x's record to r0 (a = its state); x = $FF: the summary
;---------------------------------------------------------------
Info:	cpx #$FF
	beq @sum
	jsr Slot
	bcs Bad
	ldy #TASK_REC - 1
@c:	lda (kPtr2),y
	sta (r0),y
	dey
	bpl @c
	lda (kPtr2)
	ldx #0
	rts
@sum:	ldx #SLOTS - 1          ; the tasks
	ldy #0
@n:	phx
	phy
	jsr Slot
	ply
	plx
	lda (kPtr2)
	beq @n1
	iny
@n1:	dex
	bpl @n
	tya
	sta (r0)
	jsr FreeCount
	phy
	ldy #TS_FREE
	sta (r0),y
	pla
	iny
	sta (r0),y
	iny
	lda lastErr
	sta (r0),y
	stz lastErr
	ldx #0
@nm:	lda lastName,x
	iny
	sta (r0),y
	inx
	cpx #17
	bne @nm
	ldx #0
	rts
Bad:	ldx #INV_RECORD
	rts

;---------------------------------------------------------------
; TASK_NOTE: r0's text goes with the next application
;---------------------------------------------------------------
Note:	ldy #0
@c:	lda (r0),y
	sta pend,y
	beq @z
	iny
	cpy #TASK_NOTE_LEN - 1
	bne @c
	lda #0
	sta pend,y
@z:	ldx #0
	rts

;---------------------------------------------------------------
; TASK_ASIDE: put aside at the main loop's next pass
;---------------------------------------------------------------
Aside:	lda #SWITCH_ASIDE
	sta switchReq
	ldx #0
	rts

;---------------------------------------------------------------
; TASK_ROOM (V145): a = the banks the caller may still take and be put
; aside: Fast the free ones (and the spare fonts') less the desktop's
; reserve and a small program's packed data (3); Roomy those and the
; banks of the programs aside in RAM (they go to the card), less two
;---------------------------------------------------------------
Room:	stz cnt
	jsr Roomy
	ror cardT               ; (bit 7: Roomy)
	ldx #31
@s:	lda spare,x
	jsr Bits
	bit cardT
	bpl @s1
	lda keep,x
	eor #$FF
	and tb,x
	jsr Bits
@s1:	dex
	bpl @s
	lda #RESERVE + 3
	bit cardT
	bpl @f
	lda #2
@f:	sta tmp
	jsr FreeCount
	clc
	adc cnt
	bcc @1
	lda #$FF
@1:	sec
	sbc tmp
	bcs @r
	lda #0
@r:	ldx #0
	rts

; c set: Roomy (the settings' PREFS_SWITCH; 0: below 2 MB)
Roomy:	lda kPrefs
	and #PREFS_SWITCH
	beq @m
	cmp #PREFS_ROOMY
	rts
@m:	jsr FreeCount           ; (y: the banks there are)
	tya
	eor #$80
	asl
	rts

;---------------------------------------------------------------
; TC_START (AppReset): x the flags, y $80 for the desktop
;---------------------------------------------------------------
Start:	stx curFlags
	sty curDesk
	stz switchReq
	bit booted              ; (V145) the first start: the task files'
	bmi @bt                 ; stale task files deleted (a crash, a power
	dec booted              ; loss, BASIC), r0-r7 kept (the loader's)
	ldx #15
@sv:	lda r0,x
	pha
	dex
	bpl @sv
	LoadB fslot, SLOTS - 1
@del:	jsr FileD
	dec fslot
	bpl @del
	ldx #0
@rs:	pla
	sta r0,x
	inx
	cpx #16
	bne @rs
@bt:
	stz VERA_CTRL           ; sprites 1-7's pictures cleared (unused
	LoadB VERA_ADDR_L, <(VRAM_SPRITES + $800)  ; slots then pack to
	LoadB VERA_ADDR_M, >(VRAM_SPRITES + $800)  ; nothing)
	LoadB VERA_ADDR_H, ^VRAM_SPRITES | VERA_INC1
	LoadW r0, 7 * $800
	jsr Zeros
	ldy #TASK_NOTE_LEN - 1
@c:	lda pend,y
	sta curNote,y
	lda #0
	sta pend,y
	dey
	bpl @c
	rts

;---------------------------------------------------------------
; TC_FAIL (LdApplic): x the error; the program in dirEntryBuf
;---------------------------------------------------------------
Fail:	stx lastErr
	ldx #0
@c:	lda dirEntryBuf + OFF_FNAME,x
	cmp #$A0
	beq @z
	sta lastName,x
	inx
	cpx #16
	bne @c
@z:	stz lastName,x
	rts

;---------------------------------------------------------------
; TC_TAKE (the pack image): a bank for the chain, RESERVE kept free
;---------------------------------------------------------------
Take:	bit card
	bmi @c
	lda resv
	jmp TakeBank
@c:	jsr ZpOut               ; (V145) the card: the bank just filled to the
	ldx PK_N                ; file, the rolling bank again
	lda PK_LIST - 1,x
	jsr Out8
	jsr ZpIn
	ldx #NO_BANKS
	bcs @r
	lda rollB
	ldx #0
@r:	rts

;---------------------------------------------------------------
; TC_NEXT (the unpack image, V145): the chain's next bank; the card: the
; next 8 KB from the file into the rolling bank
;---------------------------------------------------------------
Next:	bit card
	bmi @c
	inc r12L                ; (pkCur)
	ldx r12L
	lda PK_LIST,x
	rts
@c:
	jsr ZpOut
	lda rollB
	jsr In8
	jsr ZpIn
	lda rollB
	rts

; r4-r12 (the pack images') kept across the file's transfer (the
; KERNAL's calls do not promise to keep r0-r15)
ZpOut:	ldx #17
@1:	lda r4,x
	sta zpK,x
	dex
	bpl @1
	rts
ZpIn:	php
	ldx #17
@1:	lda zpK,x
	sta r4,x
	dex
	bpl @1
	plp
	rts


;---------------------------------------------------------------
; TC_DAPACK, TC_DAUNPACK (kernel/s/desk.s, V83): a desk accessory puts
; the application aside packed (no reserve: the desktop does not start);
; x = 0, or NO_BANKS (nothing taken)
;---------------------------------------------------------------
DaPack:	LoadW r0, S_kColorOn    ; (Tidy: the map shown or not)
	LoadW r1, colK
	LoadW r2, 2
	jsr FromS
	jsr Tidy
	stz resv
	lda #0
	jsr TakeBank
	cpx #0
	bne @r
	pha
	LoadW r0, PKIMG_A
	jsr Image
	pla
	sta PK_LIST
	LoadB PK_N, 1
	LoadW r4, $A000
	jsr PK_RUN
	ldx #CHAIN_MAX
@c:	lda PK_N,x              ; the chain kept
	sta daChain,x
	dex
	bpl @c
	bcc @ok
	jsr Unchain
	ldx #NO_BANKS
@r:	rts
@ok:	ldx #0
	rts
DaUnpack:
	LoadW r0, PKIMG_B
	jsr Image
	ldx #CHAIN_MAX
@c:	lda daChain,x
	sta PK_N,x
	dex
	bpl @c
	LoadW r4, $A000
	jsr PK_RUN
; the chain's banks (daChain) free
Unchain:
	ldx daChain
@f:	dex
	bmi @r
	phx
	lda daChain + 1,x
	jsr Unuse
	plx
	bra @f
@r:	rts

;---------------------------------------------------------------
; TC_DAKEEP, TC_DABACK (kernel/s/desk.s): the bank table while an
; accessory runs; back: the accessory's banks (x the first) free again,
; the fonts' kept
;---------------------------------------------------------------
DaKeep:	LoadB daOn, $80
	ldx #31
@1:	lda used,x
	sta daImg,x
	dex
	bpl @1
	ldx #23
@2:	lda runF,x
	sta daImg + 32,x
	lda runN,x
	sta daImg + 56,x
	dex
	bpl @2
	rts
DaBack:	phx
	stz daOn
	ldx #31
@1:	lda daImg,x
	ora keep,x
	sta used,x
	dex
	bpl @1
	ldx #23
@2:	lda daImg + 32,x
	sta runF,x
	lda daImg + 56,x
	sta runN,x
	dex
	bpl @2
	pla
	jmp k_BankFree

;---------------------------------------------------------------
; TC_POLL (ClockPoll, the main loop's top level, switchReq set): the
; application put aside, the desktop started; or a box asks whether it
; may quit, and the program goes on if not
;---------------------------------------------------------------
Poll:	jsr Clock0
	stz switchReq
	lda #1                  ; streams or a listing open: not now
	sta why
	lda curFlags
	and #APPF_STAY
	beq @st
	jmp Ask
@st:	LoadW r0, F_StrOpen     ; (bank F's three streams, and the listing)
	LoadW r1, tmp
	LoadW r2, 3
	jsr FromF
	LoadW r0, F_StrDir
	LoadW r1, tmp+3
	LoadW r2, 1
	jsr FromF
	lda tmp
	ora tmp+1
	ora tmp+2
	ora tmp+3
	bne @ask
	stz why                 ; (not enough memory)
	ldx #SLOTS - 1          ; a free record
@f:	jsr Slot
	lda (kPtr2)
	beq @free
	ldx sl
	dex
	bpl @f
	bra @ask
@free:	jsr FreeCount           ; (V145) the fonts no program asked for
	cmp #RESERVE + 8        ; since this one started given up first
	bcs @fc                 ; when the banks are few
	jsr GiveSpare
@fc:	stz card
	jsr Roomy
	bcc @fast
	jsr FreeCount           ; Roomy: RAM when it fits with the reserve,
	cmp #RESERVE + 3        ; else the card
	bcc @card
@fast:	LoadB resv, RESERVE
	jsr Keep
	bcc @ok
@card:	; (both modes: what does not fit in RAM goes to the card rather
	; than being asked to quit, if two banks are free for it)
	LoadB card, $80
	stz resv
	jsr Keep
	bcc @ok
@ask:	stz card
	jmp Ask
@ok:	; the record
	ldx sl
	jsr Slot
	lda #TASK_ASIDE
	sta (kPtr2)
	ldy #R_NAME
	ldx #0
@nm:	lda kAppName,x
	sta (kPtr2),y
	iny
	inx
	cpx #17
	bne @nm
	ldx #0
@no:	lda curNote,x
	sta (kPtr2),y
	iny
	inx
	cpx #TASK_NOTE_LEN
	bne @no
	lda PK_LIST
	ldy #R_CTX
	sta (kPtr2),y
	ldx #0                  ; its own banks, all, and the count
	stz cnt
@o:	lda own,x
	iny                     ; (R_OWN + x)
	sta (kPtr2),y
	lda keep,x              ; (the fonts are not counted)
	eor #$FF
	and own,x
	jsr Bits
	inx
	cpx #32
	bne @o
	lda PK_N
	clc
	adc cnt
	ldy #R_BANKS            ; (V145: on the card, those it took there)
	sta (kPtr2),y
	lda card
	ldy #R_CARD
	sta (kPtr2),y
	bit card                ; (V145) on the card: its banks but the
	bpl @cf                 ; fonts free (the context and rolling banks
	jsr MskTo               ; too); (V183) which they were, kept
	ldx #31
@cu:	lda msk,x
	eor #$FF
	and used,x
	sta used,x
	dex
	bpl @cu
	lda ctxB
	jsr Unuse
	lda rollB
	jsr Unuse
@cf:	jsr TbAll               ; tb: every task's banks
	; the record file is the task's now: bank F forgets it (its banks
	; and state stay with the task), so the next program does not
	; write it back or free it
	LoadW r0, Zero
	LoadW r1, F_RecVars     ; (isOpen)
	LoadW r2, 1
	jsr ToF
	ldx #<MsgAside
	ldy #>MsgAside
	bit card
	bpl @lg
	stz card
	ldx #<MsgCard
	ldy #>MsgCard
@lg:	jsr Log
	FARCALL k_EnterDeskTop  ; (does not return)

; the bits of a in cnt (x kept)
Bits:	phx
	ldx #8
@1:	asl
	bcc @2
	inc cnt
@2:	dex
	bne @1
	plx
	rts

; tb = the banks of every task put aside (kPtr2, sl kept)
TbAll:	MoveW kPtr2, keepP
	MoveB sl, keepP+2
	ldx #31
@z:	stz tb,x
	dex
	bpl @z
	ldx #SLOTS - 1
@t:	phx
	jsr Slot
	lda (kPtr2)
	beq @n
	jsr AllOf
	ldx #31
@b:	lda abuf,x
	ora tb,x
	sta tb,x
	dex
	bpl @b
@n:	plx
	dex
	bpl @t
	MoveW keepP, kPtr2
	MoveB keepP+2, sl
	rts

;---------------------------------------------------------------
; Keep: the running application into banks; c set if they ran out, or
; (card, V145) the card failed (why 2): nothing changed then
;---------------------------------------------------------------
Keep:	; its own banks: what it uses now that no task holds and is not a
	; spare font (fonts nobody asked for since it started)
	ldx #31
@o:	lda tb,x
	ora spare,x
	eor #$FF
	and used,x
	sta own,x
	eor #$FF                ; (V145) msk: those but the fonts (the card's)
	ora keep,x
	eor #$FF
	sta msk,x
	dex
	bpl @o
	lda resv                ; the context bank
	jsr TakeBank
	cpx #0
	bne @no
	sta ctxB
	bit card
	bpl @1
	lda #0                  ; (V145) the card's rolling bank
	jsr TakeBank
	sta rollB
	cpx #0
	beq @1
	lda ctxB
	jsr Unuse
@no:	sec
	rts
@1:	jsr CtxOut
	lda ctxB                ; (after CtxOut: $07D0 kept)
	sta PK_LIST
	LoadB PK_N, 1
	jsr IrqOff              ; (V91) its interrupt routines stop: what they
				; would change while it is packed would be lost
				; (zero page, from CtxOut's copy) or half kept
				; (RAM); their vectors are in the context bank
	jsr Tidy
	; the context bank's head, the context, bank F's part (before the
	; pages: on the card the bank goes to the file when it is full)
	lda ctxB
	sta r3H
	LoadW r0, Magic
	LoadW r1, $A000
	LoadW r2, 4
	jsr FromW
	jsr CtxTo
	lda kBankBase
	clc
	adc #BANK_F
	sta r3L
	LoadW r0, F_RecVars
	LoadW r1, FREC
	LoadW r2, REC_LEN
	jsr k_BankCopy
	LoadW r0, F_LdVars
	LoadW r1, FLD
	LoadW r2, LD_LEN
	jsr k_BankCopy
	bit card
	bpl @2
	jsr CardOwn             ; (V145) its own banks to the card
	bcs @fail
@2:	LoadW r0, PKIMG_A
	jsr Image
	LoadW r4, STREAM
	jsr PK_RUN
	bcs @fail
	lda ctxB                ; the chain's list
	sta r3H
	stz r3L                 ; (below $A000: no bank)
	LoadW r0, PK_N
	LoadW r1, CH_N
	LoadW r2, 1 + CHAIN_MAX
	jsr k_BankCopy
	bit card
	bpl @ok
	lda r4L                 ; (V145) the last bank's bytes to the card
	sta kXN
	lda r4H
	sec
	sbc #$A0
	sta kXN+1
	ldx PK_N
	lda PK_LIST - 1,x
	jsr OutX
	php
	jsr FileC
	plp
	bcs @fail
@ok:	clc
	rts
@fail:	; out of banks or the card failed: the chain freed, the context
	; back as it was (the program goes on)
	bit card
	bpl @fr
	jsr FileC               ; (V145) the file deleted, the rolling bank
	LoadB why, 2            ; freed
	jsr FileD
	lda rollB
	jsr Unuse
@fr:	ldx PK_N
@fr1:	dex
	bmi @fr2
	phx
	lda PK_LIST,x
	jsr Unuse
	plx
	bra @fr1
@fr2:	jsr CtxFrom             ; (the images ran over its second part)
	sei
	jsr CtxIn
	cli
	lda #0
	FARCALL FontSel
	jsr VecBack             ; the interrupt's vectors back (V91)
	sec
	rts

; the interrupt's vectors back from the context (V91: packing gave up)
VecBack:
	php
	sei
	ldx #VecN - 1
@vb:	ldy Vec,x
	lda vecK,x
	sta $0500,y
	dex
	bpl @vb
	lda rateKeep
	sta AUDIO_RATE
	lda ienKeep
	sta VERA_IEN
	plp
	rts

.segment "BSS"
ienKeep: .res 1
rateKeep: .res 1
.segment "CODE"
Vec:	.byte <intFirstVector, <(intFirstVector + 1), <intTopVector, <(intTopVector + 1)
	.byte <intBotVector, <(intBotVector + 1), <mouseSource, <(mouseSource + 1)
VecN = * - Vec
.assert >intFirstVector = $05 && >intTopVector = $05 && >intBotVector = $05 && >mouseSource = $05, error, "task.s: the vectors in page 5"

; the interrupt calls nothing of the program's (each vector whole:
; interrupts off, V68), and VERA's line interrupt and AFLOW are off, the
; DAC held (V91: nobody would acknowledge them; a program that used them
; arms them again; V52's AudioOff); IEN and the rate kept for VecBack
IrqOff:	php
	sei
	lda VERA_IEN
	sta ienKeep
	lda AUDIO_RATE
	sta rateKeep
.ifndef NO_AUDIO_GUARD          ; (gate audio's control kernel)
	stz AUDIO_RATE
.endif
	stz intFirstVector+1
	stz intFirstVector
	stz intTopVector
	stz intTopVector+1
	stz intBotVector
	stz intBotVector+1
	stz mouseSource
	stz mouseSource+1
	lda VERA_IEN
.ifndef NO_AUDIO_GUARD
	and #<~(VERA_LINEIRQ | VERA_AFLOW)
.else
	and #<~VERA_LINEIRQ
.endif
	sta VERA_IEN
	plp
	rts

; VRAM that holds nothing zeroed, so that it packs to nothing: the free
; part of the save-under stack (bank U's UnderFree up; not in tile mode,
; V101: the desktop's tiles), and the colour map's area while the map is
; off (it is cleared when it is turned on)
Tidy:	LoadW r0, U_UnderFree
	LoadW r1, tmp
	LoadW r2, 3
	lda kBankBase
	clc
	adc #BANK_U
	sta r3L
	adc #BANK_W - BANK_U
	sta r3H
	jsr k_BankCopy
	stz VERA_CTRL
	lda VERA_L0_TILEBASE    ; (V101) the tile desktop: its tiles are there
	cmp #TILE_TB
	beq @map
	lda tmp+2               ; (in $12C00-$16BFF)
	cmp #1
	bne @map
	lda #<$6C00
	sec
	sbc tmp
	sta r0L
	lda #>$6C00
	sbc tmp+1
	sta r0H
	bcc @map
	cmp #$40 + 1
	bcs @map
	MoveB tmp, VERA_ADDR_L
	MoveB tmp+1, VERA_ADDR_M
	LoadB VERA_ADDR_H, 1 | VERA_INC1
	jsr Zeros
@map:	bit colK
	bmi TidyR
	LoadB VERA_ADDR_L, <VRAM_FREE
	LoadB VERA_ADDR_M, >VRAM_FREE
	LoadB VERA_ADDR_H, ^VRAM_FREE | VERA_INC1
	LoadW r0, $1F000 - VRAM_FREE
Zeros:	ldy r0L                 ; (V189: the part of a page, then the
	beq @p                  ; pages 8 bytes a step; was 24 cycles a byte)
@b:	stz VERA_DATA0
	dey
	bne @b
@p:	ldx r0H
	beq TidyR
@pg:	ldy #256 / 8
@w:
.repeat 8
	stz VERA_DATA0
.endrepeat
	dey
	bne @w
	dex
	bne @pg
TidyR:	rts

; bank a used no more
Unuse:	tax
	jsr BankBit
	eor #$FF
	and used,y
	sta used,y
	rts

; r0 (bank W) -> r1 in bank r3H
FromW:	lda kBankBase
	clc
	adc #BANK_W
	sta r3L
	jmp k_BankCopy

; r0 in bank F -> r1 (bank W), r2 bytes; ToF: r0 (bank W) -> r1 in bank F
FromF:	lda kBankBase
	clc
	adc #BANK_F
	sta r3L
	adc #BANK_W - BANK_F
	sta r3H
	jmp k_BankCopy
ToF:	lda kBankBase
	clc
	adc #BANK_W
	sta r3L
	sbc #BANK_W - BANK_F - 1  ; (c clear: one less)
	sta r3H
	jmp k_BankCopy

; the same with bank S
FromS:	lda kBankBase
	clc
	adc #BANK_S
	sta r3L
	adc #BANK_W - BANK_S
	sta r3H
	jmp k_BankCopy
ToS:	lda kBankBase
	clc
	adc #BANK_W
	sta r3L
	sbc #BANK_W - BANK_S - 1
	sta r3H
	jmp k_BankCopy

; a pack image (r0: PKIMG_A or PKIMG_B, in bank C) to PK_RUN
Image:	LoadW r1, PK_RUN        ; (V189: the images in bank C)
	LoadW r2, PK_MAX
	stz r3H
	lda kBankBase
	clc
	adc #BANK_C
	sta r3L
	jmp k_BankCopy

;---------------------------------------------------------------
; CtxOut: the context into Ctx
;---------------------------------------------------------------
CtxOut:	ldx #VecN - 1           ; (VecBack's)
@vk:	ldy Vec,x
	lda $0500,y
	sta vecK,x
	dex
	bpl @vk
	jsr VarsAt              ; (V145) $0400-$07FF straight to the context
	LoadW r0, $0400         ; bank (first: the context is staged there)
	LoadW r1, VARS
	MoveB ctxB, r3H
	jsr k_BankCopy
	ldx #ZP1 - 1
@z1:	lda $22,x
	sta cZp,x
	dex
	bpl @z1
	ldx #ZP2 - 1
@z2:	lda $50,x
	sta cZp + ZP1,x
	dex
	bpl @z2
	ldx #ZP3 - 1
@z3:	lda $A9,x
	sta cZp + ZP1 + ZP2,x
	dex
	bpl @z3
	ldx #SLEEPBUF_SIZE - 1
@sl:	lda SleepN,x
	sta cSleep,x
	dex
	bpl @sl
	ldx #7
@rc:	lda kMenuRect,x
	sta cRect,x
	dex
	bpl @rc
	ldx #FONT_STATE - 1
@fo:	lda sysFont,x
	sta cFont,x
	dex
	bpl @fo
	MoveB uiTimer, cUi
	MoveB uiWake, cUi+1
	ldx #16
@nm:	lda kAppName,x
	sta cName,x
	dex
	bpl @nm
	MoveB curFlags, cFlags
	ldx #31
@b1:	lda used,x
	sta cUsed,x
	dex
	bpl @b1
	ldx #23
@b2:	lda runF,x
	sta cRunF,x
	lda runN,x
	sta cRunN,x
	dex
	bpl @b2
	LoadW r1, cProc
	FARCALL ProcOut
	LoadW r0, S_kColorOn
	LoadW r1, colK
	LoadW r2, 2
	jsr FromS
	MoveW colK, cCol
	stz VERA_CTRL
	MoveB VERA_DC_VIDEO, cVid
	ldx #13
@l:	lda VERA_L0_CONFIG,x
	sta cLay,x
	dex
	bpl @l
	jsr SprAt
	ldx #0
@s:	lda VERA_DATA0
	sta cSpr,x
	inx
	cpx #64
	bne @s
	jsr PalAt
	ldx #0
@p:	lda VERA_DATA0
	sta cPal,x
	inx
	cpx #32
	bne @p
	rts

VarsAt:	LoadW r2, $0400
	rts

; (V145) the context's two parts in main RAM to the context bank (ctxB)
; or back
CtxTo:	jsr CtxP0
	jsr CtxT1
	jsr CtxP1
CtxT1:	MoveB ctxB, r3H
	jmp k_BankCopy
CtxFrom:
	jsr CtxP0
	jsr CtxF1
	jsr CtxP1
CtxF1:	ldx #1                  ; (r0 <-> r1)
@s:	lda r0,x
	ldy r1,x
	sta r1,x
	sty r0,x
	dex
	bpl @s
	MoveB ctxB, r3L
	jmp k_BankCopy
CtxP0:	LoadW r0, CTXA
	LoadW r1, CTX
	LoadW r2, CTXA_LEN
	rts
CtxP1:	LoadW r0, CTXB
	LoadW r1, CTX + CTXA_LEN
	LoadW r2, CTXB_LEN
	rts

SprAt:	LoadB VERA_ADDR_L, <VRAM_SPRATTR
	LoadB VERA_ADDR_M, >VRAM_SPRATTR
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR | VERA_INC1
	rts
PalAt:	LoadB VERA_ADDR_L, <VRAM_PALETTE
	LoadB VERA_ADDR_M, >VRAM_PALETTE
	LoadB VERA_ADDR_H, ^VRAM_PALETTE | VERA_INC1
	rts

;---------------------------------------------------------------
; TASK_END: task x dropped
;---------------------------------------------------------------
End:	jsr Used
	bne @r
	bit daOn                ; (not while an accessory runs: chbuf)
	bmi @r
	lda #0
	sta (kPtr2)
	ldy #R_CARD             ; (V145) on the card: its file deleted, its
	lda (kPtr2),y           ; fonts no longer held
	beq @d
	lda #0
	sta (kPtr2),y
	MoveB sl, fslot
	jsr FileD
	jsr TbAll
	bra @0
@d:	jsr Drop
@0:	ldx #0
@r:	rts

; the banks of task sl (its record kPtr2, its state cleared) that nobody
; else holds and that are not fonts are free again; tb without them
Drop:	jsr TbAll
	jsr AllOf
	ldx #31
@1:	lda tb,x
	ora keep,x
	eor #$FF
	and abuf,x
	eor #$FF
	and used,x
	sta used,x
	dex
	bpl @1
	rts

; (V145) abuf = task kPtr2's banks: its own and its chain's (the context
; bank's list, chbuf); on the card only its fonts (its own that are kept)
AllOf:	ldy #R_CARD
	lda (kPtr2),y
	sta cardT
	ldy #R_OWN
	ldx #0
@o:	lda (kPtr2),y
	bit cardT
	bpl @o1
	and keep,x
@o1:	sta abuf,x
	iny
	inx
	cpx #32
	bne @o
	bit cardT
	bmi @r
	jsr ChList
	ldx chbuf
@c:	dex
	bmi @r
	phx
	lda chbuf + 1,x
	tax
	jsr BankBit
	ora abuf,y
	sta abuf,y
	plx
	bra @c
@r:	rts
; chbuf = task kPtr2's context bank's CH_N, CH_LIST
ChList:	ldy #R_CTX
	lda (kPtr2),y
	sta r3L
	jsr ToW1
	LoadW r0, CH_N
	LoadW r1, chbuf
	LoadW r2, 1 + CHAIN_MAX
	jmp k_BankCopy

;---------------------------------------------------------------
; TASK_RESUME: task x back; the caller ends
;---------------------------------------------------------------
Resume:	jsr Used
	beq @1
	rts
@1:	jsr Clock0	; the caller ends, as LdApplic ends a program (V76: the interrupt
	; calls nothing of it from now on)
	jsr IrqOff
	FARCALL AudioReset
	FARCALL PrReset
	FARCALL k_CloseRecordFile
	lda #0                  ; its streams and the listing
	FARCALL k_FClose
	ldx #31                 ; its banks: only the fonts' and the tasks'
@b:	lda keep,x              ; stay
	ora tb,x
	sta used,x
	dex
	bpl @b
	ldx #23
@r:	stz runF,x
	dex
	bpl @r
	LoadW r0, Zero          ; not the desktop now (bank S's isDesk), before
	LoadW r1, S_isDesk      ; its mode: SetVideoMode keeps the desktop's
	LoadW r2, 1             ; for its return (V177)
	jsr ToS
	; its video mode (the screens cleared: they come back below)
	ldx sl
	jsr Slot
	ldy #R_CTX
	lda (kPtr2),y
	sta tmp
	ldy #R_CARD             ; (V145) on the card: its banks back first
	lda (kPtr2),y
	beq @ram
	jsr CardIn
@ram:	lda tmp
	sta ctxB
	sta r3L
	jsr ToW0
	LoadW r0, VARS + (graphMode - $0400)
	LoadW r1, tmp+1
	LoadW r2, 1
	jsr k_BankCopy
	lda tmp+1
	FARCALL k_SetVideoMode
	; the chain's list for the image, and the image
	LoadW r0, PKIMG_B
	jsr Image
	lda tmp
	sta r3L
	stz r3H
	LoadW r0, CH_N
	LoadW r1, PK_N
	LoadW r2, 1 + CHAIN_MAX
	jsr k_BankCopy
	lda tmp                 ; (the card: the context bank is another one)
	sta PK_LIST
	LoadW r4, STREAM
	jsr PK_RUN
	bit card                ; (V145) the card's file done with
	bpl @nc
	jsr FileC
	jsr FileD
	stz card
@nc:
	; the context, bank F's part
	jsr CtxFrom
	lda kBankBase
	clc
	adc #BANK_F
	sta r3H
	LoadW r0, FREC
	LoadW r1, F_RecVars
	LoadW r2, REC_LEN
	jsr k_BankCopy
	LoadW r0, FLD
	LoadW r1, F_LdVars
	LoadW r2, LD_LEN
	jsr k_BankCopy
	LoadW r0, cProc
	FARCALL ProcIn
	LoadW r0, cCol
	LoadW r1, S_kColorOn
	LoadW r2, 2
	jsr ToS
	MoveB cFlags, curFlags  ; it runs: not the desktop (bank S's isDesk:
	stz curDesk             ; above)
	; the bank table: its own, the fonts', the other tasks'
	ldx sl
	jsr Slot
	ldy #R_NOTE             ; (its note again)
	ldx #0
@nt:	lda (kPtr2),y
	sta curNote,x
	iny
	inx
	cpx #TASK_NOTE_LEN
	bne @nt
	lda #0
	sta (kPtr2)
	ldy #R_CARD
	sta (kPtr2),y
	jsr TbAll
	ldy #R_OWN
	ldx #0
@u:	lda (kPtr2),y
	ora keep,x
	ora tb,x
	sta used,x
	iny
	inx
	cpx #32
	bne @u
	ldx #23
@ru:	lda cRunF,x
	sta runF,x
	lda cRunN,x
	sta runN,x
	dex
	bpl @ru
	; the rest with the interrupt off
	sei
	jsr CtxIn
	cli
	lda #0                  ; its banked font: the index table again
	FARCALL FontSel
	LoadB kSndReq, SND_APP
	lda curDirName          ; its working folder
	beq @go
	LoadW r0, curDirName
	FARCALL k_ChDir
@go:	ldx #<MsgBack
	ldy #>MsgBack
	jsr Log
	ldx #$FF                ; the top of its main loop, an empty stack, its
	txs                     ; bank mapped (CallRoutine: resident)
	lda #<k_MainLoop
	ldx #>k_MainLoop
	jmp k_CallRoutine

; r3L = the context bank (tmp), r3H = bank W
ToW0:	lda tmp
	sta r3L
	lda kBankBase
	clc
	adc #BANK_W
	sta r3H
	rts

;---------------------------------------------------------------
; CtxIn: the context back from Ctx (interrupts off)
;---------------------------------------------------------------
CtxIn:	stz VERA_CTRL
	ldx #13
@l:	lda cLay,x
	sta VERA_L0_CONFIG,x
	dex
	bpl @l
	lda VERA_DC_VIDEO
	and #%10001111
	sta kTmp
	lda cVid
	and #%01110000          ; the layers and sprites as they were
	ora kTmp
	sta VERA_DC_VIDEO
	jsr SprAt
	ldx #0
@s:	lda cSpr,x
	sta VERA_DATA0
	inx
	cpx #64
	bne @s
	jsr PalAt
	ldx #0
@p:	lda cPal,x
	sta VERA_DATA0
	inx
	cpx #32
	bne @p
	ldx #SLEEPBUF_SIZE - 1
@sl:	lda cSleep,x
	sta SleepN,x
	dex
	bpl @sl
	ldx #7
@rc:	lda cRect,x
	sta kMenuRect,x
	dex
	bpl @rc
	ldx #FONT_STATE - 1
@fo:	lda cFont,x
	sta sysFont,x
	dex
	bpl @fo
	MoveB cUi, uiTimer
	MoveB cUi+1, uiWake
	ldx #16
@nm:	lda cName,x
	sta kAppName,x
	dex
	bpl @nm
	; zero page (not pressFlag and the pointer: $39-$3C)
	ldx #ZP1 - 1
@z1:	cpx #$39 - $22
	bcc @z1a
	cpx #$3D - $22
	bcc @z1b
@z1a:	lda cZp,x
	sta $22,x
@z1b:	dex
	bpl @z1
	ldx #ZP2 - 1
@z2:	lda cZp + ZP1,x
	sta $50,x
	dex
	bpl @z2
	ldx #ZP3 - 1
@z3:	lda cZp + ZP1 + ZP2,x
	sta $A9,x
	dex
	bpl @z3
	; the system variables, but what is live stays
	ldx #LiveN - 1          ; (on the stack)
@l1:	ldy Live,x
	lda $0500,y
	pha
	dex
	bpl @l1
	jsr VarsAt              ; (V145) from the context bank
	LoadW r0, VARS
	LoadW r1, $0400
	MoveB ctxB, r3L
	jsr k_BankCopy
	ldx #0
@l2:	ldy Live,x
	pla
	sta $0500,y
	inx
	cpx #LiveN
	bne @l2
	rts

; the live system variables (offsets from $0500), as kernel/s/desk.s's
Live:	.byte <mouseData, <random, <(random + 1), <dblClickCount, <year, <month, <day
	.byte <hour, <minutes, <seconds, <mouseYPosW, <(mouseYPosW + 1), <mouseButtons
	.byte <mouseWheel, <keyMods, <blankDelay, <(blankDelay + 1)
LiveN = * - Live

;---------------------------------------------------------------
; Ask (Poll: why 1 busy, 0 not enough memory): a box over the program,
; "<name> / cannot be put aside now. / Quit it, losing its work?", OK
; and Cancel; OK: it ends (EnterDeskTop), Cancel: it goes on
;---------------------------------------------------------------
DLG     = dbFileNames
L1      = DLG + 32
L2      = DLG + 64
L3      = DLG + 96
Ask:	lda #0                  ; (V145: in a free bank, if there is one)
	jsr TakeBank
	cpx #0
	beq @k
	lda #0
@k:	sta askB
	beq @k1
	sta r3H
	LoadW r0, DLG
	LoadW r1, $A000
	jsr AskN
@k1:
	ldx #BoxEnd - Box - 1
@b:	lda Box,x
	sta DLG,x
	dex
	bpl @b
	lda #BOLDON
	sta L1
	ldx #0
@n:	lda kAppName,x
	sta L1 + 1,x
	beq @n1
	inx
	cpx #16
	bne @n
	stz L1 + 1,x
@n1:	ldx #31
@t:	lda TxtMem,x
	ldy why
	beq @t1
	lda TxtBusy,x
	dey
	beq @t1
	lda TxtCard,x           ; (V145) 2: the card full, OK alone: it goes on
@t1:	sta L2,x
	lda TxtQuit,x
	ldy why
	cpy #2
	bne @t2
	lda TxtCard2,x
@t2:	sta L3,x
	dex
	bpl @t
	lda why
	asl
	tay
	ldx MsgAsk,y
	lda MsgAsk + 1,y
	tay
	lda why
	cmp #2                  ; (the card: no Cancel)
	bne @lg
	stz DLG + BoxCan - Box
@lg:	jsr Log
.ifdef SWDEBUG
	lda #'['
	sta EMU_STDOUT
	ldx #0
@dd:	lda tmp,x
	ora #'0'
	sta EMU_STDOUT
	inx
	cpx #4
	bne @dd
.endif
	LoadW r0, DLG
	FARCALL k_DoDlgBox
	lda askB
	beq @r
	sta r3L
	LoadW r0, $A000
	LoadW r1, DLG
	jsr AskN
	lda askB
	jsr Unuse
@r:
	lda why
	cmp #2
	beq @go
	lda sysDBData
	cmp #OK
	beq @quit
@go:	rts
@quit:	ldx #<MsgQuit
	ldy #>MsgQuit
	jsr Log
	FARCALL k_EnterDeskTop  ; (does not return)

;---------------------------------------------------------------
; (V145) Roomy: the card
;---------------------------------------------------------------
; CardOwn (Keep, the card): the task's file opened, its own banks but the
; fonts (msk) written, a progress line over the program meanwhile (the
; band under it kept in the rolling bank); c set: the card failed
CardOwn:
	MoveB sl, fslot
	jsr FileW
	bcs @r
	lda #0                  ; the band kept
	jsr BandX
	LoadW r10, kAppName     ; "Putting <name> aside... n KB"
	lda #0
	jsr Each0
	php
	lda #1                  ; the band back
	jsr BandX
	plp
@r:	rts

; the progress band between VRAM and the rolling bank: a = 0 out, 1 in
BandX:	pha
	jsr Band
	LoadW r1, $A000
	MoveB rollB, r3L
	ldx #BAND_N
	pla
	jmp VramBank
Band:	stz VERA_CTRL
	stz VERA_ADDR_L
	stz VERA_ADDR_M
	LoadB VERA_ADDR_H, VERA_INC1
	rts

; Each0: a the verb (0 "Putting", VBRING), r10 the name: the progress
; line's text, then Each with it; Each: the banks of msk in order to the
; task's file (dir 0) or from it (dir $80), the line drawn before each
; (pOn); c set: the card failed
Each0:	tay
	ldx #0
@v:	lda Verbs,y
	beq @n
	sta TXT,x
	inx
	iny
	bra @v
@n:	ldy #0
@m:	lda (r10),y
	beq @e
	sta TXT,x
	inx
	iny
	bra @m                  ; (a name: 16 characters at most, and its 0)
@e:	ldy #0
@d:	lda Dots,y
	sta TXT,x
	inx
	iny
	cmp #0
	bne @d
	ldx #3
@k:	lda Kb,x
	sta TXT_KB,x
	dex
	bpl @k
	LoadB pOn, $80
Each:	stz kbN
	stz kbN+1
	ldx #2
@b:	stx cb
	txa
	clc
	adc #KCOPY_BANKS
	cmp kBankBase
	bcs @ok
	jsr BankBit
	and msk,y
	beq @nx
	bit pOn
	bpl @np
	jsr Prog
@np:
	lda cb
	bit dir
	bmi @in
	jsr Out8
	bra @x
@in:	jsr In8
@x:	bcs @r
	lda kbN
	adc #8                  ; (c clear)
	sta kbN
	bcc @nx
	inc kbN+1
@nx:	ldx cb
	inx
	bra @b
@ok:	clc
@r:	stz pOn
	rts

; the progress line (TXT, kbN, " KB") in the band, the system font
Prog:	jsr Band
	LoadW r0, BAND_N * 256
	jsr Zeros
	FARCALL k_UseSystemFont
	LoadB dispBufferOn, ST_WR_FORE
	stz currentMode
	stz clipOn
	stz leftMargin
	stz leftMargin+1
	lda #$FF
	sta rightMargin
	sta rightMargin+1
	lda #8
	sta r11L
	lda #11
	sta r12L
	stz r11H
	stz r12H
	LoadW r0, TXT
	FARCALL k_WPutString
	MoveW kbN, r0
	lda #%11000000          ; (left, no leading zeros)
	FARCALL k_WPutDecimal
	LoadW r0, TXT_KB
	jmp S_k_WPutString              ; (FARCALL)

; bank a: 8 KB to the task's file (Out8; OutX: kXN bytes) or from it
; (In8, up to its end); c set: it failed
Out8:	jsr N8                  ; (a kept)
OutX:	jsr XAt
	jsr k_chkout
	jsr XferOut
	ldx kXN
	bne @f
	ldx kXN+1
	bne @f
	bra XEnd
@f:	lda #$80
	bra XEnd
In8:	jsr N8
	jsr XAt
	jsr k_chkin
	jsr XferIn
XEnd:	pha
	jsr k_clrchn
	pla
	and #%10000011          ; the device gone, a time-out, a short write
	cmp #1
	rts
N8:	ldx #$20
	stz kXN
	stx kXN+1
	rts
XAt:	sta kXB
	LoadW kXA, $A000
	ldx fh
	rts

; the task fslot's file: FileW opened to be written, FileR to be read
; (c set: it could not be), FileC closed, FileD deleted
; (opened in its folder, the working folder there until FileC: x16emu's
; host folder takes no "//" path while the working folder is another)
FileW:	jsr ToTasks             ; (no TASKS folder yet: made, from the root:
	txa                     ; x16emu's host folder makes an absolute path
	beq @w                  ; only from there; never /VERANDA itself, which
	ldx #1                  ; would become the system folder)
	jsr DirAt
	FARCALL k_ChDir
	ldx #0
	jsr DirAt
	FARCALL k_MkDir
	jsr ToTasks
@w:	ldy #2                  ; ("@:" first)
	jsr NmD
	LoadW r0, kName + 2
	lda #'w'
	bra FOpn
FileR:	jsr ToTasks
	ldy #0
	jsr NmD
	LoadW r0, kName
	lda #'r'
FOpn:	FARCALL k_FOpen         ; (bank F's DocMap changes kPtr2)
	sta fh
	cpx #0
	beq @ok
	jsr FileC0
	sec
	rts
@ok:	clc
	rts
FileC:	lda fh
	beq FileC0
	FARCALL k_FClose
; the program's working folder again (curDirName; the root without one)
FileC0:	stz fh
	LoadW r0, curDirName
	lda curDirName
	cmp #'/'
	beq @c
	ldx #1
	jsr DirAt
@c:	jmp S_k_ChDir              ; (FARCALL)
ToTasks:
	ldx #0
	jsr DirAt
	jmp S_k_ChDir              ; (FARCALL)
; kName + 3 = PathS's first DirLen,x characters (a folder), r0 there
DirAt:	ldy #0
@dc:	lda PathS,y
	sta kName + 3,y
	iny
	tya
	cmp DirLen,x
	bne @dc
	lda #0
	sta kName + 3,y
	LoadW r0, kName + 3
	rts
FileD:	ldx #0                  ; "S:" and the name as a path
	ldy #2
@c:	lda PathS,x
	beq @d
	sta kName,y
	inx
	iny
	bra @c
@d:	jsr NmD
	LoadW r0, kName + 2
	jmp S_k_FDelete              ; (FARCALL)
NmD:	lda #'T'
	sta kName,y
	iny
	lda fslot
	ora #'0'
	sta kName,y
	lda #0
	sta kName + 1,y
	rts

;---------------------------------------------------------------
; CardIn (Resume, the caller ended): task sl's own banks back from the card
; where they were (msk), its context bank into a free one (tmp), the
; rolling bank taken; the file stays open for the pages (card set). The
; banks it needs that are used: the fonts nobody holds given up, the
; programs aside in RAM that hold one onto the card. A failure: the task
; is lost (dropped), the desktop comes.
;---------------------------------------------------------------
CardIn:	MoveB sl, slK
	jsr MskFrom             ; (V183: as it went onto the card)
	jsr Hits
	beq CiFree
	ldx #31                 ; the fonts nobody holds
@f:	lda tb,x
	eor #$FF
	and keep,x              ; (keep & ~tb)
	eor #$FF
	tay
	and used,x
	sta used,x
	tya
	and keep,x
	sta keep,x
	tya
	and spare,x
	sta spare,x
	dex
	bpl @f
	LoadB hitOnly, $80      ; the programs aside in RAM that hold one
@h:	jsr Slot0
	jsr MskFrom             ; (V183: as it went onto the card)
	jsr Hits
	beq CiFree
	jsr EvictAny
	bcc @h
CiLost:
	stz hitOnly
	jsr Slot0
	lda #0
	sta (kPtr2)
	ldy #R_CARD
	sta (kPtr2),y
	jsr FileC
	jsr FileD
	jsr TbAll
	FARCALL k_EnterDeskTop
CiFree:	stz hitOnly
	jsr Slot0
	jsr MskFrom             ; (V183: as it went onto the card)
	ldx #31                 ; they are its
@u:	lda msk,x
	ora used,x
	sta used,x
	dex
	bpl @u
	jsr Take2               ; the context bank, the rolling bank (before
	sta tmp                 ; its file is open: EvictAny writes others)
	jsr Take2
	sta rollB
	jsr Slot0
	jsr MskFrom             ; (V183: as it went onto the card)
	lda #R_NAME             ; "Bringing back <name>... n KB"
	clc
	adc kPtr2
	sta r10L
	lda kPtr2+1
	adc #0
	sta r10H
	jsr FileR               ; (kPtr2 changed)
	bcs CiLost
	LoadB dir, $80
	lda #VBRING
	jsr Each0
	bcs CiLost
	stz dir
	lda tmp
	jsr In8
	LoadB card, $80
	jmp Slot0
; a free bank (the programs aside in RAM go to the card for it)
Take2:	lda #0
	jsr TakeBank
	cpx #0
	beq @r
	jsr EvictAny
	bcc Take2
	jmp CiLost
@r:	rts

; kPtr2, fslot: task sl's
Slot0:	ldx slK
	stx fslot
	jmp Slot

; msk = task kPtr2's own banks but the fonts
MskOf:	ldy #R_OWN
	ldx #0
@m:	lda keep,x
	eor #$FF
	and (kPtr2),y
	sta msk,x
	iny
	inx
	cpx #32
	bne @m
	rts

; (V183) msk to bank C's table for task sl (MskTo) or back (MskFrom): a
; task on the card is brought back into the banks that were its own but
; the fonts when it went there; reckoned again then, a font loaded since
; into one of them would be taken for the task's own and left out
MskTo:	jsr MskA
	LoadW r0, msk
	MoveW kTmp, r1
	lda kBankBase
	clc
	adc #BANK_W
	sta r3L
	adc #BANK_C - BANK_W
	sta r3H
	bra MskG
MskFrom:
	jsr MskA
	MoveW kTmp, r0
	LoadW r1, msk
	lda kBankBase
	clc
	adc #BANK_C
	sta r3L
	sbc #BANK_C - BANK_W - 1        ; (c clear)
	sta r3H
MskG:	LoadW r2, 32
	jmp k_BankCopy
MskA:	lda sl
	asl
	asl
	asl
	asl
	asl
	sta kTmp
	lda #>C_TASKMSK
	sta kTmp+1
	rts

; (V183, FontBanks) the banks of the tasks on the card that are free
; marked used while a font is given banks (abuf: those marked), and
; free again (CardOn, a, x and the flags kept): a font loaded into one
; would be held while the task's own data must come back there
CardOff:
	lda #$40
	tsb daOn
	lda kPtr2               ; (kPtr2 kept: bank T's caller's)
	pha
	lda kPtr2+1
	pha
	ldx #31
@z:	stz abuf,x
	dex
	bpl @z
	ldx #SLOTS - 1
@t:	phx
	jsr Slot
	lda (kPtr2)
	beq @n
	ldy #R_CARD
	lda (kPtr2),y
	beq @n
	jsr MskFrom
	ldx #31
@o:	lda msk,x
	ora abuf,x
	sta abuf,x
	dex
	bpl @o
@n:	plx
	dex
	bpl @t
	ldx #31
@u:	lda used,x
	eor #$FF
	and abuf,x
	sta abuf,x
	ora used,x
	sta used,x
	dex
	bpl @u
	pla
	sta kPtr2+1
	pla
	sta kPtr2
	rts
CardOn:	php
	phx
	pha
	lda #$40
	trb daOn
	ldx #31
@u:	lda abuf,x
	eor #$FF
	and used,x
	sta used,x
	dex
	bpl @u
	pla
	plx
	plp
	rts

; z clear if a bank of msk is used
Hits:	ldx #31
@1:	lda used,x
	and msk,x
	bne @r
	dex
	bpl @1
	lda #0
@r:	rts


;---------------------------------------------------------------
; EvictAny (BankAlloc in Roomy mode, CardIn): a program aside in RAM (with
; hitOnly: one that holds a bank of msk) onto the card, its banks free;
; c clear if one went. Evict: task sl so: its own banks but the fonts, its
; context bank, the chain's other banks (as a put-aside writes them)
;---------------------------------------------------------------
EvictAny:
	ldx #15                 ; (r0-r7 kept: a running program's BankAlloc)
@sv:	lda r0,x
	pha
	dex
	bpl @sv
	sec
	bit daOn                ; (not while an accessory runs; nor for a
	bmi @x                  ; font, V183: bit 6, CardOff's abuf)
	bvs @x
	ldx #SLOTS - 1
@t:	phx
	jsr Slot
	lda (kPtr2)
	beq @n
	ldy #R_CARD
	lda (kPtr2),y
	bne @n
	jsr AllOf
	bit hitOnly
	bpl @e
	ldx #31
@hh:	lda abuf,x
	and msk,x
	bne @e
	dex
	bpl @hh
	bra @n
@e:	jsr Evict
	bcs @n
	plx
	clc
	bra @x
@n:	plx
	dex
	bpl @t
	sec
@x:	ror evN                 ; (c kept)
	ldx #0
@rs:	pla
	sta r0,x
	inx
	cpx #16
	bne @rs
	asl evN
	rts

; (abuf, chbuf: AllOf's)
Evict:	MoveB sl, fslot
	jsr MskOf               ; its own banks
	jsr MskTo               ; (V183) kept: which they were
	jsr FileW               ; (kPtr2 changed)
	bcs @r
	stz dir
	stz pOn
	jsr Each
	bcs @f
	lda chbuf               ; its chain (CH_LIST: the context bank first)
	sta evN
	stz evI
@c:	ldx evI
	lda chbuf + 1,x
	jsr Out8
	bcs @f
	inc evI
	dec evN
	bne @c
	jsr FileC
	ldx sl
	jsr Slot
	lda #$80                ; on the card: its banks but the fonts free
	ldy #R_CARD
	sta (kPtr2),y
	ldx #31
@u:	lda keep,x
	eor #$FF
	and abuf,x
	eor #$FF
	and used,x
	sta used,x
	dex
	bpl @u
	jsr TbAll
	ldx #<MsgEvict
	ldy #>MsgEvict
	jsr LogR
	clc
	rts
@f:	jsr FileC
	jsr FileD
	sec
@r:	rts
; r3H = bank W
ToW1:	lda kBankBase
	clc
	adc #BANK_W
	sta r3H
	rts

AskN:	LoadW r2, 128
	jmp k_BankCopy

; the console (x16emu only): "TASK <x/y> <name>"
Log:	lda #<kAppName
	sta nmP
	lda #>kAppName
	bra Log1
; the same with task kPtr2's name
LogR:	lda kPtr2
	clc
	adc #R_NAME
	sta nmP
	lda kPtr2+1
	adc #0
Log1:	sta nmP+1
	jsr IsEmu
	bne @r
	phy
	phx
	ldx #<MsgTask
	ldy #>MsgTask
	jsr LogStr
	plx
	ply
	jsr LogStr
	ldx nmP
	ldy nmP+1
	jsr LogStr
	lda #' '                ; the cycles since Clock0 (hex)
	sta EMU_STDOUT
	lda EMU_CLOCK           ; (latches)
	sta t0
	ldx #1
@c:	lda EMU_CLOCK,x
	sta t0,x
	inx
	cpx #4
	bne @c
	ldx #3
@h:	lda t0,x
	jsr Hex
	dex
	bpl @h
	jmp LogNL
@r:	rts
Hex:	pha
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
; the emulator's cycle counter from 0 (x16emu only: a write resets it)
Clock0:	jsr IsEmu
	bne @r
	sta EMU_CLOCK
@r:	rts

.segment "RODATA"

Zero:	.byte 0
Magic:	.byte "VTSK"
Box:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y
	.word L1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word L2
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_3_Y
	.word L3
	.byte OK, DBI_X_0, DBI_Y_2
BoxCan:	.byte CANCEL, DBI_X_2, DBI_Y_2
	.byte 0
BoxEnd:
.assert BoxEnd - Box <= 32, error, "the question's box"
TxtBusy: .byte "cannot be put aside now.", 0
	.res 32 - 25
TxtMem:	.byte "No memory to put it aside.", 0
	.res 32 - 27
TxtQuit: .byte "Quit it, losing its work?", 0
	.res 32 - 26
TxtCard: .byte "Not enough room on the card", 0
	.res 32 - 28
TxtCard2: .byte "to put it aside.", 0
	.res 32 - 17
MsgAsk:	.word MsgAskM, MsgAskB, MsgAskC
MsgAskC: .byte "ASK CARD ", 0
MsgCard: .byte "CARD ", 0
MsgEvict: .byte "EVICT ", 0
PathS:	.byte "/VERANDA/.SYSTEM/TASKS/", 0
DirLen:	.byte 22, 1
Verbs:	.byte "Putting ", 0
VBRING = * - Verbs
	.byte "Bringing back ", 0
Dots:	.byte "... ", 0
Kb:	.byte " KB", 0
MsgTask: .byte 10, "TASK ", 0
MsgAside: .byte "ASIDE ", 0
MsgBack: .byte "BACK ", 0
MsgAskM: .byte "ASK MEMORY ", 0
MsgAskB: .byte "ASK BUSY ", 0
MsgQuit: .byte "QUIT ", 0
