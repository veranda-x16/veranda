; VeraBASIC Run: overlay 8, dialogs, icons, pictures, sprites, tiles and
; the clipboard (phase 4, DECISIONS V90). Overlay 6 (vbui4.s) parses
; every statement: its arguments are in xi (integers), sbufb (the first
; string: all its bytes) and sbufa (the last) when these run.
;
; Dialog boxes are the kernel's (DoDlgBox, V15): the box, its texts
; (DBTXTSTR), its system icons (OK, CANCEL, YES, NO), and a DB_USR_ROUT of
; ours (through overlay 1's stub: the kernel calls with appBank mapped)
; that draws the text fields and takes the keys and the presses (Tab the
; next field, Return the default, Esc Cancel). The table and the texts are
; built in main RAM's scratch (sbounce .. sbufb: the kernel reads below
; $A000), free while a box is up. The Open and Save dialog, the clipboard
; and the tile are C (records 10 and 11: vbca.s, vbcb.s, vbcb.c).
;
; A picture (PICTURE$) is a string: its width in cards, its height in
; lines, then the bitmap compacted as BitmapUp reads it (repeats of 3-127,
; literal runs of up to 91: tools/vbveranda2.py packs the same bytes).
; Icons are ours, not the kernel's DoIcons table (which would have to stay
; in main RAM): drawn here, their places in overlay 1, which takes a press
; on one (inverted until the release) and queues an ICON event.
;
; MIT licence (LICENSE).

MAXLAB	= 8                     ; a box's texts
MAXFLD	= 4                     ; its fields
MAXICON	= 8
SRAW	= 512                   ; a sprite's picture: 512 bytes unpacked at most

.segment "OVL8BSS"
dlx:	.res 1                  ; the box: card, row, width, height
dly:	.res 1
dlw:	.res 1
dlh:	.res 1
dbtn:	.res 1                  ; its buttons: 1 OK, 2 Cancel, 4 Yes, 8 No
dopen:	.res 1                  ; 1: inside DIALOG ... END DIALOG
dres:	.res 1                  ; how the last one closed (DIALOG RESULT)
dnum:	.res 1                  ; boxes shown (_vx_dlg)
nlab:	.res 1
labx:	.res MAXLAB             ; pixels from the box's left and top (the baseline)
laby:	.res MAXLAB
labt:	.res MAXLAB * 64
nfld:	.res 1
fldx:	.res MAXFLD             ; cards from the box's corner
fldy:	.res MAXFLD
fldm:	.res MAXFLD             ; the longest text
fldn:	.res MAXFLD             ; its length
fldt:	.res MAXFLD * 64
fldv:	.res MAXFLD * 4         ; the variable: p0, xb, t0
dfoc:	.res 1                  ; the field the keys go to
dl:	.res 2                  ; the box's left, top (pixels)
dt:	.res 2
qa:	.res 2
qb:	.res 2
qc:	.res 2
qw2:	.res 1
cb_a:	.res 2                  ; the C overlays' call
cb_w:	.res 1
cb_r:	.res 1
icx:	.res MAXICON            ; the icons: card, width, line, height (0: none)
icw:	.res MAXICON
icy:	.res MAXICON * 2
ich:	.res MAXICON
ipress:	.res 1                  ; an icon pressed (its number), inverted until the release
pw:	.res 1                  ; a picture's width (cards), height
ph:	.res 1
pslen:	.res 1                  ; its string's length
ibn:	.res 1                  ; INPUTBOX$: the default's length, the longest
ibm:	.res 1
pcx:	.res 1                  ; where pdraw drew it: card, line
pcy:	.res 2
sraw:	.res SRAW               ; a sprite's picture unpacked

.segment "OVERLAY8"

; a routine with WINDOW USE's clip (xspec8)
g8run:	jsr clip8
	jsr @j
	jmp unclip8
@j:	jmp (r14)
clip8:	lda _vx_clip+8
	beq unclip8
	ldx #3
@c:	lda _vx_clip,x
	sta leftMargin,x
	lda _vx_clip+4,x
	sta windowTopW,x
	dex
	bpl @c
	lda #1
	sta clipOn
	rts
unclip8:
	stz clipOn
	stz leftMargin
	stz leftMargin+1
	LoadW rightMargin, 639
	stz windowTopW
	stz windowTopW+1
	LoadW windowBottomW, 479
	rts

ill8:	ERR E_ILLQ

;---------------------------------------------------------------
; a program starts, ends
;---------------------------------------------------------------
d_reset:
	stz dnum
	stz dres
	stz _vx_dlg
; the icons gone, sprites 2-7 off
d_end:	stz ipress
	ldx #MAXICON - 1
@i:	stz ich,x
	dex
	bpl @i
	lda #2
@s:	sta r3L
	pha
	jsr DisablSprite
	pla
	inc a
	cmp #8
	bne @s
	stz dopen
	rts

;---------------------------------------------------------------
; the C overlays (vbc.cfg): routine a/x of bank A (y = 0) or B (y = 1),
; LOW copied into main RAM first, the console's font read again after;
; x = its result
;---------------------------------------------------------------
cblob:	sta cb_a
	stx cb_a+1
	sty cb_w
	lda #<$A000             ; LOW in
	ldx #>$A000
	ldy _vx_ovlb
	jsr bcall
	ldy _vx_ovla
	lda cb_w
	beq @a
	ldy _vx_ovlb
