' expect 10: SUB Inner inside SUB Outer (line 9)
' expect 12: END SUB without SUB
' expect 13: EXIT FOR outside FOR
' expect 15: EXIT SUB outside SUB
' expect 16: LOCAL outside a SUB or FUNCTION
' expect 17: RETURN with a value outside a FUNCTION
' expect 19: SUB Twice defined twice (lines 18 and 19)
' expect 21: END SUB missing for SUB in line 20
SUB Outer
SUB Inner
END SUB
END SUB
EXIT FOR
FOR i = 1 TO 2: NEXT
EXIT SUB
LOCAL a
RETURN 5
SUB Twice: END SUB
SUB Twice: END SUB
SUB Unclosed
  PRINT "never closed"
