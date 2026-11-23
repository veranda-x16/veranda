' generated: integer expressions (the fast path, overflow into floats)
a% = 50: b% = -174: c% = -133: d% = -45
TRY: PRINT 0; NOT ((b% <> 262) * NOT $758D): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: d% = ABS(ABS(112)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 1; c%: CATCH: PRINT 1; "error"; ERR: END TRY
TRY: d% = %1110101: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 2; 193: CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; -1840: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: a% = (((-184 + d%) SHL 2) OR ((96 < %111111) <= (-a% <> 220))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 4; %110111: CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; (SGN(-%11101000) + (NOT 181 >= (-a% OR d%))): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; c%: CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; (SGN((d% - 138)) \ (b% OR 197)): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; ((ABS(d%) >= (101 - 198)) XOR 177): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; $AD8E: CATCH: PRINT 9; "error"; ERR: END TRY
TRY: c% = ABS(64): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 10; ((SGN(22) SHL 6) AND ((8 AND 38) = SGN(261))): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: a% = ABS((-$8D3D \ %11010011)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 11; b%: CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; -$6D5E: CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; (((a% + 176) - ($6B53 MOD b%)) > ((300 SHR 4) + (246 + d%))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; NOT ((59 <= -c%) XOR ($7171 * $18C7)): CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; 116: CATCH: PRINT 15; "error"; ERR: END TRY
TRY: PRINT 16; SGN((31174 \ (215 OR a%))): CATCH: PRINT 16; "error"; ERR: END TRY
TRY: d% = (188 * (ABS(97) >= (115 AND 265))): CATCH: PRINT "store"; ERR: END TRY
PRINT a%; b%; c%; d%
