' generated: strings, the heap and its collector
s$ = "rook": t$ = "owl": u$ = ""
TRY: PRINT "["; "rook"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$("tit", 4), 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$(RIGHT$(RIGHT$(s$, 6), 2), 8) + "?"); VAL(STR$(175)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(CHR$(72) + "swift" + u$ + LEFT$(t$ + CHR$(75), 6), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(LEFT$("swift", 0), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$("kite", 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(MID$(LEFT$(s$, 5), 4), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(LEFT$(LEFT$(t$, 4), 3), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(81) + LEFT$(LEFT$(s$, 2), 3) >= RIGHT$(CHR$(65), 7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "lark" = STR$(18439): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(RIGHT$(MID$("owl" + "jay", 1, 3), 7), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$("lark" + RIGHT$(CHR$(78) + STR$(292), 7), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(CHR$(68) + "kite" + MID$("jay", 3) + "?"); VAL(STR$(28)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "robin"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; STR$(b%) + RIGHT$("kite", 0); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "tit"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(RIGHT$(CHR$(88), 5), 4) + s$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(MID$("wren" + "swift", 1, 0), 5) <= RIGHT$(STR$(274), 7): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(t$, 6) + s$ + s$ + "jay"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$("jay", 3), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("tit" + u$ + "rook" + MID$(CHR$(81), 5) + MID$(s$, 3), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(STR$(%1111010) + "owl" + RIGHT$("kite", 1), 5), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
