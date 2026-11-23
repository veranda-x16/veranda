; Veranda bank T: the Veranda look's menu bar (DECISIONS V74)
;
; Bank U's menus (kernel/u/menu.s) draw a native program's main menu as
; the menu bar when uiLook has LOOK_BAR; these are its parts that classic
; menus never need, kept out of bank U:
;
; - LookBar: the line under the bar, its cards in palette entry 2 (the
;   chrome) and the mark's in entry 11 (cyan) when uiLook has a colour
;   (LOOK_HILITE), and the Veranda mark: a V on the 2 x 2 cards at the
;   bar's left (the proposal's mockup, look/mock.py's menubar()).
; Look: x = LK_BAR, LK_CLOCK, LK_HI, LK_OFF, LK_TICK, LK_ROWS or LK_CLICK
; (kernel.inc): one resident stub for them all (the resident core is full).
;
; - LookClock: at the bar's right, the sound (a speaker; crossed out
;   while the settings have the sounds off) and the date and time,
;   "Mon 16 Nov  18:42" (a screen 320 wide: "18:42"), right-aligned 8
;   pixels from the edge, in the menus' font; bank U calls it when the
;   bar is drawn and when the minute changes (LookTick).
; - LookTick (bank S's AlarmCheck, once a second from the main loop):
;   the clock drawn again when the minute changed, while the bar is up
;   (LookClock drew it; LK_OFF: DoMenu, SetVideoMode), uiLook has
;   LOOK_BAR and the main menu is open alone with menus on (no sub menu,
;   no dialog box); r0-r15, the pattern, the font and dispBufferOn kept.
; - LookClick (V120; bank U's UiClick, a press on no menu item): a click
;   on the sound or the clock, under LookTick's conditions, opens
;   Preferences over the program (bank S's BarDesk, through SysPrefs
;   SP_BAR) with deskNote DN_VOLUME (its volume pop-up) or DN_CLOCK (the
;   date and time); the bar's right drawn again after it.
; - LookHi: cards' paper written straight into the colour map (V30's
;   attributes: the shown colour, the tile index left alone), for an item
;   shown open in the selection's colour; a covered card (V33) keeps its
;   own colour in its tile and gets it back when it is uncovered.
;
; The text and the pictures go to the first bytes of dbFileNames while
; they are drawn (the drawing reads them below $A000, with bank G or G2
; mapped: kernel/u/alarm.s does the same), which are kept and put back.
;
; The palette entries are Veranda Look 2's (sdk theme.h: the SDK's
; theme_palette sets them for native programs).

.include "kernel.inc"
.import KeepLeft

.export Look
.import kMenuRect, kPrefs, sysFont, FontSel, k_UseFont, kSndReq
.global S_k_UseSystemFont, S_k_SysPrefs, S_k_WHorizontalLine, S_k_WPutString, S_k_GetCharWidth

mTop    = kMenuRect
mBot    = kMenuRect + 2
mLeft   = kMenuRect + 4
mRight  = kMenuRect + 6

CHROME  = 2                     ; palette entries (sdk theme.h)
CYAN    = 11
MAP     = VRAM_FREE             ; the colour map ($1AC00: kernel/s/color.s)
MAPW    = 128
LOW     = dbFileNames           ; the text (24), a picture (31)
LOWPIC  = LOW + 24
KEEP    = 24 + 31

.segment "BSS"

cLeft:	.res 2                  ; LookClock: from here to the right
cTop:	.res 2
cX:	.res 2                  ; the text's x
sX:	.res 2                  ; the speaker's
lastSx:	.res 2                  ; the speaker's last x (cleared from there)
hC:	.res 1                  ; LookHi: the attribute
hN:	.res 1
dY:	.res 1                  ; Dow
dK:	.res 1
buf     = LOW                   ; the date and time
lKeep:	.res KEEP               ; dbFileNames' bytes while LOW is used
tOn:	.res 1                  ; $80: the bar is up (LookClock)
tMin:	.res 1                  ; the minute its clock shows
tFont:	.res 9 + FONT_STATE + 4 ; the font, style, margins
tPat:	.res 2
tDb:	.res 1

