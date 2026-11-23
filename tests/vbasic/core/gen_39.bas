' generated: arrays of each type, their elements in expressions
DIM n%(16), f(9, 9), w$(9)
FOR i% = 0 TO 16: n%(i%) = (i% * 36) MOD 97: NEXT
FOR i% = 0 TO 9: FOR j% = 0 TO 9: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 9: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(5) + n%(16) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(9) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(4) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(3, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(16) = n%(1) - 46: PRINT n%(13): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(13) = n%(13) - $9E10: PRINT n%(8): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(4) = w$(4) + "kit": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(6, 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(17) + n%(15) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(14) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(7) + n%(9) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(8) - $D97A: PRINT n%(9): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(7) = n%(15) - 142: PRINT n%(0): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(9) = w$(2) + "lar": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(8, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(8) = w$(6) + "roo": PRINT w$(3): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(3) = w$(9) + "owl": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(10) = n%(4) - a%: PRINT n%(6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(7) + n%(5) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(13) = n%(11) - 21: PRINT n%(13): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(3) = n%(3) - 151: PRINT n%(0): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 16: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
