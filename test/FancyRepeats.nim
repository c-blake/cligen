proc demo(alpha=1, verb=0, junk= @[ "rs", "tu" ], stuff= @[ "ab", "cd" ],
          args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " verb:", verb, " junk:", repr(junk), " stuff:", repr(stuff)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  from strutils import split, `%`, join
  from argcvt   import keys, argRet, argRq  # Little helpers
  from parseutils import parseInt

  template argParse*(dst: int, key: string, val: string, help: string) =
    let Key = if key == "v": "verb" else: key
    if Key == "verb":               # make "verb" a repeatable key
      if Key in keyCount:
        inc(dst)
      else:
        dst = 1
      keyCount.inc(Key)
    else:
      if val == nil or parseInt(strip(val), dst) == 0:
        argRet(1, "Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
               [ (if val == nil: "nil" else: val), key, help ])

  template argHelp*(helpT: seq[array[0..3, string]], defVal: int,
                    parNm: string, sh: string, parHelp: string, rq: int) =
    if parNm == "verb":
      helpT.add([ keys(parNm, sh), "[bool]", argRq(rq, $defVal), parHelp ])
      shortNoVal.incl(sh[0])
      longNoVal.add(parNm)
    else:
      helpT.add([ keys(parNm, sh), "int", argRq(rq, $defVal), parHelp ])

  template argParse(dst: seq[string], key: string, val: string, help: string) =
    if val == nil:
      argRet(1, "Bad value nil for CSV param \"$1\"\n$2" % [ key, help ])
    let Key = if key == "s": "stuff" else: key
    if Key == "stuff":              # make "stuff" a repeatable key
      if Key in keyCount:
        dst = dst & val.split(",")
      else:
        dst = val.split(",")
      keyCount.inc(Key)
    else:
      dst = val.split(",")

  template argHelp(helpT: seq[array[0..3, string]], defVal: seq[string],
                   parNm: string, sh: string, parHelp: string, rq: int) =
    if parNm == "stuff":                # make "stuff" a repeatable key
      helpT.add([ keys(parNm, sh), "[CSV]",
                  argRq(rq, "\"" & defVal.join(",")) & "\"", parHelp ])
    else:
      helpT.add([ keys(parNm, sh), "CSV",
                  argRq(rq, "\"" & defVal.join(",") & "\""), parHelp ])

  import cligen
  dispatch(demo)
