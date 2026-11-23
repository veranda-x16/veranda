' generated: integer expressions (the fast path, overflow into floats)
a% = 163: b% = 181: c% = -191: d% = -102
TRY: PRINT 0; (((-c% SHL 13) - (133 SHR 6)) * ABS((b% SHR 11))): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; b%: CATCH: PRINT 1; "error"; ERR: END TRY
TRY: c% = ((-202 AND (8 OR d%)) <= NOT (198 = b%)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 2; (a% AND (24 + (28 MOD -d%))): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; ABS((($AD1C - 143) + (-254 SHL 1))): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: a% = SGN((-220 - NOT b%)): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 4; ((b% OR ($25A6 <= 70)) SHL 0): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; b%: CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; (((%1111011 OR 20385) SHL 13) AND ((2741 XOR 58) SHL 4)): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: a% = (((-245 \ 131) \ (%11000101 SHR 0)) AND ((d% >= b%) + SGN(279))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 7; ((ABS(29428) XOR (34 = -12)) SHL 2): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; 156: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; SGN(((264 - 245) XOR SGN(c%))): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; 228: CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; (((16163 >= 88) SHL 16) = (($8F09 \ a%) <= NOT -b%)): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (262 < SGN((b% + 19372))): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: b% = (a% AND (237 - (b% \ 1899))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 13; 79: CATCH: PRINT 13; "error"; ERR: END TRY
TRY: b% = ((288 <= (121 XOR $74B6)) \ a%): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 14; (((229 AND -187) MOD SGN(229)) > d%): CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; SGN((ABS(83) > (61 <> 97))): CATCH: PRINT 15; "error"; ERR: END TRY
TRY: PRINT 16; (((29 + 2946) XOR (d% SHL 4)) XOR (15191 <> ($9A24 OR 178))): CATCH: PRINT 16; "error"; ERR: END TRY
TRY: PRINT 17; ((ABS(b%) * ABS($71A5)) MOD 267): CATCH: PRINT 17; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
