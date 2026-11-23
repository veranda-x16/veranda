; Veranda bank U: menus and icons
;
; GEOS 64's behaviour (geometry, order, the flash, the fault rules), written
; for Veranda from a description of it (docs/DECISIONS.md V14):
;
; A menu table: top, bottom (bytes), left, right (words), the flags byte
; (bit 7 VERTICAL, bit 6 CONSTRAINED, bit 5 WIDE_MENU, bits 0-4 the item
; count); with WIDE_MENU two more bytes, the high bytes of top and bottom;
; then 5 bytes an item: the text, the type (bit 7 SUB_MENU, bit 6
; DYN_SUB_MENU, else an action), the sub menu, routine or action.
;
; Drawing (the foreground only): the rectangle in pattern 0, a solid
; frame, the items in the system font, the separators (vertical menus: a
; line %01010101 on each inner item boundary, from left + 1 to right - 1;
; horizontal: a vertical line %10101010 from top + 1 to bottom - 1).
; Horizontal items: boundary 0 = left, each next one = the last + 4 + the
; text's width + 4, the text at boundary + 4, baseline top + 3 + the
; font's baseline; vertical: boundary i = top + i * (height + 5), the text
; at left + 4, baseline boundary + 3 + baseline.
;
; The flash of an action (invert, wait selectionFlash, invert, wait,
; invert, the action with a = the item) and of an icon run from the main
; loop (uiTimer, UiWake): the kernel waits without Sleep, whose
; continuation would run with the application's bank mapped.
;
; The Veranda look (DECISIONS V74; uiLook bit 7, LOOK_BAR, a native
; program's choice: classic tables never set it, so GEOS programs keep
; GEOS 64's look): a horizontal main menu is the menu bar: the full width,
; 16 lines (the table's top; a line under it), on palette entry 2's cards
; (the chrome), the Veranda mark at the left (bank T, kernel/t/look.s),
; item 0 in bold (the program's name) 24 pixels in, each item 6 pixels
; from its text on both sides and its limits on 8-pixel cards, so that
; the item open shows on whole cards; the sound and the date and time at
; the right (drawn again each minute: bank T's LK_TICK). Vertical menus ("lists")
; open under their bar item or beside their list item (the table's
; position is not used: only its width), on whole cards, 16 lines an
; item, the text 8 pixels in, no separators. With uiLook's bits 0-3 a
; palette entry, the item chosen or open takes that colour on its cards
; (MenuHi; the colour map, V30) instead of being inverted. The geometry
; is the kernel's, so pointers and clicks are found as before (limL, limH).
;
; What a menu or a dialog covers comes back from: the application's
; RecoverVector if it set one; else the save-under stack if the
; application draws to the foreground only (it was saved when the menu
; opened); else the back screen (RecoverRectangle, as GEOS 64).

.include "kernel.inc"

.export k_DoMenu, k_ReDoMenu, k_DoPreviousMenu, k_GotoFirstMenu, k_RecoverMenu, k_RecoverAllMenus
.export menuState, menuStateEnd, Div8, fState, iconBusy
.export UiKey, k_DoIcons, k_DefMouse, UiClick, UiFault, UiWake, UiInit, InvertFore, AppCall, Flash, Covers
.global S_k_WIsMseInRegion, S_k_SetPattern, S_k_WRectangle, S_k_WFrameRectangle, S_k_WVerticalLine, S_k_WHorizontalLine, S_k_UseSystemFont, S_k_WPutString, S_k_WInvertRectangle, S_k_WRecoverRectangle, S_k_WBitmapUp, S_k_WSetMouseRegion, S_k_WStartMouseMode, S_k_MouseOff
.import kMenuRect, uiTimer, uiWake, AppJsr, kAppVec, sysFont, kSndReq
.export UiFont
.import DlgIcon, DlgFiles
.import UnderPush, UnderPop, UnderReset, UnderDrop, uX, uW, uTop, uBot
.global S_Look

LEVELS = 4
MAXITEMS = 31

mTop    = kMenuRect
mBot    = kMenuRect + 2
mLeft   = kMenuRect + 4
mRight  = kMenuRect + 6

F_MENU1 = 1                     ; flash steps (fState)
F_MENU2 = 2
F_ICON  = 3
F_USER  = 4                     ; another part of bank U (dialog boxes): fVec

STY_BAR  = 1                    ; mStyle (V74): the menu bar
STY_LIST = 2                    ; a vertical menu in the Veranda look
CHROME   = 2                    ; the bar's palette entry (sdk theme.h)

.segment "BSS"

menuState:
stackL:	.res LEVELS             ; each level's table
stackH:	.res LEVELS
optTab:	.res LEVELS             ; each level's item (selected, or for the pointer)
saved:	.res LEVELS             ; $FF: its area is on the save-under stack
cov:	.res LEVELS             ; $FF: its cards' colours put aside (ColorCover)
covX:	.res LEVELS             ; and its cards
covW:	.res LEVELS
covY:	.res LEVELS
covH:	.res LEVELS
mFlags:	.res 1                  ; the current level's flags byte
mBase:	.res 1                  ; its first item's offset (7 or 9)
limL:	.res MAXITEMS + 1       ; the item boundaries (x or y)
limH:	.res MAXITEMS + 1
fresh:	.res 1
fState:	.res 1
fVec:	.res 2
iTop:	.res 2                  ; the rectangle to invert (and given to actions;
iBot:	.res 2                  ; kMenuRect's order: Keep)
iLeft:	.res 2
iRight:	.res 2
et:	.res 1
d8:	.res 1
item:	.res 1
t:	.res 2
dbSave:	.res 1
patSave: .res 2
iconTab: .res 2                 ; the icon table (high byte 0: none)
iconWide: .res 1
iconN:	.res 1
iconBusy: .res 1                ; an icon's flash is running: clicks on icons wait
iconNum: .res 1
iconRout: .res 2
hitNum:	.res 1                  ; the icon pressed
hitRout: .res 2
mStyle:	.res 1                  ; the current level's look (V74): 0 GEOS 64's, STY_BAR, STY_LIST
barR:	.res 2                  ; the bar's right (its last item's end - 1; 0: not drawn yet)
barY:	.res 2                  ; its top
menuStateEnd:
pxL:	.res LEVELS             ; (V74) where each level opens (x, y: Sub)
pxH:	.res LEVELS
pyL:	.res LEVELS
pyH:	.res LEVELS
; (V137) the Veranda look's tracking: levels 0 .. LEVELS - 2 as parents
lvR:	.res (LEVELS - 1) * 8   ; each parent's rectangle (kMenuRect's order)
lvI:	.res (LEVELS - 1) * 8   ; and its item whose sub menu is open
arm:	.res 1                  ; bit 7: a sub menu opened with the button down
tgt:	.res 1                  ; Anc's level
kSel:	.res 1                  ; the item the keys show ($FF: none)

.segment "CODE"

; SetVideoMode: no menus, icons, flashes, nothing saved
UiInit:	ldx #LK_OFF             ; (V74: no menu bar)
	FARCALL Look
	jsr UnderReset
	stz iconTab+1
	stz iconBusy
	stz fState
	stz uiWake
	stz menuNumber
	ldx #LEVELS - 1
@1:	stz saved,x
	stz cov,x
	dex
	bpl @1
	rts

;---------------------------------------------------------------
; the current level's table and rectangle
;---------------------------------------------------------------
; kPtr = the table of level menuNumber; kMenuRect, mFlags, mBase; the
; pointer's region (the menu if CONSTRAINED, else the screen)
Load:	ldx menuNumber
	lda stackL,x
	sta kPtr
	lda stackH,x
	sta kPtr+1
	stz mTop+1
	stz mBot+1
	ldy #6
	lda (kPtr),y
	sta mFlags
	ldx #7
	and #WIDE_MENU
	beq @c
	ldx #9
@c:	stx mBase
	txa                     ; the bytes before the items (but the flags)
	tay                     ; into kMenuRect (LoadMap)
@l:	dey
	bmi @e
	cpy #6
	beq @l
	lda (kPtr),y
	ldx LoadMap,y
	sta kMenuRect,x
	bra @l
@e:
	jsr Look                ; (V74)
	bit mFlags
	bvc @all
	jsr MenuRegs
	jmp S_k_WSetMouseRegion
@all:	FARCALL MouseRegionAll
	rts

;---------------------------------------------------------------
; the Veranda look (V74): mStyle, and the rectangle as it is drawn
;---------------------------------------------------------------
Look:	stz mStyle
	bit uiLook
	bpl @r
	bit mFlags
	bmi List
	lda menuNumber
	bne @r                  ; (a horizontal sub menu: GEOS 64's)
	LoadB mStyle, STY_BAR
	lda mTop                ; 16 lines
	clc
	adc #15
	sta mBot
	lda mTop+1
	adc #0
	sta mBot+1
	lda barR
	ora barR+1
	beq @r
	MoveW barR, mRight      ; (drawn: to its last item)
@r:	rts

; a list: at pxL.. (a sub menu) or at the table's place, on whole cards:
; left and top to a card, the table's width + 8, 16 lines an item; moved
; left if it would leave the screen
List:	LoadB mStyle, STY_LIST
	lda mRight              ; t = the table's width
	sec
	sbc mLeft
	sta t
	lda mRight+1
	sbc mLeft+1
	sta t+1
	ldx menuNumber
	beq @own
	lda pxL,x
	sta mLeft
	lda pxH,x
	sta mLeft+1
	lda pyL,x
	sta mTop
	lda pyH,x
	sta mTop+1
@own:	lda mLeft
	and #$F8
	sta mLeft
	lda mTop
	clc
	adc #7
	and #$F8
	sta mTop
	lda mTop+1
	adc #0
	sta mTop+1
	lda mLeft               ; right = (left + width + 15) & ~7, - 1
	clc
	adc t
	tax
	lda mLeft+1
	adc t+1
	tay
	txa
	clc
	adc #15
	and #$F8
	sta mRight
	tya
	adc #0
	sta mRight+1
	lda mRight
	bne @d
	dec mRight+1
@d:	dec mRight
	jsr Count               ; bottom = top + 16 x the items - 1 (V146: the
	sta t                   ; frame on the last item's last line, so the
	stz t+1                 ; list ends on a card's: a tile screen's
	ldx #4                  ; cover takes no card row below it)
@x16:	asl t
	rol t+1
	dex
	bne @x16
	lda mTop
	clc
	adc t
	sta mBot
	lda mTop+1
	adc t+1
	sta mBot+1
	lda mBot
	bne @b1
	dec mBot+1
@b1:	dec mBot
	; past the screen's right or (V137) bottom: moved left or up, so that
	; its right (bottom) is the screen's last pixel; left alone on that
	; axis if it would then start before 0 (a list taller than the screen)
	ldx #4                  ; (x: left, right; y: the screen's width)
	ldy #0
@f:	lda kMenuRect+2,x       ; kTmp = right - width: >= 0 past the screen
	sec
	sbc screenWidth,y
	sta kTmp
	lda kMenuRect+3,x
	sbc screenWidth+1,y
	sta kTmp+1
	bcc @n
	lda kMenuRect,x         ; left - kTmp - 1, if >= 0
	clc
	sbc kTmp
	pha
	lda kMenuRect+1,x
	sbc kTmp+1
	bcc @p
	sta kMenuRect+1,x
	pla
	sta kMenuRect,x
	lda screenWidth,y       ; right = the width - 1 (c set)
	sbc #1
	sta kMenuRect+2,x
	lda screenWidth+1,y
	sbc #0
	sta kMenuRect+3,x
	bra @n
@p:	pla
@n:	ldy #2                  ; (then top, bottom; the screen's height)
	dex
	dex
	dex
	dex
	bpl @f
	rts

.segment "RODATA"
LoadMap: .byte 0, 2, 4, 5, 6, 7, 0, 1, 3   ; (a table's byte -> kMenuRect)
.segment "CODE"

; the number of items
Count:	lda mFlags
	and #%00011111
	rts

; kPtr2 = item a's entry (kPtr = the table again: drawing uses it)
Entry:	ldx menuNumber
	ldy stackL,x
	sty kPtr
	ldy stackH,x
	sty kPtr+1
	sta et
	asl
	asl
	clc
	adc et                  ; * 5 (at most 155)
	clc
	adc mBase
	clc
	adc kPtr
	sta kPtr2
	lda kPtr+1
	adc #0
	sta kPtr2+1
	rts

; the screen rectangle r3, r11, r4, r12 = the menu's
MenuRegs:
	ldy #7
@c:	lda kMenuRect,y
	cpy #4
	bcs @l
	sta r11,y
	bra @n
@l:	sta r3 - 4,y
@n:	dey
	bpl @c
	rts

;---------------------------------------------------------------
; drawing
;---------------------------------------------------------------
Draw:	lda #$FF                ; (V137: no item shown by the keys)
	sta kSel
	lda dispBufferOn
	sta dbSave
	LoadB dispBufferOn, ST_WR_FORE
	MoveW curPattern, patSave
	lda #0
	FARCALL k_SetPattern
	jsr MenuRegs
	lda mStyle
	cmp #STY_BAR
	bne @box
	stz r3                  ; (V74) the bar: the full width, a line under
	stz r3+1                ; it, its colours and the mark (bank T)
	lda screenWidth
	sec
	sbc #1
	sta r4
	lda screenWidth+1
	sbc #0
	sta r4+1
	FARCALL k_WRectangle
	ldx #LK_BAR
	FARCALL Look
	bra @pat
@box:	FARCALL k_WRectangle
	jsr MenuRegs
	lda #$FF
	FARCALL k_WFrameRectangle
	lda mStyle
	beq @pat
	jsr Cards               ; (V74) a list: its cards as opened (no
	jsr CardsK              ; item shown in colour)
	lda #0
	jsr HiK
@pat:	MoveW patSave, curPattern
	; the font and the margins kept; the system font, plain
	ldx #LK_PUSH            ; (V146: bank T keeps them)
	FARCALL Look
	jsr UiFont
	stz currentMode
	stz leftMargin
	stz leftMargin+1
	lda mRight
	sec
	sbc #1
	sta rightMargin
	lda mRight+1
	sbc #0
	sta rightMargin+1
	lda mStyle
	cmp #STY_BAR
	bne @items
	lda screenWidth         ; (the bar: to the screen's right)
	sta rightMargin
	lda screenWidth+1
	sta rightMargin+1
	; the items
@items:	stz item
	bit mFlags
	bmi @vert
	MoveW mLeft, t          ; horizontal: t = x
@h:	jsr Lim
	bne @h1
	jmp @sep
@h1:	jsr HPad
	jsr Text
	MoveW t, r11
	jsr HTop
	jsr Put
	MoveW r11, t
	jsr HEnd
	inc item
	bra @h
@vert:	MoveW mTop, t           ; vertical: t = y
@v:	jsr Lim
	beq @sep
	jsr Text
	lda #4
	ldx mStyle
	beq @v0
	lda #8
@v0:	clc
	adc mLeft
	sta r11
	lda mLeft+1
	adc #0
	sta r11+1
	lda #3
	ldx mStyle
	beq @v1
	lda #16
	jsr Mid
@v1:	clc
	adc t
	sta r12
	lda t+1
	adc #0
	sta r12+1
	jsr Put
	lda curHeight
	clc
	adc #5
	ldx mStyle
	beq @v2
	lda #16
@v2:	clc
	adc t
	sta t
	bcc @v3
	inc t+1
@v3:	inc item
	bra @v
@sep:	lda mStyle
	cmp #STY_BAR
	bne @fp
	lda t                   ; (V74) the bar: to its last item; the sound,
	sec                     ; the date and time at its right (bank T)
	sbc #1
	sta barR
	sta mRight
	lda t+1
	sbc #0
	sta barR+1
	sta mRight+1
	MoveW mTop, barY
	jsr Clock
@fp:	ldx #LK_POP
	FARCALL Look
	lda mStyle
	bne @done               ; (V74: no separators)
	; the separators, items 1 .. n - 1
	LoadB item, 1
@s:	jsr Count
	cmp item
	beq @done
	bcc @done
	ldx item                ; (ItemR: limit item on the items' axis,
	jsr ItemR               ; the menu less a pixel across)
	jsr IRegs
	bit mFlags
	bmi @sv
	MoveW r3, r4            ; horizontal menu: a vertical line
	lda #%10101010
	FARCALL k_WVerticalLine
	bra @s1
@sv:	lda #%01010101          ; vertical menu: a horizontal line
	FARCALL k_WHorizontalLine
@s1:	inc item
	bra @s
@done:	lda dbSave
	sta dispBufferOn
	rts

; limit item = t; z set if it is the last (the items' end)
Lim:	ldx item
	lda t
	sta limL,x
	lda t+1
	sta limH,x
	jsr Count
	cmp item
	rts

; (V74) a horizontal item's text: t + 4 (GEOS 64), on the bar t + 6, item
; 0 24 (after the mark) and bold
HPad:	ldx #4
	lda mStyle
	beq @a
	ldx #6
	lda item
	bne @a
	ldx #24
	LoadB currentMode, SET_BOLD
@a:	txa
	clc
	adc t
	sta t
	bcc @r
	inc t+1
@r:	rts

; r12 = its top: the menu's + 3 (GEOS 64); on the bar (V164) the
; capitals (rows 0 .. baselineOffset) in the middle of its 15 rows
HTop:	lda #3
	ldx mStyle
	beq @g
	lda #15
	jsr MidB
@g:	clc
	adc mTop
	sta r12
	lda mTop+1
	adc #0
	sta r12+1
	rts

; after the text: t + 4 (GEOS 64), on the bar + 6 up to a card, plain
HEnd:	lda mStyle
	bne @bar
	AddVW 4, t
	rts
@bar:	stz currentMode
	lda t
	clc
	adc #6 + 7
	and #$F8
	sta t
	bcc @r
	inc t+1
@r:	rts

; a = (a - curHeight) / 2, 0 if the font is taller; MidB (V164):
; (a - baselineOffset - 1) / 2, the capitals' rows centred
MidB:	clc
	sbc baselineOffset
	bra Mid1
Mid:	sec
	sbc curHeight
Mid1:	bcs @1
	lda #0
@1:	lsr
	rts

; the bar's sound and clock (bank T) from barR + 1, barY; the minute kept
Clock:	lda barR
	clc
	adc #1
	sta kTmp
	lda barR+1
	adc #0
	sta kTmp+1
	MoveW barY, kTmp+2
	ldx #LK_CLOCK
	FARCALL Look
	rts

; r0 = item's text
Text:	lda item
	jsr Entry
	ldy #0
	lda (kPtr2),y
	sta r0
	iny
	lda (kPtr2),y
	sta r0+1
	rts

; the text at r11, r12 = its top + 3 - 3 ...: r12 is the top + 3 here; the
; baseline is that + baselineOffset
; (V146) a list in the Veranda look: bank T draws it (a separator, a key)
Put:	lda r12
	clc
	adc baselineOffset
	sta r12
	bcc @1
	inc r12+1
@1:	lda mStyle
	cmp #STY_LIST
	bne @p
	MoveW t, kTmp           ; (the item's top)
	ldx #LK_ITEM
	jmp S_Look
@p:	jmp S_k_WPutString

; the font of menus and dialog boxes: the system font, or uiFont's (a
; native program's choice, V62)
UiFont:	lda uiFont
	beq @sys
	FARCALL k_UseFont
	rts
@sys:	FARCALL k_UseSystemFont
	rts

;---------------------------------------------------------------
; the pointer on item optTab[level] (fresh, or CONSTRAINED), menus and
; the mouse on
;---------------------------------------------------------------
Pointer:
	lda mouseOn
	bpl @1
	ora #SET_ICONSON
@1:	ora #SET_MENUON
	sta mouseOn
	stz mouseVector
	stz mouseVector+1
	stz mouseFaultVec
	stz mouseFaultVec+1
	lda fresh
	beq @nf
	lda menuNumber          ; (V137: the Veranda look's sub menus leave
	beq @place              ; the pointer where it is: the press that
	bit uiLook              ; opened one never lands on its item)
	bpl @place
@nf:	bit mFlags
	bvs @place
	lda #0                  ; on, where it is
	jmp S_k_WStartMouseMode
@place:	ldx menuNumber          ; r11, r12 = the middle of the item's
	lda optTab,x            ; limits (ItemR: the item 0's too)
	tax
	jsr ItemR
	ldx #0
	ldy #4
@m:	lda iTop,y
	clc
	adc iBot,y
	sta r11,x
	lda iTop+1,y
	adc iBot+1,y
	ror
	sta r11+1,x
	ror r11,x
	inx
	inx
	ldy #0
	cpx #4
	bne @m
; the pointer to r11, r12 and on; x = 0: not moved (GEOS)
Start:	lda r11
	ora r11+1
	beq @np
	lda #1
@np:	jmp S_k_WStartMouseMode

; open level menuNumber (its table in stack): save under, draw, pointer
Open:	jsr Load
	jsr Save
	jsr Cards               ; its cards in the normal colours
	lda mStyle
	cmp #STY_BAR
	beq @bar                ; (V74: the bar keeps its own: not covered)
	jsr Covers
	bra @c
@bar:	lda #0
@c:	ldx menuNumber
	sta cov,x
	lda kTmp
	sta covX,x
	lda kTmp+1
	sta covW,x
	lda kTmp+2
	sta covY,x
	lda kTmp+3
	sta covH,x
	LoadB fresh, $FF
	jsr Draw
	jmp Pointer

; the area of the current level onto the save-under stack, if it is
; recovered that way (see the top)
Save:	ldx menuNumber
	stz saved,x
	lda RecoverVector
	ora RecoverVector+1
	bne @r
	bit dispBufferOn
	bvs @r                  ; the back screen is drawn: RecoverRectangle
	jsr Cards
	jsr UnderPush
	bcs @r
	ldx menuNumber
	dec saved,x
@r:	rts

; uX, uW, uTop, uBot = the menu rectangle's cards and rows
Cards:	lda mLeft
	ldx mLeft+1
	jsr Div8
	sta uX
	lda mRight
	ldx mRight+1
	jsr Div8
	sec
	sbc uX
	ina
	sta uW
	MoveW mTop, uTop
	MoveW mBot, uBot
	rts

; the colour map under uX, uW, uTop, uBot (cards, rows): its colours put
; aside and the cards 0 (kernel/s/color.s); kTmp-kTmp+3 = the cards
; (x, width, y, height); a = $FF if they were (the map is shown)
Covers:	jsr CardsK
	lda #0
	FARCALL ColorCover
	rts

; kTmp-kTmp+3 = the cards of uX, uW, uTop, uBot (x, width, y, height)
CardsK:	lda uX
	sta kTmp
	lda uW
	sta kTmp+1
	lda uTop
	ldx uTop+1
	jsr Div8
	sta kTmp+2
	lda uBot
	ldx uBot+1
	jsr Div8
	sec
	sbc kTmp+2
	ina
	sta kTmp+3
	rts

; level x's colours back (if they were put aside)
Uncover:
	lda cov,x
	beq @r
	stz cov,x
	lda covX,x
	sta kTmp
	lda covW,x
	sta kTmp+1
	lda covY,x
	sta kTmp+2
	lda covH,x
	sta kTmp+3
	lda #1
	FARCALL ColorCover
@r:	rts

;---------------------------------------------------------------
; the calls
;---------------------------------------------------------------
; r0 menu, a item for the pointer
k_DoMenu:
	sta optTab
	stz menuNumber
	lda r0L
	sta stackL
	lda r0H
	sta stackH
	ldx #LEVELS - 1         ; areas saved for open menus: forgotten
@u:	phx                     ; (GEOS recovers nothing here either), their
	jsr Uncover             ; colours back
	plx
	lda saved,x
	beq @u1
	stz saved,x
	phx
	jsr UnderDrop
	plx
@u1:	dex
	bpl @u
	stz fState
	stz uiWake
	stz barR                ; (V74: the bar not drawn yet)
	stz barR+1
	bit uiLook
	bpl @o
	ldx #LK_OFF
	FARCALL Look
@o:	jmp Open

k_ReDoMenu:
	FARCALL k_MouseOff
	jsr Load
	stz fresh
	stz fState
	jsr Draw
	jmp Pointer

k_DoPreviousMenu:
	FARCALL k_MouseOff
	jsr k_RecoverMenu
	dec menuNumber
	jsr Load
	stz fresh
	stz fState
	jsr Draw
	jmp Pointer

k_GotoFirstMenu:
@1:	lda menuNumber
	beq @r
	jsr k_DoPreviousMenu
	bra @1
@r:	rts

; the current level's area back: r2L top, r2H bottom, r3 left, r4 right
; (and r11, r12: the wide top and bottom)
k_RecoverMenu:
	MoveB mTop, r2L
	MoveB mBot, r2H
	jsr MenuRegs
Recover:			; (r3, r4, r11, r12, r2: the area; saved[x] for x)
	ldx menuNumber
	jsr Uncover
	lda RecoverVector
	ora RecoverVector+1
	beq @k
	MoveW RecoverVector, kAppVec
	jmp AppJsr
@k:	ldx menuNumber
	lda saved,x
	beq @back
	stz saved,x
	jsr UnderPop
	rts
@back:	jmp S_k_WRecoverRectangle

k_RecoverAllMenus:
@1:	jsr Load
	jsr k_RecoverMenu
	dec menuNumber
	bpl @1
	stz menuNumber
	jmp Load

;---------------------------------------------------------------
; a press: c set if a menu or an icon took it
;---------------------------------------------------------------
UiClick:
	bit mouseData
	bmi @rel                ; a release: otherPressVec (V137: or the item)
	bit mouseOn
	bpl @no
	bvc @icons              ; SET_MENUON (bit 6)
	jsr InCur
	bcs @sel
	lda menuNumber          ; (V137) the Veranda look's sub menu open: a
	beq @icons              ; press outside it is the menus' (Outside)
	bit uiLook
	bpl @icons
	jsr Outside
	sec
	rts
@sel:	jsr Select
	sec
	rts
; (V137) a release after a sub menu opened with the button down (arm, the
; Veranda look) and held 15 frames or more: the item under the pointer
; chosen (press, drag, release); a quick click leaves the menu open
@rel:	bit arm
	bpl @no
	stz arm
	lda uiTimer
	bne @no
	bit mouseOn
	bpl @no
	bvc @no
	lda menuNumber
	beq @no
	jsr InCur
	bcs @sel
	bra @no
@icons:	ldx #LK_CLICK           ; (V120) the bar's sound or clock: Preferences
	FARCALL Look
	bcs @r
	lda mouseOn
	and #SET_ICONSON
	beq @f
	jsr IconClick
	bcs @r
@f:	jmp DlgFiles            ; a dialog box's file list
@no:	clc
@r:	rts

; the item under the pointer -> item, iTop..iRight
Find:	jsr Count
	tax
@1:	dex
	beq ItemRI              ; item 0
	bit mFlags
	bmi @v
	lda mouseXPos           ; limit <= x?
	cmp limL,x
	lda mouseXPos+1
	sbc limH,x
	bcs ItemRI
	bra @1
@v:	lda mouseYPosW
	cmp limL,x
	lda mouseYPosW+1
	sbc limH,x
	bcc @1
; item x's rectangle -> item, iTop..iRight (ItemRI): the menu's less a
; pixel on each side, along the items from limit x (+ 1 for item 0) to
; limit x + 1; ItemR: from limit x
ItemRI:	jsr ItemR
	lda item
	bne @r
	inc iTop,x              ; (x: the axis)
	bne @r
	inc iTop+1,x
@r:	rts
ItemR:	stx item
	ldy #7
@c:	lda kMenuRect,y
	sta iTop,y
	dey
	bpl @c
	ldx #4
@i:	inc iTop,x
	bne @1
	inc iTop+1,x
@1:	lda iBot,x
	bne @2
	dec iBot+1,x
@2:	dec iBot,x
	dex
	dex
	dex
	dex
	bpl @i
	ldx #0                  ; (x: the items' axis)
	bit mFlags
	bmi @v
	ldx #4
@v:	ldy item
	lda limL,y
	sta iTop,x
	lda limH,y
	sta iTop+1,x
	lda limL+1,y
	sta iBot,x
	lda limH+1,y
	sta iBot+1,x
	rts

; iTop..iRight inverted on the foreground
InvertFore:
	lda dispBufferOn
	pha
	LoadB dispBufferOn, ST_WR_FORE
	ldx #0
	jsr RCopy
	FARCALL k_WInvertRectangle
	pla
	sta dispBufferOn
	rts

;---------------------------------------------------------------
; (V74) the item chosen shown (a = 1) or not (a = 0): in the Veranda look
; with a colour (uiLook's LOOK_HILITE) on its cards, the bar's normal ones
; the chrome, a list's the normal paper (they are covered); else inverted
; (each call: GEOS 64's flash)
;---------------------------------------------------------------
MenuHi:	ldx mStyle
	beq @inv
	tax
	beq @off
	lda uiLook
	and #LOOK_HILITE
	bra @k
@off:	lda mStyle
	cmp #STY_BAR
	bne @0
	lda #CHROME
	bra @k
@0:	lda #0
@k:	pha
	lda iLeft               ; kTmp: the item's cards
	ldx iLeft+1
	jsr Div8
	sta kTmp
	lda iRight
	ldx iRight+1
	sec
	sbc #1
	bcs @2
	dex
@2:	jsr Div8
	sec
	sbc kTmp
	ina
	sta kTmp+1
	lda mStyle              ; the bar's item 0: not the mark's cards
	cmp #STY_BAR
	bne @4
	lda item
	bne @4
	inc kTmp
	inc kTmp
	dec kTmp+1
	dec kTmp+1
@4:	lda iTop
	ldx iTop+1
	jsr Div8
	sta kTmp+2
	lda iBot
	ldx iBot+1
	sec
	sbc #1
	bcs @3
	dex
@3:	jsr Div8
	sec
	sbc kTmp+2
	ina
	sta kTmp+3
	pla
	jsr HiK
	bcc @r
@inv:	jmp InvertFore
@r:	rts

; kTmp's cards in colour a if the look has colours and the map is shown
; (c clear), else c set
HiK:	tax
	lda uiLook
	and #LOOK_HILITE
	beq @no
	txa
	ldx #LK_HI
	FARCALL Look
	rts
@no:	sec
	rts

; where level y opens (Sub; the Veranda look's lists, V74): under a bar
; item (its left, the line under the bar), beside a list's item (its
; right, its top); x kept
Where:	lda mStyle
	cmp #STY_LIST
	beq @side
	lda iLeft
	sta pxL,y
	lda iLeft+1
	sta pxH,y
	lda iBot
	clc
	adc #1
	sta pyL,y
	lda iBot+1
	adc #0
	sta pyH,y
	rts
@side:	lda iRight
	clc
	adc #8
	sta pxL,y
	lda iRight+1
	adc #0
	sta pxH,y
	lda iTop
	and #$F8
	sta pyL,y
	lda iTop+1
	sta pyH,y
	rts

; a press inside the current level (V69: the menu tick, if the settings
; have it)
Select:	jsr Find
SelIt:	LoadB kSndReq, SND_MENU  ; (V137: the keys' Return: item, iTop.. set)
	FARCALL k_MouseOff
	lda #1
	jsr MenuHi
	ldx menuNumber
	lda item
	sta optTab,x
	jsr Entry
	ldy #2
	lda (kPtr2),y
	bmi SelSub
	asl
	bmi SelDyn
	; an action: the flash first
	LoadB fState, F_MENU1
Flash:	lda selectionFlash      ; (dialog boxes come here too)
	sta uiTimer
	LoadB uiWake, 1
	rts
SelSub:	ldy #3
	lda (kPtr2),y
	tax
	iny
	lda (kPtr2),y
	bra Sub
SelDyn:	jsr Regs                ; the routine returns the sub menu in r0
	lda item
	jsr AppCall
	lda r0L
	ora r0H
	beq SelR                  ; 0: nothing (the routine sees to it)
	ldx r0L
	lda r0H
Sub:	pha                     ; x/a = the sub menu: the next level
	phx
	jsr Keep
	plx
	inc menuNumber
	ldy menuNumber
	jsr Where
	txa
	sta stackL,y
	pla
	sta stackH,y
	lda #0
	sta optTab,y
	jmp Open
SelR:	rts

; for an item's routine: r0 = its address, r1L its type, r8L and r9L the
; item, r2L, r2H, r3, r4 the inverted rectangle (and r11, r12); kAppVec
Regs:	lda item
	jsr Entry
	ldy #2
	lda (kPtr2),y
	sta r1L
	iny
	lda (kPtr2),y
	sta r0L
	sta kAppVec
	iny
	lda (kPtr2),y
	sta r0H
	sta kAppVec+1
	lda item
	sta r8L
	sta r9L
; r2L, r2H, r3, r4, r11, r12 = the rectangle iTop..iRight
IRegs:	MoveB iTop, r2L
	MoveB iBot, r2H
	ldx #0
; r11, r12, r3, r4 = the rectangle at iTop + x (kMenuRect's order)
RCopy:	ldy #0
@c:	lda iTop,x
	cpy #4
	bcs @l
	sta r11,y
	bra @n
@l:	sta r3 - 4,y
@n:	inx
	iny
	cpy #8
	bne @c
	rts

; DefMouse (API 2; DECISIONS V44): what the main loop does with a button change when the
; program's mouseVector is 0 (the menus and icons, else otherPressVec), for
; a program whose mouseVector passes the change on (GEOS programs that
; chain to the mouseVector they found: GEOS's holds its own handling)
k_DefMouse:
	jsr UiClick
	bcs @r
	MoveW otherPressVec, kAppVec
	jmp AppCall
@r:	rts

; the application's routine kAppVec with a (nothing if 0); x = its low byte
AppCall:
	tay
	lda kAppVec
	ora kAppVec+1
	beq @r
	ldx kAppVec
	tya
	jmp AppJsr
@r:	rts

; the main loop: uiTimer reached 0
UiWake:	stz uiWake
	lda fState
	cmp #F_MENU1
	beq @m1
	cmp #F_MENU2
	beq @m2
	cmp #F_ICON
	beq @ic
	cmp #F_USER
	bne @r
	stz fState
	jmp (fVec)
@m1:	lda #0                  ; normal again, wait
	jsr MenuHi
	LoadB fState, F_MENU2
	jmp Flash
@m2:	stz fState              ; inverted again: the action
	lda #1
	jsr MenuHi
	ldx menuNumber
	lda optTab,x
	sta item
	jsr Regs
	lda item
	jmp AppCall
@ic:	stz fState
	jsr InvertFore
	jmp Service
@r:	rts

;---------------------------------------------------------------
; the pointer left its region: c set if the menus took it
;---------------------------------------------------------------
UiFault:
	lda mouseOn
	and #SET_MSE_ON | SET_MENUON
	cmp #SET_MSE_ON | SET_MENUON
	bne @no
	lda menuNumber
	beq @yes                ; the main menu stays
	bit uiLook              ; (V137) the Veranda look, not CONSTRAINED:
	bpl @g                  ; only the pointer's moves onto the menus
	bit mFlags              ; above count (Hover); GEOS 64's rules for
	bvs @g                  ; classic tables
	lda faultData
	and #SET_OFFMENU
	beq @yes
	jsr Hover
	bra @yes
@g:	lda faultData
	and #SET_OFFMENU
	bne @prev
	bit mFlags
	bpl @h
	lda faultData
	and #SET_OFFTOP
	bne @prev
	bra @c
@h:	lda faultData
	and #SET_OFFLEFT
	bne @prev
@c:	bit mFlags
	bvs @yes                ; CONSTRAINED: the other edges do nothing
@prev:	jsr k_DoPreviousMenu
@yes:	sec
	rts
@no:	clc
	rts

;---------------------------------------------------------------
; (V137) the Veranda look's menu tracking, as modern desktops: a sub menu
; stays open wherever the pointer goes (no fault closes it) until a click
; outside every menu (Outside: all closed), Esc, or the pointer on one of
; its parents' other items: the bar's other title (that menu opens, the
; pointer left where it is), a parent list's other item (that list again,
; more than MARGIN pixels from the sub menu: going there diagonally over
; the list does not close it). The press that opens a sub menu leaves the
; pointer where it is (Pointer), so it never chooses the first item; a
; release 15 frames or more after it, on an item, chooses it (UiClick).
; Lists that would leave the screen's bottom are moved up (List).
;---------------------------------------------------------------
MARGIN = 16

; the parent's rectangle and its item now open (Sub) for the tracking;
; arm for the release (the button down, the Veranda look), its 15 frames.
; (V155) the item's rectangle as Find sees it: the parent's across, its
; limits along, not ItemR's (a pixel inside the menu's on every side, item
; 0 one more): the pointer on the bar's top or last line, or on an item's
; first column, was in the parent but not on the item open, and Hover
; closed the menu and opened it again every poll (on an X16: it blinked)
Keep:	lda menuNumber
	asl
	asl
	asl
	ora #7
	tax
	ldy #7
@k:	lda kMenuRect,y
	sta lvR,x
	sta lvI,x
	dex
	dey
	bpl @k
	inx                     ; (x: the level's first byte)
	bit mFlags
	bmi @v
	txa                     ; (a horizontal menu: along x)
	ora #4
	tax
@v:	ldy item
	lda limL,y
	sta lvI,x
	lda limH,y
	sta lvI+1,x
	lda limL+1,y            ; (to the next item's limit - 1)
	sec
	sbc #1
	sta lvI+2,x
	lda limH+1,y
	sbc #0
	sta lvI+3,x
	lda mouseData           ; (bit 7: up)
	eor #$80
	and uiLook
	sta arm
	lda #15
	sta uiTimer
	rts

; c set if the pointer is in the current level's rectangle (InCur), the
; rectangle iTop + x (InL, x + 8 after: LVR + 8 L a parent's), or r3, r4,
; r11, r12 (InRegs)
LVR = lvR - iTop
InCur:	jsr MenuRegs
InRegs:	FARCALL k_WIsMseInRegion
	asl
	rts
InL:	jsr RCopy
	bra InRegs

; c set if the pointer is within MARGIN pixels of the current level
InWide:	jsr MenuRegs
	ldx #r11 - r3
@w:	lda r3,x                ; left (top) - MARGIN, not below 0
	sec
	sbc #MARGIN
	sta r3,x
	bcs @1
	dec r3+1,x
	bpl @1
	stz r3,x
	stz r3+1,x
@1:	lda r4,x                ; right (bottom) + MARGIN
	clc
	adc #MARGIN
	sta r4,x
	bcc @2
	inc r4+1,x
@2:	txa
	beq InRegs
	ldx #0
	bra @w

; the parents below level a, the nearest first: the one whose rectangle
; has the pointer -> tgt, a = 1 (not on its open item) or 2 (on it); a = 0
; if none
Anc:	sta tgt
@l:	dec tgt
	bmi @no
	lda tgt
	asl
	asl
	asl
	adc #LVR                ; (c clear)
	tax
	jsr InL
	bcc @l
	txa                     ; (x + 8 now: its item at lvR + 24 + 8 x)
	adc #16 - 1             ; (c set)
	tax
	jsr InL
	lda #1
	adc #0
	rts
@no:	lda #0
	rts

; back to level tgt
Back:	jsr k_DoPreviousMenu
	lda menuNumber
	cmp tgt
	bne Back
	rts

; the pointer off the sub menu (UiFault): within MARGIN only the main
; menu's other items count, else every parent's
Hover:	jsr InWide
	lda #1
	bcs @a
	lda menuNumber
@a:	jsr Anc
	dea
	bne @r                  ; none, or on the item open: it stays
	jsr Back
	lda tgt
	bne @r
	jsr Find                ; the main menu's item: its sub menu, if it
	lda item                ; has one
	jsr Entry
	ldy #2
	lda (kPtr2),y
	and #SUB_MENU | DYN_SUB_MENU
	beq @r
	jmp SelIt
@r:	rts

; a press off the sub menu: on a parent, back to it, and its item chosen
; unless it is the one open (a second click on a title closes its menu);
; within MARGIN of the menu nothing; elsewhere every sub menu closed
Outside:
	lda menuNumber
	jsr Anc
	tax
	bne @p
	jsr InWide
	bcs @r
	jmp k_GotoFirstMenu
@p:	phx
	jsr Back
	plx
	dex
	bne @r
	jmp Select
@r:	rts

; (V137) a key with a sub menu open (the Veranda look): Up and Down show
; the item before or after (kSel, around the ends), Return chooses it,
; Esc closes the menu; c set if taken (the main loop: keyVector else)
UiKey:	bit uiLook
	bpl @no
	bit mouseOn
	bvc @no
	lda menuNumber
	beq @no
	lda keyData
	cmp #KEY_ESC
	beq @esc
	cmp #CR
	beq @ret
	ldy #$FF                ; (y: -1 Up, 1 Down)
	cmp #KEY_UP
	beq @mv
	ldy #1
	cmp #KEY_DOWN
	bne @no
@mv:	phy
	jsr @off
	ply
	tya
	clc
	adc kSel
	bpl @0
	jsr Count               ; (before the first: the last)
	dea
@0:	sta kSel
	jsr Count
	cmp kSel
	bne @1
	stz kSel                ; (after the last: the first)
@1:	ldx kSel
	jsr ItemRI
	lda #1
	jsr MenuHi
	sec
	rts
@ret:	jsr @off
	bcs @y                  ; (none shown)
	jsr SelIt
	bra @y
@esc:	jsr k_DoPreviousMenu
@y:	sec
	rts
@no:	clc
	rts
; kSel's item shown no more (c clear, item, iTop..); c set if none
@off:	ldx kSel
	sec
	bmi @r
	jsr ItemRI
	lda #0
	jsr MenuHi
	clc
@r:	rts

;---------------------------------------------------------------
; icons: a count (bit 7 WIDE_ICONS), the pointer's x (word) and y (byte;
; wide: word), then 8 bytes an icon: the picture (0: an empty slot), x
; (cards), y, width (cards), height, the routine; wide icons 10 bytes:
; those, then the high bytes of y and height
;---------------------------------------------------------------
k_DoIcons:
	MoveW r0, iconTab
	MoveW r0, kPtr
	ldy #0
	lda (kPtr),y
	and #$80
	sta iconWide
	lda (kPtr),y
	and #$7F
	sta iconN
	stz iconNum
@d:	lda iconNum
	cmp iconN
	beq @dr
	jsr Icon
	lda r0L
	ora r0H
	beq @n
	FARCALL k_WBitmapUp
@n:	inc iconNum
	bra @d
@dr:	FARCALL MouseRegionAll
	lda mouseOn
	bmi @on
	and #<~SET_MENUON
@on:	ora #SET_ICONSON
	sta mouseOn
	stz mouseVector
	stz mouseVector+1
	stz mouseFaultVec
	stz mouseFaultVec+1
	stz iconBusy
	MoveW iconTab, kPtr
	ldy #1
	lda (kPtr),y
	sta r11
	iny
	lda (kPtr),y
	sta r11+1
	iny
	lda (kPtr),y
	sta r12
	stz r12+1
	bit iconWide
	bpl @p
	iny
	lda (kPtr),y
	sta r12+1
@p:	jmp Start

; icon iconNum: r0 picture, r1L x, r2L width, r11 y, r12 height (WBitmapUp),
; iconRout; kPtr2 = its entry
Icon:	lda iconNum
	asl
	asl
	asl                     ; * 8
	ldx iconWide
	beq @1
	clc
	adc iconNum
	clc
	adc iconNum             ; * 10
@1:	clc
	adc #4
	bit iconWide
	bpl @2
	clc
	adc #1                  ; (the wide header has a word y)
@2:	clc
	adc iconTab
	sta kPtr2
	lda iconTab+1
	adc #0
	sta kPtr2+1
	ldy #5
@f:	lda (kPtr2),y
	ldx IconMap,y
	sta 0,x
	dey
	bpl @f
	ldy #6
	lda (kPtr2),y
	sta iconRout
	iny
	lda (kPtr2),y
	sta iconRout+1
	stz r11+1
	stz r12+1
	bit iconWide
	bpl @r
	iny
	lda (kPtr2),y
	sta r11+1
	iny
	lda (kPtr2),y
	sta r12+1
@r:	rts

.segment "RODATA"
IconMap: .byte r0L, r0H, r1L, r11, r2L, r12
.segment "CODE"

; a press with icons on: c set if an icon took it
IconClick:
	lda iconTab+1
	beq @no
	lda mouseXPos           ; the pointer's card
	ldx mouseXPos+1
	jsr Div8
	sta t
	stz iconNum
@s:	lda iconNum
	cmp iconN
	beq @no
	jsr Icon
	lda r0L
	ora r0H
	beq @next
	lda t                   ; x <= card < x + width
	cmp r1L
	bcc @next
	lda r1L
	clc
	adc r2L
	cmp t
	beq @next
	bcc @next
	CmpW mouseYPosW, r11    ; y <= pointer < y + height
	bcc @next
	lda r11
	clc
	adc r12
	sta r12
	lda r11+1
	adc r12+1
	sta r12+1
	CmpW mouseYPosW, r12
	bcc @hit
@next:	inc iconNum
	bra @s
@no:	clc
	rts
@hit:	lda iconBusy
	bne @took               ; a flash is running: the press waits
	MoveB iconNum, hitNum
	MoveW iconRout, hitRout
	; the rectangle: x * 8 .. (x + w) * 8 - 1, y .. y + h - 1
	MoveW r11, iTop
	MoveW r12, iBot
	ldx #4
	lda r1L
	jsr Times8
	ldx #6
	lda r1L
	clc
	adc r2L
	jsr Times8
	ldx #2                  ; (the bottom and the right less one)
@d:	lda iTop,x
	bne @d1
	dec iTop+1,x
@d1:	dec iTop,x
	inx
	inx
	inx
	inx
	cpx #10
	bne @d
	lda iconSelFlg
	bmi @flash
	asl
	bpl @plain
	jsr InvertFore          ; ST_INVERT: and it stays so
@plain:	jsr Service
@took:	sec
	rts
@flash:	LoadB iconBusy, 1
	jsr InvertFore
	LoadB fState, F_ICON
	jsr Flash
	sec
	rts

; a = (x * 256 + a) / 8 (a card: below 256)
Div8:	stx d8
	lsr d8
	ror
	lsr d8
	ror
	lsr d8
	ror
	rts

; iTop + x (a word) = a * 8
Times8:	stz iTop+1,x
	asl
	rol iTop+1,x
	asl
	rol iTop+1,x
	asl
	rol iTop+1,x
	sta iTop,x
	rts

; the icon's routine: r0L the icon, r0H $FF for a double click (within
; 30 frames of the last single one), the rectangle in r2L, r2H, r3, r4
Service:
	lda dblClickCount
	beq @single
	stz dblClickCount
	lda #$FF
	bra @1
@single:
	LoadB dblClickCount, 30
	lda #0
@1:	sta r0H
	MoveB hitNum, r0L
	stz iconBusy
	jsr IRegs
	lda hitRout+1
	bne @app
	lda hitRout             ; 1-6: a dialog box's system icon
	beq @r
	jmp DlgIcon
@app:	MoveW hitRout, kAppVec
	lda hitRout
	ldx hitRout+1
	jmp AppJsr
@r:	rts
