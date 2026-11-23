' generated: loops, decisions and counters
c% = 0: t = 0
j% = 0: WHILE j% < 19: j% = j% + 3: t = t + j% / 2: WEND
PRINT 0; c%; t
IF c% = -16 THEN c% = c% \ 2 ELSE c% = c% + 2
k% = 0: DO: k% = k% + 1: IF k% > 9 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 3; c%; t
FOR i4% = -3 TO 11 STEP 3: c% = c% + i4%: NEXT
FOR i5% = 4 TO 4 STEP -1: c% = c% + i5%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 16: j% = j% + 1: t = t + j% / 2: WEND
FOR i9% = 1 TO 0 STEP 2: c% = c% + i9%: NEXT
PRINT 9; c%; t
FOR i10% = 5 TO 12 STEP 3: c% = c% + i10%: NEXT
PRINT 10; c%; t
m% = 27: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 11; c%; t
j% = 0: WHILE j% < 12: j% = j% + 3: t = t + j% / 2: WEND
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 13; c%; t
SELECT CASE c% MOD 3
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
m% = 28: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i19% = -4 TO 0 STEP 2: c% = c% + i19%: NEXT
PRINT 19; c%; t
j% = 0: WHILE j% < 12: j% = j% + 2: t = t + j% / 2: WEND
FOR i21% = -3 TO 6 STEP 3: c% = c% + i21%: NEXT
PRINT c%; t
