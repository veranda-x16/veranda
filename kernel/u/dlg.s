; Veranda bank U: dialog boxes (DoDlgBox, RstrFrmDialogue), as GEOS 64
; behaves, written from a description of it (docs/DECISIONS.md V15)
;
; The table: byte 0 DEF_DB_POS (bit 7) or the position after it (top,
; bottom bytes, left, right words; WIDE_DB, bit 5: top and bottom words),
; bits 0-4 the shadow's pattern (0: none); then the items, 0 ends them.
;
; DoDlgBox keeps the application's state (GEOS's variables, its menus and
; icons, processes, sleeping routines, GetString's state, sprites 1-7),
; starts a fresh one, draws the shadow (the box moved 8 right and down),
; the box (pattern 0, a solid frame), the items, then the icons; then runs
; the main loop until RstrFrmDialogue, which puts the state back, recovers
; the shadow and the box, and returns from DoDlgBox with r0L = sysDBData.
; The caller's r5-r10 are given back to every item.
;
; DBGETFILES x, y: a list of the files of type r7L (and of class r10, if
; not 0: equal up to its 0) at the box's left + x, top + y: FindFTypes into
; dbFileNames (DB_MAX_FILES), sorted by name; five rows of 11 pixels,
; 124 wide, a strip under it (left half up, right half down: one row a
; click). A click selects a name (inverted) and copies it to r5's buffer;
; the first is selected at the start; a second click on the selected name
; within 30 frames is OPEN. No file: the box returns at once with
; DBGETFILES and r5's buffer empty (docs/DECISIONS.md V22).

.include "kernel.inc"

.export k_DoDlgBox, k_RstrFrmDialogue, DlgKeyOK, DlgStrDone, DlgSysOpv, DlgIcon, DlgFiles, dlgOn
.import Div8, Covers, UiFont
.import AppJsr, kAppVec, kMenuRect, sysFont, k_MainLoop, SleepSave, SleepRestore
.import IconOK, IconCancel, IconYes, IconNo, IconOpen, IconDisk
.import menuState, menuStateEnd, strState, strStateEnd, k_DoIcons, k_WGetString, fState, iconBusy, uiTimer, uiWake
.import UnderPush, UnderPop, UnderSpill, uX, uW, uTop, uBot, k_Beep, kSndReq
.global S_k_SetPattern, S_k_WRectangle, S_k_WFrameRectangle, S_k_UseSystemFont, S_k_WPutString
.global S_k_WRecoverRectangle, S_k_WStartMouseMode, S_k_GraphicsString, S_ProcSave, S_ProcRestore
.global S_DlgKeyOK, S_DlgStrDone, S_DlgSysOpv

DB_ICONS = 8
FL_W    = 124                   ; the file list: width
FL_ROWH = 11                    ; a row
FL_ROWS = 5
FL_SEP  = 1 + FL_ROWS * FL_ROWH ; the line above the strip
FL_H    = FL_SEP + 12           ; the whole height

.segment "BSS"

