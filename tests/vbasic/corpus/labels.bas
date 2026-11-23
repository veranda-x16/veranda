' Labels and line numbers
GOSUB DrawBoard
GOTO Done
DrawBoard:
  PRINT "board"
  RETURN
Done: PRINT "done"
10 GOSUB 20
20 RETURN
Again: GOTO Again
