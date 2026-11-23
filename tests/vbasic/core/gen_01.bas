' generated: float expressions through the ROM's maths
x = -23.2: y = -46.25: z = 44.37: a% = -3
TRY: PRINT 0; INT(((-a% + 466) - y)): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: z = x: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 1; (INT((6E-3 ^ 3)) + LOG(ABS((39.367 / z)) + 1)): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; y: CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; LOG(ABS((LOG(ABS(x) + 1) + (z * 19.934))) + 1): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: x = x: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 4; 3.325: CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; 8E5: CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; 49.760: CATCH: PRINT 6; "error"; ERR: END TRY
TRY: z = SIN((-1E2 + (-a% / x))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 7; (((6.275 / 3.343) / -a%) * (32.339 / SIN(459))): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; (39.719 + 27.667): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; (((38.376 / 58.234) * -56) + SQR(ABS(SIN(z)))): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; (SGN(78.379) / 69.89): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; 80.451: CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; ((ATN(z) / z) ^ -1): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; ((63.352 ^ 3) / COS((60.533 / 17.110))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; (z - 73.521): CATCH: PRINT 14; "error"; ERR: END TRY
PRINT x; y; z
