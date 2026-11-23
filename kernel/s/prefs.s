; Veranda bank S: the system's settings and alarms (DECISIONS V56)
;
; The settings block (PREFS_SIZE bytes; SysPrefs PREFS_GET, PREFS_SET):
;   0-1 the paper, 2-3 the ink ($0RGB: palette entries 0 and 1 at every
;   program's start, DefColors), 4-5 blankDelay, 6 the flags (kPrefs,
;   resident: bit 7 the sounds off, bit 6 the menu ticks on (V69), bits
;   0-1 the pointer's speed, a move times 1, 2 or 4), 7 the video mode for programs that keep the mode, the shell's
;   (and at start-up; $FF: none), 8 the time zone (quarter hours, signed;
;   kept for programs), 9-14 the control panel's own (kept as they are;
;   10-13 the colour theme, sdk theme.h: V65; 14 the look, V74: bit 7
;   the theme's colours are Look 2's palette entries, bit 0 dark), 15 the
;   sounds' volume:
;   PREFS_VOLSET (bit 7) + 63 - the volume (V72: kSndAtt, resident, the
;   attenuation 0-63 in VERA's 0.5 dB steps); without bit 7 (a file saved
;   before V72, whatever its byte 15) full volume.
; The alarm table (ALARMS_GET, ALARMS_SET): ALARM_MAX entries of
; ALARM_SIZE bytes: year (0-99: 2000-2099), month, day, hour, minute, the
; state (0 none, ALARM_ARMED, ALARM_DONE), a text (0-terminated, at most
; 24 characters). ClockPoll looks once a second: the first armed entry
; whose time has come (now or earlier) is shown in a small box over any
; program (AlarmBox, bank U) with its sound (even with the sounds off), and
; marked done; while a dialog box is open it waits for it to close.
; Entries already due when the table is set are marked done.
;
; The desktop's path (DESK_GET, DESK_SET; DESK_SIZE bytes, curDirName's
; layout: the path, 0-terminated, in 0-61, the shell's video mode in 63):
; the shell's own folder, set by the shell before it starts a program and
; read when it starts (DECISIONS V63). Applications keep their working
; folder in curDirName; nothing else writes this. Written into bank S's
; pristine copy too (V50), so a crash keeps it; empty (0) until set.
;
; Both are read at start-up (Init, after TEST.PRG; and CrashInit) from the
; system folder (/VERANDA, else the root): "Veranda Prefs.cvt" and
; "Veranda Alarms.cvt", sequential GEOS files whose data (from byte 508,
; docs/APPFORMAT.md) is the block and the table as above. The kernel
; never writes them: the control panel (apps/prefs) and the Calendar
; (apps/calendar) do, and call SysPrefs for the running system.

.include "kernel.inc"

.export k_SysPrefs, SysLoad, AlarmCheck, prBlock, prMode, deskPath
.import BarDesk
.import kPrefs, kSndAtt, kKeyAct, ClockRead, DefColors, k_BankCopy, kBankBase

