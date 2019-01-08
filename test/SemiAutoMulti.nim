proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", repr(item)
  for i, f in files: echo "args[", i, "]: ", repr(f)
  return 42

proc show(gamma=1, iota=2.0, verb=false, paths: seq[string]) =
  ## show entry point with varied, meaningless parameters.
  echo "gamma:", gamma, " iota:", iota, " verb:", verb
  for i, p in paths: echo "args[", i, "]: ", repr(p)

when isMainModule:
  import cligen; include cligen/mergeCfgEnv

  dispatchGen(demo, help = { "alpha" : "what alpha does",
                             "beta"  : "what beta does ",
                             "verb"  : "on=chatty, off=quiet. 'Nuff said." },
              helpTabColumnGap=3, helpTabMinLast=20,  #test help tab tweaks
              helpTabRowSep="\n")                     #double space help table
  dispatchGen(show)

  let multisubs = @[ "demo", "show" ]
  let multidocs = @[ "demo entry point", "show entry point" ]
  let multimergeNms = @[ "SemiAutoMulti" ]
  let multiprefix = ""
  proc multi(beta=1, item="", verb=false, subcmd: seq[string]): int =
    ## Run command with no parameters for a full help message.
    if verb:
      echo "globalbeta:", beta
      echo "globalitem:", item
    let arg0 = if subcmd.len > 0: subcmd[0] else: "help"
    let subc = optionNormalize(arg0)
    let rest: seq[string] = if subcmd.len > 1: subcmd[1..^1] else: @[]
    var subcmdsN: seq[string]
    for s in multisubs: subcmdsN.add(optionNormalize(s))
    if subcmd.len == 0:
      echo "Usage:\n  ", topLevelHelp(multimergeNms[0], multisubs, multidocs)
      raise newException(HelpOnly, "")
    case subc
    of "demo": cligenQuitAux("dispatchdemo", "demo", dispatchdemo, false, false,
                             multimergeNms & "demo", rest)
    of "show": cligenQuitAux("dispatchshow", "show", dispatchshow, false, false,
                             multimergeNms & "show", rest)
    of "help":
      if rest.len > 0:
        let sub = optionNormalize(rest[0])
        case sub
        of "demo":
          discard dispatchdemo(@["--help"])
          raise newException(HelpOnly, "")
        of "show":
          dispatchshow(@["--help"])
          raise newException(HelpOnly, "")
        else:
          echo "unknown subcommand: ", sub
          echo "Did you mean: ",suggestions(sub,subcmdsN,multisubs).join("  \n")
          quit(1)
      echo "Usage:\n  SemiAutoMulti demo|show|help [subcommand-args]\n"
      echo "    This is a multiple-dispatch cmd.  Subcommand syntax:\n"
      # Don't have multiple Usage: stuff in there.  Also indent subcmd help.
      let u="SemiAutoMulti [globlOpts] $command $args\n$doc\nOptions:\n$options"
      try: discard dispatchdemo(@["--help"], prefix=multiprefix&"    ", usage=u)
      except HelpOnly: discard
      try: dispatchshow(@["--help"], prefix=multiprefix&"    ", usage=u)
      except HelpOnly: discard
      raise newException(HelpOnly, "")
    else:
      echo "unknown subcommand: ", subc
      echo "Did you mean: ", suggestions(subc, subcmdsN, multisubs).join("  \n")
      quit(1)

  dispatchGen(multi, stopWords = multisubs & "help")
  cligenQuit(dispatchmulti())
