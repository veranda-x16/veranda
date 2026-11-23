' labels as jump targets, GOSUB to a label
GOSUB Board
GOTO Done
Board:
  PRINT "board"
  RETURN
Done: PRINT "done"
n% = 0
Again: n% = n% + 1
IF n% < 3 THEN GOTO Again
PRINT "n"; n%
