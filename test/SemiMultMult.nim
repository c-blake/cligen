proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]): int =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, f in files: echo "args[", i, "]: ", f
  return 42

proc show(gamma=1, iota=2.0, verb=false, paths: seq[string]): int =
  ## show entry point with varied, meaningless parameters.
  echo "gamma:", gamma, " iota:", iota, " verb:", verb
  for i, p in paths: echo "args[", i, "]: ", p
  return 42

proc whoa(zeta=1, eta=2.0, verb=false, names: seq[string]): int =
  ## Another entry point; here we echoResult
  echo "zeta:", zeta, " eta:", eta, " verb:", verb
  for i, n in names: echo "args[", i, "]: ", n
  return 12345

proc nelly(hooves=4, races=9, verb=false, names: seq[string]): string =
  ## Yet another entry point; here we block autoEcho
  echo "hooves:", hooves, " races:", races, " verb:", verb
  for i, n in names: echo "args[", i, "]: ", n
  return "42"

when isMainModule:
  import cligen; include cligen/mergeCfgEnv

  dispatchMultiGen([ "apple" ], #XXX mergeNames=@[ "SemiMultMult", "apple" ]
                   [ demo, help = { "verb": "on=chatty, off=quiet" } ],
                   [ show, cmdName="print", short = { "gamma": 'z' } ])

  dispatchMultiGen([ "cobbler" ], #XXX mergeNames=@[ "SemiMultMult", "cobbler" ]
                   [ whoa, echoResult=true ],
                   [ nelly, noAutoEcho=true ])

  let multiSubs = @[ "apple", "cobbler" ]
  let multiDocs = @[ "apple entry point", "cobbler entry point" ]
  let multiPrefix = ""
  proc multi(cmdLine: seq[string]): int =
    ## Run command with no parameters for a full help message.
    let arg0 = if cmdLine.len > 0: cmdLine[0] else: "help"
    let subc = optionNormalize(arg0)
    let rest: seq[string] = if cmdLine.len > 1: cmdLine[1..^1] else: @[]
    var subCmdsN: seq[string]
    for s in multiSubs: subCmdsN.add(optionNormalize(s))
    if cmdLine.len == 0:
      echo topLevelHelp("", clUseMulti, "SemiMultMult", multiSubs, multiDocs)
      raise newException(HelpOnly, "")
    case subc
    of "apple": cligenQuitAux(rest, "apple", "apple", apple, false,
                              false, @[ "SemiMultMult" ] )
    of "cobbler": cligenQuitAux(rest, "cobbler", "cobbler", cobbler, false,
                                false, @[ "SemiMultMult" ])
    of "help":
      if rest.len > 0:
        let sub = optionNormalize(rest[0])
        case sub
        of "apple":
          apple(@["help"])
          raise newException(HelpOnly, "")
        of "cobbler":
          cobbler(@["help"])
          raise newException(HelpOnly, "")
        else:
          echo "unknown subcommand: ", sub
          echo "Did you mean: ",suggestions(sub,subCmdsN,multiSubs).join("  \n")
          quit(1)
      echo "Usage:\n  SemiMultMult apple|cobbler|help [subcommand-args]\n"
      echo "    This is a multiple-dispatch cmd.  Subcommand syntax:\n"
      # Don't have multiple Usage: stuff in there.  Also indent subCmd help.
      let u=multiPrefix&"SemiMultMult $command $args\n$doc Options:\n$options\n"
      try: apple(@["help"], usage = u, prefix = multiPrefix & "    ")
      except HelpOnly: discard
      try: cobbler(@["help"], usage = u, prefix = multiPrefix & "    ")
      except HelpOnly: discard
      raise newException(HelpOnly, "")
    else:
      echo "unknown subcommand: ", subc
      echo "Did you mean: ", suggestions(subc, subCmdsN, multiSubs).join("  \n")
      quit(1)

  dispatchGen(multi, stopWords = multiSubs & "help")
  cligenQuit(dispatchmulti())
