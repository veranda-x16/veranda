; sysui: the SD card read directly through VERA's SPI port, read only
; (DECISIONS V119): Disk Tools' card information and its Check, About this
; X16's card size. CMDR-DOS has no block read (its B-R and U1 answer
; "unsupported"), so a sector is read as the DOS's own driver reads one
; (x16-rom fat32/sdcard.s): CMD17 READ_SINGLE_BLOCK with the sector's
; number (the DOS takes only block-addressed SDHC/SDXC cards), the data
; token $FE, 512 bytes, the CRC; or CMD9 SEND_CSD (16 bytes: the card's
; capacity). Nothing here ever writes to the card (no CMD24 or CMD25 is
; in this file). The DOS selects and deselects the card around each of its
; own commands and leaves the port deselected at full speed: between two
; kernel calls the port is free, and this leaves it the same way.
;
;   sd_lba (4 bytes, low first), sd_buf: the sector and where it goes
;   sd_read()   0 ok, 1 no answer (no card: the emulator's host folder)
;   sd_csd()    the CSD register's 16 bytes to sd_buf; 0 ok, 1 none
;
; MIT licence (see LICENSE).

SPI_DATA = $9F3E
SPI_CTRL = $9F3F

.export _sd_lba, _sd_buf, _sd_read, _sd_csd
.importzp ptr1

.segment "BSS"
_sd_lba: .res 4
_sd_buf: .res 2
cmd:	.res 1
len:	.res 1                  ; 0: 512 bytes, else that many

.segment "CODE"

rd:	lda #$FF
	sta SPI_DATA
@w:	bit SPI_CTRL
	bmi @w
	lda SPI_DATA
	rts

wr:	sta SPI_DATA
@w:	bit SPI_CTRL
	bmi @w
	rts

deselect:
	lda SPI_CTRL
	and #$FE
	sta SPI_CTRL
	jmp rd

_sd_csd:
	lda #$40 | 9
	ldx #16
	bra go
_sd_read:
	lda #$40 | 17
	ldx #0
go:	sta cmd
	stx len
	jsr deselect
	lda SPI_CTRL
	ora #$01                ; select the card
	sta SPI_CTRL
	jsr rd
	ldx #0                  ; ready: $FF (at most 65536 reads, about 0.25 s)
	ldy #0
@rdy:	jsr rd
	cmp #$FF
	beq @ok
	dex
	bne @rdy
	dey
	bne @rdy
	jmp err
@ok:	lda cmd
	jsr wr
	lda cmd
	cmp #$40 | 9
	beq @z                  ; (CSD: argument 0)
	lda _sd_lba+3
	jsr wr
	lda _sd_lba+2
	jsr wr
	lda _sd_lba+1
	jsr wr
	lda _sd_lba
	jsr wr
	bra @crc
@z:	lda #0
	jsr wr
	jsr wr
	jsr wr
	jsr wr
@crc:	lda #1
	jsr wr
	ldy #11                 ; the R1 answer: bit 7 clear, at most 10 bytes on
@r1:	dey
	beq err
	jsr rd
	bit #$80
	bne @r1
	cmp #0
	bne err
	ldx #0                  ; the data token
	ldy #0
@tok:	jsr rd
	cmp #$FE
	beq @data
	dex
	bne @tok
	dey
	bne @tok
	jmp err
@data:	lda _sd_buf
	sta ptr1
	lda _sd_buf+1
	sta ptr1+1
	ldy #0
	lda len
	bne @short
	ldx #2                  ; (two pages, the byte read in line: 27 cycles)
@d1:	lda #$FF
	sta SPI_DATA
@d2:	bit SPI_CTRL
	bmi @d2
	lda SPI_DATA
	sta (ptr1),y
	iny
	bne @d1
	inc ptr1+1
	dex
	bne @d1
	bra @end
@short:	jsr rd
	sta (ptr1),y
	iny
	cpy len
	bne @short
@end:	jsr rd                  ; the CRC
	jsr rd
	jsr deselect
	lda #0
	tax
	rts
err:	jsr deselect
	lda #1
	ldx #0
	rts
