; gate font (DECISIONS V62): fonts from RAM banks, run as TEST.PRG
;
; The run folder has /VERANDA/FONTS/Gate Sans.cvt (records 9, 12, 18, 27)
; and Gate Mono.cvt (10 and 12: 10 drawn here), from tools/fontcvt.py
; testfonts; the same records are assembled in here (gs*.bin, gm10.bin:
; --bin-include-dir).
;
; 1. FontList, FontSizes, the built-in fonts, errors: on the console
; 2. for each test record: a line of text in every style, the font in
;    this program's memory (LoadCharSet) at y, and the same font from
;    banks (LoadFont, UseFont) at y + 240: tests/check_font.py compares
;    the rows byte for byte
; 2b. italic's lean (V122): italic, then plain text, then bold italic at
;    a string's end, a second WPutString going on from there, italic at
;    its end, in Gate Sans 27 and 18, Gate Mono 10 and the system font
;    (y 124, 156, 180, 113)
; 3. timings: 1000 characters in the system font (WPutString), in Gate
;    Sans 12 and 27 from this program's memory and from banks; LoadFont
;    the first time (the file) and again (the cache)
; 4. uiFont = FONT_UI: a menu (the UI font) at y 200, drawn by DoMenu
; Console: FONT ... lines, TIME <name> <cycles, hex>, FONT DONE.

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"

Start:
	LoadB dispBufferOn, ST_WR_FORE
	; ---- 1. the list, from a folder of the run folder: it is the current
	; directory again after (FONT CWD OK: its file opens)
	LoadW r0, NSub
	jsr ChDir
	LoadW r0, names
	lda #16
	jsr FontList
	sta cnt
	LoadW r0, NHere
	lda #'r'
	jsr FOpen
	sta hnd
	lda dosStatus
	cmp #20
	bcs @cw
	LoadW r0, MCwd
	jsr LogText
@cw:	lda hnd
	jsr FClose
	LoadW r0, NRoot
	jsr ChDir
	LoadW r0, MList
	jsr LogText
	LoadW r0, names
@l:	lda cnt
	beq @ld
	jsr LogText
	AddVW 32, r0
	dec cnt
	bra @l
@ld:	LoadW r0, NSans
	LoadW r1, sizes
	jsr FontSizes
	sta cnt
	LoadW r0, MSizes
	jsr LogText
	ldx #0
@s:	cpx cnt
	beq @sd
	lda sizes,x
	jsr PDec
	inx
	bra @s
@sd:	lda #10
	sta EMU_STDOUT
	; built-in and missing fonts: "FONT GOT <handle> <x>"
	LoadW r0, NSystem
	lda #9
	jsr Got
	LoadW r0, NUI
	lda #12
	jsr Got
	LoadW r0, NNope
	lda #9
	jsr Got
	LoadW r0, NSans
	lda #10
	jsr Got

	; ---- 2. the lines: the font in RAM at y, from banks at y + 240
	stz ti
@line:	ldx ti
	lda TRec,x
	sta r0L
	lda TRecH,x
	sta r0H
	jsr LoadCharSet
	ldx ti
	lda TY,x
	sta yy
	stz yy+1
	jsr Draw0
	ldx ti                  ; the same from banks
	lda TName,x
	sta r0L
	lda TNameH,x
	sta r0H
	jsr ClockStart          ; (TIME load<n>: from the file)
	ldx ti
	lda TSize,x
	jsr LoadFont
	sta hnd
	phx
	ldx ti
	lda TLoadL,x
	tax
	ldy #>NLoad
	jsr ClockReport
	plx
	jsr GotLog
	lda hnd
	jsr UseFont
	AddVW 240, yy
	jsr Draw0
	; FontInfo: "FONT INFO <size> <height> <baseline> <name>"
	LoadW r0, iname
	lda hnd
	jsr FontInfo
	pha
	LoadW r0, MInfo
	jsr LogTextNoNL
	pla
	jsr PDec
	lda r1L
	jsr PDec
	lda r1H
	jsr PDec
	LoadW r0, iname
	jsr LogText
	inc ti
	lda ti
	cmp #NT
	beq :+
	jmp @line
:

	; ---- 2b. italic's lean drawn whole (V122), fonts from this
	; program's memory at y 124, 156, 180, the system font at 113 (x 8): an italic run, plain
	; text after it, bold italic at the string's end; then a second
	; WPutString going on from there (plain: it keeps the lean), underline,
	; italic at its end. tests/check_font.py: as tools/fontcvt.py
	; render_runs draws them
	stz ti
