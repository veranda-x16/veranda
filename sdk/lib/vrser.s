; vrser: the serial driver's interrupt half, in the SDK (DECISIONS V98;
; Veranda Term's ser.s, V41, V91, V94, moved here unchanged so that Term
; and vrnet share one driver). MIT licence, Veranda's own.
;
; SerIrq is Veranda's intFirstVector (DECISIONS V41): the first thing in
; every interrupt, before the kernel saves anything. It
;   - acknowledges VERA's line interrupt: seven a frame, lines 60, 120
;     ... 420, besides the frame's own at 480: the UART is read every 2.1
;     ms or so, 2 bytes at 9600 baud, 8 at 38400 (V94); with ser_fast set
;     (vrnet) fifteen, lines 30, 60 ... 450: every 1.05 ms, 6 bytes at
;     57600, 12 at 115200, inside the 16-byte FIFO; since V144 the grid
;     goes on through the vertical blank (480 and 510 too; slow: 480),
;     no more 75 lines without a poll from 480 to 30, and the next armed
;     is the first of it after the beam's line, so a late interrupt never
;     stops the polls for the rest of a frame;
;   - 16C550 back-end: empties the receive FIFO into the receive ring (8 KB,
;     $A000 of RAM bank ser_rxbank) and refills the transmit FIFO from the
;     transmit ring (256 bytes). By default that is all: the UART's own
;     interrupt stays off (IER 0) and it is polled, as Packet16 does on
;     TexElec's card (V94). With ser_ier set (Term's settings/I), the
;     chip's interrupt (receive data, timeout, transmit empty) brings it
;     here too;
;   - drops RTS when the ring is 3/4 full and raises it at 1/4 (a modem
;     with hardware flow control then waits; RTS is the X16's output, so
;     this needs no CTS: on a card whose modem ignores it, as far as is
;     known the TexElec card's, it changes nothing: V91);
;   - script back-end (gates without a serial port): on each frame,
;     ser_rate bytes from the script in RAM banks into the receive ring;
;     bytes sent go to a log bank;
;   - counts frames (ser_frames) for the main loop's timers.
; It returns c set: what it serves needs nothing more, so the kernel ends
; an interrupt that VERA did not raise (V41).
;
; The C side (vrserc.c, vrser.h) programs the chip; this file has no entry
; points but SerIrq and (V210) ser_get, the ring read, moved here from
; vrserc.c: its C loop took some 120 cycles a byte, this one some 40
; (vrnet reads every byte of a download through it).

.export _SerIrq
.export _ser_on, _ser_lo, _ser_rxbank, _ser_rxhead, _ser_rxtail
.export _ser_txbuf, _ser_txhead, _ser_txtail, _ser_lost, _ser_oe
.export _ser_frames, _ser_mcr, _ser_ier, _ser_flow
.export _ser_sbank, _ser_saddr, _ser_send, _ser_rate, _ser_logbank, _ser_logpos
.export _ser_polls, _ser_fast
.export _ser_get
.import popax
.importzp ptr1, ptr2, ptr3, ptr4, tmp1

ram_bank  = $00
VERA_IEN  = $9F26
VERA_ISR  = $9F27
VERA_LINE = $9F28

UART      = $9F00           ; + ser_lo + register (y = ser_lo)
U_RBR       = UART + 0
U_THR       = UART + 0
U_IER       = UART + 1
U_LSR       = UART + 5
U_MCR       = UART + 4

.segment "DATA"

_ser_on:     .byte 0         ; 0 off, 1 the 16C550, 2 the script
_ser_lo:     .byte $E0       ; the UART's address low byte ($9Fxx)
_ser_rxbank: .byte 0
_ser_rxhead: .word 0         ; 0-8191: the interrupt writes here
_ser_rxtail: .word 0         ; the main loop reads here
_ser_txhead: .byte 0         ; the main loop writes here
_ser_txtail: .byte 0         ; the interrupt reads here
_ser_lost:   .word 0         ; bytes lost: the ring was full
_ser_oe:     .word 0         ; overrun errors the chip reported
_ser_frames: .word 0
_ser_polls:  .word 0         ; times the UART was read
_ser_mcr:    .byte $0B       ; DTR, RTS, OUT2
_ser_ier:    .byte 0         ; the receive interrupts (U_IER bits 0, 2) or 0
_ser_flow:   .byte 0         ; $80: RTS is down (the ring is full)
_ser_fast:   .byte 0         ; 0: 8 polls a frame (Term, V94); 1: 16 (vrnet)
; the script back-end
_ser_sbank:  .byte 0         ; the bank and address of the next byte
_ser_saddr:  .word $A000
_ser_send:   .word 0         ; bytes left (to 65535)
_ser_rate:   .byte 16        ; bytes a frame
_ser_logbank: .byte 0        ; bytes sent: $A000 of this bank (8 KB, then dropped)
_ser_logpos: .word 0

.segment "BSS"

_ser_txbuf:  .res 256

.segment "CODE"

_SerIrq:
	lda ram_bank
	pha
	lda VERA_ISR
	and #$02                ; VERA's line interrupt: ours
	beq @noline
	sta VERA_ISR
	; (V144) the first line of the grid (30, 60 ... 510; slow: 60, 120
	; ... 480) after the beam's, not the next of a table: one armed late
	; (the interrupt held off, or SerIrq run by another interrupt) could
	; be behind the beam, and VERA compares a line once a frame: no poll
	; for the rest of it, 5-10 ms, the FIFO overran at 57600 (gate
	; update, NET_EIO). Past the grid's last: its first (the next frame's)
	ldx #0
	bit VERA_IEN            ; (read: bit 6 the beam's line's bit 8)
	bvc @b
	inx
