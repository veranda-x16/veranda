' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 2 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * 11.19 + -40.93
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ki", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT F%(0, 165): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 45): PRINT total%
Acc total%, F%(3, 49): PRINT total%
TRY: PRINT G(49.14); G(G(-13.96)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(1, 94): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(7, 636): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 54): PRINT total%
PRINT H$("kite", 1)
Acc total%, F%(1, 29): PRINT total%
Acc total%, F%(4, 50): PRINT total%
PRINT H$("lark", 1)
TRY: PRINT G(-29.39); G(G(47.95)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 23): PRINT total%
TRY: PRINT F%(2, 529): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("lark", 4)
TRY: PRINT F%(0, 641): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(45.16); G(G(30.49)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 81): PRINT total%
TRY: PRINT F%(8, 930): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 91): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("tit", 2)
TRY: PRINT F%(3, 819): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 989): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(16.3); G(G(15.75)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(5, 664): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(5, 707): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 78): PRINT total%
TRY: PRINT G(-23.74); G(G(36.43)): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
