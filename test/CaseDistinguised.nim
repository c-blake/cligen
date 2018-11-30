var foo=2.0

proc demo(alpha=1, Abc=foo, aaah=false, aloha="") =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " Abc:", Abc, " aaah:", aaah, " aloha:", repr(aloha)

when isMainModule:
  import cligen, cligen/argcvt
  argCvtOptions.incl(acLooseOperators)
  dispatch(demo, short={"alpha": 'z'})
