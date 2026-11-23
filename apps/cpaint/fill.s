; Colour Paint: the fill's spans (draw.c's d_fill; DECISIONS V167)
;
; f_spans: while seeds are left: a seed (x, y) still of the old entry
; f_old: its span left and right of the old entry filled with cola (the
; change's box dl..db grows), the rows above and below scanned from the
; span's left to its right: a seed at the start of each run of f_old.
; The seeds: 3 bytes each (x low, x high, y) at $A000 of RAM bank f_sbank,
; at most f_max; when a seed does not fit, f_over is set (draw.c then
; passes over what changed).
;
; MIT licence (see LICENSE).

.importzp ptr1, ptr2, tmp1, tmp2
.import _pbank, _rowbank, _rowlo, _rowhi, _cola, _dl, _dt, _dr, _db
.export _f_old, _f_sbank, _f_max, _f_ns, _f_over, _f_spans, _f_push, _f_px, _f_py

.segment "BSS"

_f_old:	.res 1
_f_sbank: .res 1
_f_max:	.res 2
_f_ns:	.res 2
_f_over: .res 1
_f_px:	.res 2                  ; f_push's seed
_f_py:	.res 1
pb:	.res 1                  ; the bank mapped on entry
sy:	.res 1                  ; the span's row
sl:	.res 2                  ; its left, right
sr:	.res 2
rem:	.res 2                  ; the scan's bytes left
in:	.res 1

.segment "CODE"

; ptr1 = row a's first byte, its bank mapped
RowA:	tax
	lda _rowbank,x
	clc
	adc _pbank
	sta $00
	lda _rowlo,x
	sta ptr1
	lda _rowhi,x
	sta ptr1+1
	rts

; ptr2 = ptr1 + (a, x) (x high)
At:	clc
	adc ptr1
	sta ptr2
	txa
	adc ptr1+1
	sta ptr2+1
	rts

; push (f_px, f_py): the bank mapped kept
_f_push:
	lda $00
	pha
	lda _f_ns               ; full?
	cmp _f_max
	bne @ok
	lda _f_ns+1
	cmp _f_max+1
	bne @ok
	lda #1
	sta _f_over
	bra @r
@ok:	lda _f_ns               ; ptr2 = $A000 + 3 ns
	sta ptr2
	lda _f_ns+1
	sta ptr2+1
	asl ptr2
	rol ptr2+1
	lda ptr2
	clc
	adc _f_ns
	sta ptr2
	lda ptr2+1
	adc _f_ns+1
	clc
	adc #$A0
	sta ptr2+1
	lda _f_sbank
	sta $00
	ldy #0
	lda _f_px
	sta (ptr2),y
	iny
	lda _f_px+1
	sta (ptr2),y
	iny
	lda _f_py
	sta (ptr2),y
	inc _f_ns
	bne @r
	inc _f_ns+1
@r:	pla
	sta $00
	rts

; pop into f_px, f_py (ns > 0)
Pop:	lda _f_ns
	bne @1
	dec _f_ns+1
@1:	dec _f_ns
	lda _f_ns
	sta ptr2
	lda _f_ns+1
	sta ptr2+1
	asl ptr2
	rol ptr2+1
	lda ptr2
	clc
	adc _f_ns
	sta ptr2
	lda ptr2+1
	adc _f_ns+1
	clc
	adc #$A0
	sta ptr2+1
	lda _f_sbank
	sta $00
	ldy #0
	lda (ptr2),y
	sta _f_px
	iny
	lda (ptr2),y
	sta _f_px+1
	iny
	lda (ptr2),y
	sta _f_py
	rts

;---------------------------------------------------------------
_f_spans:
	lda $00
	sta pb
@next:	lda _f_ns
	ora _f_ns+1
	bne @pop
	lda pb
	sta $00
	rts
@pop:	jsr Pop
	lda _f_py
	sta sy
	jsr RowA                ; the row; the seed still old?
	lda _f_px
	ldx _f_px+1
	jsr At
	lda (ptr2)
	cmp _f_old
	bne @next
	; left: while x > 0 and row[x - 1] is old
	lda _f_px
	sta sl
	lda _f_px+1
	sta sl+1
@l:	lda sl
	ora sl+1
	beq @ld
	lda ptr2                ; ptr2 - 1
	bne @l1
	dec ptr2+1
@l1:	dec ptr2
	lda (ptr2)
	cmp _f_old
	bne @ld
	lda sl
	bne @l2
	dec sl+1
@l2:	dec sl
	bra @l
@ld:	; right: while x < 319 and row[x + 1] is old
	lda _f_px
	sta sr
	ldx _f_px+1
	stx sr+1
	jsr At
@r:	lda sr+1                ; sr = 319?
	beq @r0
	lda sr
	cmp #<319
	beq @rd
@r0:	inc ptr2
	bne @r1
	inc ptr2+1
@r1:	lda (ptr2)
	cmp _f_old
	bne @rd
	inc sr
	bne @r
	inc sr+1
	bra @r
@rd:	; the span filled with cola
	lda sl
	ldx sl+1
	jsr At
	lda sr                  ; n = sr - sl + 1
	sec
	sbc sl
	tay
	lda sr+1
	sbc sl+1
	tax                     ; x: the high byte (0 or 1), y: the low
	iny
	bne @f0
	inx
@f0:	lda _cola
	sty tmp1
	stx tmp2
	ldy #0
	ldx tmp2
	beq @fl
@fp:	sta (ptr2),y            ; a whole page
	iny
	bne @fp
	inc ptr2+1
@fl:	ldx tmp1
	beq @fb
@fb1:	sta (ptr2),y
	iny
	dex
	bne @fb1
@fb:	; the box: dl = min(dl, sl), dr = max(dr, sr), dt, db with sy
	jsr Box
	; the rows above and below
	lda sy
	beq @below
	dea
	jsr Scan
@below:	lda sy
	cmp #239
	beq @nx
	ina
	jsr Scan
@nx:	jmp @next

; row a from sl to sr: a seed at each run of f_old's start (V172: the
; row's bytes through (ptr2),y, 256 at most a turn: 2.5 times as fast)
Scan:	sta _f_py
	jsr RowA
	lda sl
	ldx sl+1
	jsr At                  ; ptr2: the span's first byte
	lda sr                  ; rem = sr - sl + 1
	sec
	sbc sl
	sta rem
	lda sr+1
	sbc sl+1
	sta rem+1
	inc rem
	bne @0
	inc rem+1
@0:	stz in
@chunk:	lda rem+1               ; c = min(rem, 256): x (0 = 256)
	beq @lt
	dec rem+1               ; (rem - 256)
	ldx #0
	bra @go
@lt:	ldx rem
	stz rem
@go:	ldy #0
@s:	lda (ptr2),y
	cmp _f_old
	bne @no
	lda in
	bne @c
	inc in
	phx                     ; a seed: x = ptr2 + y - the row's start
	phy
	tya
	clc
	adc ptr2
	sta _f_px
	lda ptr2+1
	adc #0
	sta _f_px+1
	lda _f_px
	sec
	sbc ptr1
	sta _f_px
	lda _f_px+1
	sbc ptr1+1
	sta _f_px+1
	lda ptr2                ; (push maps the seeds' bank, then back)
	pha
	lda ptr2+1
	pha
	jsr _f_push
	pla
	sta ptr2+1
	pla
	sta ptr2
	ply
	plx
	bra @c
@no:	stz in
@c:	iny
	dex
	bne @s
	inc ptr2+1              ; the next 256
	lda rem
	ora rem+1
	bne @chunk
	rts

; the change's box grows by (sl, sy) .. (sr, sy) (signed 16-bit ints)
Box:	lda sl                  ; sl < dl?
	cmp _dl
	lda sl+1
	sbc _dl+1
	bvc @1
	eor #$80
@1:	bpl @2
	lda sl
	sta _dl
	lda sl+1
	sta _dl+1
@2:	lda _dr                 ; dr < sr?
	cmp sr
	lda _dr+1
	sbc sr+1
	bvc @3
	eor #$80
@3:	bpl @4
	lda sr
	sta _dr
	lda sr+1
	sta _dr+1
@4:	lda sy                  ; sy < dt?
	cmp _dt
	lda #0
	sbc _dt+1
	bvc @5
	eor #$80
@5:	bpl @6
	lda sy
	sta _dt
	stz _dt+1
@6:	lda _db                 ; db < sy?
	cmp sy
	lda _db+1
	sbc #0
	bvc @7
	eor #$80
@7:	bpl @8
	lda sy
	sta _db
	stz _db+1
@8:	rts
