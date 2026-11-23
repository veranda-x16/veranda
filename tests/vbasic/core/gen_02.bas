' generated: integers and floats mixed, assignments converting
a% = 7: b% = -3: c% = 100: d% = 0: x = 2.5: y = -0.75: z = 1E3
TRY: PRINT -$E049 < (x + ((z + 3E4) - INT(x))): CATCH: PRINT "error"; ERR: END TRY
TRY: x = (((d% - 122) XOR 63) - -$D768) * 45: PRINT x: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = ((88.471 * EXP(53.745 / 50)) / SGN(ABS(4.40))): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = ((EXP(x / 50) * 703) / ABS(ABS(-a%))): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = INT(-594): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: x = 169 * (((16.588 * -3E3) + ATN(504)) + 53.998): PRINT x: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = (z / ATN(65.254)): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = (55.416 - ((x + 32.319) - 91.776)): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = (((58.349 * z) - (52.59 - 97.808)) * ((-z * 38.702) + y)): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT (((a% SHL 11) OR (6122 SHR 12)) SHL 13) <= (SIN(SIN(y)) ^ 2): CATCH: PRINT "error"; ERR: END TRY
TRY: PRINT 183 = x: CATCH: PRINT "error"; ERR: END TRY
TRY: x = 208 * z: PRINT x: CATCH: PRINT "error"; ERR: END TRY
TRY: a% = LOG(ABS(((x ^ -1) / ATN(z))) + 1): PRINT a%: CATCH: PRINT "error"; ERR: END TRY
