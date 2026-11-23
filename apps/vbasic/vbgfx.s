; VeraBASIC Run: overlay 7, graphics, text, fonts, colour and sound (phase 3,
; DECISIONS V89). Overlay 6 (vbui.s) parses each statement: its arguments
; are in xi (integers) and sbufb, sbufa (strings) when it calls these. The
; coordinates are relative to the origin (WINDOW USE) and clipped by the
; kernel (clipOn, V81); PutCards, CopyRect, ScrollRect and the colours are
; in cards from the body's first card. PLAY's sequencer runs in the
; interrupt (vbx.s _vx_irq maps this bank): it uses only r0-r15, which the
; kernel saves around it.
;
; MIT licence (LICENSE).

VRAM_PSG_L = $C0                ; the PSG at $1F9C0, 4 bytes a voice
NSLOT = 4                       ; PLAY's voices at once
PLEN  = 128                     ; a tune's bytes

.segment "OVL7BSS"
curfont: .res 1
curstyle: .res 1
curpat:	.res 1
; PLAY: a slot per tune
pvoice:	.res NSLOT              ; $FF: free
ppos:	.res NSLOT
pwait:	.res NSLOT
poff:	.res NSLOT              ; the frame its note ends (silence)
poct:	.res NSLOT
plen:	.res NSLOT
pwhole: .res NSLOT * 2          ; frames of a whole note (the tempo)
ptext:	.res NSLOT * PLEN

mn:	.res 1                  ; menus
mni:	.res 1                  ; items
mcur:	.res 1                  ; the menu ITEMs go to ($FF none)
mshown:	.res 1                  ; MENU SHOW done
mtitle:	.res MAXMENU * 24
mfirst:	.res MAXMENU
mcount:	.res MAXMENU
itext:	.res MAXITEM * 32
ikey:	.res MAXITEM
iflag:	.res MAXITEM            ; bit 0 disabled, bit 1 checked
stitle:	.res 64                 ; SCREN FULL's title (0: none)
barend:	.res 2
qq:	.res 1
appname: .res 24
classic: .res 1
qw:	.res 2
qx:	.res 2
qk:	.res 1
qj:	.res 1
qi:	.res 1
qsep:	.res 1                 ; 4: the next ITEM starts a group (ITEM "-")

.segment "OVERLAY7"
.import _vr_win, _vr_win_title, _vr_win_status, _vr_win_hit, pushax

g_reset:
	stz mn
	stz qsep
	stz mni
	stz mshown
	stz classic
	stz appname
	stz stitle
	lda #$FF
	sta mcur
	stz curfont
	stz curstyle
	lda #1                  ; BOX fills with ink until PATTERN says
	sta curpat
	jsr g_soundoff
	lda #0
	jsr SetPointer
	jsr UseSystemFont
	stz currentMode
	lda #0
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jmp WSetMouseRegion

