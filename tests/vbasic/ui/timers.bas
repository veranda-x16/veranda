' Timers: two timers, OFF, ON, STOP, DOEVENTS, SLEEP, the clock (gate vb_ui)
OPTION INTEGER
WINDOW #1, 10, 10, 60, 16, "Timers", STATUS 2
TIMER 1, 3 CALL Fast
TIMER 2, 20 CALL Slow
fast = 0 : slow = 0
PRINT LEN(TIME$); LEN(DATE$); MID$(TIME$, 3, 1); MID$(DATE$, 5, 1)
FOR i = 1 TO 2000
  IF i MOD 50 = 0 THEN DOEVENTS
NEXT
PRINT "loop done"
TIMER 1 OFF
SLEEP 30
f = fast
SLEEP 30
IF fast = f THEN PRINT "timer 1 is off"
TIMER 1 ON
SUB Fast
  fast = fast + 1
  WINDOW STATUS #1, "fast" + STR$(fast), "slow" + STR$(slow)
END SUB
SUB Slow
  slow = slow + 1
  IF slow = 6 THEN TIMER 2 STOP : TIMER 1 STOP : PRINT "stopped" : END
END SUB
