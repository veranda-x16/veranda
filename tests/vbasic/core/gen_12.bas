' generated: loops, decisions and counters
c% = 0: t = 0
m% = 5: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 0; c%; t
FOR i1% = 1 TO 2: c% = c% + i1%: NEXT
PRINT 1; c%; t
j% = 0: WHILE j% < 5: j% = j% + 3: t = t + j% / 2: WEND
FOR i3% = 1 TO 14 STEP 2: c% = c% + i3%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 7 THEN EXIT DO
LOOP: c% = c% + k%
j% = 0: WHILE j% < 10: j% = j% + 3: t = t + j% / 2: WEND
FOR i6% = 0 TO -1 STEP -1: c% = c% + i6%: NEXT
PRINT 6; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 4 THEN EXIT DO
LOOP: c% = c% + k%
j% = 0: WHILE j% < 8: j% = j% + 3: t = t + j% / 2: WEND
PRINT 8; c%; t
j% = 0: WHILE j% < 14: j% = j% + 1: t = t + j% / 2: WEND
PRINT 9; c%; t
j% = 0: WHILE j% < 9: j% = j% + 2: t = t + j% / 2: WEND
j% = 0: WHILE j% < 1: j% = j% + 2: t = t + j% / 2: WEND
IF c% > 165 THEN c% = c% \ 2 ELSE c% = c% + 5
m% = 0: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
k% = 0: DO: k% = k% + 1: IF k% > 2 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 14; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 2 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 15; c%; t
FOR i16% = -4 TO 6: c% = c% + i16%: NEXT
PRINT 16; c%; t
IF c% = 36 THEN c% = c% \ 2 ELSE c% = c% + 6
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
m% = 10: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 19; c%; t
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT c%; t
