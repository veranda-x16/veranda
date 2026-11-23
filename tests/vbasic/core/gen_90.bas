' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 5 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -1.97 + 32.4
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "wr", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
TRY: PRINT F%(4, 462): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 353): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(4, 80): PRINT total%
PRINT H$("owl", 2)
Acc total%, F%(1, 22): PRINT total%
TRY: PRINT G(24.43); G(G(-1.53)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(0, 349): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(-35.14); G(G(25.11)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("jay", 1)
TRY: PRINT F%(4, 466): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(3, 978): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT G(50.15); G(G(-48.50)): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(6, 978): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(0, 99): PRINT total%
Acc total%, F%(1, 11): PRINT total%
PRINT total%
