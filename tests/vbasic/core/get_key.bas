' GET: the next key, without waiting
k$ = ""
REPEAT: GET k$: UNTIL k$ <> ""
PRINT "key "; k$; ASC(k$)
REPEAT: GET k$: UNTIL k$ <> ""
PRINT "key "; k$
s$ = ""
FOR i% = 1 TO 3
  REPEAT: k$ = INKEY$: UNTIL k$ <> ""
  s$ = s$ + k$
NEXT
PRINT s$
