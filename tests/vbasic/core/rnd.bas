' RND: a negative argument starts a sequence; then RND(1)
x = RND(-1)
FOR i% = 1 TO 5: PRINT RND(1): NEXT
x = RND(-42)
FOR i% = 1 TO 5: PRINT INT(RND(1) * 6) + 1;: NEXT: PRINT
x = RND(-1)
PRINT RND(1)
