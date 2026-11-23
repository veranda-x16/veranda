' generated: strings, the heap and its collector
s$ = "swift": t$ = "jay": u$ = ""
TRY: PRINT MID$(MID$("kite", 4) + MID$("crow", 5, 1), 3) <= LEFT$(LEFT$(CHR$(79), 2), 4) + MID$(MID$(t$, 5), 1): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "jay"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(MID$("crow", 1, 4) + MID$("owl", 5, 2), 4, 3) + "?"); VAL(STR$(216)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(CHR$(83), 3) < MID$("jay", 5): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$("owl", 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(CHR$(67) + s$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$("swift", 6), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$(s$, 6, 3), 4) + LEFT$(STR$(76) + "kite", 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(RIGHT$("rook", 1), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT s$ > MID$("swift" + STR$(%10111) + "swift", 4, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(LEFT$(CHR$(66), 7), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(STR$($35D1), 6) > CHR$(88): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(s$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(CHR$(84), 5) + u$ + t$ + "?"); VAL(STR$(205)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(t$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$("lark", 6), 6, 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "swift" <= LEFT$(LEFT$(STR$(259) + CHR$(83), 2), 4): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "rook"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "wren" + s$ + u$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(STR$($1B57) + STR$(%1011110) + MID$("lark", 4, 4) + "?"); VAL(STR$(d%)): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$("owl" + "rook", 6, 1), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "wren"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(STR$(292) + "?"); VAL(STR$(150)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; u$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(LEFT$("kite" + CHR$(78), 1), 4, 6) + "?"); VAL(STR$($5EE7)): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$(t$, 3), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT u$ + CHR$(75) + STR$(87) + s$ >= "tit" + STR$(26078): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
