' names from the top ("/dir/name") while the current folder is not the
' top: a new file, an old one read, written again, "m", one at the top.
' Gate vb_files runs this on the SD card image only (V106): x16emu's host
' folder fails the first (a new file by an absolute path with a folder,
' from a folder below the top: error 50, its fault, not Veranda's)
MKDIR "Alpha"
MKDIR "Beta"
CHDIR "/"
OPEN #1, "Alpha/Old file.txt", "w" : PRINT #1, "old" : CLOSE
CHDIR "Beta"
PRINT CURDIR$
OPEN #1, "/Alpha/New file.txt", "w" : PRINT #1, "made from Beta" : CLOSE
OPEN #1, "/Alpha/New file.txt", "r" : LINE INPUT #1, l$ : CLOSE
PRINT l$
OPEN #1, "/Alpha/Old file.txt", "r" : LINE INPUT #1, l$ : CLOSE
PRINT l$
OPEN #1, "/Alpha/Old file.txt", "w" : PRINT #1, "written again" : CLOSE
OPEN #1, "/Alpha/Old file.txt", "m" : PUT #1, "W" : CLOSE
OPEN #1, "/Top file.txt", "w" : PRINT #1, "at the top" : CLOSE
CHDIR "/Alpha"
OPEN #1, "Old file.txt", "r" : LINE INPUT #1, l$ : CLOSE
PRINT l$
PRINT CURDIR$
END
