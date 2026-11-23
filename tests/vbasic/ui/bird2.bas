' Bird Watch, step 2: a menu with About and Quit
OPTION INTEGER
APP NAME "Bird Watch"
WINDOW #1, 10, 6, 60, 40, "Bird Watch", CLOSE, FRAME, SHADOW, STATUS 2
WINDOW USE #1
FONT UI
TEXT 16, 20, "Birds at the feeder"
MENU "Bird Watch" : ITEM "About Bird Watch", About
MENU "File" : ITEM "Quit", DoQuit, "Q"
MENU SHOW
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

SUB DoQuit
  END
END SUB
