' Bird Watch, step 5: a click handler
OPTION INTEGER
APP NAME "Bird Watch"
WINDOW #1, 10, 6, 60, 40, "Bird Watch", CLOSE, FRAME, SHADOW, STATUS 2
WINDOW USE #1
FONT UI
TEXT 16, 20, "Birds at the feeder"
MENU "Bird Watch" : ITEM "About Bird Watch", About
MENU "File" : ITEM "Quit", DoQuit, "Q"
MENU "Birds" : ITEM "Add a bird", AddBird, "B" : ITEM "Start again", Reset
MENU SHOW
count = 0
ShowCount
TIMER 1, 60 CALL Tick
ON CLICK CALL Clicked
ON CLOSE #1 CALL DoQuit
ON CLOSE #2 CALL CloseAbout

SUB About
  WINDOW #2, 25, 18, 30, 8, "About", CLOSE, FRAME, SHADOW
  WINDOW USE #2
  FONT UI
  TEXT 12, 20, "Bird Watch 1.0"
  TEXT 12, 36, "Counts the birds at the feeder."
  WINDOW USE #1
END SUB

SUB CloseAbout
  WINDOW CLOSE #2
END SUB

SUB Clicked
  IF MOUSEB AND 128 THEN EXIT SUB
  IF HIT(#1, MOUSEX, MOUSEY) <> 4 THEN EXIT SUB
  DrawBird MOUSEX, MOUSEY
  AddBird
END SUB

SUB DrawBird(x, y)
  WINDOW USE #1
  BOX x - 3, y - 2, x + 3, y + 2
  LINE x - 8, y - 6, x, y
  LINE x, y, x + 8, y - 6
END SUB

SUB AddBird
  count = count + 1
  ShowCount
END SUB

SUB Reset
  count = 0
  ShowCount
END SUB

SUB ShowCount
  WINDOW STATUS #1, STR$(count) + " birds", TIME$
END SUB

SUB Tick
  ShowCount
END SUB

SUB DoQuit
  END
END SUB
