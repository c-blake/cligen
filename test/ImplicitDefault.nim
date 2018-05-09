proc demo(alpha: int, version=false, item: string, args: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  if version:
    echo "0.0.0"
    return 0
  echo "alpha:", alpha, " version:", version, " item:", repr(item)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  import cligen
  dispatch(demo,
           implicitDefault = @[ "item" ], mandatoryOverride = @[ "version" ])
