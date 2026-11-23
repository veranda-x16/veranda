' generated: strings, the heap and its collector
s$ = "kite": t$ = "jay": u$ = ""
TRY: s$ = LEFT$(LEFT$(LEFT$(CHR$(73), 9), 5), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(70) + LEFT$("wren" + t$, 8); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(t$, 0); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(LEFT$(MID$("owl", 5), 8), 3); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("wren" + RIGHT$(CHR$(65), 5), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(73); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(CHR$(68), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; t$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(MID$(MID$("kite", 2), 6, 0), 3); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(MID$("swift" + STR$(%11000111), 2), 6, 2); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; MID$(STR$(283) + u$ + t$, 5); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$("tit", 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(RIGHT$(t$, 9) + u$, 6) <> "crow" + MID$("owl", 1, 3): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$("lark" + u$ + CHR$(76), 9); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(u$, 4) >= s$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(u$ + CHR$(83), 9) + RIGHT$(MID$("rook", 5), 0); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(CHR$(76), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$ + RIGHT$(STR$(b%), 6); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(77); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(LEFT$(u$, 3), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(s$ + t$, 4) + RIGHT$(LEFT$("swift", 3), 9); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(STR$(d%), 8) + "lark"; "]": CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
