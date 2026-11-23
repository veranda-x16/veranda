' generated: strings, the heap and its collector
s$ = "jay": t$ = "tit": u$ = ""
TRY: PRINT "["; t$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$(t$ + CHR$(74), 1), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "jay"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(t$ + t$, 5), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(s$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$("tit", 2) + s$ + CHR$(90), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT s$ > MID$("jay", 2, 4) + CHR$(65): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$(u$, 6) + MID$("wren", 2, 3), 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(s$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("swift", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(STR$($F893), 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$("wren" + LEFT$(CHR$(68), 8), 6), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "owl" >= CHR$(78): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(t$, 3) + MID$(s$, 4, 0) + CHR$(88) + t$ + "?"); VAL(STR$($505)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "swift" < MID$(LEFT$(CHR$(79), 2) + LEFT$(s$, 9), 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC("jay" + LEFT$("jay" + STR$(264), 5) + "?"); VAL(STR$(145)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(CHR$(85) + "lark", 3, 0) + LEFT$(CHR$(70), 8); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(RIGHT$("kite", 1), 6) + CHR$(65); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(LEFT$("rook", 1), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
