' generated: arrays of each type, their elements in expressions
DIM n%(38), f(9, 9), w$(9)
FOR i% = 0 TO 38: n%(i%) = (i% * 36) MOD 97: NEXT
FOR i% = 0 TO 9: FOR j% = 0 TO 9: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 9: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: n%(27) = n%(7) - 121: PRINT n%(21): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(2) + "jay": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(9, 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(18) + n%(18) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(39) + n%(23) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(34) + n%(12) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(6) = w$(6) + "jay": PRINT w$(3): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(30) = n%(3) - c%: PRINT n%(6): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(9) = w$(8) + "rob": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(28) = n%(5) - 155: PRINT n%(22): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(7, 8): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(39) + n%(38) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(5) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 38: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
