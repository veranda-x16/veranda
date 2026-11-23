; gate polish, part keys (DECISIONS V142): AUTOSTART.cvt calls the SDK's
; vr_kbd (sdk/lib/vrkbd.s: the settings' PREFS_POLISH selects the ROM's
; "PL-PL" key map), logs "KEYMAP <the ROM's layout>", then starts APP.cvt
; (Veranda Edit or Veranda Write), into which the mouse script's
; emulator types right Alt + a c e l n o s x z, with Shift, and a left
; Alt shortcut (tools/gate_polish.sh).

.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"
.import _vr_kbd

ROM_KEYMAP = $FED2

.segment "CODE"

Start:	jsr _vr_kbd
	ldy #0
@m:	lda MKey,y
	beq @n
	sta EMU_STDOUT
	iny
	bra @m
@n:	sei                     ; the ROM's layout's name (it may be in RAM bank 0)
	lda ram_bank
	pha
	sec
	jsr ROM_KEYMAP
	stx r0L
	sty r0H
	stz ram_bank
	ldy #0
@k:	lda (r0),y
	beq @e
	sta EMU_STDOUT
	iny
	cpy #12
	bne @k
@e:	pla
	sta ram_bank
	cli
	lda #10
	sta EMU_STDOUT
	LoadB longNames, LONG_NAMES
	LoadW r6, NApp
	LoadB r0L, 0
	jsr GetFile
@stop:	bra @stop               ; (an error: the script's exit ends it)

MKey:	.byte "KEYMAP ", 0
NApp:	.byte "APP", 0
