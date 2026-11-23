' Hello: a window with a close glyph, its title and status (gate vb_ui)
OPTION INTEGER
APP NAME "Hello"
WINDOW #1, 10, 6, 60, 30, "Hello window", CLOSE, FRAME, SHADOW, STATUS 2
WINDOW STATUS #1, "Click the cross to close", "VeraBASIC"
WINDOW USE #1
FONT UI
TEXT 16, 24, "Hello from VeraBASIC, in a window of its own."
BOX 16, 40, 200, 70
PRINT "body"; BODYTOP(#1); BODYBOTTOM(#1)
ON CLOSE #1 CALL Bye
SUB Bye
  WINDOW CLOSE #1
  PRINT "closed"
  END
END SUB
