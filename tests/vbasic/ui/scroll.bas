' Copy and scroll: screen areas moved, cards' colours read (gate vb_ui)
OPTION INTEGER
WINDOW #1, 2, 2, 76, 56, "Copy and scroll", FRAME
WINDOW USE #1
FOR i = 0 TO 9
  CARDS 1, i + 1, "Line" + STR$(i) + " of the cards"
NEXT
PAPER 1, 1, 20, 1, YELLOW
COPY 1, 8, 20, 40 TO 40, 8
SCROLL 1, 20, 8, 87, -16
PATTERN 3
BOX 8, 200, 150, 260
COPY 1, 200, 20, 61 TO 30, 260
PRINT CARDCOLOR(1, 1); CARDCOLOR(40, 1); POINT(9, 201); POINT(241, 261)
END