desc:	.res 2                  ; the table
items:	.res 1                  ; the offset of the item being read
pat:	.res 1                  ; the shadow's pattern
bTop:	.res 2                  ; the box
bBot:	.res 2
bLeft:	.res 2
bRight:	.res 2
card:	.res 1                  ; its left card
regs:	.res 12                 ; the caller's r5-r10
dlgSP:	.res 1
under:	.res 1                  ; $FF: on the save-under stack
dcov:	.res 1                  ; $FF: its cards' colours put aside
dcard:	.res 4                  ; those cards (kTmp's form: x, width, y, height)
appRV:	.res 2                  ; the application's RecoverVector, dispBufferOn
appDB:	.res 1
; the application's state
sZp:	.res $39 - $22          ; curPattern .. rightMargin
sVars:	.res $0549 - $0523      ; appMain .. stringY
sVarsW:	.res $056C - $0562      ; windowTopW .. stringYW
sMenu:	.res 160                ; (menuState .. menuStateEnd, checked below)
sStr:	.res 12
sRect:	.res 8
sFont:	.res FONT_STATE
sSpr:	.res 7                  ; sprites 1-7: z-depth bytes
sPtr:	.res 1                  ; pointerShape (V51: the arrow in the box)
sUi:	.res 2                  ; uiTimer, uiWake: a flash the box came in (V68)
dlgOn:	.res 1                  ; $80: a box is open (a press outside it beeps)
; the dialog's icon table (WIDE_ICONS): count, x (0: the pointer stays), y
icons:	.res 5 + 10 * DB_ICONS
; the file list (DBGETFILES): fN 0 when there is none
fN:	.res 1                  ; names
fTop:	.res 1                  ; the first one shown
fSel:	.res 1                  ; the one selected
fX:	.res 2                  ; the list's left, top
fY:	.res 2
fRow:	.res 1
fIdx:	.res 1
si:	.res 1                  ; the sort
sj:	.res 1
sk:	.res 1
ord:	.res DB_MAX_FILES       ; the names in order (indices)

.segment "CODE"

.assert menuStateEnd - menuState <= 160, error, "dlg.s: sMenu too small"
.assert strStateEnd - strState <= 12, error, "dlg.s: sStr too small"

k_DoDlgBox:
	tsx                     ; RstrFrmDialogue returns from here
	stx dlgSP
	MoveW r0, desc
	ldx #11
@r:	lda r5,x
	sta regs,x
	dex
	bpl @r
	jsr Keep
	jsr Fresh
	stz sysDBData
	jsr Geometry
	LoadB dlgOn, $80
	jsr Draw
	; the pointer on, where it is
	lda #0
	FARCALL k_WStartMouseMode
	jsr UiFont
	stz currentMode
	; the items
@item:	jsr Regs
	jsr Byte
	beq @end
	cmp #DBUSRICON + 2
	bcs @item               ; (unknown: nothing)
	asl
	tax
	lda Items - 2,x
	sta kTmp
	lda Items - 1,x
	sta kTmp+1
	jsr @go
	bra @item
@go:	jmp (kTmp)
@end:	lda icons
	and #$7F
	beq @run
	LoadW r0, icons
	jsr k_DoIcons
@run:	jmp k_MainLoop

Items:	.word SysIcon, SysIcon, SysIcon, SysIcon, SysIcon, SysIcon       ; 1-6
	.word Skip2, Skip2, Skip2, Skip2                                 ; 7-10 (FUTURE)
	.word TxtStr, VarStr, GetStr, SysOpv, GrphStr, GetFiles, OpVec   ; 11-17
	.word UsrIcon, UsrRout                                           ; 18, 19

; the next table byte (z set if 0)
Byte:	MoveW desc, kPtr
	ldy items
	inc items
	lda (kPtr),y
	rts

; the caller's r5-r10 back
Regs:	ldx #11
@1:	lda regs,x
	sta r5,x
	dex
	bpl @1
	rts

;---------------------------------------------------------------
; the state
;---------------------------------------------------------------
Keep:	ldx #$39 - $22 - 1
@z:	lda $22,x
	sta sZp,x
	dex
	bpl @z
	ldx #$0549 - $0523 - 1
@v:	lda $0523,x
	sta sVars,x
	dex
	bpl @v
	ldx #$056C - $0562 - 1
@w:	lda $0562,x
	sta sVarsW,x
	dex
	bpl @w
	ldx #<(menuStateEnd - menuState - 1)   ; (more than 128 bytes:
@m:	lda menuState,x                        ; not bpl, DECISIONS V40)
	sta sMenu,x
	dex
	cpx #$FF
	bne @m
	ldx #<(strStateEnd - strState - 1)
@s:	lda strState,x
	sta sStr,x
	dex
	bpl @s
	ldx #7
@k:	lda kMenuRect,x
	sta sRect,x
	dex
	bpl @k
	ldx #FONT_STATE - 1
@fk:	lda sysFont,x
	sta sFont,x
	dex
	bpl @fk
	MoveW RecoverVector, appRV
	MoveB dispBufferOn, appDB
	MoveB pointerShape, sPtr
	stz pointerShape
	MoveB uiTimer, sUi      ; a menu's or an icon's flash: it goes on
	MoveB uiWake, sUi+1     ; after the box (V68)
	FARCALL ProcSave
	jsr SleepSave
	; sprites 1-7: their z-depth kept, off
	ldx #1
