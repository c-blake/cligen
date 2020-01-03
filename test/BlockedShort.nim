var foo=2.0

proc demo(alpha=1, abc=foo, aaah=false, aloha="") =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " abc:", abc, " aaah:", aaah, " aloha:", aloha

when isMainModule:
  import cligen
  dispatch(demo, short={"alpha" : '\0', "abc" : '\0'})
