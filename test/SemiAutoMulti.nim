proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, f in files: echo "args[", i, "]: ", f
  return 42

proc show(gamma=1, iota=2.0, verb=false, paths: seq[string]) =
  ## show entry point with varied, meaningless parameters.
  echo "gamma:", gamma, " iota:", iota, " verb:", verb
  for i, p in paths: echo "args[", i, "]: ", p

when isMainModule:
  import cligen; include cligen/mergeCfgEnv

  var cc = clCfg
  cc.hTabColGap = 3
  cc.hTabMinLast = 20
  cc.hTabRowSep = "\n"
  dispatchGen(demo, help = { "alpha" : "what alpha does",
                             "beta"  : "what beta does ",
                             "verb"  : "on=chatty, off=quiet.  'Nuff said." },
              cf=cc)
  dispatchGen(show)

  let multiSubs = @[ "demo", "show" ]
  let multiDocs = @[ "demo entry point", "show entry point" ]
  let multiPrefix = ""
  proc multi(subCmd: seq[string]): int =
    ## Run command with no parameters for a full help message.
    let arg0 = if subCmd.len > 0: subCmd[0] else: "help"
    let subc = optionNormalize(arg0)
    let rest: seq[string] = if subCmd.len > 1: subCmd[1..^1] else: @[]
    var subCmdsN: seq[string]
    for s in multiSubs: subCmdsN.add(optionNormalize(s))
    if subCmd.len == 0:
      echo topLevelHelp("", clUseMulti, "SemiAutoMulti", multiSubs, multiDocs)
      raise newException(HelpOnly, "")
    case subc
    of "demo": cligenQuitAux(rest, "dispatchdemo", "demo", dispatchdemo, false,
                             false, @[ "SemiAutoMulti" ])
    of "show": cligenQuitAux(rest, "dispatchshow", "show", dispatchshow, false,
                             false, @[ "SemiAutoMulti" ])
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
          echo "Did you mean: ",suggestions(sub,subCmdsN,multiSubs).join("  \n")
          quit(1)
      echo "Usage:\n  SemiAutoMulti demo|show|help [subcommand-args]\n"
      echo "    This is a multiple-dispatch cmd.  Subcommand syntax:\n"
      # Don't have multiple Usage: stuff in there.  Also indent subCmd help.
      let u="SemiAutoMulti $command $args\n$doc\nOptions:\n$options"
      try: discard dispatchdemo(@["--help"], prefix=multiPrefix&"    ", usage=u)
      except HelpOnly: discard
      try: dispatchshow(@["--help"], prefix=multiPrefix&"    ", usage=u)
      except HelpOnly: discard
      raise newException(HelpOnly, "")
    else:
      echo "unknown subcommand: ", subc
      echo "Did you mean: ", suggestions(subc, subCmdsN, multiSubs).join("  \n")
      quit(1)

  dispatchGen(multi, stopWords = multiSubs & "help")
  cligenQuit(dispatchmulti())
