' the collector with locals, parameters and temporaries alive
FUNCTION Pad$(s$, n%)
  LOCAL t$
  t$ = s$
  WHILE LEN(t$) < n%: t$ = t$ + "*": WEND
  Pad$ = t$
END FUNCTION
SUB Churn(depth%, s$)
  LOCAL x$
  x$ = Pad$(s$, 40 + depth%)
  IF depth% > 0 THEN Churn depth% - 1, x$ + STR$(depth%)
  IF depth% MOD 5 = 0 THEN PRINT depth%; LEN(x$); RIGHT$(x$, 12)
END SUB
FOR r% = 1 TO 12
  Churn 20, "start" + STR$(r%)
NEXT
PRINT "done"
