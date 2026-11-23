; gate spec: the generated include assembles and its values are what the
; API promises
.include "veranda.inc"
.assert Rectangle = CLASSIC_BASE + $24, error, "Rectangle"
.assert r11L = $18 && r11H = $19, error, "r11"
.assert WRectangle >= NEW_BASE, error, "WRectangle"
.assert mouseXPos = $3A, error, "mouseXPos"
	jsr Rectangle
	jsr WRectangle
	lda #<fileHeader
