' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 15 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -33.66 + -32.29
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ti", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
PRINT H$("kite", 5)
Acc total%, F%(1, 36): PRINT total%
Acc total%, F%(4, 7): PRINT total%
TRY: PRINT G(30.78); G(G(17.79)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 182): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 362): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(3, 74): PRINT total%
Acc total%, F%(2, 39): PRINT total%
Acc total%, F%(3, 85): PRINT total%
TRY: PRINT F%(8, 451): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(3, 46): PRINT total%
TRY: PRINT F%(3, 416): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("owl", 0)
TRY: PRINT G(34.65); G(G(-1.37)): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
