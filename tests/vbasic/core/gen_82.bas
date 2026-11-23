' generated: loops, decisions and counters
c% = 0: t = 0
FOR i0% = 2 TO 9 STEP 3: c% = c% + i0%: NEXT
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i2% = -2 TO 7 STEP 2: c% = c% + i2%: NEXT
PRINT 2; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 2 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 3; c%; t
j% = 0: WHILE j% < 0: j% = j% + 3: t = t + j% / 2: WEND
m% = 1: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
k% = 0: DO: k% = k% + 1: IF k% > 9 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 6; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 9 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 8; c%; t
m% = 27: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i10% = -2 TO 13 STEP -1: c% = c% + i10%: NEXT
PRINT 10; c%; t
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 11; c%; t
m% = 10: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
IF c% < 47 THEN c% = c% \ 2 ELSE c% = c% + 5
FOR i14% = -4 TO -5 STEP 2: c% = c% + i14%: NEXT
FOR i15% = 4 TO 11 STEP -1: c% = c% + i15%: NEXT
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT c%; t
