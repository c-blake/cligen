proc demo(al_pha=1, be_ta=2.0, verb=false, item="", args: seq[string]) =
  ## demo entry point with varied, meaningless parameters with an alias system.
  ## E.g., USERALIASES='"-Dk=-a9 -b3.0" "-DK=-Rk -v 1 2"' ./UserAliases -RK 3 4
  ## or USERALIASES_CONFIG=UserAliases.cf ./UserAliases -RK 3 4
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule:
  import cligen; include cligen/mergeCfgEnv
  const ess: seq[string] = @[]
  dispatch(demo, cmdName = "UserAliases",
           help = { "al-pha" : "growth constant",
                    "bet-a"  : "shrink target" },
           alias = @[ ("Def", 'D', "define key=\"val ...\" alias", @[ess]),
                      ("Ref", 'R', "reference an alias", @[ess]) ] )