; the kernel's clip: WINDOW USE's body around a drawing statement (g7run),
; else the whole screen (the menus, the dialog boxes and the chrome are
; drawn with the text's margins too)
g7run:	jsr clip_set
	jsr @j
	jmp clip_end
@j:	jmp (r14)
clip_set:
	lda _vx_clip+8
	beq clip_end
	ldx #3
@c:	lda _vx_clip,x
	sta leftMargin,x        ; leftMargin, rightMargin
	lda _vx_clip+4,x
	sta windowTopW,x        ; windowTopW, windowBottomW
	dex
	bpl @c
	lda #1
	sta clipOn
	rts
clip_end:
	stz clipOn
	stz leftMargin
	stz leftMargin+1
	LoadW rightMargin, 639
	stz windowTopW
	stz windowTopW+1
	LoadW windowBottomW, 479
	rts

; r3, r11, r4, r12 = xi[0..3] + the origin (x, y, x, y)
rr:	ldx #0
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

both:	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	rts

ill:	ERR E_ILLQ

; CLS: the body (the clip's rectangle), or the screen under the menu bar
g_cls:	jsr both
	lda #0
	jsr SetPattern
	lda _vx_clip+8
	beq @s
	MoveW leftMargin, r3
	MoveW rightMargin, r4
	MoveW windowTopW, r11
	MoveW windowBottomW, r12
	bra @d
@s:	LoadW r3, 0
	LoadW r11, 16
	LoadW r4, 639
	LoadW r12, 479
@d:	jsr WRectangle
	lda curpat
	jmp SetPattern

g_pattern:
	lda xi+1
	bne ill
	lda xi
	cmp #34
	bcs ill
	sta curpat
	jmp SetPattern

g_box:	jsr both
	lda curpat
	jsr SetPattern
	jsr rr
	jmp WRectangle
g_frame:
	jsr both
	jsr rr
	lda #$FF
	jmp WFrameRectangle
g_invert:
	jsr both
	jsr rr
	jmp WInvertRectangle
; the drawing mode: xi[k] if given (k = a), else ink
mode:	cmp xi_n
	bcs @ink
	asl a
	tax
	lda xi+1,x
	jne ill
	lda xi,x
	cmp #2
	jcs ill
	rts
@ink:	lda #DRAW_INK
	rts
g_line:	jsr both
	jsr rr
	lda #4
	jsr mode
	jmp WDrawLine
g_plot:	jsr both
	jsr rr
	lda #2
	jsr mode
	jmp WDrawPoint
gf_point:
	jsr rr
	jsr WTestPoint
	and #1
	sta ac0
	stz ac1
	lda #TY_I
	sta aty
	rts

; COPY x, y, w, h TO x2, y2 (x, w, x2 cards; y, h, y2 lines)
g_copy:	jsr both
	lda xi
	clc
	adc _vx_ocx
	sta r3L
	lda xi+4
	sta r3H
	lda xi+2
	clc
	adc _vx_oy
	sta r11
	lda xi+3
	adc _vx_oy+1
	sta r11+1
	MoveW xi+6, r12
	lda xi+8
	clc
	adc _vx_ocx
	sta r4L
	lda xi+10
	clc
	adc _vx_oy
	sta r13
	lda xi+11
	adc _vx_oy+1
	sta r13+1
	jmp CopyRect
; SCROLL x, w, top, bottom, dy
g_scroll:
	jsr both
	lda xi
	clc
	adc _vx_ocx
	sta r3L
	lda xi+2
	sta r3H
	lda xi+4
	clc
	adc _vx_oy
	sta r11
	lda xi+5
	adc _vx_oy+1
	sta r11+1
	lda xi+6
	clc
	adc _vx_oy
	sta r12
	lda xi+7
	adc _vx_oy+1
	sta r12+1
	MoveW xi+8, r13
	lda #0
	jmp ScrollRect

g_pointer:
	lda xi+1
	bne ill2
	lda xi
	cmp #4
	bcs ill2
	jmp SetPointer
ill2:	ERR E_ILLQ

;---------------------------------------------------------------
; text and fonts
;---------------------------------------------------------------
usefont:
	lda curfont
	jsr UseFont
	lda curstyle
	sta currentMode
	rts
g_text:	jsr both
	jsr usefont
	LoadW r0, sbufb
	lda xi
	clc
	adc _vx_ox
	sta r11
	lda xi+1
	adc _vx_ox+1
	sta r11+1
	lda xi+2
	clc
	adc _vx_oy
	sta r12
	lda xi+3
	adc _vx_oy+1
	sta r12+1
	jsr WPutString
	stz currentMode
	rts
g_style:
	lda xi
	and #$F8
	sta curstyle
	rts
; FONT UI | FONT SYSTEM (the constants 6 and 4)
g_fontn:
	lda xi+1
	bne ill2
	lda xi
	ldx #FONT_UI
	cmp #6
	beq @s
	ldx #0
	cmp #4
	bne ill2
@s:	stx curfont
	rts
; FONT name$, size
g_font:	LoadW r0, sbufb
	lda xi+2
	jsr LoadFont
	cmp #FONT_NONE
	bne @ok
	ERR E_FONT
@ok:	sta curfont
	rts
gf_textwidth:
	jsr usefont
	stz ac0
	stz ac1
	ldx #0
@l:	cpx xi
	beq @d
	phx
	lda sbufb,x
	jsr GetCharWidth
	pha
	lda curstyle            ; bold: a pixel more a character
	and #SET_BOLD
	cmp #1
	pla
	adc ac0
	sta ac0
	bcc @1
	inc ac1
@1:	plx
	inx
	bra @l
@d:	stz currentMode
	lda #TY_I
	sta aty
	rts
gf_fontheight:
	LoadW r0, 0
	lda curfont
	jsr FontInfo
	lda r1L
	sta ac0
	stz ac1
	lda #TY_I
	sta aty
	rts
; CARDS column, row, s$ [, REVERSE | BOLD]: the ROM's 8 x 8 font
g_cards:
	jsr both
	ldx #0
	lda xi_n
	cmp #4
	bcc @f
	lda xi+6
	and #SET_REVERSE
	beq @1
	inx
@1:	lda xi+6
	and #SET_BOLD
	beq @f
	inx
	inx
@f:	phx
	LoadW r0, sbufb
	LoadW r1, _vb_font
	lda xi
	clc
	adc _vx_ocx
	sta r3L
	lda xi+4
	beq @z
	sta r3H
	lda xi+2
	clc
	adc _vx_ocy
	stz r11+1
	asl a
	rol r11+1
	asl a
	rol r11+1
	asl a
	rol r11+1
	sta r11
	pla
	jmp PutCards
@z:	pla
	rts

;---------------------------------------------------------------
; colour
;---------------------------------------------------------------
; PAPER column, row, w, h, colour
g_paper:
	lda xi+8
	cmp #16
	bcs ill3
	lda xi+9
	bne ill3
	lda xi
	clc
	adc _vx_ocx
	sta r3L
	lda xi+4
	sta r3H
	lda xi+2
	clc
	adc _vx_ocy
	sta r11L
	lda xi+6
	sta r11H
	lda xi+8
	jmp ColorRect
ill3:	ERR E_ILLQ
gf_cardcolor:
	lda xi
	clc
	adc _vx_ocx
	sta r3L
	lda xi+2
	clc
	adc _vx_ocy
	sta r11L
	jsr GetCardColor
	sta ac0
	stz ac1
	lda #TY_I
	sta aty
	rts
; INK $RGB
g_ink:	LoadW r0, $FFFF
	MoveW xi, r1
	jmp SetColors
; PALETTE n, $RGB: entries 12-15 only (2-11 are Look 2's)
g_palette:
	lda xi+1
	bne ill3
	lda xi
	cmp #12
	bcc ill3
	cmp #16
	bcs ill3
	asl a
	stz VERA_CTRL
	sta VERA_ADDR_L
	lda #$FA
	sta VERA_ADDR_M
	lda #$11
	sta VERA_ADDR_H
	lda xi+2
	sta VERA_DATA0          ; green, blue
	lda xi+3
	and #$0F
	sta VERA_DATA0          ; red
	rts

;---------------------------------------------------------------
; sound
;---------------------------------------------------------------
g_sound:
	lda xi
	jmp PlaySound
g_beep:	jmp Beep
; voice a (0-13): VERA's port 0 at its registers
psg:	asl a
	asl a
	clc
	adc #VRAM_PSG_L
	stz VERA_CTRL
	sta VERA_ADDR_L
	lda #$F9
	sta VERA_ADDR_M
	lda #$11
	sta VERA_ADDR_H
	rts
; SOUND OFF: the program's voices silent, the tunes stopped
g_soundoff:
	ldx #NSLOT - 1
	lda #$FF
@s:	sta pvoice,x
	dex
	bpl @s
	lda #0
	jsr psg
	ldx #14 * 4
@z:	stz VERA_DATA0
	dex
	bne @z
	rts
; VOICE v, frequency, volume [, wave [, width]]
g_voice:
	lda xi+1
	bne ill4
	lda xi
	cmp #14
	bcs ill4
	lda xi+5
	bne ill4
	lda xi+4
	cmp #64
	bcs ill4
	lda #0                  ; the wave
	ldx xi_n
	cpx #4
	bcc @w
	lda xi+6
	cmp #4
	bcs ill4
@w:	ror a
	ror a
	ror a
	and #$C0
	sta r2L
	lda #63                 ; the width
	cpx #5
	bcc @wd
	lda xi+8
	and #63
@wd:	ora r2L
	sta r2L
	; the frequency word: hz * 687 / 256 (the PSG's 0.3725 Hz steps)
	MoveW xi+2, r0
	jsr fmul
	lda xi
	jsr psg
	lda r1L
	sta VERA_DATA0
	lda r1H
	sta VERA_DATA0
	lda xi+4
	ora #$C0
	sta VERA_DATA0
	lda r2L
	sta VERA_DATA0
	rts
ill4:	ERR E_ILLQ
; r1 = r0 * 687 / 256 (r0 < 24414); r3, r4 used
fmul:	stz r3L                 ; r3L:r1 = the 24-bit product
	stz r1L
	stz r1H
	LoadW r4, 687
	ldx #16
@l:	lsr r4H
	ror r4L
	bcc @n
	lda r1L
	clc
	adc r0L
	sta r1L
	lda r1H
	adc r0H
	sta r1H
	lda r3L
	adc r3H
	sta r3L
@n:	asl r0L
	rol r0H
	rol r3H
	dex
	bne @l
	lda r1H                 ; / 256
	sta r1L
	lda r3L
	sta r1H
	rts

; PLAY v, music$
g_play:	lda xi+1
	bne ill4
	lda xi
	cmp #14
	bcs ill4
	sei
	ldx #NSLOT - 1          ; the voice's slot, or a free one
@f:	lda pvoice,x
	cmp xi
	beq @g
	dex
	bpl @f
	ldx #NSLOT - 1
@e:	lda pvoice,x
	cmp #$FF
	beq @g
	dex
	bpl @e
	cli
	ERR E_ILLQ              ; four tunes at once at most
@g:	lda #$FF
	sta pvoice,x
	stx r5L
	txa
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a                   ; * PLEN
	tay
	ldx #0
@c:	cpx xi+2
	beq @d
	cpx #PLEN - 1
	bcs @d
	lda sbufb,x
	sta ptext,y
	iny
	inx
	bra @c
@d:	lda #0
	sta ptext,y
	ldx r5L
	stz ppos,x
	lda #1
	sta pwait,x
	stz poff,x
	lda #4
	sta poct,x
	sta plen,x
	txa
	asl a
	tay
	lda #<120               ; tempo 120: 14400 / 120 frames a whole note
	sta pwhole,y
	lda #0
	sta pwhole+1,y
	lda xi
	sta pvoice,x
	cli
	rts

; the interrupt: every tune's next frame (r0-r15 only)
snd_tick:
	ldx #NSLOT - 1
@s:	lda pvoice,x
	cmp #$FF
	beq @n
	stx r6L
	jsr tune
	ldx r6L
@n:	dex
	bpl @s
	rts
tune:	lda poff,x
	beq @1
	dec poff,x
	bne @1
	lda pvoice,x            ; the note's last frame: silence
	jsr psg
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	ldx r6L
@1:	dec pwait,x
	beq @next
	rts
@next:	; the next command of the text
	txa
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	clc
	adc ppos,x
	tay                     ; (ppos < PLEN)
@c:	lda ptext,y
	bne @2
	lda #$FF                ; the end: silent, the slot free
	pha
	lda pvoice,x
	jsr psg
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	pla
	ldx r6L
	sta pvoice,x
	rts
@2:	iny
	inc ppos,x
	and #$DF                ; upper case (and ' ' to 0: skipped)
	beq @c
	cmp #'T'
	jeq @t
	cmp #'O'
	jeq @o
	cmp #'L'
	jeq @l
	cmp #'R'
	jeq @r
	cmp #'<' & $DF
	jeq @dn
	cmp #'>' & $DF
	jeq @up
	cmp #'A'
	bcc @c
	cmp #'H'
	bcs @c
	; a note: its semitone in octave 4
	sbc #'A' - 1            ; (carry clear: - 'A')
	tax
	lda semis,x
	sta r7L
	lda ptext,y             ; # + -
	cmp #'#'
	beq @sh
	cmp #'+'
	bne @fl
@sh:	inc r7L
	bra @sk
@fl:	cmp #'-'
	bne @nl
	dec r7L
@sk:	iny
	ldx r6L
	inc ppos,x
@nl:	jsr pnum                ; a length?
	bcs @ln
	ldx r6L
	lda plen,x
@ln:	jsr frames
	ldx r6L
	sta pwait,x
	lsr a                   ; silent for its last eighth
	lsr a
	lsr a
	eor #$FF
	sec
	adc pwait,x
	sta poff,x
	; the frequency: octave 4's word shifted
	lda r7L
	and #$0F
	cmp #12
	bcc @k
	lda #11
@k:	asl a
	tax
	lda notes,x
	sta r0L
	lda notes+1,x
	sta r0H
	ldx r6L
	lda poct,x
@oc:	cmp #4
	beq @of
	bcc @od
	asl r0L
	rol r0H
	dec a
	bra @oc
@od:	lsr r0H
	ror r0L
	inc a
	bra @oc
@of:	lda pvoice,x
	jsr psg
	lda r0L
	sta VERA_DATA0
	lda r0H
	sta VERA_DATA0
	lda #$C0 | 48
	sta VERA_DATA0
	lda #63                 ; a square wave
	sta VERA_DATA0
	rts
@t:	jsr pnum
	bcc @tc
	ldx r6L                 ; frames of a whole note: 14400 / tempo
	jsr div14400
	txa
	asl a
	tax
	lda r0L
	sta pwhole,x
	lda r0H
	sta pwhole+1,x
@tc:	ldx r6L
	jmp @next
@o:	jsr pnum
	bcc @tc
	ldx r6L
	cmp #8
	bcs @tc
	sta poct,x
	bra @tc
@l:	jsr pnum
	bcc @tc
	ldx r6L
	sta plen,x
	bra @tc
@dn:	ldx r6L
	lda poct,x
	beq @tc
	dec poct,x
	bra @tc
@up:	ldx r6L
	lda poct,x
	cmp #7
	bcs @tc
	inc poct,x
	bra @tc
@r:	jsr pnum
	bcs @rl
	ldx r6L
	lda plen,x
@rl:	jsr frames
	ldx r6L
	sta pwait,x
	stz poff,x
	lda pvoice,x
	jsr psg
	stz VERA_DATA0
	stz VERA_DATA0
	stz VERA_DATA0
	rts
; a number at ptext,y (y, ppos past it): a, carry set; carry clear if none
pnum:	stz r8L
	ldx r6L
	clc
	php
@l:	lda ptext,y
	cmp #'0'
	bcc @e
	cmp #'9' + 1
	bcs @e
	plp
	sec
	php
	and #$0F
	pha
	lda r8L                 ; * 10 + digit
	asl a
	asl a
	adc r8L
	asl a
	sta r8L
	pla
	adc r8L
	sta r8L
	iny
	inc ppos,x
	bra @l
@e:	plp
	lda r8L
	rts
; a = frames of a note of length a (1, 2, 4, 8, 16, 32): the whole / a
frames:	sta r8H
	ldx r6L
	txa
	asl a
	tax
	lda pwhole,x
	sta r0L
	lda pwhole+1,x
	sta r0H
	lda r8H
	beq @d
@s:	lsr a
	beq @d
	lsr r0H
	ror r0L
	bra @s
@d:	lda r0H
	bne @max
	lda r0L
	bne @r
	lda #1
@r:	rts
@max:	lda #255
	rts
; r0 = 14400 / a (a > 0)
div14400:
	sta r8H
	LoadW r0, 14400
	stz r1L
	stz r1H
	ldx #16
@l:	asl r0L
	rol r0H
	rol r1L
	rol r1H
	lda r1L
	sec
	sbc r8H
	tay
	lda r1H
	sbc #0
	bcc @n
	sta r1H
	sty r1L
	inc r0L
@n:	dex
	bne @l
	rts

semis:	.byte 9, 11, 0, 2, 4, 5, 7          ; A B C D E F G
; octave 4: C .. B, the PSG's words (hz * 2.684)
notes:	.word 702, 744, 788, 835, 885, 937, 993, 1052, 1115, 1181, 1251, 1326

;---------------------------------------------------------------
; menus (vbui.s parses them)
;---------------------------------------------------------------
g_menu:
	lda mshown              ; a new bar after MENU SHOW
	beq @1
	stz mshown
	stz mn
	stz mni
	lda #0
	O1SET OT_NITEM, 0
@1:	lda mn
	cmp #MAXMENU
	bcc @2
	ERR E_MENUS
@2:	sta mcur
	jsr mul24
	ldy #0
@c:	lda sbufb,y
	sta mtitle,x
	beq @3
	inx
	iny
	cpy #23
	bcc @c
	stz mtitle,x
@3:	ldx mcur
	stz mcount,x
	stz qsep
	lda mni
	sta mfirst,x
	pha
	txa
	clc
	adc #OT_MFIRST
	sta t0
	pla
	sta t1
	O1CALL o1_set
	inc mn
	clc
	rts
mul24:	asl a
	asl a
	asl a
	sta qw
	asl a
	clc
	adc qw
	tax
	rts

; END MENU
g_endmenu:
	lda #$FF
	sta mcur
	clc
	rts

; ITEM text$ [, procedure [, key$]]
g_item:
	lda mcur
	bpl @1
	ERR E_SYNTAX                 ; no MENU before it
@1:	lda xi                  ; "-": not an item; the next one starts a
	cmp #1                  ; group (V149, Sunroom: a dotted line over it;
	bne @2                  ; never the menu's first)
	lda sbufb
	cmp #'-'
	bne @2
	ldx mcur
	lda mcount,x
	beq @s
	lda #4
@s:	sta qsep
	clc
	rts
@2:	lda mni
	cmp #MAXITEM
	bcc @3
	ERR E_MENUS
@3:	sta qk
	jsr itp
	ldy #0
@c:	lda sbufb,y
	sta (r15),y
	beq @4
	iny
	cpy #31
	bcc @c
	lda #0
	sta (r15),y
@4:	ldx qk
	lda qsep
	sta iflag,x
	stz qsep
	stz ikey,x
	lda xi_n
	cmp #3
	bcc @5
	lda xi+4                ; the key: its first letter, upper case
	beq @5
	lda sbufa
	cmp #'a'
	bcc @k
	cmp #'z' + 1
	bcs @k
	and #$DF
@k:	sta ikey,x
@5:	lda qk
	clc
	adc #OT_IKEY
	sta t0
	lda ikey,x
	sta t1
	O1CALL o1_set
	lda qk
	clc
	adc #OT_IFLAG
	sta t0
	stz t1
	O1CALL o1_set
	lda qk
	clc
	adc #OT_ITEM
	sta t0
	stz t1
	lda xi_n
	cmp #2
	bcc @6
	lda xi+2
	inc a
	sta t1
	lda #1
	sta _vx_any
@6:	O1CALL o1_set
	ldx mcur
	inc mcount,x
	inc mni
	lda mni
	O1SET OT_NITEM, 0
	clc
	rts

; CHECK item$, on
g_check:
	jsr ifind_b             ; x = the item named sbufb (all menus)
	lda iflag,x
	and #<~2
	ldy xi+2
	bne @1
	ldy xi+3
	beq @2
@1:	ora #2
@2:	sta iflag,x
	jmp m_again

; MENU ENABLE menu$, item$, on
g_enable:
	; the menu named sbufb
	ldx #0
@m:	cpx mn
	bcs @no
	stx qk
	txa
	jsr mul24
	ldy #0
@c:	lda mtitle,x
	cmp sbufb,y
	bne @nx
	cmp #0
	beq @fm
	inx
	iny
	bra @c
@nx:	ldx qk
	inx
	bra @m
@no:	ERR E_ILLQ
@fm:	ldx qk                  ; its item named sbufa
	lda mfirst,x
	sta qi
	clc
	adc mcount,x
	sta qj
	ldx #0                  ; sbufa to sbufb
@cp:	lda sbufa,x
	sta sbufb,x
	beq @f
	inx
	bra @cp
@f:	lda qi
	jsr ifind_from
	lda xi+4
	ora xi+5
	beq @off
	lda iflag,x
	and #<~1
	bra @s
@off:	lda iflag,x
	ora #1
@s:	sta iflag,x
	pha
	txa
	clc
	adc #OT_IFLAG
	sta t0
	pla
	sta t1
	O1CALL o1_set
	jmp m_again
; x = the item named sbufb from item a to qj (ifind_b: all)
ifind_b:
	lda mni
	sta qj
	lda #0
ifind_from:
	sta qi
@l:	lda qi
	cmp qj
	bcs @no
	jsr itp
	ldy #0
@c:	lda (r15),y
	cmp sbufb,y
	bne @nx
	cmp #0
	beq @yes
	iny
	bra @c
@nx:	inc qi
	bra @l
@no:	ERR E_ILLQ
@yes:	ldx qi
	rts

; the menus' tables made again (CHECK, ENABLE), if they are shown
m_again:
	lda mshown
	beq @r
	jsr m_build
@r:	clc
	rts

; the debugger's Continue (vbdbg.s, DECISIONS V97): the program's menus
; again, if it showed them (their tables are where m_build left them; the
; bar's pixels, its title too, come back from the debugger's copy)
.ifdef VB_IDE
g_reshow:
	lda mshown
	beq @r
	jsr _theme_menus
	lda _vx_cellend
	sta r0
	lda _vx_cellend+1
	sta r0+1
	lda #0
	jmp DoMenu
@r:	rts
.endif

; MENU SHOW
g_show:
	lda mn
	bne @1
	ERR E_SYNTAX
@1:	jsr m_build
	jsr _theme_menus
	lda p0
	sta r0
	lda p0+1
	sta r0+1
	lda #0
	jsr DoMenu
	lda #1
	sta mshown
	sta _vx_used
	lda stitle
	beq @r
	jsr bar_title
@r:	clc
	rts

; the bar's and the menus' tables and texts in main RAM above the
; program's cells (free while it runs)
m_build:
	lda #FONT_UI
	jsr UseFont
	lda _vx_cellend
	sta p0
	lda _vx_cellend+1
	sta p0+1
	; the tables' size: 7 + 5 * mn, then 7 + 5 * count for each menu
	lda mn
	jsr mul5
	clc
	adc #7
	sta n1
	lda #0
	adc #0
	sta n1+1
	ldx #0
@sz:	cpx mn
	bcs @sd
	lda mcount,x
	jsr mul5
	clc
	adc #7
	adc n1
	sta n1
	bcc @s1
	inc n1+1
@s1:	inx
	bra @sz
@sd:	lda n1                  ; the texts from p0 + size
	clc
	adc p0
	sta n1
	lda n1+1
	adc p0+1
	sta n1+1
	; the bar: top 0, bottom 15, left 0, right (below), flags mn
	ldy #0
	lda #0
	sta (p0),y
	iny
	lda #15
	sta (p0),y
	iny
	lda #0
	sta (p0),y
	iny
	sta (p0),y
	iny
	iny
	iny
	lda mn
	sta (p0),y
	stz barend
	stz barend+1
	; the menus' tables after the bar's
	lda mn
	jsr mul5
	clc
	adc #7
	adc p0
	sta p2                ; the next menu table
	lda p0+1
	adc #0
	sta p2+1
	stz qk
@menu:	lda qk
	cmp mn
	jcs @bd
	; bar item qk: the title's text, SUB_MENU, the table
	lda qk
	jsr mul5
	clc
	adc #7
	tay
	lda n1
	sta (p0),y
	iny
	lda n1+1
	sta (p0),y
	iny
	lda #SUB_MENU
	sta (p0),y
	iny
	lda p2
	sta (p0),y
	iny
	lda p2+1
	sta (p0),y
	; the title (the first: the program's name, Look 2)
	lda qk
	bne @own
	lda classic
	bne @own
	lda appname
	beq @doc
	lda #<appname
	ldx #>appname
	jsr put_text
	bra @tw
@doc:	jsr put_docname
	bra @tw
@own:	lda qk
	jsr mul24
	txa
	clc
	adc #<mtitle
	pha
	lda #>mtitle
	adc #0
	tax
	pla
	jsr put_text
@tw:	jsr bar_add             ; barend past this item
	; the menu's table: top 16, bottom, left 0, right, flags
	ldx qk
	lda mcount,x
	sta qj
	ldy #0
	lda #16
	sta (p2),y
	iny
	lda qj
	asl a
	asl a
	asl a
	asl a
	clc
	adc #16
	sta (p2),y
	iny
	lda #0
	sta (p2),y
	iny
	sta (p2),y
	ldy #6
	lda qj
	ora #VERTICAL
	sta (p2),y
	; the items (V149, Sunroom: a key after a TAB, the kernel puts it
	; at the list's right)
	stz qx                  ; the widest text (the menu's right)
	stz qx+1
	ldx qk
	lda mfirst,x
	sta qi
	ldy #7
	sty qj
@il:	lda qi
	ldx qk
	sec
	sbc mfirst,x
	cmp mcount,x
	bcs @id
	ldy qj
	lda n1
	sta (p2),y
	iny
	lda n1+1
	sta (p2),y
	iny
	lda #MENU_ACTION
	sta (p2),y
	iny
	lda qk
	asl a
	asl a
	adc #<mstubs
	sta (p2),y
	iny
	lda #>mstubs
	adc #0
	sta (p2),y
	iny
	sty qj
	jsr item_text           ; at n1; its width in n0
	lda n0
	cmp qx
	lda n0+1
	sbc qx+1
	bcc @iw
	lda n0
	sta qx
	lda n0+1
	sta qx+1
@iw:	inc qi
	bra @il
@id:	lda qx                  ; right = the widest + 16
	clc
	adc #16
	ldy #4
	sta (p2),y
	lda qx+1
	adc #0
	iny
	sta (p2),y
	; the next menu's table
	lda mcount,x
	jsr mul5
	clc
	adc #7
	adc p2
	sta p2
	bcc @mn
	inc p2+1
@mn:	inc qk
	jmp @menu
@bd:	ldy #4                  ; the bar's right: its items' end
	lda barend
	sta (p0),y
	iny
	lda barend+1
	sta (p0),y
	; room: the texts' end below the C stack's area for names
	lda _dynbase
	clc
	adc _vb_dynsize
	tax
	lda _dynbase+1
	adc _vb_dynsize+1
	cmp n1+1
	bcc @full
	bne @ok
	cpx n1
	bcc @full
@ok:	jmp UseSystemFont
@full:	jsr UseSystemFont
	ERR E_MEM
mul5:	sta qw
	asl a
	asl a
	adc qw
	rts

; the 0-ended text at a/x to n1, n1 past it; n0 its width (UI font)
put_text:
	sta p1
	stx p1+1
	stz n0
	stz n0+1
	ldy #0
@l:	lda (p1),y
	sta (n1),y
	beq @e
	phy
	jsr wadd
	ply
	iny
	cpy #40
	bcc @l
	lda #0
	sta (n1),y
@e:	iny
	tya
	clc
	adc n1
	sta n1
	bcc @r
	inc n1+1
@r:	rts
; n0 += the width of character a
wadd:	jsr GetCharWidth
wadd2:	clc
	adc n0
	sta n0
	bcc @r
	inc n0+1
@r:	rts

; the document's name without its extension
put_docname:
	ldx #0
@l:	lda _docname,x
	sta sbufa,x
	beq @e
	inx
	cpx #23
	bcc @l
	stz sbufa,x
@e:	cpx #4                  ; ".bas" off
	bcc @t
	lda sbufa-4,x
	cmp #'.'
	bne @t
	stz sbufa-4,x
@t:	lda #<sbufa
	ldx #>sbufa
	jmp put_text

; barend past a bar item (its text just put, width n0; item qk): as the
; kernel lays the bar out (Look 2, tests/look_menu.py)
bar_add:
	lda qk
	bne @o
	; item 0: the mark (24), bold (a pixel a character)
	ldy #0
@c:	lda (p1),y
	beq @c1
	inc n0
	bne @c0
	inc n0+1
@c0:	iny
	bra @c
@c1:	lda #24
	bra @a
@o:	lda #6
@a:	clc
	adc n0
	sta n0
	bcc @1
	inc n0+1
@1:	lda barend
	clc
	adc n0
	sta barend
	lda barend+1
	adc n0+1
	sta barend+1
	lda barend              ; + 6, to a card
	clc
	adc #6 + 7
	and #$F8
	sta barend
	bcc @r
	inc barend+1
@r:	rts

; item qi's text at n1 (its marks, its key after a TAB: "Ctrl S"), n1
; past it; n0 its width as the kernel lays it out (a TAB 24 pixels)
item_text:
	jsr item_core
	ldx qi
	lda ikey,x
	beq @e
	pha
	lda #9
	sta (n1)
	jsr ninc
	lda #24
	jsr wadd2
	ldx #0
@kc:	lda MCtrl,x
	beq @kl
	phx
	jsr tchar
	plx
	inx
	bra @kc
@kl:	pla
	jsr tchar
@e:	lda #0
	sta (n1)
ninc:	inc n1
	bne @r
	inc n1+1
@r:	rts
; the marks and the name (no 0)
item_core:
	stz n0
	stz n0+1
	ldx qi
	lda iflag,x
	and #4                  ; (an ITEM "-" before it: a group starts here)
	beq @0
	lda #$1F
	sta (n1)
	jsr ninc
@0:	ldx qi
	lda iflag,x
	and #2
	beq @1
	lda #'*'
	jsr tchar
	lda #' '
	jsr tchar
@1:	ldx qi
	lda iflag,x
	and #1
	beq @2
	lda #'('
	jsr tchar
@2:	stz qq
@n:	lda qi
	jsr itp
	ldy qq
	lda (r15),y
	beq @3
	jsr tchar
	inc qq
	bra @n
@3:	ldx qi
	lda iflag,x
	and #1
	beq @r
	lda #')'
	jmp tchar
@r:	rts
; character a at n1, n1 + 1, its width added to n0
tchar:	pha
	sta (n1)
	inc n1
	bne @1
	inc n1+1
@1:	pla
	jmp wadd
MCtrl:	.byte "Ctrl ", 0
; r15 = item a's name (32 bytes an item)
itp:	stz r15H
	asl a
	asl a
	asl a
	asl a
	rol r15H
	asl a
	rol r15H
	clc
	adc #<itext
	sta r15L
	lda r15H
	adc #>itext
	sta r15H
	rts

; SCREEN FULL's title in the menu bar, centred from its items' end to the
; clock (vrbar.c's vr_bar_title)
bar_title:
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	stz clipOn
	lda #0
	jsr SetPattern
	lda barend
	sta r3
	lda barend+1
	sta r3+1
	LoadW r11, 1
	LoadW r4, 640 - 144
	LoadW r12, 14
	jsr WRectangle
	lda #FONT_UI
	jsr UseFont
	stz n0
	stz n0+1
	ldx #0
@w:	lda stitle,x
	beq @d
	phx
	jsr wadd
	inc n0
	plx
	inx
	bra @w
@d:	lda #SET_BOLD
	sta currentMode
	lda #<(640 - 144)       ; x = (end + 496 - width) / 2
	clc
	adc barend
	sta r11
	lda #>(640 - 144)
	adc barend+1
	sta r11+1
	lda r11
	sec
	sbc n0
	sta r11
	lda r11+1
	sbc n0+1
	lsr a
	sta r11+1
	ror r11
	lda baselineOffset      ; (V164: 3, the capitals centred as the
	clc                     ; kernel's menu titles)
	adc #3
	sta r1L
	LoadW r0, stitle        ; (main RAM? no: copied)
	ldx #0
@cp:	lda stitle,x
	sta sbufb,x
	beq @c2
	inx
	bra @cp
@c2:	LoadW r0, sbufb
	lda r11
	pha
	lda r11+1
	pha
	pla
	sta r11+1
	pla
	sta r11
	lda r1L
	sta r12
	stz r12+1
	jsr WPutString
	stz currentMode
	jmp UseSystemFont


; APP NAME (sbufb), APP CLASSIC
g_appname:
	ldx #0
@cp:	lda sbufb,x
	sta appname,x
	beq @r
	inx
	cpx #23
	bcc @cp
	stz appname,x
@r:	rts
g_classic:
	lda #1
	sta classic
	rts
; the title again (a menu's item was chosen: the kernel drew the bar again)
g_bart:	lda stitle
	beq @r
	lda mshown
	beq @r
	jmp bar_title
@r:	rts
; SCREEN FULL's title (sbufb), in the bar if it is shown
g_screen:
	ldx #0
@c:	lda sbufb,x
	sta stitle,x
	beq @3
	inx
	cpx #63
	bcc @c
	stz stitle,x
@3:	lda mshown
	beq @r
	jmp bar_title
@r:	rts

;---------------------------------------------------------------
; the window chrome (vrwin.c, compiled into this overlay) for overlay 6: t0 the window (0-3), the
; title or the left text in sbufb, the right one in sbufa; drawn with the
; clip off, to both screens
;---------------------------------------------------------------
o1_wptr:
	lda t0
	asl a
	asl a
	asl a
	sec
	sbc t0                  ; * 7
	clc
	adc #<_vx_wins
	pha
	lda #>_vx_wins
	adc #0
	tax
	pla
	rts
o1_pre:	jsr clip_end
	lda dispBufferOn
	sta o1disp
	lda #ST_WR_FORE | ST_WR_BACK
	sta dispBufferOn
	rts
o1_post:
	lda o1disp
	sta dispBufferOn
	rts
o1clip:	.byte 0
o1disp:	.byte 0

o1_win:	jsr o1_pre
	jsr o1_wptr
	jsr pushax
	lda #<sbufb
	ldx #>sbufb
	jsr _vr_win
	jmp o1_post
o1_wtitle:
	jsr o1_pre
	jsr o1_wptr
	jsr pushax
	lda #<sbufb
	ldx #>sbufb
	jsr _vr_win_title
	jmp o1_post
o1_wstatus:
	jsr o1_pre
	jsr o1_wptr
	jsr pushax
	lda #<sbufb
	ldx #>sbufb
	jsr pushax
	lda #<sbufa
	ldx #>sbufa
	jsr _vr_win_status
	jmp o1_post
; x = vr_win_hit(window t0, n0, n1)
o1_whit:
	jsr o1_wptr
	jsr pushax
	lda n0
	ldx n0+1
	jsr pushax
	lda n1
	ldx n1+1
	jsr _vr_win_hit
	tax
	rts
; x = vr_win_hit(window t0, the pointer) (ev_press)
o1_hitx:
	jsr o1_wptr
	jsr pushax
	lda mouseXPos
	ldx mouseXPos+1
	jsr pushax
	lda mouseYPosW
	ldx mouseYPosW+1
	jsr _vr_win_hit
	tax
	rts

; main.c's console window: vr_win's calls from overlay 1 (vbx.s vrw_*)
f7_win:	lda vrw_a
	ldx vrw_a+1
	jmp _vr_win
f7_title:
	lda vrw_a
	ldx vrw_a+1
	jmp _vr_win_title
f7_status:
	lda vrw_a
	ldx vrw_a+1
	jmp _vr_win_status
