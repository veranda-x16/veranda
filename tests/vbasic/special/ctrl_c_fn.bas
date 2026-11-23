' Ctrl+C stops a FUNCTION deep in a recursion, inside an expression
FUNCTION F(n)
  IF n > 0 THEN F = 1 + F(n - 1): EXIT FUNCTION
  DO
  LOOP
END FUNCTION
PRINT F(40)
