; gate mouse's menu tracking program (tools/gate_mouse.sh; DECISIONS V137):
; the Veranda look's menu bar (uiLook LOOK_BAR) with four titles:
;   Track  3 items (First, Second, Last)                 -> TRACK T n
;   Long   28 items: Item 00 .. Item 26, then More, a sub menu of 6
;          items beside it at the screen's bottom        -> TRACK L n, TRACK M n
;   Next   2 items                                       -> TRACK N n
;   Act    an action on the bar                          -> TRACK B 00
; each action logged (LogText) and the menus closed (GotoFirstMenu); a
; press the menus did not take: TRACK PRESS (otherPressVec)

.include "veranda.inc"
.include "macros.inc"

.segment "CODE"

Start:
	LoadB uiLook, LOOK_BAR
	lda #2
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	LoadW otherPressVec, Press
	LoadW r0, Menu
	lda #0
	jsr DoMenu
	LoadW r0, Ready
	jmp LogText

Press:	bit mouseData
	bmi @r                  ; (a release)
	LoadW r0, Pressed
	jmp LogText
@r:	rts

TAct:	ldx #'T'
	bra Log
LAct:	ldx #'L'
	bra Log
MAct:	ldx #'M'
	bra Log
NAct:	ldx #'N'
	bra Log
BAct:	lda #0
	ldx #'B'
; "TRACK x nn" (nn: a in decimal), the menus closed
Log:	stx Msg + 6
	ldx #'0'
@t:	cmp #10
	bcc @u
	sbc #10
	inx
	bra @t
@u:	ora #'0'
	sta Msg + 9
	stx Msg + 8
	LoadW r0, Msg
	jsr LogText
	jmp GotoFirstMenu

.segment "DATA"

Msg:	.byte "TRACK x nn", 0

.segment "RODATA"

Ready:	.byte "TRACK READY", 0
Pressed: .byte "TRACK PRESS", 0

Menu:	.byte 0, 15
	.word 0, 200
	.byte HORIZONTAL | UN_CONSTRAINED | 4
	.word STrack
	.byte SUB_MENU
	.word TrackMenu
	.word SLong
	.byte SUB_MENU
	.word LongMenu
	.word SNext
	.byte SUB_MENU
	.word NextMenu
	.word SAct
	.byte MENU_ACTION
	.word BAct

TrackMenu:
	.byte 0, 0
	.word 0, 80
	.byte VERTICAL | UN_CONSTRAINED | 3
	.word SFirst
	.byte MENU_ACTION
	.word TAct
	.word SSecond
	.byte MENU_ACTION
	.word TAct
	.word SLast
	.byte MENU_ACTION
	.word TAct

LongMenu:
	.byte 0, 0
	.word 0, 80
	.byte VERTICAL | UN_CONSTRAINED | 28
.repeat 27, I
	.word .ident(.sprintf("SL%d", I))
	.byte MENU_ACTION
	.word LAct
.endrepeat
	.word SMore
	.byte SUB_MENU
	.word MoreMenu

MoreMenu:
	.byte 0, 0
	.word 0, 80
	.byte VERTICAL | UN_CONSTRAINED | 6
.repeat 6, I
	.word .ident(.sprintf("SM%d", I))
	.byte MENU_ACTION
	.word MAct
.endrepeat

NextMenu:
	.byte 0, 0
	.word 0, 80
	.byte VERTICAL | UN_CONSTRAINED | 2
	.word SN0
	.byte MENU_ACTION
	.word NAct
	.word SN1
	.byte MENU_ACTION
	.word NAct

STrack:	.byte "Track", 0
SLong:	.byte "Long", 0
SNext:	.byte "Next", 0
SAct:	.byte "Act", 0
SFirst:	.byte "First", 0
SSecond: .byte "Second", 0
SLast:	.byte "Last", 0
SMore:	.byte "More", 0
SN0:	.byte "Next 0", 0
SN1:	.byte "Next 1", 0
.repeat 27, I
.ident(.sprintf("SL%d", I)): .byte .sprintf("Item %02d", I), 0
.endrepeat
.repeat 6, I
.ident(.sprintf("SM%d", I)): .byte .sprintf("More %d", I), 0
.endrepeat
