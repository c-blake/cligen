proc demo(alpha=1, verb=false, stuff = @[ "ab", "cd" ], args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " verb:", verb, " stuff:", repr(stuff)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  from strutils import split, `%`, join
  from argcvt   import keys, ERR, argDf  # Little helpers

  proc argParse(dst: var seq[string], key: string, dfl: seq[string], val, help: string): bool =
    if val == nil:
      ERR("Bad value nil for CSV param \"$1\"\n$2" % [ key, help ])
      return false
    dst = val.split(",")
    return true

  proc argHelp(dfl: seq[string]; parNm, sh, parHelp: string, rq: int): seq[string] =
    result = @[ keys(parNm, sh), "CSV",
                argDf(rq, "\"" & dfl.join(",") & "\""), parHelp ]

  import cligen
  dispatch(demo)
