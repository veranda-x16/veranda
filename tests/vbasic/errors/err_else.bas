' expect 7: ELSE without IF
' expect 11: Two ELSE parts for IF in line 8
' expect 13: ELSEIF after ELSE for IF in line 8
' expect 16: END IF without IF
' expect 17: ELSEIF inside a one-line IF
' expect 18: THEN missing after IF
ELSE
IF 1 THEN
  PRINT 1
ELSE
ELSE
  PRINT 2
ELSEIF 2 THEN
END IF
x = 1
END IF
IF x THEN PRINT: ELSEIF x THEN
IF x PRINT x
