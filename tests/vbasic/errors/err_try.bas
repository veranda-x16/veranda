' expect 8: CATCH without TRY
' expect 12: Two CATCH parts for TRY in line 9
' expect 14: END TRY without TRY
' expect 18: WHILE inside a one-line IF | WEND inside a one-line IF | END DIALOG missing for DIALOG in line 17 | WEND missing for WHILE in line 16 | END TRY missing for TRY in line 15
'
'
'
CATCH
TRY
  x = 1
CATCH
CATCH
END TRY
END TRY
TRY
WHILE 1
DIALOG 1, 1, 2, 2
IF x THEN WHILE 1: WEND
