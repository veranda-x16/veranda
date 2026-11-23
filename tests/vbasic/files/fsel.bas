' The Open and Save dialog: FILESAVE$ into a folder, FILEOPEN$ (gate vb_files)
MKDIR "Docs with a long folder name"
f$ = FILESAVE$("Save the notes", "")
PRINT "save "; f$; " in "; CURDIR$
OPEN #1, f$, "w"
PRINT #1, "Saved through the dialog."
CLOSE #1
g$ = FILEOPEN$("Open a text", "TXT")
PRINT "open "; g$; " in "; CURDIR$
OPEN #1, g$, "r"
LINE INPUT #1, l$
CLOSE #1
PRINT l$
h$ = FILEOPEN$("Cancelled")
PRINT "cancel ["; h$; "] "; CURDIR$
END
