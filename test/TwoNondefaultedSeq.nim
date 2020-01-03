proc demo(alpha=1, verb=false, args: seq[string], stuff: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " verb:", verb, " stuff:", stuff
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  import cligen
  dispatch(demo)
