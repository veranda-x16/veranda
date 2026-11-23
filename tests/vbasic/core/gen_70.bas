' generated: integer expressions (the fast path, overflow into floats)
a% = 33: b% = 195: c% = -225: d% = -122
TRY: PRINT 0; (91 \ ((85 MOD c%) SHL 15)): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: d% = ABS((%1100101 OR (153 AND $44))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 1; 199: CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; -c%: CATCH: PRINT 2; "error"; ERR: END TRY
TRY: c% = d%: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 3; ((ABS(%100101) * (-%1010001 - 176)) = b%): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; (20996 + 125): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; NOT ((c% \ $D1C6) \ (d% + 14787)): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: b% = (SGN(c%) MOD NOT a%): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; 12762: CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; 43: CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; d%: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; -163: CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; 14296: CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; ((d% <> -d%) - (NOT $1E8B SHL 15)): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (SGN(%10011100) XOR ((196 SHL 10) AND 52)): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; NOT ((19305 > a%) MOD (212 SHL 14)): CATCH: PRINT 13; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
