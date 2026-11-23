' Bird Watch, step 1: a window
OPTION INTEGER
APP NAME "Bird Watch"
WINDOW #1, 10, 6, 60, 40, "Bird Watch", CLOSE, FRAME, SHADOW, STATUS 2
WINDOW USE #1
FONT UI
TEXT 16, 20, "Birds at the feeder"
ON CLOSE #1 CALL DoQuit

SUB DoQuit
  END
END SUB
