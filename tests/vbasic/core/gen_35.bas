' generated: integer expressions (the fast path, overflow into floats)
a% = 222: b% = -195: c% = 150: d% = 208
TRY: PRINT 0; c%: CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; (($31C6 * -$E070) OR SGN((237 >= 159))): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; (((c% + $2E0D) XOR (d% SHL 13)) + (NOT 252 SHL 15)): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: c% = (b% MOD ((290 MOD 12) OR -27027)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 3; 264: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; (((c% SHL 11) AND (-d% AND a%)) + SGN(ABS(-2528))): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; SGN((18 AND (%11110 \ 248))): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: d% = ((b% * -a%) <= ((d% + 570) AND (%11010011 = d%))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; SGN(281): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; SGN(60): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; -b%: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; (((b% \ 2149) >= b%) > 181): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; (NOT 233 * SGN(-%110101)): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; (229 \ ABS(30636)): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (ABS((-250 SHR 15)) >= ABS(248)): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: b% = a%: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 13; 11519: CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; (b% XOR -208): CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; (ABS($C8F3) SHR 12): CATCH: PRINT 15; "error"; ERR: END TRY
TRY: PRINT 16; NOT 18931: CATCH: PRINT 16; "error"; ERR: END TRY
TRY: d% = 171: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 17; ((SGN(-111) MOD (160 * b%)) + 139): CATCH: PRINT 17; "error"; ERR: END TRY
TRY: c% = c%: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 18; a%: CATCH: PRINT 18; "error"; ERR: END TRY
TRY: b% = (NOT -229 >= -%11101010): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 19; ((($16F1 * $E81C) AND (-c% SHR 4)) + NOT (180 <> 1)): CATCH: PRINT 19; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
