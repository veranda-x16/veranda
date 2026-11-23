' floats: the ROM's 5-byte format, printed as the ROM prints them
PRINT 1.5; .25; 1E3; 1.5E-3; 123456789; 1234567890; 1E10; 1E-10
PRINT 1 / 3; 2 / 3; 10 / 4; -1 / 3
PRINT 0.1 + 0.2; 1 - 0.9; 3.14159 * 2
x = 1
FOR i% = 1 TO 10: x = x * 1.5: NEXT
PRINT x
TRY: PRINT 1E38 * 1.5: CATCH: PRINT "overflow"; ERR: END TRY
PRINT 1E-38 / 1E10
PRINT 40000; -40000; 40000 * 2
PRINT 2.5 + 1; 2.5 - 1; 2.5 * 2; 2.5 / 0.5
PRINT INT(2.5); INT(-2.5); INT(3); INT(-0.1)
PRINT ABS(-1.5); SGN(-0.5); SGN(0.0)
