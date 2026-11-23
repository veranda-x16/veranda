' Files and folders (gate vb_files): long names, PRINT #, INPUT #,
' LINE INPUT #, GET #, PUT #, SEEK, LOC, LOF, EOF, "m", the folders
' (a name has no comma: CMDR-DOS's OPEN takes "name,S,W")
OPTION INTEGER
a$ = "Birds seen from the veranda in the spring of 2026 a long list"
b$ = "A second file with a name of exactly sixty three characters.txt"
PRINT LEN(a$); LEN(b$)
MKDIR "Lists of birds and other things seen"
CHDIR "Lists of birds and other things seen"
PRINT CURDIR$
OPEN #1, a$, "w"
PRINT #1, "Robin", 3, 2.5
PRINT #1, "Wren,"; 7; ","; "x,"; -12
PRINT #1, "a, b", "c"
PRINT #1, TAB(12); "tab"; SPC(3); "spc"
PRINT #1, "no end";
PRINT #1, "!"
WRITE_LINE$ = CHR$(34) + "Blue, tit" + CHR$(34) + ", 42, 3.25"
PRINT #1, WRITE_LINE$
PRINT #1,
PRINT #1, "last"
PRINT "loc"; LOC(1); "lof"; LOF(1)
CLOSE #1
OPEN #2, a$, "r"
PRINT "lof"; LOF(2)
LINE INPUT #2, l$ : PRINT "["; l$; "]"
INPUT #2, w$, n%, x$, m%
PRINT w$; "|"; n%; "|"; x$; "|"; m%
LINE INPUT #2, l$ : PRINT "["; l$; "]"
LINE INPUT #2, l$ : PRINT "["; l$; "]"
LINE INPUT #2, l$ : PRINT "["; l$; "]"
INPUT #2, q$, r%, s
PRINT q$; "|"; r%; "|"; s
LINE INPUT #2, l$ : PRINT "["; l$; "]"
PRINT "eof"; EOF(2)
LINE INPUT #2, l$ : PRINT "["; l$; "]"
PRINT "eof"; EOF(2); "loc"; LOC(2)
CLOSE #2
' bytes: PUT, GET, SEEK, "m"
OPEN #3, b$, "w"
FOR i = 0 TO 255 : PUT #3, CHR$(i) : NEXT
FOR i = 1 TO 150 : PUT #3, STRING_OF$ : NEXT
PRINT "loc"; LOC(3)
CLOSE #3
OPEN #3, b$, "m"
SEEK #3, 10
PUT #3, "TEN"
SEEK #3, 300
GET #3, g$, 5
PRINT LEN(g$); ASC(g$)
PRINT "loc"; LOC(3); "lof"; LOF(3)
CLOSE
OPEN #1, b$, "r"
GET #1, g$, 16
FOR i = 1 TO 16 : PRINT ASC(MID$(g$, i, 1)); : NEXT : PRINT
CLOSE
' a big file: positions past 32767
OPEN #1, "Big.dat", "w"
s$ = ""
FOR i = 1 TO 250 : s$ = s$ + CHR$(65 + i MOD 26) : NEXT
FOR i = 1 TO 160 : PUT #1, s$ : NEXT
PRINT "big"; LOC(1); LOF(1)
CLOSE
OPEN #1, "Big.dat", "r"
PRINT LOF(1)
SEEK #1, 39999
GET #1, g$, 1
PRINT LOC(1); g$
SEEK #1, 33000.7
GET #1, g$, 3
PRINT g$
CLOSE
' names, folders
NAME "Big.dat" AS "Big data file renamed.dat"
OPEN #1, "Big data file renamed.dat", "r" : PRINT LOF(1) : CLOSE
KILL "Big data file renamed.dat"
TRY
  OPEN #1, "Big data file renamed.dat", "r"
CATCH
  PRINT "gone:"; ERR; ERRFILE
END TRY
MKDIR "Inner"
CHDIR "Inner"
PRINT CURDIR$
CHDIR ".."
PRINT CURDIR$
RMDIR "Inner"
CHDIR "/"
PRINT CURDIR$
PRINT FOLDER$(DOCS); " "; FOLDER$(APPS); " "; FOLDER$(FONTS); " "; FOLDER$(SYSTEM); " "; FOLDER$(DATA)
PRINT "["; DOCUMENT$; "]"
TRY
  PRINT FOLDER$(7)
CATCH
  PRINT "folder:"; ERR
END TRY
' names with a folder: "dir/name", "/dir/name" (64 characters at most)
MKDIR "Sub"
OPEN #1, "Sub/Short name.txt", "w" : PRINT #1, "in Sub" : CLOSE
TRY
  OPEN #1, "/Lists of birds and other things seen/" + a$, "r"
CATCH
  PRINT "too long:"; ERR; ERRFILE
END TRY
' three files at once, a fourth refused
OPEN #10, "/Sub/Short name.txt", "r"
OPEN #20, "Sub/Short name.txt", "r"
CHDIR "Lists of birds and other things seen"
OPEN #255, a$, "r"
TRY
  OPEN #30, b$, "r"
CATCH
  PRINT "too many:"; ERR; ERR$; ERRFILE
END TRY
LINE INPUT #10, l$ : PRINT l$
LINE INPUT #20, l$ : PRINT l$
LINE INPUT #255, l$ : PRINT l$
END
FUNCTION STRING_OF$
  STRING_OF$ = "x"
END FUNCTION
