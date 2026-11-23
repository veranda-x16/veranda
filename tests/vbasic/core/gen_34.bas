' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 10 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -32.18 + 6.32
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ro", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
PRINT H$("owl", 5)
TRY: PRINT F%(4, 331): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-32.82); G(G(-35.80)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("rook", 1)
PRINT H$("tit", 5)
TRY: PRINT F%(3, 240): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("kite", 2)
Acc total%, F%(3, 17): PRINT total%
PRINT H$("crow", 2)
TRY: PRINT F%(4, 699): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-1.55); G(G(-7.89)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-31.64); G(G(-29.84)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 786): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 89): PRINT total%
Acc total%, F%(4, 59): PRINT total%
TRY: PRINT F%(4, 111): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 979): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 964): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(3, 56): PRINT total%
PRINT H$("rook", 5)
TRY: PRINT F%(4, 820): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-35.1); G(G(-13.8)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(27.3); G(G(-49.3)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 987): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(27.58); G(G(-14.58)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("rook", 0)
Acc total%, F%(1, 10): PRINT total%
PRINT total%
