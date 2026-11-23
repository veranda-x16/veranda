' generated: strings, the heap and its collector
s$ = "kite": t$ = "wren": u$ = ""
TRY: s$ = LEFT$(RIGHT$(STR$(d%) + "robin", 6) + u$ + t$ + s$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("tit", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$("tit", 5, 0), 3) + s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(MID$(CHR$(90), 3), 3, 4) + "?"); VAL(STR$(264)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(MID$(STR$(b%) + u$ + MID$(s$, 4, 2), 5), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(s$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "lark"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$("swift", 2, 6) + CHR$(79) + CHR$(74) + "kite" <= CHR$(71) + STR$($EF47): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$("swift" + "swift", 6) + CHR$(82) + u$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(MID$(CHR$(72), 5), 6) + "?"); VAL(STR$(10055)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$("lark" + t$, 5, 3); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; u$ + "owl" + CHR$(82) + LEFT$(u$ + "crow", 7); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(u$ + u$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$("jay", 6) + "wren"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(MID$(CHR$(74), 3, 3), 3) + LEFT$(MID$("tit", 6), 7); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$("swift" + CHR$(69) + s$, 9); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(RIGHT$(MID$("robin", 5, 5), 4), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(STR$($AC33) + u$ + s$, 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$(LEFT$(CHR$(88), 5) + MID$(CHR$(83), 1), 5, 5), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC("rook" + s$ + STR$(18757) + MID$(STR$(288), 1, 3) + "?"); VAL(STR$(125)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$("swift", 1, 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(u$ + STR$(162) + CHR$(79) + "rook", 2); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("wren", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(MID$(s$, 2, 4), 4) + CHR$(76); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$(MID$(MID$(CHR$(83), 1, 4), 3), 5), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
