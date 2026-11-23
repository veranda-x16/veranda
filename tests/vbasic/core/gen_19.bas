' generated: loops, decisions and counters
c% = 0: t = 0
j% = 0: WHILE j% < 4: j% = j% + 2: t = t + j% / 2: WEND
FOR i1% = 0 TO 0 STEP 3: c% = c% + i1%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 2
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 11: j% = j% + 3: t = t + j% / 2: WEND
PRINT 4; c%; t
FOR i5% = 3 TO 3 STEP -1: c% = c% + i5%: NEXT
FOR i6% = 3 TO 5 STEP -1: c% = c% + i6%: NEXT
FOR i7% = 0 TO 4: c% = c% + i7%: NEXT
PRINT 7; c%; t
m% = 6: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i9% = 0 TO 1: c% = c% + i9%: NEXT
m% = 14: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 10; c%; t
IF c% <= 136 THEN c% = c% \ 2 ELSE c% = c% + 2
IF c% <> 198 THEN c% = c% \ 2 ELSE c% = c% + 2
m% = 21: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
IF c% <> -5 THEN c% = c% \ 2 ELSE c% = c% + 1
j% = 0: WHILE j% < 7: j% = j% + 1: t = t + j% / 2: WEND
PRINT c%; t
