' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 6 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * 20.36 + 47.58
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "wr", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT G(-42.43); G(G(-26.58)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(8, 735): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 102): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("lark", 5)
TRY: PRINT G(25.98); G(G(-3.68)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 90): PRINT total%
TRY: PRINT F%(8, 325): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-6.71); G(G(-19.15)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(7, 915): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 47): PRINT total%
TRY: PRINT G(-47.59); G(G(-7.79)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("wren", 6)
TRY: PRINT G(-11.54); G(G(42.8)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("lark", 5)
TRY: PRINT G(42.40); G(G(24.61)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 282): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 941): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("owl", 6)
PRINT H$("lark", 4)
TRY: PRINT G(-50.60); G(G(-17.43)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 30): PRINT total%
PRINT H$("jay", 0)
PRINT total%
