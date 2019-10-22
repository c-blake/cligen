proc demo(al_pha=1, be_ta=2.0, verb=false, jk=9, item="", args: seq[string]) =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", repr(item)
  echo "jk: ", jk
  for i, arg in args: echo "positional[", i, "]: ", repr(arg)

when isMainModule:
  import cligen
  dispatch(demo,
           help = { "al-pha" : "growth constant",
                    "be-ta"  : "shrink target",
                    "jk"     : "SUPPRESS" },
           short = { "a-lpha" : 'z',
                     "b-eta" : '\0' })