@sp:	jsr SprZ
	lda VERA_DATA0
	sta sSpr - 1,x
	jsr SprZ
	stz VERA_DATA0
	inx
	cpx #8
	bne @sp
	rts

; port 0 at sprite x's byte 6 (z-depth), no increment
SprZ:	stz VERA_CTRL
	txa
	asl
	asl
	asl
	clc
	adc #<(VRAM_SPRATTR + 6)
	sta VERA_ADDR_L
	lda #>(VRAM_SPRATTR + 6)
	adc #0
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^VRAM_SPRATTR
	rts

Restore:
	php
	sei
	ldx #$39 - $22 - 1
@z:	lda sZp,x
	sta $22,x
	dex
	bpl @z
	ldx #$0549 - $0523 - 1
@v:	lda sVars,x
	sta $0523,x
	dex
	bpl @v
	ldx #$056C - $0562 - 1
@w:	lda sVarsW,x
	sta $0562,x
	dex
	bpl @w
	ldx #<(menuStateEnd - menuState - 1)
@m:	lda sMenu,x
	sta menuState,x
	dex
	cpx #$FF
	bne @m
	ldx #<(strStateEnd - strState - 1)
@s:	lda sStr,x
	sta strState,x
	dex
	bpl @s
	ldx #7
@k:	lda sRect,x
	sta kMenuRect,x
	dex
	bpl @k
	ldx #FONT_STATE - 1
@fb:	lda sFont,x
	sta sysFont,x
	dex
	bpl @fb
	MoveB sPtr, pointerShape
	MoveB sUi, uiTimer
	MoveB sUi+1, uiWake
	ldx #1
@sp:	jsr SprZ
	lda sSpr - 1,x
	sta VERA_DATA0
	inx
	cpx #8
	bne @sp
	plp
	FARCALL ProcRestore
	jmp SleepRestore

