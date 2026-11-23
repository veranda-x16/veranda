' arrays passed to procedures (by reference)
DIM nums%(9), names$(2)
FOR i% = 0 TO 9: nums%(i%) = 9 - i%: NEXT
names$(0) = "c": names$(1) = "a": names$(2) = "b"
SUB SortInts(a%())
  LOCAL i%, j%, t%
  FOR i% = 0 TO UBOUND(a%) - 1
    FOR j% = i% + 1 TO UBOUND(a%)
      IF a%(j%) < a%(i%) THEN t% = a%(i%): a%(i%) = a%(j%): a%(j%) = t%
    NEXT
  NEXT
END SUB
FUNCTION Joined$(s$())
  LOCAL i%, r$
  FOR i% = 0 TO UBOUND(s$): r$ = r$ + s$(i%): NEXT
  Joined$ = r$
END FUNCTION
SortInts nums%()
FOR i% = 0 TO 9: PRINT nums%(i%);: NEXT: PRINT
PRINT Joined$(names$())
