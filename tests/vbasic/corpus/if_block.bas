' IF blocks
OPTION INTEGER
FOR t = -5 TO 25 STEP 10
  IF t < 0 THEN
    PRINT "frost"
  ELSEIF t < 10 THEN
    PRINT "cold"
  ELSEIF t < 20 THEN ' a comment after THEN
    PRINT "mild"
  ELSE
    IF t > 22 THEN
      PRINT "warm"
    END IF
    PRINT "summer"
  END IF
NEXT t
IF t THEN
END IF
