' generated: strings, the heap and its collector
s$ = "wren": t$ = "owl": u$ = ""
TRY: PRINT RIGHT$(LEFT$(u$ + u$, 5), 0) <= t$ + t$: CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(RIGHT$("swift", 5) + LEFT$(u$, 3), 3), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(84) + s$ + u$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$(u$, 4, 5), 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(RIGHT$(CHR$(68), 9), 6) + MID$("swift" + "rook", 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(LEFT$(LEFT$(s$ + "swift", 4), 9), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT u$ <> "rook": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(s$, 2) + "?"); VAL(STR$($817F)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(t$ + u$, 1) + "swift"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(t$ + s$, 3) + "lark" + u$ + MID$("rook", 1, 3) + "?"); VAL(STR$(26459)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(78); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(67); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(RIGHT$("crow", 9) + "tit", 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(u$, 1) > t$ + STR$(13): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(LEFT$(RIGHT$(t$, 8), 6), 6); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT s$ <= RIGHT$(STR$(28019) + "crow" + u$, 4): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
