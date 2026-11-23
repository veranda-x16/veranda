' generated: arrays of each type, their elements in expressions
DIM n%(12), f(2, 2), w$(2)
FOR i% = 0 TO 12: n%(i%) = (i% * 21) MOD 97: NEXT
FOR i% = 0 TO 2: FOR j% = 0 TO 2: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 2: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(0) + n%(5) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(2) = n%(1) - d%: PRINT n%(11): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(0) + n%(8) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(2) + n%(6) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(0) + "swi": PRINT w$(0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(14) + n%(10) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(0) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(8) = n%(0) - 239: PRINT n%(2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(9) = n%(8) - 231: PRINT n%(4): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(5) = n%(0) - 266: PRINT n%(12): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(2) + "rob": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(8) + n%(9) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 12: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
