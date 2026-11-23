' generated: loops, decisions and counters
c% = 0: t = 0
k% = 0: DO: k% = k% + 1: IF k% > 5 THEN EXIT DO
LOOP: c% = c% + k%
IF c% > 32 THEN c% = c% \ 2 ELSE c% = c% + 3
k% = 0: DO: k% = k% + 1: IF k% > 5 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 2; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 3; c%; t
m% = 19: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
PRINT 4; c%; t
j% = 0: WHILE j% < 20: j% = j% + 3: t = t + j% / 2: WEND
j% = 0: WHILE j% < 9: j% = j% + 1: t = t + j% / 2: WEND
j% = 0: WHILE j% < 10: j% = j% + 1: t = t + j% / 2: WEND
SELECT CASE c% MOD 4
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
PRINT 8; c%; t
k% = 0: DO: k% = k% + 1: IF k% > 4 THEN EXIT DO
LOOP: c% = c% + k%
SELECT CASE c% MOD 5
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
k% = 0: DO: k% = k% + 1: IF k% > 8 THEN EXIT DO
LOOP: c% = c% + k%
FOR i12% = 5 TO 2 STEP 2: c% = c% + i12%: NEXT
k% = 0: DO: k% = k% + 1: IF k% > 7 THEN EXIT DO
LOOP: c% = c% + k%
PRINT 13; c%; t
IF c% <> 132 THEN c% = c% \ 2 ELSE c% = c% + 5
PRINT 14; c%; t
FOR i15% = 0 TO 4 STEP 3: c% = c% + i15%: NEXT
FOR i16% = -4 TO -4 STEP 3: c% = c% + i16%: NEXT
SELECT CASE c% MOD 6
  CASE 0: t = t + 1
  CASE 1, 2: t = t * 1.5
  CASE IS > 4: t = t - 2
  CASE ELSE: c% = c% + 1
END SELECT
j% = 0: WHILE j% < 10: j% = j% + 2: t = t + j% / 2: WEND
m% = 1: REPEAT: m% = m% - 3: UNTIL m% < 0: t = t + m%
FOR i20% = 3 TO 10 STEP 2: c% = c% + i20%: NEXT
PRINT 20; c%; t
FOR i21% = 5 TO 0: c% = c% + i21%: NEXT
FOR i22% = 5 TO 7 STEP 3: c% = c% + i22%: NEXT
PRINT 22; c%; t
j% = 0: WHILE j% < 11: j% = j% + 1: t = t + j% / 2: WEND
PRINT 23; c%; t
PRINT c%; t
