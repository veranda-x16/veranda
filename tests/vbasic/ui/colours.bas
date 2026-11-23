' Colours: patterns, boxes, lines and the paper of the cards (gate vb_ui)
OPTION INTEGER
APP NAME "Colours"
WINDOW #1, 2, 3, 76, 54, "Colours", FRAME, SHADOW, STATUS 2
WINDOW USE #1
' the look's colours, each a block of cards with its name
DATA "CHROME", 2, "SIDEBAR", 3, "YELLOW", 6, "RED", 7, "GREEN", 8
DATA "PURPLE", 9, "ORANGE", 10, "CYAN", 11, "SKY", 12, "SKY2", 13, "HILL", 14, "DUSK", 15
FOR i = 0 TO 11
  READ n$, c
  x = (i MOD 6) * 12 + 1
  y = (i \ 6) * 4 + 1
  PAPER x, y, 11, 3, c
  CARDS x, y + 1, " " + n$
  IF CARDCOLOR(x, y) <> c THEN PRINT "colour"; i; "wrong"
NEXT
' patterns
FOR p = 0 TO 11
  PATTERN p
  BOX p * 48 + 8, 80, p * 48 + 48, 120
  FRAME p * 48 + 8, 80, p * 48 + 48, 120
NEXT
PATTERN 1
' lines in a fan, points on a circle
FOR a = 0 TO 300 STEP 20
  LINE 100, 300, 100 + a, 140
NEXT
FOR a = 0 TO 359 STEP 6
  PLOT 450 + INT(80 * COS(a * 3.14159 / 180)), 220 + INT(80 * SIN(a * 3.14159 / 180))
NEXT
LINE 100, 300, 400, 300, ERASE
INVERT 300, 160, 380, 200
PRINT "point"; POINT(100, 300); POINT(300, 160); POINT(310, 170)
PALETTE 12, $F80
PAPER 60, 40, 14, 6, SKY
TEXT 484, 350, "Palette 12 orange"
WINDOW STATUS #1, "12 colours, 12 patterns", "PAPER and BOX"
PRINT "done"
END
