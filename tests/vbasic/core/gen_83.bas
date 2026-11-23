' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 15 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -15.9 + 18.11
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ro", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT G(31.32); G(G(-17.69)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(20.97); G(G(14.2)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(37.81); G(G(-35.97)): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 91): PRINT total%
PRINT H$("jay", 4)
Acc total%, F%(4, 33): PRINT total%
TRY: PRINT F%(3, 586): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(2, 317): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("robin", 4)
TRY: PRINT G(-7.40); G(G(47.88)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(2.16); G(G(-36.10)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-1.0); G(G(-30.61)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(40.42); G(G(-33.72)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(3.39); G(G(26.76)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(29.11); G(G(-33.35)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(24.22); G(G(0.32)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-10.76); G(G(-18.99)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(8, 164): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(4, 741): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(15.36); G(G(45.38)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-7.78); G(G(-9.71)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 98): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 931): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-30.8); G(G(0.42)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("kite", 5)
Acc total%, F%(1, 12): PRINT total%
Acc total%, F%(3, 42): PRINT total%
PRINT total%
