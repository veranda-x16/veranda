' generated: arrays of each type, their elements in expressions
DIM n%(4), f(9, 9), w$(9)
FOR i% = 0 TO 4: n%(i%) = (i% * 10) MOD 97: NEXT
FOR i% = 0 TO 9: FOR j% = 0 TO 9: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 9: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(1) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(1) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 6): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(2) = n%(1) - b%: PRINT n%(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(6, 9): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(9) + "jay": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(0) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(1) = n%(1) - 136: PRINT n%(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(1) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 4: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
