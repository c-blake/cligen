proc demo(alpha=1, verb=false, stuff = @[ "ab", "cd" ], args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " verb:", verb, " stuff:", stuff
  for i, arg in args: echo "positional[", i, "]: ", arg
  return 42

when isMainModule:
  from strutils import split, `%`, join
  from cligen/argcvt import ArgcvtParams, argKeys         # Little helpers

  proc argParse(dst: var seq[string], dfl: seq[string],
                a: var ArgcvtParams): bool =
    dst = a.val.split(",")
    return true

  proc argHelp(dfl: seq[string]; a: var ArgcvtParams): seq[string] =
    result = @[ a.argKeys, "CSV", "\"" & dfl.join(",") & "\"" ]

  import cligen
  dispatch(demo)
