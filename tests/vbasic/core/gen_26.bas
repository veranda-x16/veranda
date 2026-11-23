' generated: loops, decisions and counters
c% = 0: t = 0
m% = 0: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i1% = 5 TO 4 STEP 3: c% = c% + i1%: NEXT
FOR i2% = -3 TO 1 STEP 3: c% = c% + i2%: NEXT
PRINT 2; c%; t
SELECT CASE c% MOD 4
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 3; c%; t
FOR i4% = -3 TO 0 STEP 2: c% = c% + i4%: NEXT
PRINT 4; c%; t
FOR i5% = -5 TO 6 STEP -1: c% = c% + i5%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 2 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 6; c%; t
IF c% = -1 THEN c% = c% \ 2 ELSE c% = c% + 5
IF c% >= 127 THEN c% = c% \ 2 ELSE c% = c% + 9
PRINT 8; c%; t
FOR i9% = -3 TO -4 STEP 2: c% = c% + i9%: NEXT
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 9: j% = j% + 2: t = t + j% / 2: WEND
m% = 2: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 12; c%; t
FOR i13% = 4 TO 12 STEP 3: c% = c% + i13%: NEXT
PRINT 13; c%; t
FOR i14% = 0 TO 1 STEP 2: c% = c% + i14%: NEXT
PRINT 14; c%; t
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 15; c%; t
FOR i16% = 4 TO 13 STEP 2: c% = c% + i16%: NEXT
PRINT 16; c%; t
FOR i17% = -3 TO 8 STEP 3: c% = c% + i17%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 0 THEN EXIT DO
LOOP: c% = c% + k%
m% = 27: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i20% = 4 TO 13 STEP -1: c% = c% + i20%: NEXT
j% = 0: WHILE j% < 7: j% = j% + 1: t = t + j% / 2: WEND
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i23% = 5 TO 14 STEP 2: c% = c% + i23%: NEXT
PRINT 23; c%; t
FOR i24% = 4 TO 9 STEP -1: c% = c% + i24%: NEXT
m% = 10: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
k% = 0: DO: k% = k% + 1: IF k% > 0 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 26; c%; t
j% = 0: WHILE j% < 16: j% = j% + 2: t = t + j% / 2: WEND
PRINT 27; c%; t
PRINT c%; t
