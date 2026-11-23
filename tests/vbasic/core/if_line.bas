' one-line IF: THEN, ELSE, a line number, nesting
x% = 5
IF x% > 3 THEN PRINT "big"
IF x% > 9 THEN PRINT "huge" ELSE PRINT "not huge"
IF x% = 5 THEN PRINT "five": PRINT "still five" ELSE PRINT "no"
IF x% = 6 THEN PRINT "six": PRINT "six again" ELSE PRINT "else": PRINT "else again"
IF x% THEN IF x% < 10 THEN PRINT "nested" ELSE PRINT "inner else"
IF 0 THEN IF 1 THEN PRINT "a" ELSE PRINT "b"
IF x% = 5 THEN 100
PRINT "skipped"
100 PRINT "at 100"
IF x% = 4 THEN 200 ELSE 300
200 PRINT "at 200"
300 PRINT "at 300"
IF x% = 5 GOTO 400
PRINT "skipped too"
400 PRINT "at 400"
IF 1.5 THEN PRINT "float true"
IF 0.0 THEN PRINT "float false" ELSE PRINT "zero is false"
IF "a" = "a" THEN PRINT "strings equal"
