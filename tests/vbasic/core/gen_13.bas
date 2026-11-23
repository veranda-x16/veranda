' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 7 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -46.50 + 16.5
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "wr", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT F%(3, 89): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-38.22); G(G(19.29)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-40.8); G(G(14.89)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 513): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 334): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-24.71); G(G(-3.15)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 34): PRINT total%
TRY: PRINT G(37.31); G(G(-0.66)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(2, 74): PRINT total%
PRINT H$("wren", 6)
TRY: PRINT G(50.36); G(G(-40.84)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 93): PRINT total%
TRY: PRINT F%(0, 558): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(1, 16): PRINT total%
TRY: PRINT G(-41.58); G(G(15.16)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-23.6); G(G(33.69)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(10.78); G(G(5.34)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(0.49); G(G(28.98)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-34.22); G(G(-22.97)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 120): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 567): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 673): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
