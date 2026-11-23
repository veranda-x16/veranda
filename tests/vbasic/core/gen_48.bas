' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 9 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -43.41 + -15.64
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "la", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT F%(3, 148): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 33): PRINT total%
PRINT H$("crow", 4)
TRY: PRINT G(-3.14); G(G(44.74)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("jay", 4)
PRINT H$("kite", 6)
TRY: PRINT F%(2, 941): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 17): PRINT total%
TRY: PRINT G(50.33); G(G(15.89)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("swift", 4)
Acc total%, F%(3, 23): PRINT total%
TRY: PRINT G(-36.60); G(G(-3.81)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 99): PRINT total%
TRY: PRINT F%(6, 733): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("crow", 6)
Acc total%, F%(2, 61): PRINT total%
TRY: PRINT F%(6, 882): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 16): PRINT total%
PRINT H$("kite", 1)
Acc total%, F%(1, 54): PRINT total%
Acc total%, F%(0, 64): PRINT total%
TRY: PRINT F%(8, 235): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(5, 534): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 10): PRINT total%
PRINT H$("rook", 5)
TRY: PRINT G(-31.9); G(G(-28.21)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-40.11); G(G(-11.91)): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
