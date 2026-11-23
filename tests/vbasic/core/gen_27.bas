' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 14 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -3.72 + 30.64
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ja", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
Acc total%, F%(2, 40): PRINT total%
TRY: PRINT G(46.47); G(G(49.9)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("lark", 3)
TRY: PRINT F%(3, 345): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 213): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-5.25); G(G(49.52)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(5, 774): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 31): PRINT total%
PRINT H$("lark", 6)
PRINT H$("jay", 4)
TRY: PRINT G(40.81); G(G(-3.94)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("rook", 1)
PRINT H$("robin", 0)
TRY: PRINT F%(4, 270): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
