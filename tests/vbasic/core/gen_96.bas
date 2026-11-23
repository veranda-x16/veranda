' generated: loops, decisions and counters
c% = 0: t = 0
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 1; c%; t
j% = 0: WHILE j% < 13: j% = j% + 2: t = t + j% / 2: WEND
j% = 0: WHILE j% < 9: j% = j% + 3: t = t + j% / 2: WEND
PRINT 3; c%; t
SELECT CASE c% MOD 3
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 4; c%; t
FOR i5% = 1 TO -1: c% = c% + i5%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 2 THEN EXIT DO
LOOP: c% = c% + k%
IF c% > 163 THEN c% = c% \ 2 ELSE c% = c% + 7
PRINT 7; c%; t
FOR i8% = -2 TO 4 STEP 2: c% = c% + i8%: NEXT
IF c% < 34 THEN c% = c% \ 2 ELSE c% = c% + 2
FOR i10% = -4 TO 12 STEP 2: c% = c% + i10%: NEXT
PRINT 10; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 11; c%; t
FOR i12% = -3 TO 10: c% = c% + i12%: NEXT
FOR i13% = 5 TO 0 STEP 2: c% = c% + i13%: NEXT
IF c% <> 124 THEN c% = c% \ 2 ELSE c% = c% + 9
PRINT 14; c%; t
FOR i15% = 5 TO -1 STEP -1: c% = c% + i15%: NEXT
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 16; c%; t
FOR i17% = 5 TO 8: c% = c% + i17%: NEXT
PRINT 17; c%; t
PRINT c%; t
