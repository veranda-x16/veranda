' generated: loops, decisions and counters
c% = 0: t = 0
IF c% >= 165 THEN c% = c% \ 2 ELSE c% = c% + 7
FOR i1% = 5 TO 13 STEP 2: c% = c% + i1%: NEXT
PRINT 1; c%; t
FOR i2% = -4 TO 13 STEP 2: c% = c% + i2%: NEXT
PRINT 2; c%; t
j% = 0: WHILE j% < 14: j% = j% + 3: t = t + j% / 2: WEND
PRINT 3; c%; t
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 5; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
m% = 12: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i8% = 3 TO -1 STEP -1: c% = c% + i8%: NEXT
PRINT 8; c%; t
IF c% < 52 THEN c% = c% \ 2 ELSE c% = c% + 3
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
j% = 0: WHILE j% < 10: j% = j% + 1: t = t + j% / 2: WEND
FOR i12% = -3 TO 14 STEP -1: c% = c% + i12%: NEXT
PRINT 12; c%; t
IF c% < -13 THEN c% = c% \ 2 ELSE c% = c% + 2
PRINT 13; c%; t
j% = 0: WHILE j% < 16: j% = j% + 2: t = t + j% / 2: WEND
j% = 0: WHILE j% < 7: j% = j% + 3: t = t + j% / 2: WEND
m% = 13: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
j% = 0: WHILE j% < 20: j% = j% + 3: t = t + j% / 2: WEND
IF c% <= 177 THEN c% = c% \ 2 ELSE c% = c% + 1
IF c% <= 50 THEN c% = c% \ 2 ELSE c% = c% + 5
PRINT 19; c%; t
m% = 19: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i21% = -4 TO 6 STEP 2: c% = c% + i21%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 7 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 22; c%; t
FOR i23% = -1 TO 7: c% = c% + i23%: NEXT
PRINT 23; c%; t
j% = 0: WHILE j% < 8: j% = j% + 2: t = t + j% / 2: WEND
PRINT c%; t
