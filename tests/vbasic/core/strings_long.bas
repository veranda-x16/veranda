' strings up to 255 characters
s$ = ""
FOR i% = 1 TO 25: s$ = s$ + "abcdefghij": NEXT
PRINT LEN(s$)
s$ = s$ + "12345": PRINT LEN(s$); RIGHT$(s$, 7)
TRY
  s$ = s$ + "x"
CATCH
  PRINT "caught"; ERR; ERR$
END TRY
PRINT LEN(s$)
t$ = MID$(s$, 100, 20): PRINT t$
