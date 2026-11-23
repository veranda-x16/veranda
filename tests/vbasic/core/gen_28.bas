' generated: integer expressions (the fast path, overflow into floats)
a% = 234: b% = 174: c% = 56: d% = 196
TRY: PRINT 0; (b% = (286 + NOT d%)): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: d% = (a% * ((-a% SHR 12) XOR (d% SHR 8))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 1; ABS((-$8CF3 <= -a%)): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; (d% MOD ((202 >= 80) \ ABS(-13731))): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: b% = (208 AND 209): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 3; ((($8856 * a%) <> (-a% SHL 5)) > 290): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; NOT 24: CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; (((a% = 3) + (74 MOD d%)) XOR SGN((%1111 * %1001011))): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; SGN((($EE47 > %11100111) SHR 3)): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; ((0 >= ABS(243)) MOD SGN(ABS(a%))): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; -211: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; (%100110 SHL 8): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; NOT (SGN(21422) MOD (-100 AND d%)): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: b% = (a% MOD d%): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 11; 201: CATCH: PRINT 11; "error"; ERR: END TRY
TRY: d% = (((c% = 5) MOD 202) AND ((113 SHL 3) XOR (%10010100 SHR 6))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 12; (ABS(219) XOR d%): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; SGN(SGN(NOT 167)): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; 24693: CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; (SGN(($B1E1 SHR 0)) OR ((-169 OR d%) XOR ($DCC1 + b%))): CATCH: PRINT 15; "error"; ERR: END TRY
TRY: c% = NOT 62: CATCH: PRINT "store"; ERR: END TRY
PRINT a%; b%; c%; d%
