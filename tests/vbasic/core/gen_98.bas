' generated: integer expressions (the fast path, overflow into floats)
a% = 142: b% = -14: c% = 267: d% = -167
TRY: PRINT 0; ABS(b%): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; ((258 * ABS(d%)) OR (-c% SHL 2)): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; $B9E3: CATCH: PRINT 2; "error"; ERR: END TRY
TRY: d% = -155: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 3; 141: CATCH: PRINT 3; "error"; ERR: END TRY
TRY: c% = NOT (-%100011 SHR 17): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 4; (((c% <= 29555) + (27 MOD a%)) SHR 6): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; ((ABS(188) AND -192) SHR 13): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; 39: CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; (((31361 SHR 12) MOD (69 - 34)) < ((a% \ $80AC) AND ($4182 SHL 14))): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: a% = 147: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 8; -220: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; $B41D: CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; c%: CATCH: PRINT 10; "error"; ERR: END TRY
TRY: PRINT 11; ((NOT -70 <> (c% SHR 15)) - %10111011): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; NOT (120 \ (a% \ 21916)): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: a% = (c% SHR 14): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 13; (NOT -70 MOD ((141 - %11110011) \ (60 >= 157))): CATCH: PRINT 13; "error"; ERR: END TRY
TRY: c% = ($CB87 + 239): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 14; ((SGN(b%) * a%) OR ((226 SHL 17) SHR 15)): CATCH: PRINT 14; "error"; ERR: END TRY
TRY: PRINT 15; (-a% OR 262): CATCH: PRINT 15; "error"; ERR: END TRY
TRY: PRINT 16; 283: CATCH: PRINT 16; "error"; ERR: END TRY
TRY: PRINT 17; ((SGN(76) \ (245 SHR 3)) * ((-286 < b%) + -189)): CATCH: PRINT 17; "error"; ERR: END TRY
TRY: d% = 4: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 18; SGN($7BAA): CATCH: PRINT 18; "error"; ERR: END TRY
TRY: PRINT 19; (((d% SHR 10) SHR 15) OR (($1F1F OR %10111101) >= 71)): CATCH: PRINT 19; "error"; ERR: END TRY
TRY: a% = d%: CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 20; ((181 * 15799) * 39): CATCH: PRINT 20; "error"; ERR: END TRY
TRY: d% = (256 SHR 15): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 21; 233: CATCH: PRINT 21; "error"; ERR: END TRY
TRY: PRINT 22; ((NOT b% + SGN($F7CC)) <> %110001): CATCH: PRINT 22; "error"; ERR: END TRY
TRY: PRINT 23; (c% + 259): CATCH: PRINT 23; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
