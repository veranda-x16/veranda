' generated: arrays of each type, their elements in expressions
DIM n%(7), f(4, 4), w$(4)
FOR i% = 0 TO 7: n%(i%) = (i% * 26) MOD 97: NEXT
FOR i% = 0 TO 4: FOR j% = 0 TO 4: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 4: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(7) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(1) + "wre": PRINT w$(0): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(2) = n%(0) - a%: PRINT n%(5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(4) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(6) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(8) + n%(4) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(5) - 103: PRINT n%(7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(0) = n%(1) - 4000: PRINT n%(5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 7: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
