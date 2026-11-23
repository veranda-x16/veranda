' generated: strings, the heap and its collector
s$ = "jay": t$ = "owl": u$ = ""
TRY: PRINT "["; MID$("jay", 1) + s$ + STR$(d%) + RIGHT$("crow" + CHR$(85), 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$("swift", 2, 5), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$("wren", 5, 2); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(STR$(b%), 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$(LEFT$("rook", 7), 1) + "?"); VAL(STR$(269)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$("robin", 7) + "lark" + STR$(237) + "robin" + "?"); VAL(STR$(60)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$("wren" + u$ + STR$(a%) + RIGHT$("wren", 7), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$("swift", 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(LEFT$(s$ + "swift", 0), 4), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(LEFT$(RIGHT$(CHR$(81), 6), 0), 5, 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(MID$(LEFT$("jay", 6), 6, 4), 0), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$(s$, 2), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(u$, 3); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$("rook", 9) <= MID$(MID$(LEFT$("wren", 4), 3, 2), 4, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$("swift" + t$, 6) + "tit", 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$("owl", 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(83); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(RIGHT$(CHR$(77) + CHR$(69), 0), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("swift", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$ + "jay" + CHR$(68); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC("wren" + "?"); VAL(STR$(%11010011)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(MID$("tit", 1, 4) + CHR$(78), 4, 2), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(s$ + CHR$(89), 9) = "tit": CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