@it:	ldx ti
	lda IRec,x
	sta r0L
	lda IRecH,x
	sta r0H
	bne @ir
	jsr UseSystemFont       ; (0: the system font, its bold and italic
	bra @iy                 ; from its fast path's rows: V122)
@ir:	jsr LoadCharSet
@iy:	ldx ti
	lda IY,x
	clc
	adc baselineOffset
	sta r12
	lda #0
	adc #0
	sta r12+1
	LoadW r11, 8
	LoadW r0, Ital1
	jsr WPutString
	stz currentMode
	LoadW r0, Ital2
	jsr WPutString
	stz currentMode
	inc ti
	lda ti
	cmp #NI
	bne @it

	; ---- 2c. (V141) the system font has no $A0-$FF, and $80-$9F are
	; no characters: '?' for both, at x 400, y 113
	jsr UseSystemFont
	LoadW r11, 400
	LoadW r12, 113 + 6
	LoadW r0, NoHi
	jsr WPutString

	; ---- 3. timings, below y 120 and 360 (cleared after)
	jsr UseSystemFont
	LoadW r0, NText
	jsr Time1000
	LoadW r0, NSys20
	jsr Time20
	LoadW r0, GS12
	jsr LoadCharSet
	LoadW r0, NRam12
	jsr Time20
	LoadW r0, NSans
	lda #12
	jsr LoadFont
	jsr UseFont
	LoadW r0, NBank12
	jsr Time20
	LoadW r0, GS27
	jsr LoadCharSet
	LoadW r0, NRam27
	jsr Time20
	LoadW r0, NSans
	lda #27
	jsr LoadFont
	jsr UseFont
	LoadW r0, NBank27
	jsr Time20
	; LoadFont again: from the cache
	jsr ClockStart
	LoadW r0, NSans
	lda #18
	jsr LoadFont
	ldx #<NCache
	ldy #>NCache
	jsr ClockReport
	; the first time: Gate Mono 10 was loaded in part 2; time a fresh
	; one after the timings: none left, so the cache's speed is all
	; the timing area cleared
	jsr UseSystemFont
	lda #0
	jsr SetPattern
	LoadW r3, 0
	LoadW r4, 639
	LoadW r11, 360
	LoadW r12, 479
	jsr WRectangle

	; ---- 4. a menu in the UI font
	LoadB uiFont, FONT_UI
	LoadW r0, Menu
	lda #0
	jsr DoMenu
	lda #0
	sta uiFont

	LoadW r0, MDone
	jsr LogText
	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF

; one line, its top at yy, in every style
Draw0:	lda yy
	clc
	adc baselineOffset
	sta r12
	lda yy+1
	adc #0
	sta r12+1
	LoadW r11, 8
	LoadW r0, Styles
	jsr WPutString
	rts
; (Draw0 for the banked line: yy + 240 set by the caller)

; r0, a = size: LoadFont -> "FONT GOT <handle> <error>"
Got:	jsr LoadFont
	sta hnd
GotLog:	phx
	LoadW r0, MGot
	jsr LogTextNoNL
	lda hnd
	jsr PDec
	pla
	jsr PDec
	lda #10
	sta EMU_STDOUT
	rts

; 1000 characters (10 x 100) at y 380-479, foreground; r0 = the name
Time1000:
	MoveW r0, tname
	LoadW yy, 380
	.byte $CB               ; WAI
	jsr ClockStart
	LoadB kn, 10
@tl:	LoadW r0, Line100
	LoadW r11, 0
	MoveW yy, r12
	jsr WPutString
	AddVW 10, yy
	dec kn
	bne @tl
	ldx tname
	ldy tname+1
	jmp ClockReport

; 1000 characters as 50 lines of 20 at y 400 (every font fits), r0 the name
Time20:
	MoveW r0, tname
	.byte $CB               ; WAI
	jsr ClockStart
	LoadB kn, 50
@tl:	LoadW r0, Line20
	LoadW r11, 0
	LoadW r12, 420
	jsr WPutString
	dec kn
	bne @tl
	ldx tname
	ldy tname+1
	jmp ClockReport

; a as a decimal number and a space
PDec:	phx
	ldx #0
@h:	cmp #100
	bcc @t
	sbc #100
	inx
	bra @h
@t:	pha
	txa
	beq @t0
	ora #'0'
	sta EMU_STDOUT
@t0:	pla
	ldy #0
@u:	cmp #10
	bcc @o
	sbc #10
	iny
	bra @u
@o:	pha
	tya
	bne @t1
	cpx #0
	beq @t2
@t1:	ora #'0'
	sta EMU_STDOUT
@t2:	pla
	ora #'0'
	sta EMU_STDOUT
	lda #' '
	sta EMU_STDOUT
	plx
	rts

LogTextNoNL:
	ldy #0
@1:	lda (r0),y
	beq @2
	sta EMU_STDOUT
	iny
	bra @1
@2:	rts

ClockStart:
	sta EMU_CLOCK
	rts

; x/y = name: "TIME <name> <32-bit hex>"
ClockReport:
	lda EMU_CLOCK
	sta clk
	lda EMU_CLOCK+1
	sta clk+1
	lda EMU_CLOCK+2
	sta clk+2
	lda EMU_CLOCK+3
	sta clk+3
	stx r0L
	sty r0H
	ldy #0
@1:	lda TimePfx,y
	beq @2
	sta EMU_STDOUT
	iny
	bne @1
@2:	ldy #0
@3:	lda (r0),y
	beq @4
	sta EMU_STDOUT
	iny
	bne @3
@4:	lda #' '
	sta EMU_STDOUT
	ldx #3
@5:	lda clk,x
	jsr Hex
	dex
	bpl @5
	lda #10
	sta EMU_STDOUT
	rts

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

.segment "RODATA"

NT = 5
TRec:	.byte <GS9, <GS12, <GS18, <GS27, <GM10
TRecH:	.byte >GS9, >GS12, >GS18, >GS27, >GM10
TName:	.byte <NSans, <NSans, <NSans, <NSans, <NMono
TNameH:	.byte >NSans, >NSans, >NSans, >NSans, >NMono
TSize:	.byte 9, 12, 18, 27, 10
TY:	.byte 4, 20, 40, 66, 100
TLoadL:	.byte <NLoad9, <NLoad12, <NLoad18, <NLoad27, <NLoad10
.assert >NLoad9 = >NLoad10, error, "the load names in one page"
NI = 4                          ; (tests/check_font.py ITESTS)
IRec:	.byte <GS27, <GS18, <GM10, 0
IRecH:	.byte >GS27, >GS18, >GM10, 0
IY:	.byte 124, 156, 180, 113
NLoad:
NLoad9:	.byte "load9", 0
NLoad12: .byte "load12", 0
NLoad18: .byte "load18", 0
NLoad27: .byte "load27", 0
NLoad10: .byte "loadmono10", 0

Styles:	.byte "Veranda Za", $BF, $F3, $B3, $E5, " ", $AF, $D3, $A3, $C5, " {gjpqy} ", BOLDON  ; (V141: "Zażółć ŻÓŁĆ", ISO-8859-16), "Bold ", PLAINTEXT, ITALICON, "Italic "
	.byte PLAINTEXT, ULINEON, "Under", ULINEOFF, " ", REV_ON, "Rev", REV_OFF, " WiM", 0
Ital1:	.byte ITALICON, "Italic", PLAINTEXT, "plain", ITALICON, BOLDON, "Wf", 0
NoHi:	.byte "a", $BF, $90, "b", 0       ; (2c: "a??b")
Ital2:	.byte "Hm", ULINEON, "u", ULINEOFF, ITALICON, "lW", 0
Line20:	.byte "The quick brown fox ", 0
Line100: .byte "The quick brown fox jumps over the lazy dog. 0123456789 "
	.byte "Pack my box with five dozen liquor jugs!!", 0

; a horizontal menu, 20 rows (the UI font: 12; GEOS's places the text at
; top + 3 + baseline)
Menu:	.byte 200, 219
	.word 0, 239
	.byte HORIZONTAL | 3
	.word MI1
	.byte SUB_MENU
	.word 0
	.word MI2
	.byte MENU_ACTION
	.word 0
	.word MI3
	.byte MENU_ACTION
	.word 0
MI1:	.byte "File", 0
MI2:	.byte "Edit Text", 0
MI3:	.byte "Options", 0

NSub:	.byte "/SUB/DEEP", 0
NRoot:	.byte "/", 0
NHere:	.byte "HERE.TXT", 0
MCwd:	.byte "FONT CWD OK", 0
NSans:	.byte "Gate Sans", 0
NMono:	.byte "Gate Mono", 0
NSystem: .byte "System", 0
NUI:	.byte "Veranda UI", 0
NNope:	.byte "No Such Font", 0
MList:	.byte "FONT LIST", 0
MSizes:	.byte "FONT SIZES ", 0
MGot:	.byte "FONT GOT ", 0
MInfo:	.byte "FONT INFO ", 0
MDone:	.byte "FONT DONE", 0
TimePfx: .byte "TIME ", 0
NText:	.byte "text1000", 0
NSys20:	.byte "sys20", 0
NRam12:	.byte "ram12", 0
NBank12: .byte "bank12", 0
NRam27:	.byte "ram27", 0
NBank27: .byte "bank27", 0
NCache:	.byte "loadcached", 0

GS9:	.incbin "gs9.bin"
GS12:	.incbin "gs12.bin"
GS18:	.incbin "gs18.bin"
GS27:	.incbin "gs27.bin"
GM10:	.incbin "gm10.bin"

.segment "BSS"

names:	.res 16 * 32
sizes:	.res 64
iname:	.res 32
cnt:	.res 1
ti:	.res 1
hnd:	.res 1
yy:	.res 2
kn:	.res 1
tname:	.res 2
clk:	.res 4
