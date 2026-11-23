' Files with long names
OPEN #1, "Holiday photos from the lake.txt", "w"
PRINT #1, "first line"
PRINT #1, 1; 2; 3
PUT #1, CHR$(0) + CHR$(1)
CLOSE #1
OPEN #1, "Holiday photos from the lake.txt", "r"
LINE INPUT #1, l$
INPUT #1, a, b, c
GET #1, block$, 2
PRINT LOF(1), LOC(1), EOF(1)
SEEK #1, 0
WHILE NOT EOF(1): LINE INPUT #1, l$: PRINT l$: WEND
CLOSE
NAME "Holiday photos from the lake.txt" AS "Lake.txt"
MKDIR "Birds"
CHDIR "Birds"
PRINT CURDIR$
CHDIR FOLDER$(DOCS)
RMDIR "Birds"
KILL "Lake.txt"
f$ = DIR$("*.TXT")
WHILE f$ <> ""
  PRINT f$
  f$ = DIR$()
WEND
IF DOCUMENT$ <> "" THEN PRINT DOCUMENT$
PRINT FOLDER$(APPS), FOLDER$(FONTS), FOLDER$(SYSTEM), FOLDER$(DATA)
