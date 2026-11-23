' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 16 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * 34.66 + -14.70
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "sw", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT F%(8, 973): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("owl", 6)
PRINT H$("owl", 4)
TRY: PRINT F%(2, 864): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 18): PRINT total%
Acc total%, F%(3, 50): PRINT total%
TRY: PRINT G(-41.70); G(G(42.20)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-23.42); G(G(-48.14)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 75): PRINT total%
TRY: PRINT G(-18.77); G(G(-14.22)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(1, 989): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 646): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 455): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-4.78); G(G(30.34)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 53): PRINT total%
PRINT H$("crow", 3)
TRY: PRINT G(32.55); G(G(15.78)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(28.79); G(G(23.64)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(4.80); G(G(-12.60)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 46): PRINT total%
PRINT H$("wren", 2)
PRINT H$("tit", 2)
TRY: PRINT G(15.7); G(G(36.26)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 688): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 54): PRINT total%
PRINT total%
