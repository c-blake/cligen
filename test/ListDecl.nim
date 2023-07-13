when not declared(addFloat): import std/formatfloat

{.push.}
when (NimMajor, NimMinor) >= (1, 7):
  {.warning[ImplicitDefaultValue]: off.}

proc demo(args: seq[int]; alpha, beta: float = 1; verb=false): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

{.pop.}

when isMainModule:
  import cligen
  dispatch(demo)
