' generated: integer expressions (the fast path, overflow into floats)
a% = -234: b% = 73: c% = 254: d% = 188
TRY: PRINT 0; (d% < ((80 SHL 0) MOD 50)): CATCH: PRINT 0; "error"; ERR: END TRY
TRY: PRINT 1; ((($C9D9 MOD 300) SHR 9) \ (ABS(c%) MOD SGN(-13))): CATCH: PRINT 1; "error"; ERR: END TRY
TRY: PRINT 2; ((c% * (50 + 245)) SHL 13): CATCH: PRINT 2; "error"; ERR: END TRY
TRY: PRINT 3; (ABS((b% < 25121)) + (183 \ $DEA8)): CATCH: PRINT 3; "error"; ERR: END TRY
TRY: PRINT 4; (24254 SHR 4): CATCH: PRINT 4; "error"; ERR: END TRY
TRY: PRINT 5; NOT (106 + (%1000100 XOR -a%)): CATCH: PRINT 5; "error"; ERR: END TRY
TRY: PRINT 6; ((ABS(233) MOD 8) * SGN((108 OR $26C7))): CATCH: PRINT 6; "error"; ERR: END TRY
TRY: PRINT 7; ABS((ABS(165) >= (210 * a%))): CATCH: PRINT 7; "error"; ERR: END TRY
TRY: PRINT 8; NOT 137: CATCH: PRINT 8; "error"; ERR: END TRY
TRY: PRINT 9; 225: CATCH: PRINT 9; "error"; ERR: END TRY
TRY: PRINT 10; SGN(14417): CATCH: PRINT 10; "error"; ERR: END TRY
TRY: b% = ((9140 SHR 1) \ ((123 \ -$FFA0) XOR (%1011000 MOD -105))): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 11; (36 + 241): CATCH: PRINT 11; "error"; ERR: END TRY
TRY: PRINT 12; (251 MOD ((115 XOR 235) * (279 * 185))): CATCH: PRINT 12; "error"; ERR: END TRY
TRY: d% = NOT ((273 * -68) * 7): CATCH: PRINT "store"; ERR: END TRY
TRY: PRINT 13; SGN(((%10011100 SHL 16) > ABS(245))): CATCH: PRINT 13; "error"; ERR: END TRY
PRINT a%; b%; c%; d%
