; gate shell: a tiny application started from the shell; it logs its line,
; draws a pattern, and 30 frames later returns to the shell (EnterDeskTop)
; in its own colours: paper yellow, ink red, the colour map shown (the
; shell starts in Veranda's: DECISIONS V33).
; Started with a document (r0L bit 7, ST_LD_DATA: the shell opened a plain
; file with it) it logs "APP n DOC <dataFileName> IN <curDirName>" too.
; -D APPN=1 or 2.
; -D GO (DECISIONS V63): then it changes to /Mods, as its working folder,
; with ChDir and curDirName (as Veranda Calc's chooser does), before it
; quits; -D GO -D CRASH: then it crashes there (a BRK; Return in the ROM's
; keyboard queue for the panic box's OK).
; -D ZAP (DECISIONS V73): it zeroes the zero page $A9-$FF first.
; -D LFN (DECISIONS V82): as a GEOS program (longNames left 0), it also
; logs "APP n LONG <dataLongName>" and "APP n READ <the file's first
; line>", the document opened by FOpen(dataFileName): its short form
; opens the long-named file.
; -D DA (DECISIONS V82): a desk accessory that logs "DA RAN" and returns.
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.segment "CODE"
.ifdef DA
	LoadW r0, MsgDa         ; -D DA (V82): a desk accessory that logs
	jsr LogText             ; "DA RAN" and ends at once
	jmp RstrAppl
.endif
	lda r0L
	sta opts
	LoadW r0, Msg
	jsr LogText
	bit opts
	bmi @doc
	jmp @nodoc
@doc:	ldx #0                 ; "APP n DOC " name " IN " folder
@m:	lda Doc,x
	sta line,x
	beq @m1
	inx
	bra @m
@m1:	ldy #0
@n:	lda dataFileName,y
	beq @n1
	sta line,x
	inx
	iny
	cpy #17
	bne @n
@n1:	ldy #0
@i:	lda In,y
	beq @i1
	sta line,x
	inx
	iny
	bra @i
@i1:	ldy #0
@f:	lda curDirName,y
	sta line,x
	beq @f1
	inx
	iny
	cpy #40
	bne @f
	stz line,x
@f1:	LoadW r0, line
	jsr LogText
.ifdef LFN
	LoadW r0, Long          ; "APP n LONG " dataLongName
	ldx #0
	jsr Cat
	LoadW r0, dataLongName
	jsr Cat
	stz line,x
	LoadW r0, line
	jsr LogText
	LoadW r0, curDirName    ; (the document's folder, V48)
	jsr ChDir
	LoadW r0, dataFileName  ; "APP n READ " its first line
	lda #'r'
	jsr FOpen
	sta fh
	ldx #0
@ld:	lda Read,x
	sta line,x
	beq @ld1
	inx
	bra @ld
@ld1:	lda fh
	cmp #2
	bcc @ld2
	stx r0L                 ; (FRead into line + x: 40 bytes)
	clc
	lda #<line
	adc r0L
	sta r0L
	lda #>line
	adc #0
	sta r0H
	phx
	LoadW r1, 40
	lda fh
	jsr FRead
	lda fh
	jsr FClose
	pla
	clc
	adc r1L
	tax
@ld2:	stz line,x
	ldx #1                  ; (after the log line's own 10)
@ld3:	lda line,x              ; (the line ends at its new line)
	beq @ld4
	cmp #10
	beq @ld5
	inx
	bra @ld3
@ld5:	stz line,x
@ld4:	LoadW r0, line
	jsr LogText
.endif
@nodoc:
.ifdef GO
	LoadW r0, Mods
	jsr ChDir
	ldx #Mods1 - Mods
@g:	lda Mods,x
	sta curDirName,x
	dex
	bpl @g
.ifdef CRASH
	lda #13
	jsr k_kbdbuf_put
	brk
	.byte 0
.endif
.endif
.ifdef ZAP
	ldx #$FF - $A9          ; (gate basic, V73) all of the application's
@zp:	stz $A9,x               ; zero page $A9-$FF zeroed, as a program
	dex                     ; may: BASIC's CHRGET ($E7) and TXTTAB with it
	bpl @zp
.endif
	lda #APPN + 1
	jsr SetPattern
	LoadW r3, 0
	LoadW r11, 0
	LoadW r4, 639
	LoadW r12, 479
	jsr WRectangle
	LoadW r0, 30
	jsr Sleep               ; (to the main loop; back here 30 frames later)
	LoadW r0, $0FF0         ; paper yellow, ink red
	LoadW r1, $0800
	jsr SetColors
	LoadB r3L, 0            ; the colour map: every card colour 6
	LoadB r3H, 80
	LoadB r11L, 0
	LoadB r11H, 60
	lda #6
	jsr ColorRect
	jmp EnterDeskTop

.ifdef LFN
; r0's text appended to line at x
Cat:	ldy #0
@1:	lda (r0),y
	beq @2
	sta line,x
	inx
	iny
	bne @1
@2:	rts
.endif

.segment "RODATA"
.ifdef DA
MsgDa:	.byte 10, "DA RAN", 0
.endif
.ifdef LFN
Long:	.byte 10, "APP ", '0' + APPN, " LONG ", 0
Read:	.byte 10, "APP ", '0' + APPN, " READ ", 0
.endif
Msg:	.byte 10, "APP ", '0' + APPN, " RAN", 0
Doc:	.byte 10, "APP ", '0' + APPN, " DOC ", 0
In:	.byte " IN ", 0
.ifdef GO
Mods:	.byte "/Mods"
Mods1:	.byte 0
.endif

.segment "BSS"
opts:	.res 1
fh:	.res 1
line:	.res 120
