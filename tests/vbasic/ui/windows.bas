' Windows: three, in use one after the other, hit tests, clipping (gate vb_ui)
OPTION INTEGER
WINDOW #1, 2, 3, 40, 30, "One", FRAME, STATUS 2
WINDOW #2, 30, 12, 46, 24, "Two", CLOSE, FRAME, SHADOW
WINDOW #3, 8, 38, 64, 18, "Three", TOOL 3, STATUS 2, FRAME
WINDOW BACK #1
WINDOW BACK #3
WINDOW USE #1
PATTERN 2
BOX -20, -20, 400, 400
PRINT "one"; BODYTOP(#1); BODYBOTTOM(#1); HIT(#1, 10, 10)
WINDOW USE #2
CLS
FRAME 4, 4, 300, 100
TEXT 8, 40, "Window two is in front, clipped to its body"
PRINT "two"; BODYTOP(#2); HIT(#2, 0, -8); HIT(#2, 360, -12); HIT(#2, 50, 50)
WINDOW USE #3
CARDS 1, 1, "Window three's body, cards"
PAPER 0, 0, 64, 1, GREEN
WINDOW STATUS #3, "Status of three", "right"
WINDOW TITLE #3, "Three, renamed"
WINDOW USE #0
PRINT HIT(#1, 20, 30); HIT(#3, 100, 330); HIT(#3, 100, 450); HIT(#3, 700, 10)
ON CLICK CALL Clicked
SUB Clicked
  IF MOUSEB AND 128 THEN EXIT SUB
  PRINT "hit"; HIT(#1, MOUSEX, MOUSEY); HIT(#2, MOUSEX, MOUSEY); HIT(#3, MOUSEX, MOUSEY)
  IF HIT(#2, MOUSEX, MOUSEY) = 1 THEN
    WINDOW CLOSE #2
    WINDOW FRONT #1
    END
  END IF
END SUB
