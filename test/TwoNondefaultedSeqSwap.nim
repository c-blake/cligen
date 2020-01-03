proc demo(alpha=1, verb=false, args: seq[string], stufF: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " verb:", verb, " stuff:", stuff
  for i, arg in args: echo "args[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen
  dispatch(demo, positional="stu_ff",
           help={ "st-uff" : "[ stuff (0 or more strings) ]" })
