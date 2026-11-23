; Veranda C: the keyboard's layout (vrcs.h, DECISIONS V142)
;
;   void vr_kbd(void);
;   void __fastcall__ vr_keymap(const char *name);
;
; vr_kbd: with the settings' Polish keyboard (PREFS_POLISH) the ROM's key
; map becomes "PL-PL", Polish (programmers): the US layout, and right Alt
; + a c e l n o s x z (Shift: capitals) types the ISO-8859-16 letters; the
; kernel passes right Alt to the ROM's map then (KeyHook). Without the
; setting nothing changes (the layout the X16 started with stays). The
; shell calls it when it starts, Preferences after Save.
; vr_keymap: the ROM's keymap call with a layout's name (below $A000).
;
; MIT licence (see LICENSE).

.include "veranda.inc"
.export _vr_kbd
.import _vr_keymap

ROM_KEYMAP = $FED2

.segment "RODATA"
plpl:	.byte "PL-PL", 0

.segment "CODE"

_vr_kbd:
	tsx                     ; the settings into PREFS_SIZE bytes of the stack
	txa                     ; (no BSS: the shell's main RAM is full)
	sec
	sbc #PREFS_SIZE
	tax
	txs
	inx
	stx r0L
	lda #1
	sta r0H
	lda #PREFS_GET
	jsr SysPrefs
	ldy #6
	lda (r0),y
	and #PREFS_POLISH
	tay
	tsx
	txa
	clc
	adc #PREFS_SIZE
	tax
	txs
	tya
	beq Done
	lda #<plpl
	ldx #>plpl
	jmp _vr_keymap
Done:	rts