.segment "CODE"

Look:	jmp (LookTab,x)
LookTab: .word LookBar, LookClock, LookHi, LookOff, LookTick, LookRows, LookClick
	.word LookPush, LookPop, LookItem

.segment "TAIL"                 ; (after RBIMG: bank T's code space before its page is full)

; (V146: from LATE) y into buf + x (a kept)
PutY:	pha
	tya
	sta buf,x
	inx
	pla
	rts


;---------------------------------------------------------------
; LK_CLICK (V120; bank U's UiClick: a press on no menu): on the bar's
; sound (from sX, 20 pixels) or its clock (right of it), with the bar up
; and the main menu alone (Up: LookTick's conditions), Preferences over
; the program (bank S's BarDesk) with deskNote DN_VOLUME or DN_CLOCK, a
; beep if it did not start, the sound and clock drawn again after it (the
; sounds may be off now); c set then, else c clear
;---------------------------------------------------------------
LookClick:
	jsr Up
	bcs @no
	lda mouseYPosW+1
	bne @no
	lda mouseYPosW          ; (the bar's 15 lines above its line)
	sec
	sbc cTop
	cmp #15
	bcs @no
	lda mouseXPos           ; x - sX - 1 (c clear)
	sbc sX
	tax
	lda mouseXPos+1
	sbc sX+1
	bcc @no
	ldy #DN_CLOCK
	cmp #0
	bne @n
	cpx #20
	bcs @n
	ldy #DN_VOLUME
@n:	jmp Click
@no:	clc
	rts

;---------------------------------------------------------------
; LK_ROWS (V81): a glyph of the UI font (in this bank) for bank G's
; fast path (kernel/g/text.s, UiFast): kPtr2 its row 0 (rowSrc), kTmp
; its bit in the row (sShift), kTmp+1 its width (1-8; bold 1-7); its
; curHeight rows to kPtr (bank G's, on the stack), each left aligned,
; masked to the width, bold applied (v OR v >> 1)
;---------------------------------------------------------------
LookRows:
	ldx kTmp+1
	lda #$FF
	cpx #8
	bcs @m
	lda KeepLeft,x          ; (the top x bits)
@m:	sta kTmp+2
	lda kTmp                ; the shift: a jump into the chain (3 bytes a step)
	sta kTmp+1
	asl a
	adc kTmp+1
	sta kTmp+1
	lda #<@ce
	sec
	sbc kTmp+1
	sta @rj+1
	lda #>@ce
	sbc #0
	sta @rj+2
	ldy #0
@r:	phy
	lda (kPtr2)
	sta kTmp+3
	ldy #1
	lda (kPtr2),y
@rj:	jmp @ce           ; (the 16 bits left by sShift)
.repeat 7
	asl a
	rol kTmp+3
.endrepeat
@ce:
	lda kTmp+3
	and kTmp+2
	sta kTmp+3
	bit currentMode         ; bold (SET_BOLD, bit 6)
	bvc @nb
	lsr a
	ora kTmp+3
@nb:	ply
	sta (kPtr),y
	iny
	lda kPtr2
	clc
	adc curSetWidth
	sta kPtr2
	lda kPtr2+1
	adc curSetWidth+1
	sta kPtr2+1
	cpy curHeight
	bne @r
	rts

.segment "CODE"

LookOff:
	stz tOn
	rts

; (V146: from LATE, for room)
; a (0-99) -> y = the tens' digit, a = the ones' (characters)
Num2:	ldy #'0' - 1
	sec
@1:	iny
	sbc #10
	bcs @1
	adc #'0' + 10
	rts

; LookClick's (in CODE: TAIL is full): y the note
Click:	sty deskNote
	lda tOn                 ; (the accessory's ModeVars: LK_OFF)
	pha
	lda #SP_BAR             ; (bank S's BarDesk)
	FARCALL k_SysPrefs
	stz deskNote
	pla
	sta tOn
	txa
	beq @ok
	LoadB kSndReq, SND_ERROR ; (it did not start)
@ok:	LoadB tMin, $FF
	jsr LookTick
	sec
	rts

; c clear if the bar is up with the main menu open alone, menus on
; (LookTick's conditions, LookClick's)
Up:	sec
	bit tOn
	bpl @r
	bit uiLook
	bpl @r
	lda menuNumber
	bne @r
	lda mouseOn
	and #SET_MENUON
	beq @r
	clc
@r:	rts

;---------------------------------------------------------------
; LK_PUSH, LK_POP (V146: bank U's FontPush and FontPop, moved here for
; room; LookTick's own): the font, the style and the margins kept in
; tFont and put back (a banked font: its index table again)
;---------------------------------------------------------------
LookPush:
	ldx #8
@fs:	lda baselineOffset,x
	sta tFont,x
	dex
	bpl @fs
	ldx #FONT_STATE - 1
@fk:	lda sysFont,x
	sta tFont+9,x
	dex
	bpl @fk
	ldx #3
@fm:	lda leftMargin,x
	sta tFont+9+FONT_STATE,x
	dex
	bpl @fm
	rts

LookPop:
	ldx #8
@fr:	lda tFont,x
	sta baselineOffset,x
	dex
	bpl @fr
	ldx #FONT_STATE - 1
@fb:	lda tFont+9,x
	sta sysFont,x
	dex
	bpl @fb
	ldx #3
@fn:	lda tFont+9+FONT_STATE,x
	sta leftMargin,x
	dex
	bpl @fn
	lda #0                  ; a banked font: its index table (V62)
	jmp FontSel

;---------------------------------------------------------------
; LookTick: the clock again (see the top)
;---------------------------------------------------------------
LookTick:
	jsr Up
	bcs @r
	lda minutes
	cmp tMin
	bne @go
@r:	rts

@go:	ldx #31                 ; (V146: r0-r15 on the stack)
@s:	lda r0,x
	pha
	dex
	bpl @s
	MoveW curPattern, tPat
	lda dispBufferOn
	sta tDb
	LoadB dispBufferOn, ST_WR_FORE
	jsr LookPush
	lda uiFont              ; the menus' font (bank U's UiFont)
	beq @sys
	jsr k_UseFont
	bra @f
@sys:	FARCALL k_UseSystemFont
@f:	stz currentMode
	stz leftMargin
	stz leftMargin+1
	MoveW screenWidth, rightMargin
	jsr Clock
	jsr LookPop
	lda tDb
	sta dispBufferOn
	MoveW tPat, curPattern
	ldx #0
@l:	pla
	sta r0,x
	inx
	cpx #32
	bne @l
	rts

;---------------------------------------------------------------
; LookBar: the bar's line (at mBot, the full width), colours, the mark
;---------------------------------------------------------------
LookBar:
	jsr Lend
	jsr Bar
	jmp Lback

Bar:	stz r3
	stz r3+1
	lda screenWidth
	sec
	sbc #1
	sta r4
	lda screenWidth+1
	sbc #0
	sta r4+1
	MoveW mBot, r11
	lda #$FF
	FARCALL k_WHorizontalLine
	lda uiLook
	and #LOOK_HILITE
	beq @mark
	stz r3L                 ; the bar's cards: the chrome
	lda screenWidth
	ldx screenWidth+1
	jsr Cd8
	sta r3H
	jsr Rows
	lda #CHROME
	FARCALL k_ColorRect
	jsr MarkX               ; the mark's: cyan
	sta r3L
	LoadB r3H, 2
	jsr Rows
	lda #CYAN
	FARCALL k_ColorRect
@mark:	LoadW kPtr, Mark
	jsr Pic
	jsr MarkX
	sta r1L
	LoadB r2L, 2
	MoveW mTop, r11
	LoadW r12, 15
	FARCALL k_WBitmapUp
	rts

; r11L, r11H = the bar's card rows
Rows:	lda mTop
	ldx mTop+1
	jsr Cd8
	sta r11L
	LoadB r11H, 2
	rts

; a = the mark's card (the bar's left)
MarkX:	lda mLeft
	ldx mLeft+1
	; (falls through)

; a = (x * 256 + a) / 8
Cd8:	stx hN
	lsr hN
	ror
	lsr hN
	ror
	lsr hN
	ror
	rts

;---------------------------------------------------------------
; LookClock: kTmp = the left limit, kTmp+2 = the bar's top; the font,
; dispBufferOn set by the caller (bank U); r0-r12 changed
;---------------------------------------------------------------
LookClock:
	MoveW kTmp, cLeft
	MoveW kTmp+2, cTop
	LoadB tOn, $80
Clock:	jsr Lend
	jsr Clk
	jmp Lback

; LOW's bytes kept, and put back
Lend:	ldx #KEEP - 1
@1:	lda LOW,x
	sta lKeep,x
	dex
	bpl @1
	rts
Lback:	ldx #KEEP - 1
@1:	lda lKeep,x
	sta LOW,x
	dex
	bpl @1
	rts

; the picture at kPtr (31 bytes) to LOWPIC, r0 = there
Pic:	ldy #30
@1:	lda (kPtr),y
	sta LOWPIC,y
	dey
	bpl @1
	LoadW r0, LOWPIC
	rts

Clk:	lda minutes
	sta tMin
	jsr Text
	; cX = the screen's width - 8 - the text's
	MoveW screenWidth, cX
	AddVW -8, cX
	ldx #0
@w:	lda buf,x
	beq @wd
	phx
	FARCALL k_GetCharWidth
	plx
	sta hN
	lda cX
	sec
	sbc hN
	sta cX
	bcs @w1
	dec cX+1
@w1:	inx
	bra @w
@wd:	lda cX                  ; sX = (cX - 22) & ~7
	sec
	sbc #22
	and #$F8
	sta sX
	lda cX+1
	sbc #0
	sta sX+1
	; cleared from the first of sX and the last one, not left of cLeft
	CmpW sX, lastSx
	bcs @c1
	MoveW sX, lastSx
@c1:	MoveW lastSx, r3
	CmpW r3, cLeft
	bcs @c2
	MoveW cLeft, r3
@c2:	MoveW sX, lastSx
	lda screenWidth
	sec
	sbc #1
	sta r4
	lda screenWidth+1
	sbc #0
	sta r4+1
	CmpW r4, r3
	bcs @c3
	rts                     ; (no room at all)
@c3:	MoveW cTop, r11
	lda cTop
	clc
	adc #14
	sta r12
	lda cTop+1
	adc #0
	sta r12+1
	lda #0
	FARCALL k_SetPattern
	FARCALL k_WRectangle
	; the speaker, if it is right of the menus
	CmpW sX, cLeft
	bcc @t
	LoadW kPtr, Speaker
	lda kPrefs
	bpl @s1                 ; (PREFS_NOSOUND: crossed out)
	LoadW kPtr, Muted
@s1:	jsr Pic
	lda sX
	ldx sX+1
	jsr Cd8
	sta r1L
	LoadB r2L, 2
	MoveW cTop, r11
	LoadW r12, 15
	FARCALL k_WBitmapUp
@t:	CmpW cX, cLeft
	bcc @r
	LoadW r0, buf
	MoveW cX, r11
	lda #14                 ; (V164) the capitals (rows 0 .. baselineOffset)
	sec                     ; in the middle of the bar's 15 lines, as
	sbc baselineOffset      ; bank U's menu titles (HTop)
	bcs @m
	lda #0
@m:	lsr
	clc
	adc baselineOffset
	clc
	adc cTop
	sta r12
	lda cTop+1
	adc #0
	sta r12+1
	FARCALL k_WPutString
@r:	rts

; buf = "Mon 16 Nov  18:42" (a screen narrower than 512: "18:42")
Text:	ldx #0
	lda screenWidth+1
	cmp #2
	bcc @time
	ldy month
	beq @time
	cpy #13
	bcs @time
	lda year                ; (V127) never set (it reads 2000): "Set clock"
	bne @set
	jmp SetClk
@set:	jsr Dow                 ; the day of the week
	sta hN
	asl
	adc hN                  ; (x 3; c clear: at most 18)
	tay
	jsr Three
	lda day
	jsr Num2
	cpy #'0'
	beq @d1
	jsr PutY
@d1:	sta buf,x
	inx
	lda #' '
	sta buf,x
	inx
	lda month               ; the month's name
	sta hN
	asl
	adc hN
	adc #MonT - DowN - 3    ; (DowN + y: MonT's entry month - 1)
	tay
	jsr Three
	lda #' '
	sta buf,x
	inx
@time:	lda hour
	jsr Num2
	jsr PutY
	sta buf,x
	inx
	lda #':'
	sta buf,x
	inx
	lda minutes
	jsr Num2
	jsr PutY
	sta buf,x
	inx
	stz buf,x
	rts


; a = the day of the week of year (2000-2099), month, day: 0 Sunday
; (Sakamoto's: y + y / 4 - y / 100 + y / 400 + t[m] + d, January and
; February counted in the year before; y / 100 and y / 400 are the same
; in every year of the century and drop out mod 7, but in 1999: + 1)
Dow:	stz dK
	lda year
	ldy month
	cpy #3
	bcs @1
	dea
	bpl @1
	lda #99                 ; (January, February 2000: 1999)
	inc dK
@1:	sta dY
	lsr
	lsr
	clc
	adc dY
	adc DowT - 1,y
	adc day
	adc dK
@m:	cmp #7
	bcc @r
	sbc #7
	bra @m
@r:	rts

;---------------------------------------------------------------
; LookHi: kTmp x, kTmp+1 width, kTmp+2 y, kTmp+3 height (cards), a = the
; colour: the cards' shown paper; c set (nothing done) if the colour map
; is hidden (VERA's layer 1 off: V30); in tile mode (V101) bank S's TileHi
;---------------------------------------------------------------
LookHi:	tax
	stz VERA_CTRL
	lda VERA_DC_VIDEO
	and #$20
	bne @on
@no:	sec
	rts
@on:	lda VERA_L0_TILEBASE    ; (V101) tile mode: bank S's
	cmp #TILE_TB
	bne @1
	txa
	FARCALL TileHi
	rts
@1:	cmp #CANVAS_TB          ; (V166: the canvas: no map, inverted instead)
	beq @no
	txa
	asl
	asl
	asl
	asl
	sta hC
	lda kTmp+3
	beq @done
	sta hN
	ldy kTmp+2
@row:	cpy #60
	bcs @done
	lda kTmp                ; the cards in this row: clipped at 80
	cmp #80
	bcs @done
	asl
	ora #1                  ; (the attribute: an entry's second byte)
	sta VERA_ADDR_L
	tya
	clc
	adc #>(MAP & $FFFF)
	sta VERA_ADDR_M
	LoadB VERA_ADDR_H, ^MAP | $20 ; (increment 2)
	lda #80
	sec
	sbc kTmp
	cmp kTmp+1
	bcc @n
	lda kTmp+1
@n:	tax
	beq @done
	lda hC
@c:	sta VERA_DATA0
	dex
	bne @c
	iny
	dec hN
	bne @row
@done:	clc
	rts

.segment "RODATA"

DowT:	.byte 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4
DowN:	.byte "SunMonTueWedThuFriSat"
MonT:	.byte "JanFebMarAprMayJunJulAugSepOctNovDec"

; the mark: a V (look/mock.py's polygon (3,3) (7,3) (8,9) (9,3) (13,3)
; (10,12) (6,12)), 16 x 15 (the line under the bar is row 15),
; compacted (BitmapUp: 30 bytes as they are)
Mark:	.byte $80 + 30
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00011111, %01111100
	.byte %00011111, %01111100
	.byte %00001111, %01111000
	.byte %00001111, %01111000
	.byte %00001111, %11111000
	.byte %00000111, %11110000
	.byte %00000111, %11110000
	.byte %00000111, %11110000
	.byte %00000011, %11100000
	.byte %00000011, %11100000
	.byte %00000000, %00000000
	.byte %00000000, %00000000

; the speaker (the mockup's: a box, a cone, a sound wave), and crossed out
Speaker: .byte $80 + 30
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00000001, %00000000
	.byte %00000011, %00000000
	.byte %00000111, %00010000
	.byte %01111111, %00001000
	.byte %01111111, %00001000
	.byte %01111111, %00001000
	.byte %01111111, %00001000
	.byte %00000111, %00010000
	.byte %00000011, %00000000
	.byte %00000001, %00000000
	.byte %00000000, %00000000
	.byte %00000000, %00000000
Muted:	.byte $80 + 30
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00000000, %00000000
	.byte %00000001, %00000000
	.byte %00000011, %00000000
	.byte %00000111, %00000000
	.byte %01111111, %00100100
	.byte %01111111, %00011000
	.byte %01111111, %00011000
	.byte %01111111, %00100100
	.byte %00000111, %00000000
	.byte %00000011, %00000000
	.byte %00000001, %00000000
	.byte %00000000, %00000000
	.byte %00000000, %00000000

; (V127) the bar's clock while the clock reads 2000 (never set): "Set
; clock" into buf (in LATE, after the variables: CODE ends a few bytes
; before the UI font's page)
.segment "LATE"

;---------------------------------------------------------------
; LK_ITEM (V146, Sunroom's menus: bank U's Put for a list in the Veranda
; look): the item's text r0 at r11, baseline r12, the item's top kTmp.
; A text that starts with MENU_SEP ($1F) gets a dotted line on its top
; row, across the list (a group starts there; the byte is not drawn); a
; TAB ends the text, and what follows it (the item's key, "Ctrl O") is
; drawn right-aligned 8 pixels from the list's right
;---------------------------------------------------------------
MENU_SEP = $1F
LookItem:
	lda (r0)
	cmp #MENU_SEP
	bne @t
	IncW r0
	PushW r11
	MoveW kTmp, r11          ; (the item's top: a word, r11H too)
	lda mLeft               ; (left + 1 .. right - 1: a list's left is
	ldx mLeft+1             ; a card's, its right a card's last pixel)
	ina
	sta r3
	stx r3+1
	lda mRight
	ldx mRight+1
	dea
	sta r4
	stx r4+1
	lda #%01010101
	FARCALL k_WHorizontalLine
	PopW r11
@t:	ldy #0
@s:	lda (r0),y
	beq @put
	cmp #9
	beq @tab
	iny
	bne @s
@put:	jmp S_k_WPutString
@tab:	lda #0                  ; the text to the TAB (r0 then past it: the
	sta (r0),y              ; key; r12 kept)
	FARCALL k_WPutString
	lda r0
	sec
	sbc #1
	sta kTmp
	lda r0+1
	sbc #0
	sta kTmp+1
	lda #9
	sta (kTmp)
@k:	lda mRight              ; r11 = right - 7 - its width
	sec
	sbc #7
	sta r11
	lda mRight+1
	sbc #0
	sta r11+1
	ldy #0
@w:	lda (r0),y
	beq @put
	phy
	FARCALL k_GetCharWidth
	sta kTmp
	lda r11
	sec
	sbc kTmp
	sta r11
	bcs @w1
	dec r11+1
@w1:	ply
	iny
	bra @w

; (V127: PutY, Three and Num2 moved here from CODE, for room)

; three characters from DowN + y, then a space, into buf + x
Three:	lda #3
	sta hC
@1:	lda DowN,y
	sta buf,x
	inx
	iny
	dec hC
	bne @1
	lda #' '
	sta buf,x
	inx
	rts


SetClk:	lda SetT,x
	sta buf,x
	beq @r
	inx
	bra SetClk
@r:	rts
SetT:	.byte "Set clock", 0
