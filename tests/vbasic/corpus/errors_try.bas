' TRY, CATCH and the V2-style handlers
TRY
  OPEN #1, "Bird list.txt", "r"
  LINE INPUT #1, first$
CATCH
  MSGBOX "Could not read the list: " + ERR$
END TRY
CLOSE #1
TRY
  ERROR 200, "No birds"
CATCH
  PRINT ERR, ERR$, ERL, ERRFILE
END TRY
TRY: x = 1 / 0: CATCH: x = 0: END TRY
ON ERROR GOTO 900
ERROR 201
ON ERROR GOTO 0
END
900 PRINT "Error"; ERR; "in line"; ERL
RESUME NEXT
