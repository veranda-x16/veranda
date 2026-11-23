' generated: strings, the heap and its collector
s$ = "jay": t$ = "lark": u$ = ""
TRY: PRINT MID$(LEFT$("swift", 9) + STR$($367), 5) > MID$(MID$(u$, 6), 6, 0): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(s$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(LEFT$("robin", 9), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$("swift", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(MID$(CHR$(75), 4, 3), 8) + "kite", 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(s$ + CHR$(68), 2) + RIGHT$(t$ + u$, 6) >= s$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; STR$(83); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(MID$(CHR$(71) + RIGHT$(CHR$(87), 4), 1), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; CHR$(73); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; "kite"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$("tit" + STR$($81D9) + u$ + t$, 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(t$ + CHR$(65), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$("crow", 5) + MID$(u$, 4, 3) + CHR$(83), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; u$ + STR$(%1101111); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; LEFT$(t$, 7) + s$ + STR$(61) + s$ + "owl"; "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$("swift", 6, 6) + MID$(t$, 6, 6), 9); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT CHR$(72) <> CHR$(90) + CHR$(77): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(s$, 2) <= "kite": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(LEFT$("jay", 6), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(s$, 7) + u$ + LEFT$(RIGHT$(CHR$(86), 4), 4); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$("jay", 4) <> CHR$(73) + LEFT$("tit", 5): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; s$ + MID$(LEFT$("crow", 8), 1); "]": CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(STR$(217), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: s$ = LEFT$(MID$(MID$(CHR$(66), 4, 0), 6, 5) + CHR$(82), 60): PRINT LEN(s$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "["; RIGHT$(MID$(t$, 6) + "tit", 9); "]": CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
