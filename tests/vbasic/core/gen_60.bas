' generated: arrays of each type, their elements in expressions
DIM n%(4), f(3, 3), w$(3)
FOR i% = 0 TO 4: n%(i%) = (i% * 47) MOD 97: NEXT
FOR i% = 0 TO 3: FOR j% = 0 TO 3: f(i%, j%) = i% / (j% + 1): NEXT j%, i%
FOR i% = 0 TO 3: w$(i%) = MID$("robinwrentitjayowlkitecrowrooklarkswift", i% + 1, 3): NEXT
TRY: PRINT n%(0) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(1) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(2) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(2, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(2) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(3) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(4) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(4, 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(5) + n%(0) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT n%(4) + n%(2) * 2: CATCH: PRINT "error"; ERR: END TRY
TRY: n%(4) = n%(2) - 297: PRINT n%(0): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT f(0, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: w$(1) = w$(0) + "cro": PRINT w$(0): CATCH: PRINT "error"; ERR: END TRY
s = 0: FOR i% = 0 TO 4: s = s + n%(i%): NEXT: PRINT s; UBOUND(n%); UBOUND(f, 2)
