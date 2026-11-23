' generated: loops, decisions and counters
c% = 0: t = 0
IF c% <= 66 THEN c% = c% \ 2 ELSE c% = c% + 5
PRINT 0; c%; t
j% = 0: WHILE j% < 10: j% = j% + 2: t = t + j% / 2: WEND
j% = 0: WHILE j% < 6: j% = j% + 2: t = t + j% / 2: WEND
IF c% > 106 THEN c% = c% \ 2 ELSE c% = c% + 8
PRINT 3; c%; t
FOR i4% = -3 TO 4: c% = c% + i4%: NEXT
PRINT 4; c%; t
IF c% > 2 THEN c% = c% \ 2 ELSE c% = c% + 9
PRINT 5; c%; t
FOR i6% = -4 TO 10: c% = c% + i6%: NEXT
FOR i7% = 0 TO 7: c% = c% + i7%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 0 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 8; c%; t
j% = 0: WHILE j% < 9: j% = j% + 1: t = t + j% / 2: WEND
j% = 0: WHILE j% < 20: j% = j% + 2: t = t + j% / 2: WEND
PRINT 10; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 5 THEN EXIT DO
LOOP: c% = c% + k%
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
FOR i13% = -4 TO 5 STEP 3: c% = c% + i13%: NEXT
PRINT 13; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 3 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 14; c%; t
SELECT CASE c% MOD 7
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
IF c% <> 83 THEN c% = c% \ 2 ELSE c% = c% + 9
IF c% = -6 THEN c% = c% \ 2 ELSE c% = c% + 9
PRINT c%; t
