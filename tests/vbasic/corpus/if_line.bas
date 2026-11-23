' One-line IFs
x% = 3
IF x% > 2 THEN PRINT "big"
IF x% > 2 THEN PRINT "big" ELSE PRINT "small"
IF x% > 1 THEN IF x% > 5 THEN PRINT "huge" ELSE PRINT "medium" ELSE PRINT "tiny"
IF x% = 3 THEN x% = 0: PRINT "reset": PRINT x%
IF x% THEN 100 ELSE 200
100 PRINT "hundred"
200 IF x% = 0 GOTO 300
300 IF x% = 0 THEN 100
