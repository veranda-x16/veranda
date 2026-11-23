; VeraBASIC Run: the C overlays' bank A (record 10; vbc.cfg, DECISIONS
; V90): the SDK's Open and Save dialog (vrchoose.c) and its entry. Overlay
; 8 (vbdlg.s) calls it through bcall with LOW in main RAM (vbcb.s first).
; Its arguments and result are in main RAM's inbuf (vb.s _vb_inbuf):
;   +0 the mode (VRF_OPEN, VRF_SAVE), +1 the result (1 chosen, 0 not)
;   +2 the name (64: in and out), +66 the title, +130 the type filter
;   ("TXT files:TXT", 0: none), +194 the box's number for _vx_dlg
;
; MIT licence (LICENSE).

.setcpu "65C02"
.import _vr_file, _vr_file_hook, _vr_file_filter, _vr_file_types
.import _vb_inbuf, _vx_dlg, pusha, pushax
.import __BSS_RUN__, __BSS_SIZE__
.importzp ptr1

.segment "ACODE"

	jmp afile               ; $A000

afile:	lda #<__BSS_RUN__       ; the C parts' variables cleared (main RAM's
	sta ptr1                ; scratch: the interpreter's before)
	lda #>__BSS_RUN__
	sta ptr1+1
	ldx #>__BSS_SIZE__
	ldy #0
	tya
@p:	cpx #0
	beq @t
@pg:	sta (ptr1),y
	iny
	bne @pg
	inc ptr1+1
	dex
	bra @p
@t:	cpy #<__BSS_SIZE__
	beq @c
	sta (ptr1),y
	iny
	bra @t
@c:	lda #<hook
	sta _vr_file_hook
	lda #>hook
	sta _vr_file_hook+1
	lda _vb_inbuf+130
	beq @nt
	lda #<(_vb_inbuf+130)
	sta _vr_file_types
	lda #>(_vb_inbuf+130)
	sta _vr_file_types+1
@nt:	lda _vb_inbuf
	jsr pusha
	lda #<(_vb_inbuf+66)
	ldx #>(_vb_inbuf+66)
	jsr pushax
	lda #<(_vb_inbuf+2)
	ldx #>(_vb_inbuf+2)
	jsr _vr_file
	sta _vb_inbuf+1
	rts

; every pass of the box's main loop: the box is up (the gate's scripts)
hook:	lda _vb_inbuf+194
	sta _vx_dlg
	rts
