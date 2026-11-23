' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 24 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -34.66 + -8.28
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ja", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
PRINT H$("jay", 6)
TRY: PRINT G(22.70); G(G(36.70)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(32.40); G(G(29.61)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 34): PRINT total%
Acc total%, F%(1, 77): PRINT total%
TRY: PRINT G(-6.2); G(G(29.72)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 6): PRINT total%
TRY: PRINT G(-29.27); G(G(-21.25)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(8, 662): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(1, 972): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("owl", 5)
TRY: PRINT G(-50.73); G(G(-34.12)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-33.91); G(G(-7.70)): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
