' integers: literals, the fast path, overflow into floats
PRINT 1 + 2; 7 - 10; 6 * 7; 32767 + 1; -32768 - 1
PRINT 200 * 200; 181 * 181; -181 * 181; 255 * 128; 256 * 128
PRINT $FF; $FFFF; %1010; $7FFF; $8000
a% = 1000: b% = 30
PRINT a% * b%; a% \ b%; a% MOD b%; a% / b%
PRINT 7 \ 2; -7 \ 2; 7 \ -2; -7 \ -2
PRINT 7 MOD 3; -7 MOD 3; 7 MOD -3; -7 MOD -3
PRINT -32768 \ -1; -32768 MOD -1
PRINT 2 ^ 10; 2 ^ 15; 2 ^ 16; 3 ^ 0; 0 ^ 0; (-2) ^ 3; 10 ^ 9
PRINT ABS(-32768); -(-32768); ABS(-5); SGN(-5); SGN(0); SGN(9)
x% = 32767: x% = x% - 1: PRINT x%
