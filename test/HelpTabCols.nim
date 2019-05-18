proc demo(alpha=1, beta=2.0, verb=false, item="", args: seq[string]) =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", repr(item)
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)

when isMainModule:
  import cligen
  clCfg.hTabCols = @[ clOptKeys, clDescrip, clDflVal ]
  clCfg.reqSep = true
  dispatch(demo,
           help = { "alpha" : "growth constant",
                    "beta"  : "shrink target" },
           short = { "alpha" : 'z' })
