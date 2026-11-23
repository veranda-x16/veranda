' generated: arrays of each type, their elements in expressions
DIM n%(38), f(3, 3), w$(3)
FOR i% = 0 TO 38: n%(i%) = (i% * 30) MOD 97: NEXT
FOR i% = 0 TO 3: FOR j% = 0 TO 3: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 3: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: n%(19) = n%(19) - 139: PRINT n%(34): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(2, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(16) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(6) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(23) + n%(35) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(6) = n%(29) - d%: PRINT n%(20): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(3) + n%(16) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(4) + "wre": PRINT w$(3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(3) = w$(0) + "rob": PRINT w$(2): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(2) = w$(0) + "kit": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(22) = n%(30) - $B753: PRINT n%(37): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(3) + "cro": PRINT w$(1): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(22) = n%(14) - %1011: PRINT n%(4): CATCH: PRINT "error"; ERR: END TRY
TRY: n%(36) = n%(38) - a%: PRINT n%(30): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(0) = w$(3) + "swi": PRINT w$(3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(1, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 3): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 38: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
