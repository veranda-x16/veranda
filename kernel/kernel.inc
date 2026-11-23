; Veranda kernel: internal definitions (not part of the API)

.ifndef KERNEL_INC
KERNEL_INC = 1

.include "veranda.inc"
.include "x16hw.inc"
.include "macros.inc"

.setcpu "65C02"

; kernel zero page: GEOS's variables end at $3E; $3F-$4F are the kernel's
gPtr            = $3F           ; 2: FarCall's inline parameters
fbBufPtr        = $41           ; 2: the span engine's source buffer
kPtr            = $43           ; 2: scratch pointer (any bank, not across calls)
kPtr2           = $45           ; 2: scratch pointer
kTmp            = $47           ; 4: scratch

FONT_STATE      = 3             ; sysFont, fontBank, fontPage (resident, in this order)
IDX_COPY        = $C000 - 2 * 97 ; bank G: the current banked font's index table (V62)
STRIP_ROWS      = 32            ; bank G: text's strip (the tallest font)
ROWBUF          = 12            ; FontRow: the most bytes a glyph row (glyphs up to 88 pixels)

; bank T's Look (DECISIONS V74: kernel/t/look.s), x = what (one resident
; stub for all)
LK_BAR          = 0             ; the menu bar's line, colours and mark
LK_CLOCK        = 2             ; its sound and clock (kTmp: left, top)
LK_HI           = 4             ; cards' shown colour (kTmp: x w y h; a)
LK_OFF          = 6             ; no bar now (DoMenu, SetVideoMode)
LK_TICK         = 8             ; the clock again if the minute changed
LK_ROWS         = 10            ; a UI font glyph's rows for bank G (V81)
LK_CLICK        = 12            ; a press on the bar's sound or clock: c set (V120)
LK_PUSH         = 14            ; (V146) bank U's FontPush: the font, style, margins kept
LK_POP          = 16            ; and put back
LK_ITEM         = 18            ; a list's item: its separator, its text, its key (Put)
SP_BAR          = $80           ; SysPrefs, the kernel's own: bank S's BarDesk (V120; no
				; resident stub of its own: the core is full)

; logical kernel banks (docs/PLAN.md 4.4): bank number = kBankBase + n
BANK_G          = 0             ; graphics, text, system font
BANK_G2         = 1             ; bitmaps, GraphicsString, sprites, classic shims
BANK_U          = 2             ; menus, icons, dialogs, text input
BANK_F          = 3             ; files
BANK_S          = 4             ; start-up, loader, time, mode
BANK_X          = 5             ; spare
BANK_P          = 6             ; printing: the PDF writer (V38)
BANK_T          = 7             ; fonts: the font service, the UI font (V62)
BANK_W          = 8             ; the switcher and the RAM banks (V83)
BANK_C          = 9             ; (V165) the canvas: Paint's 8 bpp picture, and room
KERNEL_BANKS    = 10            ; the kernel banks at the top of RAM
KCOPY_BANKS     = 9             ; (V165) G .. W have their pristine copy below them (V50);
				; bank C, the last, has none (one RAM bank kept for programs)
; the copies of the kernel banks go in two parts (r2 is 16 bits: 9 banks
; are 72 KB): KB_HALF banks from the first, then KB_HALF from bank
; KCOPY_BANKS / 2 (an odd count: the middle bank is copied twice)
KB_HALF         = (KCOPY_BANKS + 1) / 2

