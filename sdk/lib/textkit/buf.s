; Veranda Edit: the text, a gap buffer across RAM banks (the hot paths)
;
; The text is one array of "physical" bytes, 8 KB a RAM bank, through a
; table of bank numbers (gb_bk: physical byte p is at $A000 + (p & $1FFF)
; of bank gb_bk[p >> 13]); the banks need not be consecutive. The array
; holds the text before the cursor at [0, gs), the gap at [gs, ge), the
; text after it at [ge, cap); cap <= gb_nb * 8192. A logical position q
; (0 .. len) is physical q below gs, else q + (ge - gs).
;
; Growing never moves the text after the gap: a new bank goes into the
; table at the bank boundary at or after ge, and the bytes of [ge, that
; boundary) move up into it (less than 8 KB), so the gap grows by 8 KB.
;
; The routines take their arguments in the exported variables (gb_a, gb_b,
; gb_n, gb_lp) and map banks at $A000 themselves; every one puts the
; caller's bank back. Positions are 4-byte C longs (the top byte 0).
;
; MIT licence (see LICENSE).

.export _gb_bk, _gb_nb, _gb_gs, _gb_ge, _gb_cap, _gb_len
.export _gb_a, _gb_b, _gb_n, _gb_r, _gb_lp, _gb_mode, _gb_crst
.export _gb_hs, _gb_line, _gb_mk, _gb_mkc, _gb_eof, _gb_lcols, _gb_tab
.export _gb_pat, _gb_plen, _gb_ftab, _ul_bk
.export _gb_get, _gb_moveto, _gb_ins, _gb_del, _gb_grow, _gb_read
.export _gb_append, _gb_flush, _gb_export, _gb_render, _gb_fwd_lines
.export _gb_line_start, _gb_count, _gb_find, _gb_col, _gb_at_col
.export _ul_read, _ul_write, _tk_blink_due

COLS    = 80                    ; the line buffer (the window shows 79)

.macro Cmp24 l, r               ; c set: l >= r
	lda l
	cmp r
	lda l+1
	sbc r+1
	lda l+2
	sbc r+2
.endmacro
.macro Copy24 s, d
	lda s
	sta d
	lda s+1
	sta d+1
	lda s+2
	sta d+2
.endmacro
.macro Add24 l, r, d            ; d = l + r
	clc
	lda l
	adc r
	sta d
	lda l+1
	adc r+1
	sta d+1
	lda l+2
	adc r+2
	sta d+2
.endmacro
.macro Sub24 l, r, d            ; d = l - r
	sec
	lda l
	sbc r
	sta d
	lda l+1
	sbc r+1
	sta d+1
	lda l+2
	sbc r+2
	sta d+2
.endmacro
.macro Inc16 v
	inc v
	bne :+
	inc v+1
:
.endmacro
.macro Inc24 v
	inc v
	bne :+
	inc v+1
	bne :+
	inc v+2
:
.endmacro

.segment "ZEROPAGE"

bp:	.res 2                  ; into the mapped bank
lp:	.res 2                  ; into low memory
tbl:	.res 2                  ; the bank table in use (gb_bk or ul_bk)
dp:	.res 2                  ; a second pointer into a bank

.segment "BSS"

blink_t: .res 1                ; (tk_blink_due) the jiffies at the last toggle

_gb_bk:	.res 64
_ul_bk:	.res 8                  ; the undo log's banks (undo.c)
_gb_nb:	.res 1
_gb_gs:	.res 4
_gb_ge:	.res 4
_gb_cap: .res 4
_gb_len: .res 4
_gb_a:	.res 4
_gb_b:	.res 4
_gb_n:	.res 4
_gb_r:	.res 4
_gb_lp:	.res 2
_gb_mode: .res 1                ; line ends: 0 LF, 1 CR LF, 2 CR
_gb_crst: .res 1                ; loading CR LF: a CR waits for its LF
_gb_hs:	.res 2                  ; render: the first column shown
_gb_line: .res COLS
_gb_mk:	.res 12                 ; render: three positions ...
_gb_mkc: .res 6                 ; ... and their columns ($FFFF: not here)
_gb_eof: .res 1                 ; render: the line has no LF (the last)
_gb_tab: .res 1                 ; render: not 0: the line has a tab (V215)
_gb_lcols: .res 2               ; render: the line's width in columns
_gb_pat: .res 64                ; find: the pattern (folded)
_gb_plen: .res 1
_gb_ftab: .res 256              ; find: the folding table (C fills it)

