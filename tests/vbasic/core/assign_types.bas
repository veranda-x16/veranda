' assignment converts between integers and floats
a% = 3.7: PRINT a%
a% = -3.7: PRINT a%
b = 7: PRINT b; b / 2
c% = 32767.9: PRINT c%
TRY
  c% = 32768
CATCH
  PRINT "overflow:"; ERR; ERR$
END TRY
TRY
  d$ = 5
CATCH
  PRINT "type:"; ERR; ERR$
END TRY
TRY
  e = "x"
CATCH
  PRINT "type:"; ERR
END TRY
LET f% = 12: LET g$ = "let": PRINT f%; g$
