' expect 7: CASE expected after SELECT CASE in line 6
' expect 11: CASE without SELECT CASE
' expect 15: CASE after CASE ELSE
' expect 17: END SELECT without SELECT CASE
x = 1
SELECT CASE x
  PRINT "before any CASE"
  CASE 1
    PRINT "one"
END SELECT
CASE 2
SELECT CASE x
  CASE ELSE
    PRINT "other"
  CASE 3
END SELECT
END SELECT
