; sysui: a CMDR-DOS command the kernel's API has no call for (DECISIONS
; V119: Disk Tools' "R-H:name", the card's name), through the kernel's own
; command channel: logical file 15 to unit 8, secondary address 15, which
; the kernel opens once and keeps open (kernel/f/stream.s, CmdOpen; a
; second channel to the command channel confused CMDR-DOS on the SD card).
; The caller makes sure it is open first with any kernel call that sends a
; command (ChDir does). The command goes out as the kernel sends its own
; (CHKOUT 15, the bytes, CLRCHN); the reply is read as the kernel reads
; the status (CHKIN 15, CHRIN to the CR).
;
;   dos_send(s)          the 0-terminated command; 0, or 1 if the channel
;                        is not open
;   dos_reply(buf, max)  the reply's bytes up to its CR (not stored) or max,
;                        0-terminated (buf holds max + 1); the count
;
; MIT licence (see LICENSE).

CHKIN   = $FFC6
CHKOUT  = $FFC9
CHRIN   = $FFCF
CHROUT  = $FFD2
CLRCHN  = $FFCC
READST  = $FFB7

.export _dos_send, _dos_reply
.import popax
.importzp ptr1

.segment "BSS"
max:	.res 1
cnt:	.res 1
ptr:	.res 2

.segment "CODE"

_dos_send:
	sta ptr
	stx ptr+1
	ldx #15
	jsr CHKOUT
	bcs @e
	stz cnt
@l:	lda ptr
	sta ptr1
	lda ptr+1
	sta ptr1+1
	ldy cnt
	lda (ptr1),y
	beq @d
	jsr CHROUT
	inc cnt
	bne @l
@d:	jsr CLRCHN
	lda #0
	tax
	rts
@e:	jsr CLRCHN
	lda #1
	ldx #0
	rts

_dos_reply:
	sta max
	jsr popax
	sta ptr
	stx ptr+1
	stz cnt
	ldx #15
	jsr CHKIN
	bcs @end
@l:	lda cnt
	cmp max
	beq @end
	jsr CHRIN
	cmp #13
	beq @end
	pha
	lda ptr
	sta ptr1
	lda ptr+1
	sta ptr1+1
	pla
	ldy cnt
	sta (ptr1),y
	inc cnt
	jsr READST
	beq @l
@end:	jsr CLRCHN
	lda ptr
	sta ptr1
	lda ptr+1
	sta ptr1+1
	ldy cnt
	lda #0
	sta (ptr1),y
	lda cnt
	ldx #0
	rts
