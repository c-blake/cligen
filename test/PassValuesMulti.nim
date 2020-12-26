proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]) =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, f in files: echo "args[", i, "]: ", f

proc show(gamma=1, iota=2.0, verb=false, paths: seq[string]): int =
  ## show entry point with varied, meaningless parameters.
  echo "gamma:", gamma, " iota:", iota, " verb:", verb
  for i, p in paths: echo "args[", i, "]: ", p
  return 42

proc punt(zeta=1, eta=2.0, verb=false, names: seq[string]): int =
  ## Another entry point; here we echoResult
  echo "zeta:", zeta, " eta:", eta, " verb:", verb
  for i, n in names: echo "args[", i, "]: ", n
  return 12345

proc nel_Ly(hooves=4, races=9, verb=false, names: seq[string]): string =
  ## Yet another entry point; here we block autoEcho
  echo "hooves:", hooves, " races:", races, " verb:", verb
  for i, n in names: echo "args[", i, "]: ", n
  return "42"

when isMainModule:
  import cligen, tables; include cligen/mergeCfgEnv
  {.push hint[GlobalVar]: off.}

  const hlUse = "\e[7m$command $args\e[m\n\e[1m${doc}\e[mOptions:\n$options"

  const nimbleFile = staticRead "../cligen.nimble"  #Use YOURPKG not cligen
  let docLine = nimbleFile.fromNimble("description") & "\n\n"

  let topLvlUse = """${doc}Usage:
  $command {SUBCMD}  [sub-command options & parameters]

SUBCMDs:
$subcmds
$command {-h|--help} or with no args at all prints this message.
$command --help-syntax gives general cligen syntax help.
Run "$command {help SUBCMD|SUBCMD --help}" to see help for just SUBCMD.
Run "$command help" to get *comprehensive* help.$ifVersion"""

  clCfg.version = "0.0.1" #or maybe nimbleFile.fromNimble("version")
  clCfg.reqSep = true

  var noVsn = clCfg
  {.pop.}
  noVsn.version = ""
  const demohelp = { "verb": "on=chatty, off=quiet" }.toTable
  dispatchMulti([ "multi", doc = docLine, usage = topLvlUse ],
                [ demo, usage=hlUse, help = demohelp ],
                [ show, cmdName="print", usage=hlUse, short = { "gamma": 'z' }],
                [ punt, echoResult=true, usage=hlUse, cf=noVsn ],
                [ nel_Ly, cmdName="nel-ly", usage=hlUse, noAutoEcho=true ] )
