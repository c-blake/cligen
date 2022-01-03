import cligen

proc demo(al_pha=1, be_ta=2.0, verb=false, item="", args: seq[string]) =
  ## demo entry point with varied, meaningless parameters.  A Nim invocation
  ## might be: demo(alpha=2, @[ "hi", "ho" ]) corresponding to the command
  ## invocation "demo --alpha=2 hi ho" (assuming executable gets named demo).
  if args.len < 2:
    raise newException(HelpError, "Too few args; Full ${HELP}")
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule: dispatch demo
