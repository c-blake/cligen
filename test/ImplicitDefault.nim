proc demo(alpha: int, bypass=false, iteM: string, args: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  if bypass:
    echo "0.0.0"
    return 0
  echo "alpha:", alpha, " bypass:", bypass, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen
  dispatch(demo, implicitDefault = @[ "ite_m" ])
