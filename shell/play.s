; Veranda shell: the test hook's player (shell/main.c, SHELL.TST)
;
; A part of the script is a list of 8-byte records: frame (word), x, y
; (words), flags, key. Flags bit 0 the button (bit 1 the right one); bit 7 a key (the key byte
; into the ROM's keyboard buffer); bit 6 the end of the part (key byte 0:
; stop; 1: log SHELL DONE and end with a VRAM dump; 2: stop, the shell
; exports the screen (play_shot, DECISIONS V101), then 1); bit 5: it plays
; even while the shell is busy (a press on a progress box's cancel, or
; the end during a copy).
;
; Played through mouseSource: a record's position is absolute (c set) on
; its frame; on the other frames the same position as a device's (c clear:
; no move), so where the kernel puts the pointer (on a sub menu's item)
; stays. The frame counter stands still while play_busy is not 0 (the
; shell reads the disk or draws), so the script waits for the shell.
.include "veranda.inc"
.include "macros.inc"
.include "x16hw.inc"

.export _play_start, _play_busy, _play_shot, _play_done

.segment "ZEROPAGE"
ptr:	.res 2

.segment "CODE"

; a/x = the part's first record
_play_start:
	sta rec
	stx rec+1
	LoadW frame, $FFFF
	stz _play_end
	LoadB moved, $80
	LoadW mouseSource, Player
	rts

; the emulator's VRAM dump and the end
; (from the interrupt: dialog boxes have their own appMain)
_play_done:
Done:	ldx #0
@1:	lda DoneMsg,x
	beq @2
	sta EMU_STDOUT
	inx
	bra @1
@2:	lda #1
	sta EMU_SAVE_ON_EXIT
	jmp $FFFF
DoneMsg: .byte 10, "SHELL DONE", 10, 0

Player:	lda _play_end
	bne @out
	lda _play_busy
	beq @go
	MoveW rec, ptr          ; busy: only a record that plays while the
	ldy #6                  ; shell is busy (flags bit 5) goes on
	lda (ptr),y
	and #$20
	bne @go
@out:	jmp Out
@go:	IncW frame
	MoveW rec, ptr
@next:	ldy #1
	lda (ptr),y
	cmp frame+1
	bcc @take
	bne @save
	dey
	lda (ptr),y
	cmp frame
	beq @take
	bcs @save
@take:	ldy #6
	lda (ptr),y
	bit #$40
	bne @end
	bit #$80
	bne @key
	and #3                  ; (bit 1: the right button, V83)
	sta pb
	ldy #2
@xy:	lda (ptr),y
	sta px-2,y
	iny
	cpy #6
	bne @xy
	LoadB moved, $80
	bra @adv
@key:	ldy #7
	lda (ptr),y
	jsr k_kbdbuf_put
@adv:	AddVW 8, ptr
	bra @next
@end:	ldy #7
	lda (ptr),y
	beq @stop
	cmp #2
	bne @done
	sta _play_shot          ; (the shell's idle exports the screen)
	bra @stop
@done:	jmp Done
@stop:	dec _play_end           ; stop
@save:	MoveW ptr, rec
Out:	MoveW px, r0
	MoveW py, r1
	asl moved               ; c: moved on this frame
	lda pb
	rts

.segment "DATA"
frame:	.word $FFFF
rec:	.word 0
px:	.word 320
py:	.word 240
pb:	.byte 0
moved:	.byte $80
_play_busy: .byte 0
_play_end: .byte 0              ; not 0: stopped
_play_shot: .byte 0             ; not 0: export the screen, then Done