@a:	lda cb_a
	ldx cb_a+1
	jsr bcall
	stx cb_r
	lda #<_vb_fontload
	ldx #>_vb_fontload
	ldy appBank
	jsr bcall
	ldx cb_r
	rts

; the kernel's error x (a C overlay's): the program's
kerr8:	cpx #0
	bne @e
	rts
@e:	stx kerr
	lda #E_FNF
	cpx #FILE_NOT_FOUND
	beq @r
	lda #E_PICT
	cpx #INCOMPATIBLE
	beq @r
	lda #E_DISK
@r:	jmp raise

;---------------------------------------------------------------
; dialog boxes
;---------------------------------------------------------------
; a box of w (a) by h (x) cards, centred; no texts, fields, buttons
dbox:	sta dlw
	stx dlh
	lda #80
	sec
	sbc dlw
	lsr a
	sta dlx
	lda #60
	sec
	sbc dlh
	lsr a
	sta dly
dclear:	stz nlab
	stz nfld
	stz dbtn
	stz dfoc
	rts

; text a/x (0-ended, main RAM or this bank) as the box's text at card
; column y, card row in qw2 (its baseline 9 lines down): to LF or 0;
; carry set when it ended at an LF (p1 then past it)
dlabel:	sta p1
	stx p1+1
	lda nlab
	cmp #MAXLAB
	bcc @1
	ERR E_DLG
@1:	tax
	tya
	asl a
	asl a
	asl a
	sta labx,x
	lda qw2
	asl a
	asl a
	asl a
	clc
	adc #9
	sta laby,x
	txa
	jsr labp                ; p0 = its text's place
	ldy #0
@c:	lda (p1),y
	beq @e
	cmp #10
	beq @lf
	sta (p0),y
	iny
	cpy #63
	bcc @c
@e:	lda #0
	sta (p0),y
	inc nlab
	clc
	rts
@lf:	lda #0
	sta (p0),y
	inc nlab
	iny
	tya
	clc
	adc p1
	sta p1
	bcc @lf1
	inc p1+1
@lf1:	sec
	rts
; p0 = label a's text (64 bytes a label; x kept)
labp:	stz p0+1
	asl a
	asl a
	asl a
	asl a
	rol p0+1
	asl a
	rol p0+1
	asl a
	rol p0+1
	clc
	adc #<labt
	sta p0
	lda p0+1
	adc #>labt
	sta p0+1
	rts

; the lines of the text at a/x (LF between them) from card row qw2 down
dlines:	ldy #2
	jsr dlabel
	bcc @r
	inc qw2
	inc qw2
	lda p1
	ldx p1+1
	bra dlines
@r:	rts

; the longest line (characters) of sbufa's t0 bytes in a, the lines in x
lines_of:
	ldy #0
	ldx #1
	stz qw2
	stz qa
@l:	cpy t0
	beq @d
	lda sbufa,y
	iny
	cmp #10
	beq @n
	inc qa
	lda qa
	cmp qw2
	bcc @l
	sta qw2
	bra @l
@n:	inx
	stz qa
	bra @l
@d:	lda qw2
	rts

; a box's width for a text of a characters: 7 pixels each and margins,
; 24 to 76 cards
dwidth:	cmp #80
	bcc @1
	lda #80
@1:	sta qa
	lsr a
	lsr a
	lsr a
	sta qb                  ; n * 7 / 8 = n - n / 8
	lda qa
	sec
	sbc qb
	clc
	adc #6
	cmp #24
	bcs @2
	lda #24
@2:	cmp #77
	bcc @3
	lda #76
@3:	rts

; the box shown (DoDlgBox) until a button, Return or Esc: dres
dshow:	inc dnum
	; the table at sbounce, the texts at sbufa + 64 * i
	lda dlx
	jsr x8a
	sta dl
	stx dl+1
	lda dly
	jsr x8a
	sta dt
	stx dt+1
	lda #SET_DB_POS | WIDE_DB | 2
	sta sbounce
	lda dt
	sta sbounce+1
	lda dt+1
	sta sbounce+2
	lda dly
	clc
	adc dlh
	jsr x8a
	sec
	sbc #1
	sta sbounce+3
	txa
	sbc #0
	sta sbounce+4
	lda dl
	sta sbounce+5
	lda dl+1
	sta sbounce+6
	lda dlx
	clc
	adc dlw
	jsr x8a
	sec
	sbc #1
	sta sbounce+7
	txa
	sbc #0
	sta sbounce+8
	lda #DB_USR_ROUT
	sta sbounce+9
	lda #<dlg_rout
	sta sbounce+10
	lda #>dlg_rout
	sta sbounce+11
	ldy #12
	ldx #0
@lab:	cpx nlab
	beq @lab9
	lda #DBTXTSTR
	sta sbounce,y
	lda labx,x
	sta sbounce+1,y
	lda laby,x
	sta sbounce+2,y
	txa                     ; the text below $A000: sbufa + 64 * x
	lsr a
	lsr a
	clc
	adc #>sbufa
	sta sbounce+4,y
	txa
	and #3
	lsr a
	ror a
	ror a
	adc #<sbufa
	sta sbounce+3,y
	bcc @lc
	lda sbounce+4,y
	inc a
	sta sbounce+4,y
