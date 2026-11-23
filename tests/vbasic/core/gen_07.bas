' generated: integer expressions (the fast path, overflow into floats)
a% = -47: b% = -169: c% = 85: d% = 275
TRY: PRINT 0; (SGN(NOT 23838) < NOT %100000): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; ((20522 AND (a% OR %11000111)) * %11000): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; ((c% + (66 < -56)) \ ABS((c% <> 86))): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; SGN((SGN(209) XOR a%)): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: c% = 35: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 4; -15741: CATCH: PRINT 4; "error"; ERR: END TRY
TRY: b% = (NOT (75 > a%) AND ((-23 MOD $8DAC) + 33)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 5; (-a% OR ((254 - 235) = -c%)): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: b% = (SGN((19 XOR b%)) \ (44 = 48)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; (b% OR (27415 > 208)): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; 30952: CATCH: PRINT 7; "error"; ERR: END TRY
TRY: a% = NOT ABS((300 \ 82)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 8; (((b% AND c%) SHR 6) OR (31 SHR 8)): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: d% = (189 OR SGN((a% XOR 235))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 9; (b% SHR 0): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; ABS(d%): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; (((177 AND 69) XOR NOT -95) OR (NOT c% XOR (-292 = -a%))): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (((110 * $244D) OR 218) >= (NOT -5602 SHL 17)): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; ((SGN($C145) - (275 + 290)) SHR 16): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; NOT NOT (291 XOR -d%): CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; c%: CATCH: PRINT 15; "error"; ERR: END TRY
TRY: PRINT 16; (SGN(ABS(c%)) + b%): CATCH: PRINT 16; "error"; ERR: END TRY
TRY: PRINT 17; SGN(((b% XOR 179) <> NOT 22)): CATCH: PRINT 17; "error"; ERR: END TRY
TRY: PRINT 18; 9: CATCH: PRINT 18; "error"; ERR: END TRY
TRY: PRINT 19; ABS(((45 * a%) * -40)): CATCH: PRINT 19; "error"; ERR: END TRY
TRY: PRINT 20; $ED51: CATCH: PRINT 20; "error"; ERR: END TRY
TRY: PRINT 21; (c% + 115): CATCH: PRINT 21; "error"; ERR: END TRY
TRY: a% = (25991 - c%): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 22; ((244 <> NOT 125) XOR SGN(260)): CATCH: PRINT 22; "error"; ERR: END TRY
TRY: PRINT 23; (((c% - $1158) + NOT d%) \ -c%): CATCH: PRINT 23; "error"; ERR: END TRY
TRY: PRINT 24; (SGN(%11111111) * (($722B SHR 15) * (a% MOD 62))): CATCH: PRINT 24; "error"; ERR: END TRY
TRY: PRINT 25; %11001100: CATCH: PRINT 25; "error"; ERR: END TRY
TRY: PRINT 26; ABS(ABS(197)): CATCH: PRINT 26; "error"; ERR: END TRY
TRY: PRINT 27; 234: CATCH: PRINT 27; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
