' generated: arrays of each type, their elements in expressions
DIM n%(40), f(2, 2), w$(2)
FOR i% = 0 TO 40: n%(i%) = (i% * 29) MOD 97: NEXT
FOR i% = 0 TO 2: FOR j% = 0 TO 2: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 2: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT f(2, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(0) + "owl": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(3) = n%(13) - 40: PRINT n%(20): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(1) + "kit": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(0) + "lar": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(7) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(38) + n%(34) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(2, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(22) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(37) - $8558: PRINT n%(38): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(0) + "swi": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(17) + n%(28) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(1) + "owl": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(1) + "kit": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(2) + "roo": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 40: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
