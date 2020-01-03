var f=2.0

proc demo(alpha: int, beta=f, verb=false, item: string, args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
