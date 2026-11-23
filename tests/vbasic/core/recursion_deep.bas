' recursion deep enough to use the BASIC stack's bank
SUB Down(n%)
  IF n% > 0 THEN Down n% - 1 ELSE PRINT "bottom"
END SUB
FUNCTION Sum%(n%)
  IF n% = 0 THEN Sum% = 0 ELSE Sum% = n% + Sum%(n% - 1)
END FUNCTION
Down 300
PRINT Sum%(100)
FUNCTION Ack%(m%, n%)
  IF m% = 0 THEN RETURN n% + 1
  IF n% = 0 THEN RETURN Ack%(m% - 1, 1)
  RETURN Ack%(m% - 1, Ack%(m%, n% - 1))
END FUNCTION
PRINT Ack%(2, 3)
