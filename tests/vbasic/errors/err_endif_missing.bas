' expect 13: END IF missing for IF in line 4
x = 1
PRINT "before"
IF x THEN
  PRINT "one"
  WHILE x < 3
    x = x + 1
  WEND
ELSE
  PRINT "two"
REM the END IF never comes
PRINT "after"
PRINT "the end"