@lc:	phx
	phy
	lda sbounce+3,y
	sta p1
	lda sbounce+4,y
	sta p1+1
	txa
	jsr labp
	ldy #0
@cp:	lda (p0),y
	sta (p1),y
	beq @cp9
	iny
	bra @cp
@cp9:	ply
	plx
	tya
	clc
	adc #5
	tay
	inx
	bra @lab
@lab9:	; the buttons: from the right, at the bottom
	lda dlh
	asl a
	asl a
	asl a
	sec
	sbc #24
	sta qw2                 ; their line
	lda dlw
	sec
	sbc #7
	sta qa                  ; the next one's card
	ldx #0
@b:	lda dbtn
	and btnbit,x
	beq @b9
	lda btncode,x
	sta sbounce,y
	lda qa
	sta sbounce+1,y
	lda qw2
	sta sbounce+2,y
	iny
	iny
	iny
	lda qa
	sec
	sbc #7
	sta qa
@b9:	inx
	cpx #4
	bne @b
	lda #0
	sta sbounce,y
	LoadW r0, sbounce
	jsr DoDlgBox
	lda r0L
	sta dres
	stz _vx_dlg
	rts
; the order from the right: OK, Cancel ... (No, Yes)
btnbit:	.byte 1, 2, 8, 4
btncode: .byte OK, CANCEL, NO, YES

; a/x = a * 8
x8a:	ldx #0
	stx qc
	asl a
	rol qc
	asl a
	rol qc
	asl a
	rol qc
	ldx qc
	rts

;---------------------------------------------------------------
; the box's routine, keys and presses (overlay 1's stubs: dlg_rout,
; dlg_key, dlg_press)
;---------------------------------------------------------------
d_rout:	lda #<dlg_key
	sta keyVector
	lda #>dlg_key
	sta keyVector+1
	lda #<dlg_press
	sta otherPressVec
	lda #>dlg_press
	sta otherPressVec+1
	ldx #0
@f:	cpx nfld
	beq @d
	phx
	jsr fdraw
	plx
	inx
	bra @f
@d:	lda dnum
	sta _vx_dlg
	rts

; field x's frame: r3, r11, r4, r12 (qb = x)
frect:	stx qb
	lda fldx,x              ; left: the box's + 8 * x - 3
	jsr x8a
	clc
	adc dl
	sta r3
	txa
	adc dl+1
	sta r3+1
	lda r3
	sec
	sbc #3
	sta r3
	bcs @1
	dec r3+1
@1:	ldx qb                  ; top: the box's + 8 * y - 2
	lda fldy,x
	jsr x8a
	clc
	adc dt
	sta r11
	txa
	adc dt+1
	sta r11+1
	lda r11
	sec
	sbc #2
	sta r11
	bcs @2
	dec r11+1
@2:	lda r11                 ; bottom: top + 13
	clc
	adc #13
	sta r12
	lda r11+1
	adc #0
	sta r12+1
	ldx qb                  ; right: left + 7 * max + 8 (255 at most)
	lda fldm,x
	cmp #35
	bcc @3
	lda #247
	bra @4
@3:	asl a
	asl a
	asl a
	sec
	sbc fldm,x
@4:	clc
	adc #8
	clc
	adc r3
	sta r4
	lda r3+1
	adc #0
	sta r4+1
	lda dlx                 ; and the box's right - 8 at most
	clc
	adc dlw
	jsr x8a
	sec
	sbc #9
	sta qa
	txa
	sbc #0
	sta qa+1
	lda qa
	cmp r4
	lda qa+1
	sbc r4+1
	bcs @5
	MoveW qa, r4
@5:	ldx qb
	rts

; field x drawn: its frame, its text, the cursor if it has the keys
fdraw:	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	jsr frect
	lda #0
	jsr SetPattern
	jsr WRectangle
	lda #$FF
	jsr WFrameRectangle
	lda #FONT_UI
	jsr UseFont
	stz currentMode
	ldx qb                  ; its text to inbuf
	txa
	jsr fldp
	ldy #0
@c:	tya
	cmp fldn,x
	beq @c9
	lda (p0),y
	sta inbuf,y
	iny
	bra @c
@c9:	lda #0
	sta inbuf,y
	lda r11                 ; the baseline: the top + 11
	clc
	adc #11
	sta r12
	lda r11+1
	adc #0
	sta r12+1
	lda r3                  ; x: the left + 3
	clc
	adc #3
	sta r11
	lda r3+1
	adc #0
	sta r11+1
	LoadW r0, inbuf
	jsr WPutString          ; (r11 is past the text after it)
	ldx qb
	cpx dfoc
	bne @r
	MoveW r11, r3           ; the cursor: a line after the text
	MoveW r11, r4
	lda r12
	sec
	sbc #9
	sta r11
	lda r12+1
	sbc #0
	sta r11+1
	lda r12
	clc
	adc #1
	sta r12
	bcc @k
	inc r12+1
@k:	jsr WInvertRectangle
@r:	rts

; p0 = field a's text (64 bytes a field; a, x kept)
fldp:	pha
	stz p0+1
	asl a
	asl a
	asl a
	asl a
	rol p0+1
	asl a
	rol p0+1
	asl a
	rol p0+1
	clc
	adc #<fldt
	sta p0
	lda p0+1
	adc #>fldt
	sta p0+1
	pla
	rts

