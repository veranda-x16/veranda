' a recursion too deep: Stack overflow, caught
SUB Forever(n%)
  LOCAL a, b, c, d
  Forever n% + 1
END SUB
TRY
  Forever 1
CATCH
  PRINT "caught"; ERR; ERR$
END TRY
PRINT "on"
