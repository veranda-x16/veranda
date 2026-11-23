' expect 5: red is a built-in constant
' expect 7: Undefined SUB Two
' expect 9: Clash is both a label and a SUB
' expect 10: END SUB inside a one-line IF | END SUB missing for SUB in line 10
DIM red(3)
SUB One
  Two
END SUB
Clash: PRINT
SUB Clash: IF 1 THEN LOCAL q: END SUB
