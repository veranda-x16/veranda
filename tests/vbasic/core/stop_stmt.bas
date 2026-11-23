' STOP stops the program (not catchable by TRY)
PRINT "one"
TRY
  STOP
CATCH
  PRINT "never caught"
END TRY
PRINT "never"
