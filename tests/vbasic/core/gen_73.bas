' generated: strings, the heap and its collector
s$ = "lark": t$ = "jay": u$ = ""
TRY: u$ = LEFT$(RIGHT$(MID$(MID$(s$, 6, 3), 1), 6), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("lark", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(CHR$(86), 6) + "jay" + "lark" + MID$(MID$(t$, 6), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(u$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$ + "kite"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(74) <> t$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(LEFT$(CHR$(84), 1) + RIGHT$("wren", 9), 8) + "?"); VAL(STR$(d%)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(u$, 2) + "?"); VAL(STR$(28352)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(RIGHT$(MID$(MID$(t$, 5, 2), 4, 2), 5) + "?"); VAL(STR$(40)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(t$ + t$ + "lark", 4, 4) + "?"); VAL(STR$(225)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "kite"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$("tit" + CHR$(89), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$("kite", 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
