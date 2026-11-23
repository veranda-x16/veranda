' Operators and their priority
a% = 7
b% = 2
PRINT a% + b% * 3, (a% + b%) * 3
PRINT a% / b%, a% \ b%, a% MOD b%, a% ^ 2
PRINT a% AND b%, a% OR b%, a% XOR b%, NOT a%
PRINT a% SHL 2, a% SHR 1
PRINT a% = b%, a% <> b%, a% < b%, a% > b%, a% <= b%, a% >= b%
PRINT -a%, -(a% + 1), a% * -b%, 2 - -3
s$ = "con" + "cat"
IF a% > 1 AND NOT b% = 0 OR a% < 0 THEN PRINT s$
