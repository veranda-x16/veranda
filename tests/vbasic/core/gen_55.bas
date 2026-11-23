' generated: SUBs and FUNCTIONs with parameters, locals, recursion
total% = 0
FUNCTION F%(a%, b%)
  LOCAL t%
  t% = (a% * 16 + b%) MOD 1000
  IF a% > 0 THEN t% = t% + F%(a% - 1, b% \ 2)
  F% = t%
END FUNCTION
FUNCTION G(x)
  G = x * -42.25 + 5.8
END FUNCTION
FUNCTION H$(s$, n%)
  IF n% <= 0 THEN RETURN s$
  H$ = H$(LEFT$(s$ + "ro", 30), n% - 1)
END FUNCTION
SUB Acc(BYREF v%, d%)
  v% = (v% + d%) MOD 30000
END SUB
Acc total%, F%(3, 66): PRINT total%
Acc total%, F%(1, 57): PRINT total%
TRY: PRINT G(8.99); G(G(8.79)): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("swift", 3)
TRY: PRINT F%(2, 924): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("swift", 5)
Acc total%, F%(4, 8): PRINT total%
TRY: PRINT F%(1, 721): CATCH: PRINT "error"; ERR: END TRY
Acc total%, F%(3, 26): PRINT total%
Acc total%, F%(1, 62): PRINT total%
TRY: PRINT F%(2, 66): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT F%(8, 6): CATCH: PRINT "error"; ERR: END TRY
PRINT H$("owl", 4)
PRINT H$("swift", 4)
Acc total%, F%(4, 36): PRINT total%
Acc total%, F%(3, 47): PRINT total%
Acc total%, F%(2, 10): PRINT total%
Acc total%, F%(4, 37): PRINT total%
TRY: PRINT G(-42.5); G(G(-31.67)): CATCH: PRINT "error"; ERR: END TRY
PRINT total%
