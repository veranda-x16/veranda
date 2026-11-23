' block IF with ELSEIF and ELSE, nested
FOR t% = -5 TO 35 STEP 10
  IF t% < 0 THEN
    PRINT t%; "frost"
  ELSEIF t% < 10 THEN
    PRINT t%; "cold"
  ELSEIF t% < 20 THEN
    PRINT t%; "mild"
    IF t% = 15 THEN
      PRINT "  exactly fifteen"
    ELSE
      PRINT "  not fifteen"
    END IF
  ELSE
    PRINT t%; "warm"
  END IF
NEXT
IF 1 THEN ' a comment after THEN
  PRINT "block with a comment"
END IF
IF 0 THEN
  PRINT "never"
END IF
PRINT "end"
