' the heap: many strings made and dropped (the collector runs)
OPTION MEMORY 4
DIM w$(50)
FOR i% = 0 TO 50: w$(i%) = "item" + STR$(i%): NEXT
total% = 0
FOR round% = 1 TO 40
  FOR i% = 0 TO 50
    w$(i%) = LEFT$(w$(i%) + "........................................", 30 + (i% + round%) MOD 20)
    total% = total% + LEN(w$(i%)) MOD 7
  NEXT
  junk$ = Letters$(round%)
NEXT
PRINT total%; junk$
FOR i% = 0 TO 50 STEP 10: PRINT i%; LEN(w$(i%)); LEFT$(w$(i%), 8): NEXT
FUNCTION Letters$(n%)
  LOCAL s$, k%
  FOR k% = 1 TO n%: s$ = s$ + CHR$(65 + k% MOD 26): NEXT
  Letters$ = s$
END FUNCTION