@b:	stx tmp                 ; (the beam's line: tmp, tmp2)
	lda VERA_LINE           ; (read: its low byte)
	sta tmp2
	lda #30
	ldx _ser_fast
	bne @s
	asl a                   ; (60)
@s:	sta cnt                 ; (the step)
	ldy #0                  ; (the line: y, a)
@lp:	cpy tmp
	bne @ne
	cmp tmp2
@ne:	bcc @up
	bne @c                  ; (ahead of the beam)
@up:	clc
	adc cnt
	bcc @lp
	iny
	bra @lp
@c:	cpy #1                  ; 511 or more: the first
	bcc @l1
	bne @z
	cmp #<511
	bcc @l1
@z:	lda cnt
	ldy #0
@l1:	sta VERA_LINE
	lda VERA_IEN
	and #$7F
	cpy #0                  ; bit 8 of the line: IEN bit 7
	beq @l2
	ora #$80
@l2:	sta VERA_IEN
@noline:
	lda VERA_ISR
	and #$01
	beq @nof
	inc _ser_frames
	bne @nof
	inc _ser_frames+1
@nof:
	lda _ser_rxbank
	sta ram_bank
	lda _ser_on
	cmp #1
	bne @notu
	jsr Uart
	bra @flow
@notu:	cmp #2
	bne @done
	lda VERA_ISR
	and #$01
	beq @done
	jsr Script
@flow:	jsr Flow
@done:	pla
	sta ram_bank
	sec
	rts

; the 16C550: the receive FIFO into the ring, the ring into the transmit
; FIFO
Uart:	inc _ser_polls
	bne @0
	inc _ser_polls+1
@0:	ldy _ser_lo
	sty @thr+1              ; (V91) the stores to the UART are absolute:
	sty @ier+1              ; an indexed store's dummy read (sta abs,y
	inc @ier+1              ; reads its address first) could take a byte
				; out of RBR (THR's address) on real hardware.
				; The reads stay indexed: lda abs,y reads once
				; when no page is crossed ($9F00 + $60-$FF + 7)
@rx:	lda U_LSR,y
	bit #$02
	beq @rx1
	inc _ser_oe
	bne @rx1
	inc _ser_oe+1
@rx1:	lsr a
	bcc @tx
	lda U_RBR,y
	jsr Put
	bra @rx
@tx:	lda U_LSR,y
	and #$20                ; the transmit FIFO is empty: up to 16 bytes
	beq @r
	ldx _ser_txtail
	lda #16
	sta cnt
@t1:	cpx _ser_txhead
	beq @tdone
	lda _ser_txbuf,x
@thr:	sta U_THR + $E0         ; (its low byte: ser_lo)
	inx
	dec cnt
	bne @t1
@tdone:	stx _ser_txtail
	; the transmit interrupt only while there is more to send, and only
	; when the UART's interrupt is used at all (V94: I off, the default,
	; IER stays 0: the polls alone)
	lda _ser_ier
	beq @t2
	cpx _ser_txhead
	beq @t2
	ora #$02
@t2:
@ier:	sta U_IER + $E0         ; (ser_lo + 1)
@r:	rts

