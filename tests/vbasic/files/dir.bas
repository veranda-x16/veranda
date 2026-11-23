' DIR$: a folder's listing, all of it and by patterns (gate vb_files; the
' gate checks the names against the folder on the host)
MKDIR "Listing of a folder"
CHDIR "Listing of a folder"
FOR i = 1 TO 5
  OPEN #1, "Birds of the veranda part" + STR$(i) + ".txt", "w"
  PRINT #1, "part"; i
  CLOSE #1
NEXT
OPEN #1, "Seeds.DAT", "w" : CLOSE #1
OPEN #1, "A file with a name of sixty-three characters for the listing.tx", "w" : CLOSE #1
MKDIR "A folder inside the folder"
f$ = DIR$("*")
WHILE f$ <> ""
  PRINT "all "; f$
  f$ = DIR$()
WEND
f$ = DIR$("*.txt")
WHILE f$ <> ""
  PRINT "txt "; f$
  f$ = DIR$()
WEND
f$ = DIR$("birds*3.TXT")
WHILE f$ <> ""
  PRINT "three "; f$
  f$ = DIR$()
WEND
PRINT "none ["; DIR$("*.xyz"); "] ["; DIR$; "]"
END
