' generated: arrays of each type, their elements in expressions
DIM n%(26), f(4, 4), w$(4)
FOR i% = 0 TO 26: n%(i%) = (i% * 14) MOD 97: NEXT
FOR i% = 0 TO 4: FOR j% = 0 TO 4: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 4: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: w$(3) = w$(1) + "cro": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(4) + "lar": PRINT w$(3): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(5) + "cro": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(4) = w$(4) + "cro": PRINT w$(0): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(14) = n%(8) - 293: PRINT n%(6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(28) + n%(12) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(2) + "owl": PRINT w$(4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(23) = n%(24) - 70: PRINT n%(19): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(15) + n%(17) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(15) = n%(16) - $87F2: PRINT n%(0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(13) = n%(21) - $86: PRINT n%(6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(8) + n%(5) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(18) = n%(19) - %100101: PRINT n%(17): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 26: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
