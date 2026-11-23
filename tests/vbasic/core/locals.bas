' LOCAL and SHARED; a global seen from a SUB
total% = 10
count% = 0
SUB AddUp(n%)
  LOCAL count%
  count% = n% * 2
  total% = total% + count%
  PRINT "inside"; count%; total%
END SUB
SUB Bump
  SHARED count%
  count% = count% + 1
END SUB
AddUp 5: AddUp 1
PRINT "outside"; count%; total%
CALL Bump: Bump: PRINT count%
SUB Deep(n%)
  LOCAL s$
  s$ = "level" + STR$(n%)
  IF n% < 3 THEN Deep n% + 1
  PRINT s$
END SUB
Deep 1
