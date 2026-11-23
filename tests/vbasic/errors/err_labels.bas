' expect 7: Undefined label Nowhere
' expect 8: Undefined line 500
' expect 9: Undefined SUB Missing
' expect 12: Label Start defined twice (lines 10 and 12)
' expect 14: Line number 20 used twice (lines 13 and 14)
' expect 15: Undefined line 30
GOTO Nowhere
GOSUB 500
Missing 1, 2
Start: PRINT "a"
GOTO Start
Start: PRINT "b"
20 PRINT
20 PRINT
ON x GOTO 20, 30
ON ERROR GOTO 0