; a key: Tab, Return, Esc, Backspace, a character for the field
d_key:	lda keyData
	cmp #KEY_TAB
	bne @1
	lda nfld
	jeq @r
	ldx dfoc
	inx
	cpx nfld
	bcc @t
	ldx #0
@t:	lda dfoc
	stx dfoc
	tax
	jsr fdraw
	ldx dfoc
	jmp fdraw
@1:	cmp #13
	bne @2
	lda #OK
	ldx dbtn
	cpx #4                  ; (Yes and No: Return is Yes)
	bcc dend
	lda #YES
	bra dend
@2:	cmp #KEY_ESC
	bne @3
	lda dbtn
	lsr a
	lsr a
	bcs @c                  ; Cancel
	lsr a
	lsr a
	bcs @n                  ; No
	lda #OK
	bra dend
@c:	lda #CANCEL
	bra dend
@n:	lda #NO
	bra dend
@3:	ldx nfld
	beq @r
	ldx dfoc
	cmp #KEY_LEFT           ; Backspace
	beq @bs
	cmp #$14
	beq @bs
	cmp #32
	bcc @r
	cmp #127
	bcc @ch
	cmp #160
	bcc @r
@ch:	pha
	lda fldn,x
	cmp fldm,x
	pla
	bcs @r
	pha
	txa
	jsr fldp
	ldy fldn,x
	pla
	sta (p0),y
	inc fldn,x
	jmp fdraw
@bs:	lda fldn,x
	beq @r
	dec fldn,x
	jmp fdraw
@r:	rts
; the box closed with a
dend:	sta sysDBData
	jmp RstrFrmDialogue

; a press on a field gives it the keys
d_press:
	bit mouseData
	bmi @r
	ldx #0
@l:	cpx nfld
	beq @r
	stx qb
	jsr frect
	ldx qb
	lda mouseXPos
	cmp r3
	lda mouseXPos+1
	sbc r3+1
	bcc @n
	lda r4
	cmp mouseXPos
	lda r4+1
	sbc mouseXPos+1
	bcc @n
	lda mouseYPosW
	cmp r11
	lda mouseYPosW+1
	sbc r11+1
	bcc @n
	lda r12
	cmp mouseYPosW
	lda r12+1
	sbc mouseYPosW+1
	bcc @n
	lda dfoc                ; this one
	stx dfoc
	tax
	jsr fdraw
	ldx dfoc
	jmp fdraw
@n:	inx
	bra @l
@r:	rts

;---------------------------------------------------------------
; the icons' presses (overlay 1, vbev.s ev_icon, from otherPressVec): c
; set when an icon took it; x an icon released on itself (its number), else 0
;---------------------------------------------------------------
i8_icon:
	lda mouseData
	bmi @rel
	ldx #MAXICON - 1
@l:	lda ich,x
	beq @n
	jsr iinside
	bcc @n
	inx
	stx ipress
	dex
	jsr iinvert
	ldx #0
	sec
	rts
@n:	dex
	bpl @l
	clc
	rts
@rel:	ldx ipress
	beq @no
	stz ipress
	dex
	phx
	jsr iinvert
	plx
	jsr iinside
	bcc @o
	inx                     ; (its number)
	sec
	rts
@o:	ldx #0
	sec
	rts
@no:	clc
	rts
; c set if the pointer is in icon x (x kept)
iinside:
	lda mouseXPos+1         ; its card
	lsr a
	lda mouseXPos
	ror a
	lsr a
	lsr a
	cmp icx,x
	bcc @no
	sec
	sbc icx,x
	cmp icw,x
	bcs @no
	txa
	asl a
	tay
	lda mouseYPosW
	sec
	sbc icy,y
	sta qa
	lda mouseYPosW+1
	sbc icy+1,y
	bcc @no                 ; above
	bne @no
	lda qa
	cmp ich,x
	bcs @no
	sec
	rts
@no:	clc
	rts
; icon x inverted on the front screen (x kept)
iinvert:
	phx
	lda #ST_WR_FORE
	sta dispBufferOn
	lda icx,x
	jsr x8a
	sta r3
	stx r3+1
	plx
	phx
	lda icx,x
	clc
	adc icw,x
	jsr x8a
	sec
	sbc #1
	sta r4
	txa
	sbc #0
	sta r4+1
	plx
	phx
	txa
	asl a
	tay
	lda icy,y
	sta r11
	clc
	adc ich,x
	sta r12
	lda icy+1,y
	sta r11+1
	adc #0
	sta r12+1
	lda r12
	bne @e
	dec r12+1
@e:	dec r12
	jsr WInvertRectangle
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	plx
	rts

;---------------------------------------------------------------
; MSGBOX, ASK, INPUTBOX$
;---------------------------------------------------------------
; the box for sbufa's text (LF: a new line) with buttons a; the title
; (when there is one) in sbufb, bold
mbox:	pha
	jsr lines_of            ; a: the longest, x: the lines
	pha
	txa
	asl a
	clc
	adc #6                  ; height: 2 rows a line, 6 more
	ldy xi_n
	cpy #2
	bcc @h
	clc
	adc #2                  ; (a title)
@h:	tax
	pla
	jsr dwidth
	jsr dbox
	pla
	sta dbtn
	lda #2
	sta qw2
	lda xi_n
	cmp #2
	bcc @t
	lda #BOLDON             ; the title: BOLDON and sbufb
	sta sbounce
	ldx #0
