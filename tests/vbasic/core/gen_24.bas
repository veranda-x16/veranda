' generated: strings, the heap and its collector
s$ = "robin": t$ = "wren": u$ = ""
TRY: PRINT u$ > CHR$(71) + STR$($2012) + "wren" + STR$(b%): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT MID$(LEFT$("owl" + CHR$(72), 1), 3) > "crow" + "kite": CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(STR$(27128) + MID$(CHR$(65), 3, 2), 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT "owl" > u$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(LEFT$(MID$(CHR$(75), 4), 0) + "jay" + "?"); VAL(STR$(4)): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(RIGHT$(LEFT$("swift" + STR$(16), 5), 7), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(STR$(28592), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: t$ = LEFT$(STR$(222) + CHR$(83) + "swift" + STR$(%10100), 60): PRINT LEN(t$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT LEFT$(MID$(RIGHT$(u$, 4), 5, 4), 9) >= RIGHT$(MID$(MID$(CHR$(79), 5, 3), 2, 3), 1): CATCH: PRINT "error"; ERR: END TRY
TRY: u$ = LEFT$(t$, 60): PRINT LEN(u$): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT RIGHT$(MID$(STR$(237), 1), 9) + RIGHT$(t$, 6) >= t$: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT ASC(MID$(RIGHT$(t$, 6), 3, 0) + "?"); VAL(STR$(251)): CATCH: PRINT "error"; ERR: END TRY
PRINT s$; "|"; t$; "|"; u$
