' generated: integer expressions (the fast path, overflow into floats)
a% = 44: b% = -192: c% = 230: d% = 132
TRY: PRINT 0; 14095: CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; 148: CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; ABS(149): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; %111: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; (177 = (18 > NOT -c%)): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; (SGN(($BEAD XOR d%)) <> (%11000001 SHR 9)): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: a% = (SGN((227 \ 4266)) SHR 8): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 6; ((-111 = (86 AND -164)) SHR 14): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: c% = (%10000111 SHL 16): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 7; (((118 + $27B4) > -266) <= ((-d% <= -c%) < 21131)): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; ABS(220): CATCH: PRINT 8; "error"; ERR: END TRY
TRY: c% = ((-37 - (42 <> 32702)) = 10335): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 9; (69 >= (($8F5E - -b%) SHL 15)): CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; (-94 - ((292 >= 26) AND -188)): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; %1111001: CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (((-30 XOR 20062) AND -c%) * (d% OR (a% XOR 82))): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: PRINT 13; ((118 XOR (d% SHL 4)) MOD ((183 * 32523) OR (a% OR 229))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: PRINT 14; a%: CATCH: PRINT 14; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
