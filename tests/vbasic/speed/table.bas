' gate vb_speed: the plan's section 3.3 table, timed with the emulator's
' cycle counter ($9FB8-$9FBB, 8 MHz cycles; reading $9FB8 latches the four
' bytes); each line "T name cycles count"
b% = 3: t$ = "abcdefghij": z = 1
GOSUB Clock: c0 = c
FOR i% = 1 TO 10000: NEXT
GOSUB Clock: PRINT "T for_empty"; c - c0; 10000
GOSUB Clock: c0 = c
FOR i% = 1 TO 5000: a% = a% + b% * 2: NEXT
GOSUB Clock: PRINT "T int_assign"; c - c0; 5000
GOSUB Clock: c0 = c
FOR i% = 1 TO 2000: z = z * 1.0001: NEXT
GOSUB Clock: PRINT "T float_mul"; c - c0; 2000
GOSUB Clock: c0 = c
FOR i% = 1 TO 2000: Two 1, 2: NEXT
GOSUB Clock: PRINT "T sub_call"; c - c0; 2000
GOSUB Clock: c0 = c
FOR i% = 1 TO 10000
NEXT
GOSUB Clock: PRINT "T for_two_lines"; c - c0; 10000
GOSUB Clock: c0 = c
FOR i% = 1 TO 10000: GOTO 9000
9000 NEXT
GOSUB Clock: PRINT "T goto"; c - c0; 10000
GOSUB Clock: c0 = c
FOR i% = 1 TO 2000: s$ = LEFT$(t$, 5) + "x": NEXT
GOSUB Clock: PRINT "T string"; c - c0; 2000
GOSUB Clock: c0 = c
FOR i% = 1 TO 2000: NEXT
GOSUB Clock: PRINT "T for_2000"; c - c0; 2000
GOSUB Clock: c0 = c
GOSUB Clock: PRINT "T clock"; c - c0; 1
END
SUB Two(p%, q%)
END SUB
Clock: c = PEEK($9FB8) + 256 * PEEK($9FB9) + 65536 * PEEK($9FBA) + 16777216 * PEEK($9FBB): RETURN
