; Veranda C: the ROM's keyboard layout by name (vrcs.h, DECISIONS V142)
;
;   void __fastcall__ vr_keymap(const char *name);
;
; The ROM's keymap call ($FED2) with a layout's name below $A000 ("PL-PL",
; "EN-US" ...); vr_kbd (vrkbd.s) uses it. Its own object, so a program
; short of main RAM (the shell) can call it alone.
;
; MIT licence (see LICENSE).

.export _vr_keymap

ROM_KEYMAP = $FED2

.segment "CODE"

_vr_keymap:
	phx
	tax
	ply
	clc
	jmp ROM_KEYMAP
