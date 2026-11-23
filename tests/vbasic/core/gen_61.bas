' generated: loops, decisions and counters
c% = 0: t = 0
FOR i0% = -4 TO 15 STEP 3: c% = c% + i0%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 0 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 1; c%; t
j% = 0: WHILE j% < 10: j% = j% + 3: t = t + j% / 2: WEND
PRINT 2; c%; t
FOR i3% = -1 TO 13: c% = c% + i3%: NEXT
PRINT 3; c%; t
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
SELECT CASE c% MOD 4
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 4: j% = j% + 2: t = t + j% / 2: WEND
PRINT 6; c%; t
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 7; c%; t
FOR i8% = -5 TO 12 STEP -1: c% = c% + i8%: NEXT
PRINT 8; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 4 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 9; c%; t
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
m% = 7: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 11; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 3 THEN EXIT DO
LOOP: c% = c% + k%
PRINT c%; t
