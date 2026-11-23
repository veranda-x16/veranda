' generated: strings, the heap and its collector
s$ = "wren": t$ = "crow": u$ = ""
TRY: u$ = LEFT$(MID$(LEFT$(u$, 0) + CHR$(79), 6, 2), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(CHR$(89), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$("rook", 4), 5, 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(CHR$(86) + t$ + RIGHT$("jay", 8), 3) + "?"); VAL(STR$(c%)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(t$, 4) = MID$(RIGHT$(LEFT$(CHR$(70), 4), 4), 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(MID$(STR$(27751), 1) + t$, 6) <= STR$(16): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(LEFT$(STR$(b%), 7), 2) > "robin": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(s$ + "?"); VAL(STR$(c%)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(s$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$("swift", 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(CHR$(88), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(STR$(8176), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(CHR$(80), 5, 5) <> STR$(13685): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(s$, 2, 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(t$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT STR$(162) <= RIGHT$("robin" + CHR$(67) + "robin", 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "robin"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(CHR$(75), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; t$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "rook"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(s$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(STR$(83), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$("lark", 5), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(MID$(u$, 5, 6), 5) + MID$(RIGHT$("rook", 2), 5) + "?"); VAL(STR$(c%)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(66) + "wren" + RIGHT$(CHR$(84), 8) + MID$("rook" + "tit", 2, 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(u$, 5) + "rook" <= t$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(MID$(CHR$(70), 3, 6), 2, 1) + "wren" + "?"); VAL(STR$(84)): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
