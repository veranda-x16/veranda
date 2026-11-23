' generated: integer expressions (the fast path, overflow into floats)
a% = -290: b% = -19: c% = 69: d% = -176
TRY: PRINT 0; ABS((SGN(127) = (a% XOR a%))): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; ((ABS(d%) * 223) <> ((265 < -4001) MOD NOT a%)): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; 153: CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; d%: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; (($9D75 AND 227) XOR b%): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; (-c% SHL 9): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: c% = (202 * (SGN(7030) \ (a% = 39))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; ((NOT %11 SHR 13) <> (a% XOR -$2EA6)): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; (($EEAF = (224 - d%)) AND b%): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; (NOT a% SHL 10): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; (((289 SHL 1) \ (a% MOD 250)) AND ABS((204 + 64))): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; 227: CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; (d% OR ((198 OR 13045) AND (298 <> $429A))): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; b%: CATCH: PRINT 12; "error"; ERR: END TRY
TRY: b% = ((-62 <= (-272 + 88)) AND ((-119 XOR 116) + ABS(206))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 13; ABS(((d% SHL 0) - SGN(c%))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; (((%10000101 SHL 0) SHL 16) - (-c% OR c%)): CATCH: PRINT 14; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
