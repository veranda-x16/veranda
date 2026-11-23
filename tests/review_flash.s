; gate review, finding 1 (DECISIONS V68): a dialog box opened while a
; menu's or an icon's flash runs. A session for tests/ui.s (320x240, the
; script through mouseSource, keys into the ROM's queue).
;
; A main menu (act: an action; sub: a sub menu whose go is an action) and
; an icon. The program's keyVector opens a box on 'b'. The script clicks
; act, types 'b' within the flash (20 frames), closes the box with Return;
; the same for the icon, then for go in the sub menu. Each action and the
; icon's routine log "ACT <which> <1 if a box is open>"; the box logs BOX
; and BOX END; at the end "FLASH m s i <mouseOn>": how often each ran.
; Expected: each runs once, after its box (0), the pointer on.
;
; -D SUB: go alone (the sub menu's action: before the fix the box's main
; loop took the main menu's item 0 there, the SUB_MENU entry, and jumped
; to its table's address as code).
;
; -D ALARM: the alarm's box instead (V56): the clock set to 11:59:58, an
; alarm at 12:00, a flash of 2 x 150 frames from act clicked at once: the
; alarm comes due inside the flash and must wait for it (the kernel logs
; "ALARM 12:00" when its box opens): ACT M 0 before ALARM.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export UiSession, UiScript
.import UiFrame

.segment "CODE"

UiSession:
	LoadB dispBufferOn, ST_WR_FORE | ST_WR_BACK
	lda #0
	jsr SetPattern
	LoadB r2L, 0
	LoadB r2H, 199
	LoadW r3, 0
	LoadW r4, 319
	jsr Rectangle
.ifdef ALARM
	LoadB r0L, 126          ; 2026-11-16 11:59:58
	LoadB r0H, 11
	LoadB r1L, 16
	LoadB r1H, 11
	LoadB r2L, 59
	LoadB r2H, 58
	LoadB r3H, 2
	jsr SetClock
	LoadW r0, Alarms
	lda #ALARMS_SET
	jsr SysPrefs
	LoadB selectionFlash, 150
.endif
	LoadW keyVector, KeyH
	LoadW appMain, Main
	LoadW r0, Icons
	jsr DoIcons
	LoadW r0, MainMenu
	lda #0
	jsr DoMenu
	jmp MainLoop

; the last frame's report (ui.s logs UI DONE at the end frame: a frame
; before it, from the main loop)
Main:	lda done
	bne @r
	lda UiFrame+1           ; ($FFFF before the first frame)
	cmp #$FF
	beq @r
	CmpWI UiFrame, END - 2
	bcc @r
	inc done
	lda #10
	jsr Put
	ldx #0
@t:	lda TFlash,x
	beq @n
	jsr Put
	inx
	bra @t
@n:	lda cM
	jsr Hex
	jsr Sp
	lda cS
	jsr Hex
	jsr Sp
	lda cI
	jsr Hex
	jsr Sp
	lda mouseOn
	jsr Hex
	lda #10
	jsr Put
@r:	rts

KeyH:	lda keyData
	cmp #'b'
	bne @r
	LoadW r0, TBox
	jsr LogText
	inc inBox
	LoadW r0, Box
	jsr DoDlgBox
	stz inBox
	LoadW r0, TBoxEnd
	jsr LogText
@r:	rts

ActMain:
	inc cM
	lda #'M'
	jsr Act
	jmp ReDoMenu
ActSub:	inc cS
	lda #'S'
	jsr Act
	jmp GotoFirstMenu
ActIcon:
	inc cI
	lda #'I'
; "ACT <a> <inBox>"
Act:	pha
	lda #10
	jsr Put
	lda #'A'
	jsr Put
	lda #'C'
	jsr Put
	lda #'T'
	jsr Put
	jsr Sp
	pla
	jsr Put
	jsr Sp
	lda inBox
	jsr Hex
	lda #10
	jmp Put

Sp:	lda #' '
Put:	sta EMU_STDOUT
	rts
Hex:	pha
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

cM:	.byte 0
cS:	.byte 0
cI:	.byte 0
inBox:	.byte 0
done:	.byte 0

.segment "RODATA"

TBox:	.byte "BOX", 0
TBoxEnd: .byte "BOX END", 0
TFlash:	.byte "FLASH ", 0

Box:	.byte DEF_DB_POS | 1
	.byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y
	.word TText
	.byte OK, DBI_X_1, DBI_Y_2
	.byte 0
TText:	.byte "A box in a flash.", 0

MainMenu:
	.byte 0, 14
	.word 0, 80
	.byte HORIZONTAL | UN_CONSTRAINED | 2
	.word TAct
	.byte MENU_ACTION
	.word ActMain
	.word TSub
	.byte SUB_MENU
	.word SubMenu

SubMenu:
	.byte 14, 14 + 2 * 14
	.word 30, 100
	.byte VERTICAL | UN_CONSTRAINED | 2
	.word TGo
	.byte MENU_ACTION
	.word ActSub
	.word TGo
	.byte MENU_ACTION
	.word ActSub

TAct:	.byte "act", 0
TSub:	.byte "sub", 0
TGo:	.byte "go", 0

Icons:	.byte 1
	.word 0
	.byte 0
	.word Pic
	.byte 20, 100, 3, 16
	.word ActIcon
Pic:	.byte 3, $FF, 42, $81, 3, $FF

.ifdef ALARM
Alarms:	.byte 26, 11, 16, 12, 0, ALARM_ARMED
	.byte "Review", 0
	.res 32 - 13, 0
	.res 32 * (ALARM_MAX - 1), 0
.endif

.macro EV ef, ex, ey, eb
	.word ef, ex
	.byte ey, eb
.endmacro
.macro KEY ef, code
	.word ef, code
	.byte 0, $80
.endmacro

.ifdef SUB
END = 200
UiScript:
	EV 0, 200, 150, 0
	EV 70, 40, 7, 0         ; on sub
	EV 72, 40, 7, 1
	EV 73, 50, 22, 1
	EV 75, 50, 22, 0
	EV 80, 50, 22, 0        ; on go
	EV 82, 50, 22, 1
	EV 83, 50, 22, 0
	KEY 86, 'b'
	KEY 120, CR
	.word $FFFF, END
	.byte 0, 0
.elseif .not .defined(ALARM)
END = 300
UiScript:
	EV 0, 200, 150, 0
	EV 10, 10, 7, 0         ; on act
	EV 12, 10, 7, 1         ; press: the flash (20 frames)
	EV 13, 10, 7, 0
	KEY 16, 'b'             ; a box within it
	KEY 50, CR              ; closed: the flash goes on, then the action
	EV 90, 170, 108, 0      ; on the icon
	EV 92, 170, 108, 1
	EV 93, 170, 108, 0
	KEY 96, 'b'
	KEY 130, CR
	EV 170, 40, 7, 0        ; on sub
	EV 172, 40, 7, 1        ; its sub menu
	EV 173, 50, 22, 1
	EV 175, 50, 22, 0
	EV 180, 50, 22, 0       ; on go
	EV 182, 50, 22, 1
	EV 183, 50, 22, 0
	KEY 186, 'b'
	KEY 220, CR
	.word $FFFF, END
	.byte 0, 0
.else
END = 600
UiScript:
	EV 0, 200, 150, 0
	EV 10, 10, 7, 0         ; on act
	EV 12, 10, 7, 1         ; press: the flash (300 frames)
	EV 13, 10, 7, 0
	KEY 500, CR             ; the alarm's box closed
	.word $FFFF, END
	.byte 0, 0
.endif
