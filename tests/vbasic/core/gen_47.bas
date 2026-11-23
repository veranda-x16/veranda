' generated: loops, decisions and counters
c% = 0: t = 0
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 0; c%; t
m% = 16: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 1; c%; t
FOR i2% = 2 TO 8 STEP -1: c% = c% + i2%: NEXT
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 3; c%; t
IF c% < 0 THEN c% = c% \ 2 ELSE c% = c% + 1
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 12: j% = j% + 3: t = t + j% / 2: WEND
PRINT 6; c%; t
FOR i7% = -5 TO 13: c% = c% + i7%: NEXT
SELECT CASE c% MOD 3
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 8; c%; t
FOR i9% = 2 TO -3: c% = c% + i9%: NEXT
PRINT 9; c%; t
FOR i10% = -3 TO 5 STEP 2: c% = c% + i10%: NEXT
PRINT 10; c%; t
IF c% <= 22 THEN c% = c% \ 2 ELSE c% = c% + 5
FOR i12% = -1 TO 4 STEP -1: c% = c% + i12%: NEXT
PRINT c%; t
