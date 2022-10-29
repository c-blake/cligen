import cligen
# export `$` in cligen generates a deprecation warning; export just `$`(float)?
when not compiles($1.0): import std/formatfloat

var fooParse: seq[ClParse]

proc foo(alpha = 1.0, beta = 2, rest: seq[int]) =
  if "alpha" in fooParse:
    echo "user sets of alpha saw these value strings: "
    for s in fooParse:
      if s.paramName == "alpha": echo "  ", s
  if "beta" notin fooParse:
    echo "proc-default value for beta"
  if fooParse.numOfStatus({clBadKey, clBadVal}) > 0:
    echo "There was some kind of parse error."
  echo "alpha: ", alpha, " beta: ", beta
  echo "fooParse: ", fooParse

dispatchGen(foo, setByParse = fooParse.addr)
cligenQuit(dispatchfoo())
