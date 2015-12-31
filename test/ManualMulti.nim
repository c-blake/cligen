proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", repr(item)
  for i, f in files: echo "args[", i, "]: ", repr(f)
  return 42

proc show(gamma=1, iota=2.0, verb=false, paths: seq[string]): int =
  ## show entry point with varied, meaningless parameters.
  echo "gamma:", gamma, " iota:", iota, " verb:", verb
  for i, p in paths: echo "args[", i, "]: ", repr(p)
  return 42

when isMainModule:
  import cligen, os
  dispatchGen(demo, doc="  This does the demo.")
  dispatchGen(show, doc="  This shows me something.")
  var pars = commandLineParams()
  var subcmd = pars[0]
  case pars[0]
  of "demo": quit(dispatchdemo(cmdline = pars[1..high(pars)]))
  of "show": quit(dispatchshow(cmdline = pars[1..high(pars)]))
  of "--help":
      echo "Usage:\n  ManualMulti demo|show [subcommand-args]\n"
      echo "    This is a multiple-dispatch cmd.  Subcommand syntax:\n"
      let use = "ManualMulti $command $optPos\n$doc\nOptions:\n$options"
      discard dispatchdemo(cmdline = @[ "--help" ], prefix="    ", usage=use)
      discard dispatchshow(cmdline = @[ "--help" ], prefix="    ", usage=use)
      quit(0)
  else: echo "unknown subcommand: ", subcmd
  quit(1)
