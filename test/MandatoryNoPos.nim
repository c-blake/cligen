var foo=2.0

proc demo(alpha: int, beta=foo, verb=false, item: string): int =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