@tc:	lda sbufb,x
	sta sbounce+1,x
	beq @t1
	inx
	cpx #62
	bcc @tc
	stz sbounce+1,x
@t1:	lda #<sbounce
	ldx #>sbounce
	ldy #2
	jsr dlabel
	lda #4
	sta qw2
@t:	ldx t0                  ; the text, 0-ended
	stz sbufa,x
	lda #<sbufa
	ldx #>sbufa
	jsr dlines
	jmp dshow

; MSGBOX text$ [, title$] (the title is the first string: then the text
; is sbufa, the last)
d_msgbox:
	lda xi_n
	cmp #2
	bcs @2
	lda xi                  ; one: sbufa is it
	sta t0
	lda #1
	jsr mbox
	clc
	rts
@2:	jsr swapb               ; text$ in sbufa, title$ in sbufb
	lda #1
	jsr mbox
	clc
	rts
; sbufa <-> sbufb (t0 = the first string's length: text$)
swapb:	ldx #0
@l:	lda sbufa,x
	ldy sbufb,x
	sta sbufb,x
	tya
	sta sbufa,x
	inx
	bne @l
	lda xi
	sta t0
	rts

; ASK(text$): 1 Yes, 0 No
d_ask:	lda xi
	sta t0
	stz xi_n                ; (no title)
	inc xi_n
	lda #4 | 8
	jsr mbox
	stz ac1
	stz ac0
	lda dres
	cmp #YES
	bne @r
	inc ac0
@r:	rts

; INPUTBOX$(prompt$ [, default$ [, length]]): "" on Cancel
d_inputbox:
	lda #63                 ; the length
	sta ibm
	lda xi_n
	cmp #3
	bcc @1
	lda xi+5
	jne @ill
	lda xi+4
	jeq @ill
	cmp #64
	jcs @ill
	sta ibm
@1:	lda xi_n                ; the default: sbufa (two strings) or ""
	cmp #2
	bcs @2
	stz fldt
	stz ibn
	bra @3
@2:	lda xi+2
	cmp ibm
	bcc @d
	lda ibm
@d:	sta ibn
	ldx #0
@c:	lda sbufa,x
	sta fldt,x
	inx
	cpx #64
	bne @c
@3:	ldx #0                  ; the prompt (sbufb) as sbufa's text
@p:	lda sbufb,x
	sta sbufa,x
	inx
	bne @p
	lda xi
	sta t0
	jsr lines_of
	pha
	txa
	asl a
	clc
	adc #9
	tax
	pla
	cmp #40
	bcs @w
	lda #40
@w:	jsr dwidth
	jsr dbox
	lda #1 | 2
	sta dbtn
	lda #2
	sta qw2
	ldx t0
	stz sbufa,x
	lda #<sbufa
	ldx #>sbufa
	jsr dlines
	lda #1                  ; the field under the text
	sta nfld
	lda #3
	sta fldx
	lda qw2
	clc
	adc #2
	sta fldy
	lda ibm
	sta fldm
	lda ibn
	sta fldn
	jsr dshow
	stz t0
	lda dres
	cmp #OK
	bne @r
	ldx #0
@o:	cpx fldn
	beq @o9
	lda fldt,x
	sta sbufa,x
	inx
	bra @o
@o9:	stx t0
@r:	rts
@ill:	ERR E_ILLQ

;---------------------------------------------------------------
; DIALOG ... END DIALOG
;---------------------------------------------------------------
d_dialog:
	lda xi+1
	ora xi+3
	ora xi+5
	ora xi+7
	bne @ill
	lda xi
	clc
	adc xi+4
	cmp #81
	bcs @ill
	lda xi+2
	cmp #2
	bcc @ill
	clc
	adc xi+6
	cmp #61
	bcs @ill
	lda xi+4
	cmp #16
	bcc @ill
	lda xi+6
	cmp #6
	bcc @ill
	lda xi
	sta dlx
	lda xi+2
	sta dly
	lda xi+4
	sta dlw
	lda xi+6
	sta dlh
	jsr dclear
	lda #1
	sta dopen
	rts
@ill:	ERR E_ILLQ
dinside:
	lda dopen
	beq @no
	rts
@no:	ERR E_DLG

; LABEL x, y, text$
d_label:
	jsr dinside
	lda xi+1
	ora xi+3
	bne @ill
	lda xi
	cmp #32
	bcs @ill
	lda xi+2
	cmp dlh
	bcs @ill
	sta qw2
	ldx xi+4
	stz sbufb,x
	ldy xi
	lda #<sbufb
	ldx #>sbufb
	jmp dlabel
@ill:	ERR E_ILLQ

; FIELD x, y, v$, length (p0, xb, t0: the variable)
d_field:
	jsr dinside
	ldx nfld
	cpx #MAXFLD
	bcc @1
	ERR E_DLG
@1:	lda xi+1
	ora xi+3
	ora xi+7
	bne @ill
	lda xi
	cmp dlw
	bcs @ill
	sta fldx,x
	lda xi+2
	cmp dlh
	bcs @ill
	sta fldy,x
	lda xi+6
	beq @ill
	cmp #64
	bcs @ill
	sta fldm,x
	txa                     ; the variable's place
	asl a
	asl a
	tay
	lda p0
	sta fldv,y
	lda p0+1
	sta fldv+1,y
	lda xb
	sta fldv+2,y
	lda t0
	sta fldv+3,y
	lda xi+4                ; its value: the text
	cmp fldm,x
	bcc @2
	lda fldm,x
@2:	sta fldn,x
	txa
	jsr fldp
	ldy #0
@c:	tya
	cmp fldn,x
	beq @c9
	lda sbufb,y
	sta (p0),y
	iny
	bra @c
@c9:	inc nfld
	rts
@ill:	ERR E_ILLQ

; BUTTON OK | CANCEL
d_button:
	jsr dinside
	lda #1
	ldx xi
	cpx #<TX_OK
	beq @1
	lda #2
@1:	tsb dbtn
	rts

; END DIALOG: the box, then each field's text to its variable (logged),
; and how it closed (logged)
d_enddialog:
	jsr dinside
	stz dopen
	lda dbtn
	bne @1
	lda #1                  ; no button: OK
	sta dbtn
@1:	jsr dshow
	ldx #0
@f:	cpx nfld
	beq @d
	phx
	lda dres
	cmp #OK
	bne @n                  ; Cancel: the variables as they were
	txa
	jsr fldp
	ldy #0
@c:	tya
	cmp fldn,x
	beq @c9
	lda (p0),y
	sta sbufa,y
	iny
	bra @c
@c9:	sty t0
.ifdef VB_TEST
	lda #$AC
	jsr lg8s
.endif
	PCALL btt0
	plx
	phx
	txa
	asl a
	asl a
	tay
	lda fldv,y
	sta p0
	lda fldv+1,y
	sta p0+1
	lda fldv+2,y
	sta xb
	lda fldv+3,y
	sta t0
	PCALL store
@n:	plx
	inx
	bra @f
@d:
.ifdef VB_TEST
	lda #$A8
	jsr lg8n
.endif
	rts

; DIALOG RESULT
d_result:
	lda dres
	sta ac0
	stz ac1
	rts

.ifdef VB_TEST
; "VB= @nn "sbufa's t0 bytes"" and "VB= @nn dres" (the reference takes
; the fields' texts and the result from them)
lg8h:	pha
	ldx #0
@m:	lda M8,x
	beq @h
	sta EMU_STDOUT
	inx
	bra @m
@h:	pla
	jsr hex8
	lda #' '
	sta EMU_STDOUT
	rts
lg8s:	jsr lg8h
	lda #'"'
	sta EMU_STDOUT
	ldx #0
@l:	cpx t0
	beq @e
	lda sbufa,x
	cmp #' '
	bcc @x
	cmp #$7F
	bcs @x
	cmp #$5C
	beq @x
	sta EMU_STDOUT
	bra @n
@x:	pha
	lda #$5C
	sta EMU_STDOUT
	pla
	jsr hex8
@n:	inx
	bra @l
@e:	lda #'"'
	sta EMU_STDOUT
	lda #10
	sta EMU_STDOUT
	rts
lg8n:	jsr lg8h
	lda dres
	ora #'0'                ; (1-4)
	sta EMU_STDOUT
	lda #10
	sta EMU_STDOUT
	rts
hex8:	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr @d
	pla
	and #15
@d:	cmp #10
	bcc @1
	adc #6
@1:	adc #'0'
	sta EMU_STDOUT
	rts
M8:	.byte "VB= @", 0
; "VB CD path": the folder the Open and Save dialog chose
lgcd:	ldx #0
@m:	lda MCD,x
	beq @p
	sta EMU_STDOUT
	inx
	bra @m
@p:	ldx #0
@c:	lda curDirName,x
	beq @e
	sta EMU_STDOUT
	inx
	cpx #64
	bcc @c
@e:	lda #10
	sta EMU_STDOUT
	rts
MCD:	.byte "VB CD ", 0
.endif

;---------------------------------------------------------------
; FILEOPEN$, FILESAVE$: the SDK's dialog (vr_file, record 10)
;---------------------------------------------------------------
; FILEOPEN$(title$ [, extension$]): the title is sbufb; the extension sbufa
d_fileopen:
	stz inbuf+2             ; no name
	stz inbuf+130
	lda xi_n
	cmp #2
	bcc @1
	lda xi+2                ; "EXT files:EXT"
	beq @1
	cmp #9
	bcs @1
	ldx #0
@e:	lda sbufa,x
	sta inbuf+130,x
	inx
	cpx xi+2
	bne @e
	ldy #0
@f:	lda MFiles,y
	sta inbuf+130,x
	inx
	iny
	cpy #7
	bne @f
	ldy #0
@g:	lda sbufa,y
	sta inbuf+130,x
	inx
	iny
	cpy xi+2
	bne @g
	stz inbuf+130,x
@1:	lda #VRF_OPEN
	bra dfile
MFiles:	.byte " files:"
	.byte 0
; FILESAVE$(title$, default$)
d_filesave:
	ldx #0
@n:	lda sbufa,x             ; the name: the last string
	sta inbuf+2,x
	inx
	cpx #63
	bcc @n
	ldx xi+2
	cpx #63
	bcc @z
	ldx #63
@z:	stz inbuf+2,x
	stz inbuf+130
	lda #VRF_SAVE
dfile:	sta inbuf
	ldx #0                  ; the title: the first string
@t:	lda sbufb,x
	sta inbuf+66,x
	beq @t9
	inx
	cpx #63
	bcc @t
	stz inbuf+66,x
@t9:	inc dnum
	lda dnum
	sta inbuf+194
	lda #<$A000
	ldx #>$A000
	ldy #0
	jsr cblob
	stz _vx_dlg
	stz t0
	lda inbuf+1
	beq @r
.ifdef VB_TEST
	jsr lgcd
.endif
	ldx #0
@c:	lda inbuf+2,x
	beq @c9
	sta sbufa,x
	inx
	cpx #63
	bcc @c
@c9:	stx t0
@r:	rts
VRF_OPEN = 0
VRF_SAVE = 1

;---------------------------------------------------------------
; the clipboard, the tile (record 11)
;---------------------------------------------------------------
; CLIPBOARD$
d_clipget:
	lda #<$A003
	ldx #>$A003
	ldy #1
	jsr cblob
	stx t0
	ldy #0
@c:	cpy t0
	beq @r
	lda inbuf,y
	sta sbufa,y
	iny
	bra @c
@r:	rts
; CLIPBOARD s$
d_clipput:
	lda xi
	sta inbuf
	ldx #0
@c:	cpx xi
	beq @1
	lda sbufb,x
	sta inbuf+1,x
	inx
	bra @c
@1:	lda #<$A006
	ldx #>$A006
	ldy #1
	jsr cblob
	jmp kerr8
; CLIPBOARD PICTURE x1, y1, x2, y2 (cards: x1 / 8 .. x2 / 8)
d_clippict:
	jsr rr8                 ; r3, r11, r4, r12
	lda r3                  ; the card, the width
	ldx r3+1
	jsr div8
	sta inbuf
	lda r4
	ldx r4+1
	jsr div8
	sec
	sbc inbuf
	bcc @ill
	inc a
	sta inbuf+1
	lda r11
	sta inbuf+2
	lda r11+1
	sta inbuf+3
	lda r12
	sec
	sbc r11
	sta inbuf+4
	lda r12+1
	sbc r11+1
	sta inbuf+5
	bcc @ill
	inc inbuf+4
	bne @1
	inc inbuf+5
@1:	lda #<$A00C
	ldx #>$A00C
	ldy #1
	jsr cblob
	jmp kerr8
@ill:	ERR E_ILLQ
; a/x / 8 (a byte)
div8:	stx qc
	lsr qc
	ror a
	lsr qc
	ror a
	lsr qc
	ror a
	rts
; r3, r11, r4, r12 = xi[0..3] + the origin
rr8:	ldx #0
	ldy #0
@l:	lda xi,y
	clc
	adc _vx_ox
	sta r3,x
	lda xi+1,y
	adc _vx_ox+1
	sta r3+1,x
	lda xi+2,y
	clc
	adc _vx_oy
	sta r11,x
	lda xi+3,y
	adc _vx_oy+1
	sta r11+1,x
	cpx #0
	bne @r
	ldx #r4 - r3
	ldy #4
	bra @l
@r:	rts

; TILE x, y, name$ [, colour] (cards from the origin's)
d_tile:	lda xi+1
	ora xi+3
	bne @ill
	lda xi
	clc
	adc _vx_ocx
	cmp #77
	bcs @ill
	sta inbuf
	lda xi+2
	clc
	adc _vx_ocy
	cmp #57
	bcs @ill
	sta inbuf+1
	lda #$FF
	ldx xi_n
	cpx #4
	bcc @c
	lda xi+7
	bne @ill
	lda xi+6
	cmp #16
	bcs @ill
@c:	sta inbuf+2
	ldx #0
@n:	lda sbufb,x
	sta inbuf+3,x
	beq @1
	inx
	cpx #63
	bcc @n
	stz inbuf+3,x
@1:	lda #<$A009
	ldx #>$A009
	ldy #1
	jsr cblob
	jmp kerr8
@ill:	ERR E_ILLQ

;---------------------------------------------------------------
; pictures
;---------------------------------------------------------------
; sbufb: a picture of a bytes (its header checked): pw, ph, pslen
pcheck:	sta pslen
	cmp #3
	bcc @no
	cpx #0
	bne @no
	lda sbufb
	beq @no
	cmp #81
	bcs @no
	sta pw
	lda sbufb+1
	beq @no
	sta ph
	rts
@no:	ERR E_PICT

; BITMAP x, y, picture$ (x to a card)
d_bitmap:
	lda xi+4
	ldx xi+5
	jsr pcheck
	MoveW xi, r1
	MoveW xi+2, r11
; sbufb's picture at x r1, y r11 (+ the origin; x to a card): drawn,
; r1L its card
pdraw:	lda r1L
	clc
	adc _vx_ox
	pha
	lda r1H
	adc _vx_ox+1
	tax
	pla
	jsr div8
	sta r1L
	lda r11
	clc
	adc _vx_oy
	sta r11
	lda r11+1
	adc _vx_oy+1
	sta r11+1
	lda r1L                 ; (kept: the kernel's call changes them)
	sta pcx
	MoveW r11, pcy
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	LoadW r0, sbufb+2
	lda pw
	sta r2L
	lda ph
	sta r12
	stz r12+1
	jmp WBitmapUp

; ICON id, x, y, picture$, procedure
d_icon:	jsr iconid
	phx
	lda xi+6
	ldx xi+7
	jsr pcheck
	MoveW xi+2, r1
	MoveW xi+4, r11
	jsr pdraw
	plx
	lda pcx                 ; its place
	sta icx,x
	lda pw
	sta icw,x
	txa
	asl a
	tay
	lda pcy
	sta icy,y
	lda pcy+1
	sta icy+1,y
	lda ph
	sta ich,x
	lda xi+8                ; the procedure + 1
	inc a
	sta t2
	stx t0
	O1CALL o1_icon
	rts
; x = the icon xi[0] (1-8) - 1
iconid:	lda xi+1
	bne @ill
	ldx xi
	beq @ill
	cpx #MAXICON + 1
	bcs @ill
	dex
	rts
@ill:	ERR E_ILLQ

; ICON OFF id: taken away (its place cleared)
d_iconoff:
	jsr iconid
	jmp ioff
; ICONS CLEAR
d_iconsclear:
	ldx #MAXICON - 1
@l:	phx
	jsr ioff
	plx
	dex
	bpl @l
	rts
; icon x taken away (x kept)
ioff:	lda ich,x
	beq @r
	stx qb
	inx
	cpx ipress
	bne @p
	stz ipress
@p:	dex
	stx t0
	stz t2
	O1CALL o1_icon
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	ldx qb
	lda icx,x
	jsr x8a
	sta r3
	stx r3+1
	ldx qb
	lda icx,x
	clc
	adc icw,x
	jsr x8a
	sec
	sbc #1
	sta r4
	txa
	sbc #0
	sta r4+1
	ldx qb
	txa
	asl a
	tay
	lda icy,y
	clc
	adc ich,x
	sta r12
	lda icy+1,y
	adc #0
	sta r12+1
	lda r12
	bne @1
	dec r12+1
@1:	dec r12
	lda icy,y
	sta r11
	lda icy+1,y
	sta r11+1
	lda #0
	jsr SetPattern
	jsr WRectangle
	ldx qb
	stz ich,x
@r:	rts

; SPRITE n, picture$: its 24 x 21 (the picture's top left) to sprite n
d_sprite:
	jsr sprn
	lda xi+2
	ldx xi+3
	jsr pcheck
	jsr unpack              ; sraw: pw by ph
	LoadW p1, sraw          ; the row
	LoadW p0, sbounce       ; 21 rows of 3 bytes
	ldx #0
@r:	ldy #0
@b:	lda #0
	cpx ph
	bcs @z
	cpy pw
	bcs @z
	lda (p1),y
@z:	sta (p0),y
	iny
	cpy #3
	bne @b
	lda p0
	clc
	adc #3
	sta p0
	bcc @n
	inc p0+1
@n:	cpx ph
	bcs @n2
	lda p1
	clc
	adc pw
	sta p1
	bcc @n2
	inc p1+1
@n2:	inx
	cpx #21
	bne @r
	lda qb+1
	sta r3L
	LoadW r4, sbounce
	jmp DrawSprite
; the sprite xi[0] (2-7) in qb+1
sprn:	lda xi+1
	bne @ill
	lda xi
	cmp #2
	bcc @ill
	cmp #8
	bcs @ill
	sta qb+1
	rts
@ill:	ERR E_ILLQ
; SPRITE n AT x, y
d_spriteat:
	jsr sprn
	sta r3L
	lda xi+2
	clc
	adc _vx_ox
	sta r4
	lda xi+3
	adc _vx_ox+1
	sta r4+1
	lda xi+4
	clc
	adc _vx_oy
	sta r11
	lda xi+5
	adc _vx_oy+1
	sta r11+1
	jmp WPosSprite
; SPRITE n ON | OFF
d_spriteon:
	jsr sprn
	sta r3L
	lda xi+2
	bne @off
	jmp EnablSprite
@off:	jmp DisablSprite

; sbufb's picture (pw, ph) unpacked into sraw (pw * ph bytes, 512 at most)
unpack:	lda pw
	sta qa
	stz qa+1
	ldx ph                  ; the size: pw * ph
	stz qc
	stz qc+1
@m:	lda qc
	clc
	adc qa
	sta qc
	bcc @m1
	inc qc+1
@m1:	dex
	bne @m
	lda qc+1
	cmp #>SRAW
	bcc @ok
	bne @bad
	lda qc
	cmp #<SRAW + 1
	bcs @bad
@ok:	LoadW p1, sraw
	ldy #2                  ; the data from sbufb + 2
@c:	lda qc
	ora qc+1
	beq @r
	cpy pslen
	bcs @bad
	lda sbufb,y
	iny
	beq @bad
	cmp #128
	bcc @rep
	cmp #220
	bcs @bad
	sbc #128 - 1            ; literal: a - 128 bytes
	beq @bad
	tax
@lit:	cpy pslen
	bcs @bad
	lda sbufb,y
	iny
	jsr put1
	dex
	bne @lit
	bra @c
@rep:	cmp #0
	beq @bad
	tax
	cpy pslen
	bcs @bad
	lda sbufb,y
	iny
@rp:	jsr put1
	dex
	bne @rp
	bra @c
@r:	rts
@bad:	ERR E_PICT
; a byte to p1 (qc counts down; beyond the size: dropped)
put1:	pha
	lda qc
	ora qc+1
	beq @s
	pla
	sta (p1)
	inc p1
	bne @1
	inc p1+1
@1:	lda qc
	bne @2
	dec qc+1
@2:	dec qc
	rts
@s:	pla
	rts

