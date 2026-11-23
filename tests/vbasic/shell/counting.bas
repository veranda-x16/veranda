' Counting the birds at the feeder in 2026: a .BAS source in a folder,
' with line numbers (V2 style); VeraBASIC Run is found in the top folder
10 DIM C%(6)
20 FOR D% = 1 TO 6
30 C%(D%) = (D% * 7) MOD 5 + D%
40 NEXT D%
50 T% = 0
60 FOR D% = 1 TO 6
70 IF C%(D%) > 4 THEN PRINT "Day"; D%; ": busy,"; C%(D%) ELSE PRINT "Day"; D%; ":"; C%(D%)
80 T% = T% + C%(D%)
90 NEXT D%
100 GOSUB 200
110 END
200 PRINT "Week:"; T%; "birds"
210 RETURN
