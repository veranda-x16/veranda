' generated: loops, decisions and counters
c% = 0: t = 0
m% = 24: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
m% = 22: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 1; c%; t
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
m% = 29: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
FOR i6% = -2 TO 6 STEP 3: c% = c% + i6%: NEXT
PRINT 6; c%; t
m% = 9: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 7; c%; t
FOR i8% = 1 TO 12 STEP 2: c% = c% + i8%: NEXT
j% = 0: WHILE j% < 6: j% = j% + 1: t = t + j% / 2: WEND
PRINT 9; c%; t
FOR i10% = 3 TO 13: c% = c% + i10%: NEXT
PRINT 10; c%; t
FOR i11% = 2 TO 13: c% = c% + i11%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 3 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 12; c%; t
FOR i13% = 0 TO 7 STEP -1: c% = c% + i13%: NEXT
j% = 0: WHILE j% < 9: j% = j% + 3: t = t + j% / 2: WEND
PRINT 14; c%; t
FOR i15% = -2 TO 14 STEP 3: c% = c% + i15%: NEXT
FOR i16% = 3 TO 15 STEP 2: c% = c% + i16%: NEXT
PRINT 16; c%; t
FOR i17% = -3 TO 5 STEP 2: c% = c% + i17%: NEXT
PRINT 17; c%; t
FOR i18% = 1 TO 0 STEP 2: c% = c% + i18%: NEXT
PRINT 18; c%; t
FOR i19% = -2 TO 3 STEP 3: c% = c% + i19%: NEXT
j% = 0: WHILE j% < 8: j% = j% + 3: t = t + j% / 2: WEND
FOR i21% = 5 TO 9 STEP -1: c% = c% + i21%: NEXT
PRINT 21; c%; t
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 22; c%; t
m% = 5: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i24% = 0 TO 5: c% = c% + i24%: NEXT
PRINT 24; c%; t
PRINT c%; t
