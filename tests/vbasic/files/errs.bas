' the kernel's errors on files and folders, each caught by TRY
SUB Report(what$)
  PRINT what$; ": "; ERR; ERR$; " kernel"; ERRFILE
END SUB
TRY : OPEN #1, "No such file.txt", "r" : CATCH : Report "open r" : END TRY
TRY : OPEN #1, "No such file.txt", "m" : CATCH : Report "open m" : END TRY
TRY : KILL "No such file.txt" : CATCH : Report "kill" : END TRY
TRY : NAME "No such file.txt" AS "Other.txt" : CATCH : Report "name" : END TRY
OPEN #1, "a.txt", "w" : PRINT #1, "a" : CLOSE #1
OPEN #1, "b.txt", "w" : PRINT #1, "b" : CLOSE #1
TRY : NAME "a.txt" AS "b.txt" : CATCH : Report "name exists" : END TRY
NAME "a.txt" AS "c.txt"
PRINT "renamed"
MKDIR "Sub folder"
TRY : MKDIR "Sub folder" : CATCH : Report "mkdir exists" : END TRY
TRY : CHDIR "No such folder" : CATCH : Report "chdir" : END TRY
CHDIR "Sub folder"
PRINT CURDIR$
OPEN #2, "inner.txt", "w" : PRINT #2, "in" : CLOSE #2
KILL "inner.txt"
PRINT "killed inside"
OPEN #2, "inner2.txt", "w" : PRINT #2, "in" : CLOSE #2
NAME "inner2.txt" AS "inner3.txt"
PRINT "renamed inside"
CHDIR ".."
PRINT CURDIR$
TRY : RMDIR "Sub folder" : CATCH : Report "rmdir full" : END TRY
TRY : RMDIR "No such folder" : CATCH : Report "rmdir none" : END TRY
OPEN #1, "c.txt", "r"
OPEN #2, "b.txt", "r"
OPEN #3, "b.txt", "r"
TRY : OPEN #4, "c.txt", "r" : CATCH : Report "open 4" : END TRY
TRY : OPEN #3, "c.txt", "r" : CATCH : Report "open again" : END TRY
TRY : PRINT #1, "x" : CATCH : Report "print r" : END TRY
TRY : PRINT #9, "x" : CATCH : Report "print 9" : END TRY
TRY : PRINT #0, "x" : CATCH : Report "print 0" : END TRY
LINE INPUT #1, a$ : PRINT a$
TRY : LINE INPUT #1, a$ : CATCH : Report "past end" : END TRY
CLOSE
TRY : OPEN #1, "x.txt", "q" : CATCH : Report "mode" : END TRY
OPEN #1, "c.txt", "m"
SEEK #1, 1
PRINT #1, "Z";
CLOSE
OPEN #1, "c.txt", "r" : GET #1, g$, 10 : PRINT LEN(g$); ASC(g$); ASC(MID$(g$, 2)) : CLOSE
END
