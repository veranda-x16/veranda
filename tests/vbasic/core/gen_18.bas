' generated: arrays of each type, their elements in expressions
DIM n%(20), f(5, 5), w$(5)
FOR i% = 0 TO 20: n%(i%) = (i% * 23) MOD 97: NEXT
FOR i% = 0 TO 5: FOR j% = 0 TO 5: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 5: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT f(5, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(9) = n%(0) - a%: PRINT n%(20): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(13) + n%(19) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(9) + n%(12) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(15) + n%(15) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(5, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(15) = n%(19) - 145: PRINT n%(2): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(5) = w$(1) + "owl": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(16) = n%(10) - 74: PRINT n%(18): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(12) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(13) + n%(16) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(5, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(11) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(13) + n%(8) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(9) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 4): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 20: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
