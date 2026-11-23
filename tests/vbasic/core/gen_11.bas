' generated: arrays of each type, their elements in expressions
DIM n%(34), f(9, 9), w$(9)
FOR i% = 0 TO 34: n%(i%) = (i% * 23) MOD 97: NEXT
FOR i% = 0 TO 9: FOR j% = 0 TO 9: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 9: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(26) + n%(16) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(7) = n%(29) - c%: PRINT n%(15): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(27) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(35) + n%(9) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(10, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(13) + n%(5) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(3) + "lar": PRINT w$(8): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(3) = w$(9) + "rob": PRINT w$(9): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(35) + n%(19) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(31) + n%(27) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(8) = w$(2) + "rob": PRINT w$(9): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(5, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(9) + "roo": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(11) = n%(27) - 168: PRINT n%(11): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 34: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
