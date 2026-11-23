; Veranda kernel: WDrawLine's zero page (bank G's kernel/g/draw.s and
; bank T's FbLine, kernel/t/line.s; DECISIONS V159). Scratch, not across
; calls (the interrupt keeps it).

lnE     = gPtr                  ; (2) the error term d
lnI1    = fbBufPtr              ; (2) 2 * minor
lnI2    = kPtr                  ; (2) 2 * (minor - major)
lnC     = kPtr2                 ; (2) |major|; FbLine: the points left
lnM     = kTmp                  ; FbLine: the pixel's mask (first |minor|)
lnP     = kTmp + 1              ; FbLine: a fill's byte, 0 or $FF
lnSy    = kTmp + 2              ; the minor step: 1 or $FF
lnSt    = kTmp + 3              ; $FF steep (the axes exchanged), 0 flat;
lnF     = kTmp + 3              ; FbLine: bit 7 recover, bit 6 both screens
