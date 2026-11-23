' generated: loops, decisions and counters
c% = 0: t = 0
IF c% <> 135 THEN c% = c% \ 2 ELSE c% = c% + 9
FOR i1% = 1 TO 14 STEP 2: c% = c% + i1%: NEXT
j% = 0: WHILE j% < 11: j% = j% + 1: t = t + j% / 2: WEND
m% = 10: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i4% = -1 TO 3 STEP 3: c% = c% + i4%: NEXT
j% = 0: WHILE j% < 9: j% = j% + 1: t = t + j% / 2: WEND
j% = 0: WHILE j% < 16: j% = j% + 1: t = t + j% / 2: WEND
FOR i7% = 5 TO 5 STEP -1: c% = c% + i7%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
k% = 0: DO: k% = k% + 1: IF k% > 1 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 9; c%; t
j% = 0: WHILE j% < 12: j% = j% + 3: t = t + j% / 2: WEND
PRINT 10; c%; t
IF c% = 3 THEN c% = c% \ 2 ELSE c% = c% + 8
PRINT 11; c%; t
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 12; c%; t
FOR i13% = 3 TO 11 STEP -1: c% = c% + i13%: NEXT
FOR i14% = -4 TO 8: c% = c% + i14%: NEXT
m% = 11: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 15; c%; t
j% = 0: WHILE j% < 10: j% = j% + 1: t = t + j% / 2: WEND
k% = 0: DO: k% = k% + 1: IF k% > 9 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 17; c%; t
j% = 0: WHILE j% < 12: j% = j% + 2: t = t + j% / 2: WEND
PRINT 18; c%; t
PRINT c%; t
