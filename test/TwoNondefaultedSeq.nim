proc demo(alpha=1, verb=false, args: seq[string], stuff: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " verb:", verb, " stuff:", repr(stuff)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  from strutils import split, `%`, join
  from argcvt   import keys, argRet, argRq  # Little helpers

  template argParse(dst: seq[string], key: string, dfl: seq[string], val: string, help: string) =
    if val == nil:
      argRet(1, "Bad value nil for CSV param \"$1\"\n$2" % [ key, help ])
    dst = val.split(",")

  template argHelp(helpT: seq[array[0..3, string]], defVal: seq[string],
                   parNm: string, sh: string, parHelp: string, rq: int) =
    helpT.add([keys(parNm, sh), "CSV",
               argRq(rq, "\"" & defVal.join(",") & "\""), parHelp])

  import cligen
  dispatch(demo)
