proc demo(alpha=1, verb=0, junk= @[ "rs", "tu" ], stuff= @[ "ab", "cd" ],
          args: seq[string]): int=
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " verb:", verb, " junk:", repr(junk), " stuff:", repr(stuff)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)
  return 42

when isMainModule:
  from strutils import split, `%`, join, strip
  from argcvt   import argKeys, argDf, ERR  # Little helpers
  from textUt   import TextTab
  from parseutils import parseInt

  proc argParse*(dst: var int, key: string, dfl: int; val, help: string): bool =
    let Key = if key == "v": "verb" else: key
    if Key == "verb":               # make "verb" a repeatable key
#     if Key in keyCount:
        inc(dst)
#     else:
#       dst = 1
#     keyCount.inc(Key)
    else:
      if val == nil or parseInt(strip(val), dst) == 0:
        ERR("Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
               [ (if val == nil: "nil" else: val), key, help ])
        return false
    return true

  proc argHelp*(defVal: int, parNm: string, sh: string, parHelp: string, rq: int): seq[string] =
    if parNm == "verb":
      result = @[ argKeys(parNm, sh), "[bool]", argDf(rq, $defVal), parHelp ]
#     shortNoVal.incl(sh[0])
#     longNoVal.add(parNm)
    else:
      result = @[ argKeys(parNm, sh), "int", argDf(rq, $defVal), parHelp ]

  proc argParse(dst: var seq[string], key: string, dfl: seq[string]; val, help: string): bool =
    if val == nil:
      ERR("Bad value nil for CSV param \"$1\"\n$2" % [ key, help ])
      return false
    let Key = if key == "s": "stuff" else: key
    if Key == "stuff":              # make "stuff" a repeatable key
#     if Key in keyCount:
        dst = dst & val.split(",")
#     else:
#       dst = val.split(",")
#     keyCount.inc(Key)
    else:
      dst = val.split(",")
    return true

  proc argHelp(defVal: seq[string], parNm: string, sh: string, parHelp: string, rq: int): seq[string] =
    if parNm == "stuff":                # make "stuff" a repeatable key
      result = @[ argKeys(parNm, sh), "+CSV", argDf(rq, "\"" & defVal.join(",")) & "\"", parHelp ]
    else:
      result = @[ argKeys(parNm, sh), "CSV", argDf(rq, "\"" & defVal.join(",") & "\""), parHelp ]

  import cligen
  dispatch(demo)
