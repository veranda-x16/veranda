' generated: arrays of each type, their elements in expressions
DIM n%(21), f(8, 8), w$(8)
FOR i% = 0 TO 21: n%(i%) = (i% * 3) MOD 97: NEXT
FOR i% = 0 TO 8: FOR j% = 0 TO 8: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 8: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(5) + n%(11) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(11) = n%(21) - $482B: PRINT n%(1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(19) = n%(1) - 174: PRINT n%(13): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(22) + n%(15) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(15) = n%(5) - $8B77: PRINT n%(6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(15) + n%(6) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(1) + "owl": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(17) = n%(1) - 31: PRINT n%(9): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(12) + n%(8) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(9, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(3) - 26: PRINT n%(18): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(21) + n%(20) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(11) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(6, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(9, 0): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 21: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