ph:	.res 3                  ; a physical address
room:	.res 2                  ; bytes from ph to the end of its bank
run:	.res 2                  ; the reader: bytes left at bp
rl:	.res 3                  ; the reader: the logical position
t3:	.res 3
atp:	.res 3                  ; gb_at_col: the position before the character read (not t3:
				; RdSeek's, which a new run's first read clobbers; V216)
gap:	.res 3
cnt:	.res 3
col:	.res 2
sbank:	.res 1
chunk:	.res 1                  ; 1-256 (0 = 256)
tmp:	.res 3
nb2:	.res 1
sph:	.res 3
dph:	.res 3
droom:	.res 2
dbank:	.res 1
csz:	.res 3
pcol:	.res 2
wr:	.res 2
keep:	.res 8                  ; find: the reader's state
bbuf:	.res 256                ; a bounce buffer between two banks

.segment "CODE"

; the cursor's blink clock (view_blink; DECISIONS V160): 1 when BLINK of
; the ROM's jiffies (RDTIM, $FFDE: 1/60 s; the ROM's interrupt handler
; counts them under Veranda too) have passed since the last 1, else 0.
; On the clock, not on main loop passes: an 8 MHz X16's loop is fast
; enough that 32 passes blinked several times a second. Main RAM, so any
; bank's code may call it.
BLINK   = 30                    ; half a second shown, half hidden
_tk_blink_due:
	jsr $FFDE               ; a: the jiffies' low byte
	tay
	sec
	sbc blink_t
	cmp #BLINK
	lda #0
	tax
	bcc @r
	sty blink_t
	lda #1
@r:	rts

Enter:	lda $00
	sta sbank
	lda #<_gb_bk
	sta tbl
	lda #>_gb_bk
	sta tbl+1
	rts

Leave:	lda sbank
	sta $00
	rts

; ph -> the bank mapped, bp = $A000 + (ph & $1FFF), room = $2000 - that
Map:	lda ph+1
	and #$1F
	sta tmp
	ora #$A0
	sta bp+1
	lda ph
	sta bp
	sec
	lda #0
	sbc ph
	sta room
	lda #$20
	sbc tmp
	sta room+1
	lda ph+2
	asl
	asl
	asl
	sta tmp
	lda ph+1
	lsr
	lsr
	lsr
	lsr
	lsr
	ora tmp
	tay
	lda (tbl),y
	sta $00
	rts

; gap = ge - gs
GapLen:	Sub24 _gb_ge, _gb_gs, gap
	rts

; chunk = min(n (cnt, 24 bits), 256, room): a = chunk (0 = 256)
Chunk:	lda cnt+2
	ora cnt+1
	bne @big
	lda cnt                 ; cnt < 256
	ldx room+1
	bne @a
	cmp room
	bcc @a
	lda room
@a:	sta chunk
	rts
@big:	lda room+1              ; cnt >= 256
	bne @256
	lda room
	sta chunk
	rts
@256:	stz chunk
	rts

; cnt -= chunk, ph += chunk, lp += chunk
Step:	lda chunk
	beq @256
	sta tmp
	stz tmp+1
	bra @s
@256:	stz tmp
	lda #1
	sta tmp+1
@s:	sec
	lda cnt
	sbc tmp
	sta cnt
	lda cnt+1
	sbc tmp+1
	sta cnt+1
	lda cnt+2
	sbc #0
	sta cnt+2
	clc
	lda ph
	adc tmp
	sta ph
	lda ph+1
	adc tmp+1
	sta ph+1
	lda ph+2
	adc #0
	sta ph+2
	clc
	lda lp
	adc tmp
	sta lp
	lda lp+1
	adc tmp+1
	sta lp+1
	rts

; cnt = 0 ?
CntZ:	lda cnt
	ora cnt+1
	ora cnt+2
	rts

