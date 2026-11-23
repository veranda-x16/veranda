' generated: strings, the heap and its collector
s$ = "wren": t$ = "wren": u$ = ""
TRY: PRINT ASC("tit" + "?"); VAL(STR$(b%)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(RIGHT$(RIGHT$(u$, 5), 8), 6) + "?"); VAL(STR$(a%)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(u$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$ + "crow" + LEFT$("kite", 2) + MID$("robin" + CHR$(84), 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(RIGHT$("owl" + "tit", 1), 6); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "lark"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(RIGHT$("rook", 0), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(s$ + "?"); VAL(STR$(192)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(LEFT$(RIGHT$("owl", 8), 0), 2, 6), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$("crow", 9) + "swift" + t$ + CHR$(75) + s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(CHR$(86), 5, 4) + "?"); VAL(STR$(181)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "swift" = "tit" + STR$($316A) + "lark" + CHR$(67) + STR$(a%) + STR$(266): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(LEFT$(t$, 7), 0) + "robin" + "robin" + STR$(3) + "?"); VAL(STR$($E6A)): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(u$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(MID$(u$, 6), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(STR$(6595) + s$ + "lark" + "?"); VAL(STR$(d%)): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(u$, 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; STR$(98) + MID$(MID$(CHR$(75), 2), 2, 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$(MID$("jay", 4), 3, 2), 3, 2); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; STR$(180) + "wren" + u$ + MID$(t$, 3, 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$(LEFT$(u$, 0), 4, 4), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT STR$($72FC) > STR$(b%): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(t$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(67) = "jay": CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
