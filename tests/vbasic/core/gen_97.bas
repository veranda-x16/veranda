' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 26 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -27.57 + -0.13
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ki", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
Acc total%, F%(3, 34): PRINT total%
Acc total%, F%(4, 96): PRINT total%
TRY: PRINT G(24.85); G(G(-10.95)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 905): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("tit", 0)
PRINT H$("tit", 4)
TRY: PRINT F%(8, 52): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 2): PRINT total%
TRY: PRINT F%(6, 940): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(1, 486): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(38.74); G(G(-44.91)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-12.22); G(G(20.17)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-41.74); G(G(-29.49)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("crow", 6)
PRINT H$("rook", 1)
TRY: PRINT G(29.93); G(G(-22.6)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 60): PRINT total%
Acc total%, F%(4, 76): PRINT total%
TRY: PRINT F%(0, 333): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 60): PRINT total%
TRY: PRINT G(-36.11); G(G(23.48)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("lark", 3)
TRY: PRINT F%(8, 55): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 254): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 12): PRINT total%
Acc total%, F%(4, 32): PRINT total%
Acc total%, F%(1, 93): PRINT total%
PRINT total%
