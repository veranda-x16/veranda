' END in the middle; the rest is not run
PRINT "start"
GOSUB 100
PRINT "back"
END
100 PRINT "in 100": RETURN
PRINT "not reached"