; a fresh state for the dialog (GEOS's start-up values)
Fresh:	stz currentMode
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	stz mouseOn
	stz windowTopW
	stz windowTopW+1
	stz windowTop
	lda screenHeight
	sec
	sbc #1
	sta windowBottomW
	lda screenHeight+1
	sbc #0
	sta windowBottomW+1
	beq @b
	lda #$FF
	bra @b1
@b:	lda windowBottomW
@b1:	sta windowBottom
	stz leftMargin
	stz leftMargin+1
	lda screenWidth
	sec
	sbc #1
	sta rightMargin
	lda screenWidth+1
	sbc #0
	sta rightMargin+1
	stz pressFlag
	php                     ; (the interrupt's vectors among them: V68)
	sei
	ldx #$0537 - $0523 - 1  ; appMain .. alarmTmtVector
@v:	stz $0523,x
	dex
	bpl @v
	plp
	stz uiWake              ; no flash of the program's in the box (V68)
	stz fState
	stz iconBusy
	stz RecoverVector
	stz RecoverVector+1
	LoadB selectionFlash, 10
	stz alphaFlag
	LoadB iconSelFlg, ST_FLASH
	stz faultData
	stz menuNumber
	LoadB icons, WIDE_ICONS ; no icons yet
	stz icons+1
	stz icons+2
	stz items
	stz fN
	rts

; the box from the table; items = its first item
Geometry:
	jsr Byte
	sta kTmp+2
	and #%00011111
	sta pat
	bit kTmp+2
	bmi @def
	jmp @own
@def:	; the default box: GEOS's (64-255, 32-127) at 320 wide, else centred
	lda screenWidth+1
	cmp #>320
	bne @c
	lda screenWidth
	cmp #<320
	bne @c
	LoadW bLeft, DEF_DB_LEFT
	LoadW bRight, DEF_DB_RIGHT
	LoadW bTop, DEF_DB_TOP
	LoadW bBot, DEF_DB_BOT
	jmp @card
@c:	lda screenWidth         ; left = (width - 192) / 2
	sec
	sbc #192
	sta bLeft
	lda screenWidth+1
	sbc #0
	lsr
	sta bLeft+1
	ror bLeft
	lda screenHeight        ; top = (height - 96) / 2
	sec
	sbc #96
	sta bTop
	lda screenHeight+1
	sbc #0
	lsr
	sta bTop+1
	ror bTop
	lda bLeft
	clc
	adc #191
	sta bRight
	lda bLeft+1
	adc #0
	sta bRight+1
	lda bTop
	clc
	adc #95
	sta bBot
	lda bTop+1
	adc #0
	sta bBot+1
	jmp @card
@own:	stz bTop+1
	stz bBot+1
	jsr Byte
	sta bTop
	bit kTmp+2              ; WIDE_DB: words
	lda kTmp+2
	and #WIDE_DB
	beq @o1
	jsr Byte
	sta bTop+1
@o1:	jsr Byte
	sta bBot
	lda kTmp+2
	and #WIDE_DB
	beq @o2
	jsr Byte
	sta bBot+1
@o2:	jsr Byte
	sta bLeft
	jsr Byte
	sta bLeft+1
	jsr Byte
	sta bRight
	jsr Byte
	sta bRight+1
@card:	lda bLeft
	ldx bLeft+1
	jsr Div8
	sta card
	rts

; r3, r11, r4, r12 = the box (a = 0) or the shadow (a = 8)
Box:	sta kTmp+3
	lda bLeft
	clc
	adc kTmp+3
	sta r3
	lda bLeft+1
	adc #0
	sta r3+1
	lda bRight
	clc
	adc kTmp+3
	sta r4
	lda bRight+1
	adc #0
	sta r4+1
	lda bTop
	clc
	adc kTmp+3
	sta r11
	lda bTop+1
	adc #0
	sta r11+1
	lda bBot
	clc
	adc kTmp+3
	sta r12
	lda bBot+1
	adc #0
	sta r12+1
	MoveB r11, r2L          ; (classic: RecoverVector)
	MoveB r12, r2H
	rts

Draw:	; the box and its shadow: its cards in the normal colours; what it
	; covers onto the save-under stack, if it comes back that way
	MoveB card, uX
	lda bRight              ; to the shadow's right card
	ldx bRight+1
	jsr Div8
	clc
	adc #2
	sec
	sbc card
	sta uW
	MoveW bTop, uTop
	lda bBot
	clc
	adc #8
	sta uBot
	lda bBot+1
	adc #0
	sta uBot+1
	jsr Covers
	sta dcov
	ldx #3
@k:	lda kTmp,x
	sta dcard,x
	dex
	bpl @k
	stz under
	lda appRV
	ora appRV+1
	bne @d
	bit appDB
	bvs @d
	jsr UnderPush
	bcs @sp
	dec under
	bra @d
@sp:	jsr UnderSpill          ; (no room: the back screen keeps it, V84)
@d:	LoadB dispBufferOn, ST_WR_FORE | ST_WRGS_FORE
	lda pat
	beq @box
	FARCALL k_SetPattern
	lda #8
	jsr Box
	FARCALL k_WRectangle
@box:	lda #0
	FARCALL k_SetPattern
	lda #0
	jsr Box
	FARCALL k_WRectangle
	MoveW bRight, rightMargin
	lda #0
	jsr Box
	lda #$FF
	FARCALL k_WFrameRectangle
	rts

;---------------------------------------------------------------
; the items
;---------------------------------------------------------------
Skip2:	jsr Byte
	jmp Byte

; x = left + byte (r11), y = top + byte (r12)
XY:	jsr Byte
	clc
	adc bLeft
	sta r11
	lda bLeft+1
	adc #0
	sta r11+1
	jsr Byte
	clc
	adc bTop
	sta r12
	lda bTop+1
	adc #0
	sta r12+1
	rts

; a word from the table into r0
Word:	jsr Byte
	pha
	jsr Byte
	sta r0H
	pla
	sta r0L
	rts

TxtStr:	jsr XY
	jsr Word
Str:	FARCALL k_WPutString
	rts

VarStr:	jsr XY
	jsr Byte                ; a zero page pointer
	tax
	lda 0,x
	sta r0L
	lda 1,x
	sta r0H
	bra Str

GetStr:	jsr XY
	jsr Byte
	tax
	lda 0,x
	sta r0L
	lda 1,x
	sta r0H
	jsr Byte
	sta r2L
	LoadW keyVector, S_DlgStrDone
	stz r1L
	jmp k_WGetString

SysOpv:	LoadW otherPressVec, S_DlgSysOpv
	rts

GrphStr:
	jsr Word
	FARCALL k_GraphicsString
	rts

; the file list (above)
GetFiles:
	jsr XY
	MoveW r11, fX
	MoveW r12, fY
	LoadW r6, dbFileNames   ; (r7L, r10: the caller's)
	LoadB r7H, DB_MAX_FILES
	FARCALL k_FindFTypes
	lda #DB_MAX_FILES
	sec
	sbc r7H
	sta fN
	bne @some
	MoveW regs, kPtr        ; none: r5's name empty, the box ends
	lda #0
	tay
	sta (kPtr),y
	lda #DBGETFILES
	jmp End
@some:	jsr Sort
	stz fTop
	stz fSel
	; the frame, the strip's line and divider, the arrows
	lda #0
	ldx #FL_W - 1
	jsr FXs
	lda #0
	ldx #FL_H - 1
	jsr FYs
	lda #$FF
	FARCALL k_WFrameRectangle
	lda #FL_SEP
	jsr FYs
	lda #$FF
	FARCALL k_WHorizontalLine
	lda #0
	ldx #FL_W / 2
	jsr FXs
	lda #FL_SEP
	ldx #FL_H - 1
	jsr FYs
	lda #$FF
	FARCALL k_WVerticalLine
	stz fRow                ; row i of the arrows: i pixels each side
@ar:	lda #FL_W / 4
	sec
	sbc fRow
	pha
	lda #FL_W / 4
	clc
	adc fRow
	tax
	pla
	jsr FXs
	lda #FL_SEP + 4
	clc
	adc fRow
	jsr FYs
	lda #$FF
	FARCALL k_WHorizontalLine
	lda #FL_W * 3 / 4
	sec
	sbc fRow
	pha
	lda #FL_W * 3 / 4
	clc
	adc fRow
	tax
	pla
	jsr FXs
	lda #FL_SEP + 7
	sec
	sbc fRow
	jsr FYs
	lda #$FF
	FARCALL k_WHorizontalLine
	inc fRow
	lda fRow
	cmp #4
	bne @ar
	jsr FNames
	jmp FCopy

; r3 = fX + a, r4 = fX + x
FXs:	clc
	adc fX
	sta r3
	lda fX+1
	adc #0
	sta r3+1
	txa
	clc
	adc fX
	sta r4
	lda fX+1
	adc #0
	sta r4+1
	rts

; r11 = fY + a, r12 = fY + x
FYs:	clc
	adc fY
	sta r11
	lda fY+1
	adc #0
	sta r11+1
	txa
	clc
	adc fY
	sta r12
	lda fY+1
	adc #0
	sta r12+1
	rts

; a/x = name a's address (dbFileNames + 17 a); y kept
NameA:	sta kTmp
	stz kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	asl
	rol kTmp+1
	clc
	adc kTmp
	bcc @1
	inc kTmp+1
@1:	clc
	adc #<dbFileNames
	pha
	lda kTmp+1
	adc #>dbFileNames
	tax
	pla
	rts

; ord = the names sorted (insertion; byte order)
Sort:	ldx #0
@id:	txa
	sta ord,x
	inx
	cpx fN
	bne @id
	LoadB si, 1
@o:	lda si
	cmp fN
	bcs @r
	tax
	lda ord,x
	sta sk
	stx sj
@in:	ldx sj
	beq @put
	lda ord - 1,x
	jsr NameA
	sta kPtr
	stx kPtr+1
	lda sk
	jsr NameA
	sta kPtr2
	stx kPtr2+1
	ldy #0                  ; name kPtr after name kPtr2?
@c:	lda (kPtr),y
	cmp (kPtr2),y
	bne @d
	cmp #0
	beq @put                ; equal
	iny
	bra @c
@d:	bcc @put
	ldx sj
	lda ord - 1,x
	sta ord,x
	dec sj
	bra @in
@put:	ldx sj
	lda sk
	sta ord,x
	inc si
	bra @o
@r:	rts

; the selected name to r5's buffer (at most 16 characters and a 0)
FCopy:	ldx fSel
	lda ord,x
	jsr NameA
	sta kPtr
	stx kPtr+1
	MoveW regs, kPtr2
	ldy #0
@1:	lda (kPtr),y
	sta (kPtr2),y
	beq @r
	iny
	cpy #16
	bne @1
	lda #0
	sta (kPtr2),y
@r:	rts

; the five rows: cleared, the names from fTop, the selected one inverted;
; in the system font, whatever uiFont is (its rows are 11 lines: V79)
FNames:	FARCALL k_UseSystemFont
	lda #0
	FARCALL k_SetPattern
	lda #FL_W - 3           ; the names end inside the list
	ldx #0
	jsr FXs
	MoveW r3, rightMargin
	stz fRow
@row:	jsr RowRect
	FARCALL k_WRectangle
	lda fRow
	clc
	adc fTop
	sta fIdx
	cmp fN
	bcs @next
	tax
	lda ord,x
	jsr NameA
	sta r0L
	stx r0H
	lda #3
	jsr FXs
	MoveW r3, r11
	ldx fRow
	lda RowY,x
	clc
	adc #7                  ; the baseline
	jsr FYs
	MoveW r11, r12
	MoveW r3, r11
	FARCALL k_WPutString
	lda fIdx
	cmp fSel
	bne @next
	jsr RowRect
	FARCALL k_WInvertRectangle
@next:	inc fRow
	lda fRow
	cmp #FL_ROWS
	bne @row
	MoveW bRight, rightMargin
	jmp UiFont

; r3, r11, r4, r12 = row fRow's rectangle, inside the frame
RowRect:
	lda #1
	ldx #FL_W - 2
	jsr FXs
	ldx fRow
	lda RowY,x
	pha
	clc
	adc #FL_ROWH - 1
	tax
	pla
	jmp FYs
RowY:	.byte 1, 1 + FL_ROWH, 1 + 2 * FL_ROWH, 1 + 3 * FL_ROWH, 1 + 4 * FL_ROWH

; a press (UiClick, after the icons): c set if the file list took it
DlgFiles:
	lda fN
	beq @no
	lda mouseXPos           ; inside the frame?
	sec
	sbc fX
	sta kTmp
	lda mouseXPos+1
	sbc fX+1
	bne @no
	lda kTmp
	beq @no
	cmp #FL_W - 1
	bcs @no
	lda mouseYPosW
	sec
	sbc fY
	tax
	lda mouseYPosW+1
	sbc fY+1
	bne @no
	txa
	beq @no
	cmp #FL_SEP
	bcc @list
	cmp #FL_H - 1
	bcs @no
	lda kTmp                ; the strip: up or down
	cmp #FL_W / 2
	bcs @down
	lda fTop
	beq @took
	dec fTop
	bra @show
@down:	lda fTop
	clc
	adc #FL_ROWS
	cmp fN
	bcs @took
	inc fTop
@show:	jsr FNames
@took:	sec
	rts
@no:	jmp DlgOut
@list:	sbc #0                  ; (c clear: - 1) the row
	ldx #0
@dv:	cmp #FL_ROWH
	bcc @rw
	sbc #FL_ROWH
	inx
	bra @dv
@rw:	txa
	clc
	adc fTop
	cmp fN
	bcs @took
	cmp fSel
	bne @new
	lda dblClickCount       ; the selected one again, soon: OPEN
	beq @arm
	stz dblClickCount
	lda #OPEN
	jmp DlgIcon
@new:	sta fSel
	jsr FNames
	jsr FCopy
@arm:	LoadB dblClickCount, 30
	sec
	rts

; a press no item took: outside an open box, the beep (V51); c clear
DlgOut:	bit dlgOn
	bpl @r
	CmpW mouseYPosW, bTop
	bcc @out
	CmpW bBot, mouseYPosW
	bcc @out
	CmpW mouseXPos, bLeft
	bcc @out
	CmpW bRight, mouseXPos
	bcs @r
@out:	jsr k_Beep
@r:	clc
	rts

OpVec:	jsr Word
	MoveW r0, otherPressVec
	rts

UsrRout:
	jsr Word
	MoveW r0, kAppVec
	jmp AppJsr

; a system icon: a = its number (1-6) was the command
SysIcon:
	MoveW desc, kPtr        ; (the command again)
	ldy items
	dey
	lda (kPtr),y
	pha
	cmp #YES                ; YES or NO: a question (V69: its sound)
	bcc @0
	cmp #NO + 1
	bcs @0
	ldx #SND_WARNING
	stx kSndReq
@0:	cmp #OK
	bne @1
	lda keyVector           ; OK: Return ends the box too
	ora keyVector+1
	bne @1
	LoadW keyVector, S_DlgKeyOK
@1:	pla
	tax
	lda SysPicL - 1,x
	sta r0L
	lda SysPicH - 1,x
	sta r0H
	stx r1L                 ; the routine: the number (DlgIcon knows it)
	stz r1H
	LoadB r2L, 6
	LoadB r2H, 16
	bra Add

SysPicL: .byte <IconOK, <IconCancel, <IconYes, <IconNo, <IconOpen, <IconDisk
SysPicH: .byte >IconOK, >IconCancel, >IconYes, >IconNo, >IconOpen, >IconDisk

; a user icon: x, y, its descriptor (picture, x, y, width, height, routine)
UsrIcon:
	jsr Byte                ; (x, y: below)
	jsr Byte
	jsr Word
	ldy #0
	lda (r0),y
	pha
	iny
	lda (r0),y
	pha
	ldy #4
	lda (r0),y
	sta r2L
	iny
	lda (r0),y
	sta r2H
	iny
	lda (r0),y
	sta r1L
	iny
	lda (r0),y
	sta r1H
	pla
	sta r0H
	pla
	sta r0L
	dec items               ; back to its x and y
	dec items
	dec items
	dec items
	jsr Add
	inc items
	inc items
	rts

; add an icon: r0 picture, r2L width, r2H height, r1 routine; x and y the
; next two table bytes (cards from the box's left card, pixels from its
; top). The dialog's icon table is WIDE_ICONS: entries of 10 bytes, from 5
Add:	lda icons
	and #$7F
	cmp #DB_ICONS
	bcs @full
	sta kTmp
	asl
	asl
	asl
	clc
	adc kTmp
	clc
	adc kTmp
	tax                     ; 10n
	lda r0L
	sta icons + 5,x
	lda r0H
	sta icons + 6,x
	jsr Byte
	clc
	adc card
	sta icons + 7,x
	jsr Byte
	clc
	adc bTop
	sta icons + 8,x
	lda bTop+1
	adc #0
	sta icons + 13,x
	lda r2L
	sta icons + 9,x
	lda r2H
	sta icons + 10,x
	stz icons + 14,x
	lda r1L
	sta icons + 11,x
	lda r1H
	sta icons + 12,x
	inc icons
	rts
@full:	jmp Skip2

;---------------------------------------------------------------
; the handlers (resident stubs in the vectors) and the end
;---------------------------------------------------------------
DlgKeyOK:
	lda keyData
	cmp #CR
	bne @r
	lda #OK
	bra End
@r:	rts

DlgStrDone:
	lda #DBGETSTRING
	bra End

DlgSysOpv:
	bit mouseData
	bmi @r
	lda #DBSYSOPV
	bra End
@r:	rts

; a system icon was chosen: a = its number
DlgIcon:
End:	sta sysDBData
k_RstrFrmDialogue:
	stz fN
	stz dlgOn
	jsr Restore
	lda #0                  ; a banked font: its index table (V62)
	FARCALL FontSel
	lda dcov                ; the colours back
	beq @c
	stz dcov
	ldx #3
@k:	lda dcard,x
	sta kTmp,x
	dex
	bpl @k
	lda #1
	FARCALL ColorCover
@c:	; the shadow, then the box: the application's RecoverVector, the
	; save-under stack, or the back screen
	lda under
	beq @rv
	jsr UnderPop
	bra @ret
@rv:	lda pat
	beq @b
	lda #8
	jsr Rec
@b:	lda #0
	jsr Rec
@ret:	lda sysDBData
	sta r0L
	ldx dlgSP
	txs
	rts                     ; from DoDlgBox

Rec:	jsr Box
	lda RecoverVector
	ora RecoverVector+1
	beq @back
	MoveW RecoverVector, kAppVec
	jmp AppJsr
@back:	FARCALL k_WRecoverRectangle
	rts
