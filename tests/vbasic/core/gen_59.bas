' generated: strings, the heap and its collector
s$ = "crow": t$ = "crow": u$ = ""
TRY: PRINT "["; t$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$(RIGHT$(MID$(CHR$(80), 1), 4), 3), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(t$ + u$ + "crow" + "tit", 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(t$, 0); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(68) > s$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; STR$(199); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT RIGHT$(MID$(t$, 4), 4) + s$ <> "tit" + MID$(CHR$(75), 6): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(t$ + "?"); VAL(STR$(206)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(CHR$(68) + "?"); VAL(STR$(d%)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(t$, 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "jay"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(t$, 3); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(RIGHT$(MID$("rook", 5, 1) + "crow", 3), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "wren"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(CHR$(71) + RIGHT$(LEFT$("jay", 7), 5) + "?"); VAL(STR$(243)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(CHR$(67), 5), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$(RIGHT$(u$, 2) + u$, 9) + "?"); VAL(STR$(103)): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