; physical [ph, ph + cnt) <-> low memory at lp (tbl's banks)
PRead:	jsr CntZ
	beq @r
	jsr Map
	jsr Chunk
	ldy #0
@c:	lda (bp),y
	sta (lp),y
	iny
	cpy chunk
	bne @c
	jsr Step
	bra PRead
@r:	rts

PWrite:	jsr CntZ
	beq @r
	jsr Map
	jsr Chunk
	ldy #0
@c:	lda (lp),y
	sta (bp),y
	iny
	cpy chunk
	bne @c
	jsr Step
	bra PWrite
@r:	rts

;---------------------------------------------------------------
; the reader: logical bytes in order
;---------------------------------------------------------------
; rl -> bp, run (the bytes there up to the gap, the bank's end or the
; text's end); run = 0 at the end
RdSeek:	Cmp24 rl, _gb_len
	bcc @in
	stz run
	stz run+1
	rts
@in:	Cmp24 rl, _gb_gs
	bcs @post
	Copy24 rl, ph
	Sub24 _gb_gs, rl, t3
	bra @map
@post:	jsr GapLen
	Add24 rl, gap, ph
	Sub24 _gb_cap, ph, t3
@map:	jsr Map
	lda t3+2
	bne @room
	lda t3+1
	cmp room+1
	bcc @t
	bne @room
	lda t3
	cmp room
	bcc @t
@room:	lda room
	sta run
	lda room+1
	sta run+1
	rts
@t:	lda t3
	sta run
	lda t3+1
	sta run+1
	rts

; a = the byte at rl, rl + 1; c set at the end
RdNext:	lda run
	ora run+1
	bne @have
	jsr RdSeek
	lda run
	ora run+1
	bne @have
	sec
	rts
@have:	lda (bp)
	inc bp
	bne @1
	inc bp+1
@1:	ldx run
	bne @2
	dec run+1
@2:	dec run
	Inc24 rl
	clc
	rts

; the reader on by y bytes (1-255; y < run)
Skip:	tya
	clc
	adc bp
	sta bp
	bcc @1
	inc bp+1
@1:	sty tmp
	sec
	lda run
	sbc tmp
	sta run
	bcs @2
	dec run+1
@2:	clc
	lda rl
	adc tmp
	sta rl
	bcc @r
	inc rl+1
	bne @r
	inc rl+2
@r:	rts

; chunk for a scan: y limit = min(run, 255) (run > 0)
ScanLim: lda run+1
	bne @255
	lda run
	rts
@255:	lda #255
	rts

; the reader backwards: rl -> bp at the byte before rl, run = the bytes
; there and below it (to the bank's start, the gap's end, 0)
RbSeek:	lda rl
	ora rl+1
	ora rl+2
	bne @in
	stz run
	stz run+1
	rts
@in:	sec                     ; t3 = rl - 1
	lda rl
	sbc #1
	sta t3
	lda rl+1
	sbc #0
	sta t3+1
	lda rl+2
	sbc #0
	sta t3+2
	Cmp24 t3, _gb_gs
	bcs @post
	Copy24 t3, ph           ; avail = t3 + 1
	Inc24 t3
	bra @map
@post:	jsr GapLen
	Add24 t3, gap, ph       ; avail = ph - ge + 1
	Sub24 ph, _gb_ge, t3
	Inc24 t3
@map:	jsr Map
	; the bytes below bp in its bank: ($2000 - room) + 1
	sec
	lda #0
	sbc room
	sta tmp
	lda #$20
	sbc room+1
	sta tmp+1
	inc tmp
	bne @1
	inc tmp+1
@1:	lda t3+2
	bne @tmp
	lda t3+1
	cmp tmp+1
	bcc @t
	bne @tmp
	lda t3
	cmp tmp
	bcc @t
@tmp:	lda tmp
	sta run
	lda tmp+1
	sta run+1
	rts
@t:	lda t3
	sta run
	lda t3+1
	sta run+1
	rts

; a = the byte before rl, rl - 1; c set at the start
RdPrev:	lda run
	ora run+1
	bne @have
	jsr RbSeek
	lda run
	ora run+1
	bne @have
	sec
	rts
@have:	lda (bp)
	pha
	lda bp
	bne @1
	dec bp+1
@1:	dec bp
	lda run
	bne @2
	dec run+1
@2:	dec run
	lda rl
	bne @3
	lda rl+1
	bne @4
	dec rl+2
@4:	dec rl+1
@3:	dec rl
	pla
	clc
	rts

;---------------------------------------------------------------
; the calls
;---------------------------------------------------------------
; a = the byte at gb_a (0 past the end)
_gb_get:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	jsr RdNext
	bcc @1
	lda #0
@1:	pha
	jsr Leave
	pla
	ldx #0
	rts

; the gap to gb_a (0 .. len)
_gb_moveto:
	jsr Enter
	Cmp24 _gb_a, _gb_gs
	bcs @fwd
	jmp @back
@fwd:	Sub24 _gb_a, _gb_gs, cnt        ; forward: [ge, ge + n) to [gs, ...)
	Copy24 _gb_ge, sph
	Copy24 _gb_gs, dph
@fl:	jsr CntZ
	bne @f1
	jmp @fd
@f1:
	Copy24 dph, ph
	jsr Map
	jsr KeepDst
	Copy24 sph, ph
	jsr Map
	jsr MinRoom
	jsr Chunk
	jsr Csz
	lda $00
	cmp dbank
	bne @fb
	ldy #0                          ; the same bank: in place
@fs:	lda (bp),y
	sta (dp),y
	iny
	cpy chunk
	bne @fs
	bra @fn
@fb:	jsr Bounce
@fn:	Add24 sph, csz, sph
	Add24 dph, csz, dph
	Sub24 cnt, csz, cnt
	jmp @fl
@fd:	Copy24 dph, _gb_gs
	Copy24 sph, _gb_ge
	jmp Leave

@back:	Sub24 _gb_gs, _gb_a, cnt        ; backward: [a, gs) to [ge - n, ge)
	Copy24 _gb_gs, sph              ; the source's end
	Copy24 _gb_ge, dph              ; the destination's end
@bl:	jsr CntZ
	bne @b1
	jmp @bd
@b1:
	; the room below each end: ((end - 1) & $1FFF) + 1
	lda dph
	sec
	sbc #1
	sta droom
	lda dph+1
	sbc #0
	and #$1F
	sta droom+1
	Inc16 droom
	lda sph
	sec
	sbc #1
	sta room
	lda sph+1
	sbc #0
	and #$1F
	sta room+1
	Inc16 room
	jsr MinRoom
	jsr Chunk
	jsr Csz
	Sub24 dph, csz, dph
	Sub24 sph, csz, sph
	Copy24 dph, ph
	jsr Map
	jsr KeepDst
	Copy24 sph, ph
	jsr Map
	lda $00
	cmp dbank
	bne @bb
	ldy chunk                       ; the same bank: from the top down
	dey
@bs:	lda (bp),y
	sta (dp),y
	dey
	cpy #$FF
	bne @bs
	bra @bn
@bb:	jsr Bounce
@bn:	Sub24 cnt, csz, cnt
	jmp @bl
@bd:	Copy24 sph, _gb_gs
	Copy24 dph, _gb_ge
	jmp Leave

; the destination just mapped: dp, its room, its bank
KeepDst: lda bp
	sta dp
	lda bp+1
	sta dp+1
	lda room
	sta droom
	lda room+1
	sta droom+1
	lda $00
	sta dbank
	rts

; room = min(room, droom)
MinRoom: lda droom+1
	cmp room+1
	bcc @t
	bne @r
	lda droom
	cmp room
	bcs @r
@t:	lda droom
	sta room
	lda droom+1
	sta room+1
@r:	rts

; csz = chunk (0: 256), 24 bits
Csz:	stz csz+2
	lda chunk
	sta csz
	stz csz+1
	bne @r
	inc csz+1
@r:	rts

; chunk bytes from (bp) (mapped) to (dp) in bank dbank, through bbuf
Bounce:	ldy #0
@1:	lda (bp),y
	sta bbuf,y
	iny
	cpy chunk
	bne @1
	lda dbank
	sta $00
	ldy #0
@2:	lda bbuf,y
	sta (dp),y
	iny
	cpy chunk
	bne @2
	rts

; insert gb_n bytes (16 bits) from gb_lp at the gap (the caller made room)
_gb_ins:
	jsr Enter
	lda _gb_n
	sta cnt
	lda _gb_n+1
	sta cnt+1
	stz cnt+2
	Copy24 _gb_gs, ph
	lda _gb_lp
	sta lp
	lda _gb_lp+1
	sta lp+1
	jsr PWrite
	Copy24 ph, _gb_gs
	clc
	lda _gb_len
	adc _gb_n
	sta _gb_len
	lda _gb_len+1
	adc _gb_n+1
	sta _gb_len+1
	lda _gb_len+2
	adc #0
	sta _gb_len+2
	jmp Leave

; delete gb_n bytes (24 bits) after the gap
_gb_del:
	Add24 _gb_ge, _gb_n, _gb_ge
	Sub24 _gb_len, _gb_n, _gb_len
	rts

; the gap 8 KB longer: bank a into the table at the bank boundary at or
; after ge, the bytes of [ge, that boundary) (and below cap) moved up
; into it
_gb_grow:
	sta nb2
	jsr Enter
	; B = the boundary: ge rounded up
	Copy24 _gb_ge, t3
	lda t3+1
	and #$1F
	ora t3
	beq @aligned
	lda t3+1
	ora #$1F
	sta t3+1
	lda #$FF
	sta t3
	Inc24 t3
@aligned:
	; cnt = min(B, cap) - ge
	Cmp24 t3, _gb_cap
	bcc @1
	Sub24 _gb_cap, _gb_ge, cnt
	bra @2
@1:	Sub24 t3, _gb_ge, cnt
@2:	Copy24 _gb_ge, ph
@mv:	jsr CntZ
	beq @ins
	jsr Map
	jsr Chunk
	ldy #0
@c1:	lda (bp),y
	sta bbuf,y
	iny
	cpy chunk
	bne @c1
	lda nb2                         ; the same offset in the new bank
	sta $00
	ldy #0
@c2:	lda bbuf,y
	sta (bp),y
	iny
	cpy chunk
	bne @c2
	jsr Step
	bra @mv
@ins:	; index j = B >> 13; entries j.. up one
	lda t3+2
	asl
	asl
	asl
	sta tmp
	lda t3+1
	lsr
	lsr
	lsr
	lsr
	lsr
	ora tmp
	sta tmp
	ldx _gb_nb
@sh:	cpx tmp
	beq @put
	lda _gb_bk-1,x
	sta _gb_bk,x
	dex
	bra @sh
@put:	lda nb2
	sta _gb_bk,x
	inc _gb_nb
	clc
	lda _gb_ge+1
	adc #$20
	sta _gb_ge+1
	bcc @3
	inc _gb_ge+2
@3:	clc
	lda _gb_cap+1
	adc #$20
	sta _gb_cap+1
	bcc @4
	inc _gb_cap+2
@4:	jmp Leave

; gb_n bytes (16 bits) from gb_a to gb_lp; a/x = the bytes copied (to
; the end at most); gb_a moves past them
_gb_read:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	lda _gb_lp
	sta lp
	lda _gb_lp+1
	sta lp+1
	lda _gb_n
	sta cnt
	lda _gb_n+1
	sta cnt+1
	stz wr
	stz wr+1
@l:	lda cnt
	ora cnt+1
	beq @d
	jsr RdNext
	bcs @d
	sta (lp)
	inc lp
	bne @1
	inc lp+1
@1:	lda cnt
	bne @2
	dec cnt+1
@2:	dec cnt
	inc wr
	bne @l
	inc wr+1
	bra @l
@d:	Copy24 rl, _gb_a
	jsr Leave
	lda wr
	ldx wr+1
	rts

; loading: gb_n bytes (16 bits) from gb_lp appended at cap (the text
; after the gap), the line ends turned into LF (gb_mode); gb_r counts the
; LFs (the caller zeroes it); the caller made room
_gb_append:
	jsr Enter
	lda _gb_lp
	sta lp
	lda _gb_lp+1
	sta lp+1
	Copy24 _gb_cap, ph
	jsr Map
	lda _gb_n
	sta cnt
	lda _gb_n+1
	sta cnt+1
@l:	lda cnt
	ora cnt+1
	beq @d
	lda (lp)
	inc lp
	bne @1
	inc lp+1
@1:	ldx cnt
	bne @2
	dec cnt+1
@2:	dec cnt
	ldx _gb_mode
	beq @out                ; LF: as it is
	cpx #2
	beq @cr
	; CR LF: a CR waits for the next byte
	ldx _gb_crst
	beq @c0
	stz _gb_crst
	cmp #10
	beq @out                ; CR LF -> LF
	pha
	lda #13                 ; a lone CR stays
	jsr Out
	pla
@c0:	cmp #13
	bne @out
	inc _gb_crst
	bra @l
@cr:	cmp #13                 ; CR: CR and LF change places
	bne @cr1
	lda #10
	bra @out
@cr1:	cmp #10
	bne @out
	lda #13
@out:	jsr Out
	bra @l
@d:	jmp Leave

; a byte at ph (bp mapped) for the load; ph, cap, len + 1
Out:	sta (bp)
	cmp #10
	bne @1
	Inc24 _gb_r
@1:	Inc24 _gb_len
	Inc24 _gb_cap
	inc bp
	bne @2
	inc bp+1
@2:	Inc24 ph
	lda ph
	bne @r
	lda ph+1
	and #$1F
	bne @r
	jsr Map                 ; the next bank
@r:	rts

; the load's end: a CR still waiting is a lone CR
_gb_flush:
	lda _gb_crst
	beq @r
	stz _gb_crst
	jsr Enter
	Copy24 _gb_cap, ph
	jsr Map
	lda #13
	jsr Out
	jmp Leave
@r:	rts

; saving: from gb_a, up to gb_n (16 bits, >= 2) bytes into gb_lp, LF
; written as the file's line end (gb_mode); a/x = the bytes; gb_a moves
_gb_export:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	lda _gb_lp
	sta lp
	lda _gb_lp+1
	sta lp+1
	sec                     ; room for one more CR LF: n - 1
	lda _gb_n
	sbc #1
	sta cnt
	lda _gb_n+1
	sbc #0
	sta cnt+1
	stz wr
	stz wr+1
@l:	lda wr+1               ; written < n - 1 ?
	cmp cnt+1
	bcc @go
	bne @d
	lda wr
	cmp cnt
	bcs @d
@go:	jsr RdNext
	bcs @d
	ldx _gb_mode
	beq @put
	cpx #2
	beq @cr
	cmp #10                 ; CR LF
	bne @put
	lda #13
	jsr Put
	lda #10
	bra @put
@cr:	cmp #10
	bne @cr1
	lda #13
	bra @put
@cr1:	cmp #13
	bne @put
	lda #10
@put:	jsr Put
	bra @l
@d:	Copy24 rl, _gb_a
	jsr Leave
	lda wr
	ldx wr+1
	rts
Put:	sta (lp)
	inc lp
	bne @1
	inc lp+1
@1:	inc wr
	bne @2
	inc wr+1
@2:	rts

;---------------------------------------------------------------
; lines
;---------------------------------------------------------------
; the line at gb_a (its start) into gb_line: the columns gb_hs ..
; gb_hs + 79, tabs to multiples of 8, spaces after its end; gb_mkc[i] =
; the column where position gb_mk[i] is in it ($FFFF: not in it); gb_a =
; the next line's start; gb_eof = 1 if the line has no LF; gb_lcols its
; width
_gb_render:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	stz col
	stz col+1
	stz _gb_eof
	stz _gb_tab
	ldx #COLS - 1
	lda #' '
@sp:	sta _gb_line,x
	dex
	bpl @sp
	ldx #5
	lda #$FF
@mk:	sta _gb_mkc,x
	dex
	bpl @mk
@l:	jsr Marks
	jsr RdNext
	bcs @eof
	cmp #10
	beq @lf
	cmp #9
	beq @tab
	jsr PutCol
	bra @l
@tab:	lda #' '
	sta _gb_tab
	jsr PutCol
	lda col
	and #7
	bne @tab
	bra @l
@eof:	lda #1
	sta _gb_eof
@lf:	Copy24 rl, _gb_a
	lda col
	sta _gb_lcols
	lda col+1
	sta _gb_lcols+1
	jmp Leave

; a at column col (if it is shown); col + 1
PutCol:	cmp #0                  ; a NUL shows as glyph $80 (PutCards
	bne @c                  ; stops at a 0)
	lda #$80
@c:	tay
	sec
	lda col
	sbc _gb_hs
	tax
	lda col+1
	sbc _gb_hs+1
	bne @n
	cpx #COLS
	bcs @n
	tya
	sta _gb_line,x
@n:	inc col
	bne @r
	inc col+1
@r:	rts

; a mark at rl: its column (the first time); the three marks' low bytes
; first (V215: a character's usual case)
Marks:	lda rl
	cmp _gb_mk
	bne @1
	ldx #0
	ldy #0
	jsr Mark1
	lda rl
@1:	cmp _gb_mk+4
	bne @2
	ldx #4
	ldy #2
	jsr Mark1
	lda rl
@2:	cmp _gb_mk+8
	bne @r
	ldx #8
	ldy #4
	jmp Mark1
@r:	rts

; mark x / 4 (its column at gb_mkc + y) at rl? (its low byte is)
Mark1:	lda rl+1
	cmp _gb_mk+1,x
	bne @n
	lda rl+2
	cmp _gb_mk+2,x
	bne @n
	lda _gb_mkc+1,y
	and _gb_mkc,y
	cmp #$FF
	bne @n
	lda col
	sta _gb_mkc,y
	lda col+1
	sta _gb_mkc+1,y
@n:	rts

; from gb_a over up to gb_n (16 bits) LFs: gb_a after the last one (or
; the end); a/x = the LFs passed
_gb_fwd_lines:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	stz cnt
	stz cnt+1
	lda _gb_n
	ora _gb_n+1
	beq @d
@seg:	lda run
	ora run+1
	bne @sc
	jsr RdSeek
	lda run
	ora run+1
	beq @d
@sc:	jsr ScanLim
	sta chunk
	ldy #0
@s:	lda (bp),y
	cmp #10
	beq @f
	iny
	cpy chunk
	bne @s
	jsr Skip
	bra @seg
@f:	iny                     ; past the LF
	jsr Skip
	inc cnt
	bne @1
	inc cnt+1
@1:	lda cnt
	cmp _gb_n
	bne @seg
	lda cnt+1
	cmp _gb_n+1
	bne @seg
@d:	Copy24 rl, _gb_a
	jsr Leave
	lda cnt
	ldx cnt+1
	rts

; gb_a = the start of the line gb_a is in
_gb_line_start:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
@seg:	lda run                 ; (V215: a run at a time, as gb_fwd_lines)
	ora run+1
	bne @sc
	jsr RbSeek
	lda run
	ora run+1
	beq @d                  ; (the text's start)
@sc:	jsr ScanLim             ; k = min(run, 255) bytes: bp, bp - 1 ..
	sta chunk
	dec a
	sta tmp                 ; dp = bp - (k - 1), y = k - 1 (bp)
	sec
	lda bp
	sbc tmp
	sta dp
	lda bp+1
	sbc #0
	sta dp+1
	ldy tmp
@s:	lda (dp),y
	cmp #10
	beq @f
	dey
	cpy #$FF
	bne @s
	ldy chunk               ; none: k bytes back
	jsr Back
	bra @seg
@f:	tya                     ; the LF: back over the k - 1 - y bytes after it
	eor #$FF
	sec
	adc tmp
	tay
	beq @d
	jsr Back
@d:	Copy24 rl, _gb_a
	jmp Leave

; the reader back by y bytes (1-255; y <= run): rl, run, bp
Back:	sty tmp
	sec
	lda rl
	sbc tmp
	sta rl
	lda rl+1
	sbc #0
	sta rl+1
	lda rl+2
	sbc #0
	sta rl+2
	sec
	lda run
	sbc tmp
	sta run
	lda run+1
	sbc #0
	sta run+1
	sec
	lda bp
	sbc tmp
	sta bp
	lda bp+1
	sbc #0
	sta bp+1
	rts

; gb_r = the LFs in [gb_a, gb_b)
_gb_count:
	jsr Enter
	Copy24 _gb_a, rl
	Sub24 _gb_b, _gb_a, cnt
	stz run
	stz run+1
	stz _gb_r
	stz _gb_r+1
	stz _gb_r+2
	stz _gb_r+3
@seg:	jsr CntZ
	beq @d
	lda cnt+2
	bmi @d                  ; (b < a)
	lda run
	ora run+1
	bne @sc
	jsr RdSeek
	lda run
	ora run+1
	beq @d
@sc:	jsr ScanLim             ; y limit = min(run, 255, cnt)
	ldx cnt+2
	bne @lim
	ldx cnt+1
	bne @lim
	cmp cnt
	bcc @lim
	lda cnt
@lim:	sta chunk
	ldy #0
@s:	lda (bp),y
	cmp #10
	bne @n
	Inc24 _gb_r
@n:	iny
	cpy chunk
	bne @s
	jsr Skip
	sec
	lda cnt
	sbc chunk
	sta cnt
	lda cnt+1
	sbc #0
	sta cnt+1
	lda cnt+2
	sbc #0
	sta cnt+2
	bra @seg
@d:	jmp Leave

; the display column of gb_b in the line starting at gb_a (a/x)
_gb_col:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	stz col
	stz col+1
@l:	Cmp24 rl, _gb_b
	bcs @d
	jsr RdNext
	bcs @d
	cmp #10
	beq @d
	jsr ColStep
	bra @l
@d:	jsr Leave
	lda col
	ldx col+1
	rts

; col over the character a (a tab to the next multiple of 8)
ColStep: cmp #9
	bne @1
	lda col
	ora #7
	sta col
@1:	inc col
	bne @r
	inc col+1
@r:	rts

; from the line start gb_a to the first position at column >= gb_n (16
; bits), or the line's end: gb_a; a/x = its column
_gb_at_col:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
	stz col
	stz col+1
@l:	lda col+1
	cmp _gb_n+1
	bcc @go
	bne @d
	lda col
	cmp _gb_n
	bcs @d
@go:	Copy24 rl, atp          ; (the position before this character)
	lda col
	sta pcol
	lda col+1
	sta pcol+1
	jsr RdNext
	bcs @d
	cmp #10
	beq @back
	pha
	jsr ColStep
	pla
	cmp #9                  ; a tab past the goal: before it
	bne @l
	lda col+1
	cmp _gb_n+1
	bcc @l
	bne @tb
	lda col
	cmp _gb_n
	bcc @l
	beq @d
@tb:	Copy24 atp, rl
	lda pcol
	sta col
	lda pcol+1
	sta col+1
	bra @d
@back:	Copy24 atp, rl          ; the LF stays after the cursor
@d:	Copy24 rl, _gb_a
	jsr Leave
	lda col
	ldx col+1
	rts

;---------------------------------------------------------------
; finding: gb_pat (gb_plen bytes, already through gb_ftab) from gb_a on;
; gb_a = the first match, or $FFFFFFFF
;---------------------------------------------------------------
_gb_find:
	jsr Enter
	Copy24 _gb_a, rl
	stz run
	stz run+1
@seg:	lda run
	ora run+1
	bne @sc
	jsr RdSeek
	lda run
	ora run+1
	bne @sc
	jmp @no
@sc:	jsr ScanLim
	sta chunk
	ldy #0
@s:	lda (bp),y
	tax
	lda _gb_ftab,x
	cmp _gb_pat
	beq @cand
	iny
	cpy chunk
	bne @s
	jsr Skip
	bra @seg
@cand:	cpy #0
	beq @c0
	jsr Skip                ; the reader at the candidate
@c0:	jsr Keep                ; the reader's state; compare from it
	jsr RdNext              ; the first byte (matched)
	ldy #1
@cmp:	cpy _gb_plen
	beq @hit
	phy
	jsr RdNext
	ply
	bcs @miss
	tax
	lda _gb_ftab,x
	cmp _gb_pat,y
	bne @miss
	iny
	bra @cmp
@miss:	jsr Restore
	jsr RdNext              ; past the candidate
	bcc @seg
@no:	lda #$FF
	sta _gb_a
	sta _gb_a+1
	sta _gb_a+2
	sta _gb_a+3
	jmp Leave
@hit:	jsr Restore
	Copy24 rl, _gb_a
	jmp Leave

Keep:	Copy24 rl, keep
	lda run
	sta keep+3
	lda run+1
	sta keep+4
	lda bp
	sta keep+5
	lda bp+1
	sta keep+6
	lda $00
	sta keep+7
	rts
Restore: Copy24 keep, rl
	lda keep+3
	sta run
	lda keep+4
	sta run+1
	lda keep+5
	sta bp
	lda keep+6
	sta bp+1
	lda keep+7
	sta $00
	rts

;---------------------------------------------------------------
; the undo log's banks: gb_n bytes (16 bits) between its physical gb_a
; and gb_lp
;---------------------------------------------------------------
UlSet:	lda $00
	sta sbank
	lda #<_ul_bk
	sta tbl
	lda #>_ul_bk
	sta tbl+1
	Copy24 _gb_a, ph
	lda _gb_n
	sta cnt
	lda _gb_n+1
	sta cnt+1
	stz cnt+2
	lda _gb_lp
	sta lp
	lda _gb_lp+1
	sta lp+1
	rts

_ul_read:
	jsr UlSet
	jsr PRead
	jmp Leave

_ul_write:
	jsr UlSet
	jsr PWrite
	jmp Leave
