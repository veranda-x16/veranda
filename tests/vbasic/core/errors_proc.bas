' an error in a procedure is caught by the caller's TRY; frames unwound
FUNCTION Inv(x)
  Inv = 1 / x
END FUNCTION
SUB Deep(n%)
  LOCAL s$
  s$ = "deep" + STR$(n%)
  IF n% = 0 THEN ERROR 222, "bottom"
  Deep n% - 1
END SUB
TRY
  PRINT Inv(4); Inv(0)
CATCH
  PRINT "caught"; ERR; ERR$
END TRY
TRY
  Deep 5
CATCH
  PRINT "caught"; ERR; ERR$
END TRY
FOR i% = 1 TO 3
  TRY
    IF i% = 2 THEN ERROR 230
    PRINT "ok"; i%
  CATCH
    PRINT "failed"; i%
  END TRY
NEXT
PRINT Inv(2)
