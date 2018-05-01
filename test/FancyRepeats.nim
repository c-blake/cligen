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
  from argcvt   import argcvtParams, argKeys, argDf, ERR  # Little helpers
  from textUt   import TextTab
  from parseutils import parseInt

  proc argParse*(dst: var int, dfl: int; a: var argcvtParams): bool =
    if a.parNm == "verb":               # make "verb" a special kind of int
      inc(dst)                          # that just counts its occurances
    else:
      if a.val == nil or parseInt(strip(a.val), dst) == 0:
        ERR("Bad value: \"$1\" for option \"$2\"; expecting int\n$3" %
               [ (if a.val == nil: "nil" else: a.val), a.key, a.Help ])
        return false
    return true

  proc argHelp*(defVal: int, a: var argcvtParams): seq[string] =
    if a.parNm == "verb":
      result = @[ a.argKeys, "countr", a.argDf($defVal) ]
      if a.parSh.len > 0:
        a.shortNoVal.incl(a.parSh[0])
      a.longNoVal.add(a.parNm)
    else:
      result = @[ a.argKeys, "int", a.argDf($defVal) ]

  proc argParse(dst: var seq[string], dfl: seq[string]; a: var argcvtParams): bool =
    if a.val == nil:
      ERR("Bad value nil for CSV param \"$1\"\n$2" % [ a.key, a.Help ])
      return false
    if a.parNm == "stuff":              # make "stuff" a repeatable key
      if a.parCount == 1:
        dst = a.val.split(",")
      else:
        dst &= a.val.split(",")
    else:
      dst = a.val.split(",")
    return true

  proc argHelp(defVal: seq[string], a: var argcvtParams): seq[string] =
    if a.parNm == "stuff":              # make "stuff" a repeatable key
      result = @[ a.argKeys, "+CSV", a.argDf("\"" & defVal.join(",")) & "\"" ]
    else:
      result = @[ a.argKeys, "CSV", a.argDf("\"" & defVal.join(",") & "\"") ]

  import cligen
  dispatch(demo)
