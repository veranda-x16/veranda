' generated: loops, decisions and counters
c% = 0: t = 0
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i1% = 1 TO 4 STEP -1: c% = c% + i1%: NEXT
FOR i2% = -2 TO 5: c% = c% + i2%: NEXT
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 3; c%; t
SELECT CASE c% MOD 4
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i5% = 4 TO 13 STEP 3: c% = c% + i5%: NEXT
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i7% = -3 TO 12 STEP -1: c% = c% + i7%: NEXT
PRINT 7; c%; t
IF c% > 73 THEN c% = c% \ 2 ELSE c% = c% + 9
PRINT 8; c%; t
FOR i9% = 1 TO 1: c% = c% + i9%: NEXT
FOR i10% = -1 TO 5 STEP -1: c% = c% + i10%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
k% = 0: DO: k% = k% + 1: IF k% > 9 THEN EXIT DO
LOOP: c% = c% + k%
FOR i14% = -4 TO 8: c% = c% + i14%: NEXT
SELECT CASE c% MOD 4
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 15; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 16; c%; t
FOR i17% = 4 TO -5: c% = c% + i17%: NEXT
PRINT 17; c%; t
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i19% = 0 TO 6 STEP 3: c% = c% + i19%: NEXT
PRINT c%; t
