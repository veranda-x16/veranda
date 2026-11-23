' generated: integer expressions (the fast path, overflow into floats)
a% = 19: b% = -124: c% = -215: d% = 109
TRY: PRINT 0; SGN(($7B32 < NOT a%)): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; 192: CATCH: PRINT 1; "error"; ERR: END TRY
TRY: d% = $EDD2: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 2; ((d% = -257) AND ((272 = -137) SHL 12)): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: c% = SGN((292 - (21 <= 105))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 3; 185: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; ((%11010001 + (3528 MOD -d%)) OR 28767): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; (((a% + $7C32) MOD (c% XOR -244)) <= NOT (78 SHL 13)): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: a% = 106: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; ((150 + (a% = b%)) > (270 - NOT c%)): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; (a% * (214 \ b%)): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; (ABS((143 - 179)) > (%11010100 XOR (283 + 128))): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: b% = 233: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 9; ($91BB <= SGN(SGN(-a%))): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: b% = (143 OR (($2F63 OR $D5CC) SHL 16)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 10; (((-d% * 146) \ ABS(213)) MOD 208): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; 243: CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; ((-$70D9 * c%) OR (142 >= ABS(6247))): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; (((139 AND 100) SHL 4) + (ABS(-31) + (193 > 144))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; $8188: CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; ((NOT 184 <> (-81 < c%)) * (-$4308 > %100011)): CATCH: PRINT 15; "error"; ERR: END TRY
TRY: a% = SGN(SGN((d% > 262))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 16; 47: CATCH: PRINT 16; "error"; ERR: END TRY
TRY: PRINT 17; ABS(ABS(d%)): CATCH: PRINT 17; "error"; ERR: END TRY
TRY: b% = (d% * 1901): CATCH: PRINT "store"; ERR: END TRY
PRINT a%; b%; c%; d%
