' generated: arrays of each type, their elements in expressions
DIM n%(10), f(8, 8), w$(8)
FOR i% = 0 TO 10: n%(i%) = (i% * 37) MOD 97: NEXT
FOR i% = 0 TO 8: FOR j% = 0 TO 8: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 8: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(5) + n%(10) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(8) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(2, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(9, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(8, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(5, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(10) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(4) = n%(5) - 10: PRINT n%(9): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(5) = w$(4) + "swi": PRINT w$(7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(7, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(9) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 10: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