; the resident exit (DECISIONS V64, the RBOOT model): ToBASIC with
; TOBASIC_KEEP fills RAM bank RB = kBankBase - RB_BELOW, under the kernel
; banks' copy (free for BankAlloc while Veranda runs), with the resident
; core as it is then, the code that puts it back (RCore, RLow:
; kernel/s/reentry.s) and a descriptor, and leaves MEMTOP at $8800 with
; the bank count RB
RB_BELOW        = KCOPY_BANKS + 1 ; RB = kBankBase - 10
RB_SIG          = $A000         ; 8: "VERANDA" and RB_VERSION (RBOOT looks for it)
RB_VERSION      = 1
RB_CRC          = $A008         ; 2: CRC-16 (the ROM's memory_crc) of RB_HEAD .. RB_HEADEND-1
RB_HEAD         = $A00A
RB_BASE         = $A00A         ; kBankBase
RB_SELF         = $A00B         ; RB itself
RB_BANKS        = $A00C         ; MEMTOP as the loader found it: banks, x, y (kMemBanks ..)
RB_IMGCRC       = $A00F         ; 2: the resident image's CRC
RB_KCRC         = $A011         ; 2 x KCOPY_BANKS: each copied kernel bank's CRC
RB_CORE         = $A040         ; RCore (kernel/s/reentry.s): entered with RB mapped and
				; ROM bank 0; puts the resident core back, goes on in
				; RLow; returns c set only if the copy is damaged
RB_LOW          = $A100         ; RLow's image (run at RLOW_RUN)
RB_HEADEND      = $A200
.assert RB_KCRC + 2 * KCOPY_BANKS <= RB_CORE, error, "the descriptor overlaps RCore"
RB_DIR          = $A200         ; 64: curDirName when Veranda went to BASIC
RB_IMAGE        = $A300         ; the resident core $8800-$9EFF (RESIDENT_SIZE)
RLOW_RUN        = $0400         ; RLow runs there (fileHeader: unused then)
RB_ENTRY        = NEW_BASE      ; ReEntry: SYS 35328 (ToBASIC writes it over the
				; second jump table: kernel/s/reentry.s)
; the images in bank T (kernel/t/reentry.s; segment RBIMG at a fixed
; address, as bank S, linked apart, copies them with BankCopy)
RBI_ENTRY       = $BC00         ; ReEntry (96 bytes)
RBI_CORE        = $BC60         ; RCore (160)
RBI_SUM         = $BD00         ; RLowSum (256)
RBI_LOW         = $BE00         ; RLow (256)
RBI_ENTRYLEN    = $60
RBI_CORELEN     = $A0
RB_BANKOFF      = 9             ; ReEntry's byte with RB's number
RB_QUITOFF      = 8             ; (V73) Quit: ReEntry's "lda #RB" made "bra" to
RB_QUITBRA      = $26           ; its message (no bank read, nothing called)
; (V73) BASIC's zero page as the loader found it (CHRGET, TXTTAB, ...):
; programs may use $A9-$FF; ToBASIC puts it back before BASIC runs
BZP_START       = $A9
BZP_LEN         = $100 - BZP_START
RBI_BZP         = $BF00         ; bank T (with its pristine copy, V50)
RB_TOPHI        = $88           ; MEMTOP while BASIC runs with Veranda kept: $8800

; the switcher's own operations of TaskCtl (bank W, kernel/w/task.s; the
; API's are TASK_INFO .. TASK_ASIDE): a >= $80 only from the kernel
TC_POLL         = $80           ; ClockPoll: switchReq at the main loop's top level
TC_START        = $81           ; AppReset: x the info block's flags, y $80 the desktop
TC_DAKEEP       = $82           ; DaRun: the bank table kept
TC_DABACK       = $83           ; RstrAppl: it back, x the accessory's first bank freed
TC_FAIL         = $84           ; LdApplic failed (x the error): the desktop comes
TC_TAKE         = $85           ; the pack image: a = one more bank for the data
TC_DAPACK       = $86           ; DaRun: the application packed (x NO_BANKS: not)
TC_DAUNPACK     = $87           ; RstrAppl: it unpacked, the banks freed
C_TASKMSK       = $BF00         ; (V183) bank C's last page: each task on the card,
				; its own banks but the fonts as they were then
				; (TASK_MAX x 32; tools/kbuild.py keeps it free)
TC_NEXT         = $88           ; the unpack image: a = the chain's next bank
				; (V145: from the card in Roomy mode)
PK_RUN          = $0600         ; the pack image runs there (dbFileNames: the
				; system variables are put aside first, V83)
PK_BUF          = $0400         ; and its page buffer (fileHeader)
PK_N            = $07D0         ; the chain's banks: how many (dataLongName's
PK_LIST         = $07D1         ; end), and they (CHAIN_MAX)
CHAIN_MAX       = 40

; why the panic box came (kCrashWhy, kernel/res/crash.s)
CR_BRK          = 0
CR_PANIC        = 1
CR_STACK        = 2

; a call into another kernel bank (from the resident core, a bank or the
; application): a, x, y in; a, x, y and the flags out; the caller's RAM
; bank is restored (kernel/res/farcall.s; S_<name> is generated)
.macro FARCALL name
	.global .ident(.concat("S_", .string(name)))
	jsr .ident(.concat("S_", .string(name)))
.endmacro
; inside a routine FARCALL reached, the byte its caller pushed last is at
; $0100 + S + FAR_STACK: the caller's jsr (2 bytes), then FarGo's caller
; bank and FarRet - 1 (3); parameters on the stack (V80: FbCols, VCopy)
FAR_STACK       = 6

; byte to the emulator's console (nothing on hardware)
.macro LOGCHAR ch
	lda #ch
	sta EMU_STDOUT
.endmacro

.endif