ARMED   = ALARM_ARMED
DONE    = ALARM_DONE
NAMEBUF = $0801                 ; a path for FOpen (below $A000; start-up
				; and a crash only: no program's RAM is live)

.segment "DATA"

prBlock:	.word $0FFF             ; the paper
		.word $0223             ; the ink (V74: Look 2's dark slate)
		.word 600               ; blankDelay
		.byte 0                 ; the flags
prMode:		.byte $FF               ; the video mode: none
		.res PREFS_SIZE - 8

.segment "BSS"

alTab:	.res ALARM_SIZE * ALARM_MAX
deskPath: .res DESK_SIZE        ; the desktop's path (DESK_SET)
alBusy:	.res 1                  ; $80: a box is up (the nested main loop)
regs:	.res 32                 ; r0-r15 while it is
fh:	.res 1
dirI:	.res 1
nameP:	.res 2
cnt:	.res 2

.segment "CODE"

;---------------------------------------------------------------
; SysPrefs: a = PREFS_GET, PREFS_SET, ALARMS_GET, ALARMS_SET, DESK_GET or
; DESK_SET, r0 the buffer (below $A000); x = 0, or INV_RECORD for another a;
; r0-r3 kept. SP_BAR (V120, the kernel's own: bank T has no stub of its
; own for it): desk.s's BarDesk, Preferences from the menu bar
;---------------------------------------------------------------
k_SysPrefs:
	tax
	MoveW r0, kPtr2
	txa
	cmp #1
	beq @set
	bcc @get
	cmp #3
	beq @aset
	bcs @desk
	; ALARMS_GET
	ldy #0
@ag:	lda alTab,y
	sta (kPtr2),y
	iny
	bne @ag
	bra @ok
@get:	MoveW blankDelay, prBlock + 4
	ldy #PREFS_SIZE - 1
@g:	lda prBlock,y
	sta (kPtr2),y
	dey
	bpl @g
	bra @ok
@set:	ldy #PREFS_SIZE - 1
@s:	lda (kPtr2),y
	sta prBlock,y
	dey
	bpl @s
	jsr Apply
	bra @ok
@aset:	ldy #0
@as:	lda (kPtr2),y
	sta alTab,y
	iny
	bne @as
	jsr Past
@ok:	ldx #0
	rts
@desk:	cmp #DESK_SET
	beq @dset
	bcs @bad
	ldy #DESK_SIZE - 1      ; DESK_GET
@dg:	lda deskPath,y
	sta (kPtr2),y
	dey
	bpl @dg
	bra @ok
@dset:	ldy #DESK_SIZE - 1
@ds:	lda (kPtr2),y
	sta deskPath,y
	dey
	bpl @ds
	jsr Keep
	bra @ok
@bad:	cmp #SP_BAR             ; (V120: the kernel's own, bank T)
	beq @bar
	ldx #INV_RECORD
	rts
@bar:	jmp BarDesk

; deskPath into bank S's pristine copy (a crash copies the banks back from
; it: V50); r0-r3 kept
Keep:	ldx #7
@p:	lda r0,x
	pha
	dex
	bpl @p
	LoadW r0, deskPath
	LoadW r1, deskPath
	LoadW r2, DESK_SIZE
	lda kBankBase
	clc
	adc #BANK_S
	sta r3L
	sec
	sbc #KCOPY_BANKS
	sta r3H
	jsr k_BankCopy
	ldx #0
@q:	pla
	sta r0,x
	inx
	cpx #8
	bne @q
	rts

; the block's live parts: blankDelay, the flags, the volume
Apply:	MoveW prBlock + 4, blankDelay
	lda prBlock + 6
	sta kPrefs
	lda prBlock + PREFS_VOLUME
	bmi @v                  ; (PREFS_VOLSET: stored since V72)
	lda #0                  ; (an older block: full volume)
@v:	and #63
	sta kSndAtt
	rts

; every armed entry already due: done
Past:	ldx #0
@1:	lda alTab + 5,x
	cmp #ARMED
	bne @2
	jsr Due
	bcc @2
	lda #DONE
	sta alTab + 5,x
@2:	txa
	clc
	adc #ALARM_SIZE
	tax
	bne @1
	rts

; c set if entry x's time (year .. minute) is now or earlier; keeps x
Due:	stx kTmp
	ldy #0
@1:	lda alTab,x
	cmp year,y
	bcc @yes                ; earlier
	bne @no                 ; later
	inx
	iny
	cpy #5
	bne @1
@yes:	ldx kTmp
	sec
	rts
@no:	ldx kTmp
	clc
	rts

;---------------------------------------------------------------
; AlarmCheck (ClockPoll, once a second): the first armed entry that is
; due: its box (AlarmBox, bank U: c set while another box is open, then
; it waits), then done. r0-r15 kept (the entry goes to AlarmBox in them).
;---------------------------------------------------------------
AlarmCheck:
	ldx #LK_TICK            ; (V74: the menu bar's clock, bank T)
	FARCALL Look
	bit alBusy
	bmi @r
	ldx #0
@e:	lda alTab + 5,x
	cmp #ARMED
	bne @n
	jsr Due
	bcs @fire
@n:	txa
	clc
	adc #ALARM_SIZE
	tax
	bne @e
@r:	rts
@fire:	LoadB alBusy, $80
	phx
	txa                     ; (x: the entry's last byte)
	ora #ALARM_SIZE - 1
	tax
	ldy #31
@k:	lda r0,y                ; r0-r15 kept, the entry in them
	sta regs,y
	lda alTab,x
	sta r0,y
	dex
	dey
	bpl @k
	LoadB kKeyAct, $80      ; (a blanked screen wakes, V51)
	FARCALL AlarmBox
	plx
	bcs @w                  ; (a box open: next time)
	lda #DONE
	sta alTab + 5,x
@w:	ldy #31
@b:	lda regs,y
	sta r0,y
	dey
	bpl @b
	stz alBusy
	rts

;---------------------------------------------------------------
; SysLoad (Init, CrashInit): the settings and the alarms from the system
; folder, if they are there; the clock read first (the entries already
; due are marked done). The video mode is Init's.
;---------------------------------------------------------------
SysLoad:
	jsr ClockRead
	LoadW kPtr2, PrefsName
	jsr Open
	bcs @a
	LoadW r0, alTab
	LoadW r1, PREFS_SIZE
	jsr Read
	bne @a                  ; (short: closed)
	jsr Close
	ldy #PREFS_SIZE - 1
@c:	lda alTab,y
	sta prBlock,y
	dey
	bpl @c
	jsr Apply
	jsr DefColors
@a:	LoadW kPtr2, AlarmsName
	jsr Open
	bcs @r
	ldy #0                  ; (a short file: the rest empty)
	tya
@z:	sta alTab,y
	iny
	bne @z
	LoadW r0, alTab
	LoadW r1, ALARM_SIZE * ALARM_MAX
	jsr Read
	bne @p
	jsr Close
@p:	jmp Past
@r:	ldy #0                  ; (none: an empty table, not Open's bytes)
	tya
@z2:	sta alTab,y
	iny
	bne @z2
	rts

; open the file named at kPtr2 in /VERANDA/.SYSTEM, else in /VERANDA (a card
; not set up yet, V71), else in the root, and read
; past its first 508 bytes (into alTab); c clear: open (fh)
Open:	MoveW kPtr2, nameP
	stz dirI
@d:	ldx dirI                ; NAMEBUF = the folder + the name
	ldy #0
@p:	lda Dirs,x
	beq @p1
	sta NAMEBUF,y
	inx
	iny
	bne @p
@p1:	inx
	stx dirI                ; (the next folder)
	MoveW nameP, kPtr2
	tya
	tax
	ldy #0
@n:	lda (kPtr2),y
	sta NAMEBUF,x
	inx
	iny
	cmp #0
	bne @n
	LoadW r0, NAMEBUF
	lda #'r'
	FARCALL k_FOpen
	sta fh
	cpx #0
	bne @next               ; (refused: nothing open)
	lda dosStatus
	cmp #20
	bcc @ok
	lda fh                  ; (not there)
	FARCALL k_FClose
@next:	ldx dirI
	lda Dirs,x
	bne @d
	sec
	rts
@ok:	LoadW r0, alTab         ; the entry, the signature and the info block
	LoadW r1, 254
	jsr Read
	bne @bad
	LoadW r0, alTab
	LoadW r1, 254
	jsr Read
	bne @bad
	clc
	rts
@bad:	sec                     ; (closed by Read)
	rts

; read r1 bytes into r0 (bank S); z set if all came; else the file is
; closed (z clear). Read leaves it open: Close after the last read.
Read:	MoveW r1, cnt
	lda fh
	FARCALL k_FRead
	lda r1L
	cmp cnt
	bne Close
	lda r1H
	cmp cnt+1
	bne Close
	rts
Close:	lda fh
	FARCALL k_FClose
	lda #1                  ; z clear
	rts

.segment "RODATA"

Dirs:		.byte VR_DATAPATH, 0, VR_SYSPATH, 0, VR_ROOTPATH, 0, 0
PrefsName:	.byte "Veranda Prefs.cvt", 0
AlarmsName:	.byte "Veranda Alarms.cvt", 0
