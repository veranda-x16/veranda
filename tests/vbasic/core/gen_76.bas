' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 22 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * 24.29 + 31.56
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "wr", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT G(-9.70); G(G(-49.37)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-30.10); G(G(-35.85)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 172): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 717): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("swift", 4)
TRY: PRINT F%(6, 469): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 545): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("kite", 6)
TRY: PRINT G(35.8); G(G(18.10)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(1, 905): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("kite", 0)
PRINT H$("owl", 0)
TRY: PRINT F%(3, 583): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(45.18); G(G(30.8)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("swift", 3)
TRY: PRINT F%(6, 100): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(31.75); G(G(28.31)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("kite", 0)
Acc total%, F%(0, 4): PRINT total%
TRY: PRINT G(42.75); G(G(-4.72)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 456): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
