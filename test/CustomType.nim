proc demo(alpha=1, verb=false, stuff = @[ "ab", "cd" ], args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
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

  template argHelp(ht: seq[seq[string]], dfl: seq[string];
                   parNm, sh, parHelp: string, rq: int) =
    ht.add(@[ keys(parNm, sh), "CSV",
              argRq(rq, "\"" & dfl.join(",") & "\""), parHelp])

  import cligen
  dispatch(demo)
