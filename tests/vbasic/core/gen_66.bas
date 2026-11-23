' generated: strings, the heap and its collector
s$ = "crow": t$ = "lark": u$ = ""
TRY: PRINT "["; LEFT$("robin" + u$ + RIGHT$("lark", 0), 2); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "owl"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(u$ + "?"); VAL(STR$(197)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT s$ + LEFT$(CHR$(69), 3) + "jay" < MID$(MID$("tit", 5, 2), 3) + u$ + CHR$(77): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$(LEFT$("crow", 4), 3) + "?"); VAL(STR$(2011)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$(RIGHT$(CHR$(75), 8), 4) + u$ + u$ + LEFT$(u$, 3), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(t$ + CHR$(77) + MID$("owl", 1, 4), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(78) <= MID$(MID$(CHR$(65), 1), 2) + RIGHT$(STR$(103) + CHR$(81), 6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(MID$("kite", 3), 7) + LEFT$(t$ + "owl", 7) + "?"); VAL(STR$(b%)): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(MID$(MID$(s$, 6, 5), 1, 5), 6), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(RIGHT$(s$, 2), 4) < t$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT RIGHT$(CHR$(89), 9) > LEFT$("robin" + u$, 9) + RIGHT$(CHR$(65), 2) + u$ + CHR$(87): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
