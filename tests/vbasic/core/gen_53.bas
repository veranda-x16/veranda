' generated: arrays of each type, their elements in expressions
DIM n%(27), f(5, 5), w$(5)
FOR i% = 0 TO 27: n%(i%) = (i% * 41) MOD 97: NEXT
FOR i% = 0 TO 5: FOR j% = 0 TO 5: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 5: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT f(4, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(4) = w$(1) + "rob": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(10) + n%(16) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(20) + n%(11) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(23) = n%(16) - $58F8: PRINT n%(7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(16) + n%(11) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(21) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(16) = n%(25) - 44: PRINT n%(17): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 4): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(15) = n%(2) - 33: PRINT n%(24): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(16) + n%(26) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(1) - 0: PRINT n%(13): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(15) + n%(3) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(0) + n%(24) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(0) + "owl": PRINT w$(0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(1) + n%(23) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(2, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(22) + n%(4) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(19) + n%(21) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(0) = n%(21) - 97: PRINT n%(3): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(0) + "rob": PRINT w$(5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(26) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(24) = n%(16) - c%: PRINT n%(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(19) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(8) + n%(21) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(4) + "owl": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(9) + n%(24) * 2: CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 27: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