; a = a received byte into the ring (unless it is full); keeps x and y
Put:	pha
	lda _ser_rxhead         ; the next head, modulo 8 KB
	clc
	adc #1
	sta tmp
	lda _ser_rxhead+1
	adc #0
	and #$1F
	sta tmp2
	lda tmp                 ; full if it reaches the tail
	cmp _ser_rxtail
	bne @ok
	lda tmp2
	cmp _ser_rxtail+1
	bne @ok
	pla
	inc _ser_lost
	bne @f
	inc _ser_lost+1
@f:	rts
@ok:	lda _ser_rxhead
	sta @st+1
	lda _ser_rxhead+1
	ora #$A0
	sta @st+2
	pla
@st:	sta $A000
	lda tmp
	sta _ser_rxhead
	lda tmp2
	sta _ser_rxhead+1
	rts

; RTS down at 6 KB in the ring, up again below 2 KB
Flow:	lda _ser_rxhead+1
	sec
	sbc _ser_rxtail+1
	and #$1F
	bit _ser_flow
	bmi @up
	cmp #$18
	bcc @r
	lda #$80
	sta _ser_flow
	lda _ser_mcr
	and #$FD
	bra @set
@up:	cmp #$08
	bcs @r
	stz _ser_flow
	lda _ser_mcr
@set:	ldx _ser_on
	cpx #1
	bne @r
	ldy _ser_lo
	iny
	iny
	iny
	iny
	sty @mcr+1
@mcr:	sta U_MCR + $E0         ; (its low byte: ser_lo + 4, V91)
@r:	rts

; (V210) unsigned int __fastcall__ ser_get(unsigned char *buf, unsigned int max):
; up to max received bytes into buf (below $A000), the count; the RAM
; bank kept
_ser_get:
	sta ptr4
	stx ptr4+1
	jsr popax
	sta ptr1
	stx ptr1+1
	lda ram_bank
	pha
	sei                     ; (the head as it is now: ptr3)
	lda _ser_rxhead
	sta ptr3
	lda _ser_rxhead+1
	cli
	ora #$A0
	sta ptr3+1
	lda _ser_rxtail         ; ptr2: the tail, in the ring's bank
	sta ptr2
	lda _ser_rxtail+1
	ora #$A0
	sta ptr2+1
	lda _ser_rxbank
	sta ram_bank
	ldy #0                  ; (the count: gc, y its low byte)
	stz tmp1
@l:	cpy ptr4                ; max taken?
	bne @1
	lda tmp1
	cmp ptr4+1
	beq @f
@1:	lda ptr2                ; the head reached?
	cmp ptr3
	bne @2
	lda ptr2+1
	cmp ptr3+1
	beq @f
@2:	lda (ptr2)
	sta (ptr1)
	inc ptr1
	bne @3
	inc ptr1+1
@3:	iny
	bne @4
	inc tmp1
@4:	inc ptr2
	bne @l
	inc ptr2+1
	lda ptr2+1
	cmp #$C0
	bne @l
	lda #$A0
	sta ptr2+1
	bra @l
@f:	pla
	sta ram_bank
	lda ptr2+1
	and #$1F
	tax
	lda ptr2
	sei
	sta _ser_rxtail
	stx _ser_rxtail+1
	cli
	tya
	ldx tmp1
	rts

; the script: ser_rate bytes a frame; what was sent into the log
Script:	lda _ser_rate
	sta cnt
@s:	lda _ser_send
	ora _ser_send+1
	beq @log
	lda _ser_sbank
	sta ram_bank
	lda _ser_saddr
	sta @ld+1
	lda _ser_saddr+1
	sta @ld+2
@ld:	lda $A000
	pha
	lda _ser_rxbank
	sta ram_bank
	pla
	jsr Put
	lda _ser_send
	bne @d
	dec _ser_send+1
@d:	dec _ser_send
	inc _ser_saddr
	bne @c
	inc _ser_saddr+1
	lda _ser_saddr+1
	cmp #$C0
	bne @c
	lda #$A0
	sta _ser_saddr+1
	inc _ser_sbank
@c:	dec cnt
	bne @s
@log:	ldx _ser_txtail
	cpx _ser_txhead
	beq @r
	lda _ser_logbank
	beq @skip
	sta ram_bank
	lda _ser_logpos+1
	cmp #$20
	bcs @skip
	ora #$A0
	sta @sl+2
	lda _ser_logpos
	sta @sl+1
	lda _ser_txbuf,x
@sl:	sta $A000
	inc _ser_logpos
	bne @skip
	inc _ser_logpos+1
@skip:	inx
	stx _ser_txtail
	bra @log
@r:	lda _ser_rxbank
	sta ram_bank
	rts

.segment "BSS"
cnt:	.res 1
tmp:	.res 1
tmp2:	.res 1
