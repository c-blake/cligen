when not declared(addFloat): import std/formatfloat
var bo_go = 1

proc demo(be_ta=2.0, verb=false, item="", args: seq[string]) =
  ## demo entry point with varied, meaningless parameters and a global.  A Nim
  ## invocation might be: `bogo=2; demo(@[ "hi", "ho" ])` corresponding to the
  ## CL invocation "demo --bogo=2 hi ho" (assuming executable is named "demo").
  echo "bogo:", boGo, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule: import cligen; dispatch demo, vars = @["bOgo"],
  short={"b-ogo": 'z', "b-eta": '\0'},
  help={"bOGO": "growth constant", "be-ta": "shrink target"}
