## Test sub-sub-command CLI instantiation
##with outdented and later
##     indented (pre-formatted) comment continuation.

proc demo(alpha=1, beta=2.0, verb=false, item="", files: seq[string]) =
  ## demo entry point with varied, meaningless parameters.
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, f in files: echo "args[", i, "]: ", f

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
  import cligen
  include cligen/mergeCfgEnvMulMul
  const nd = staticRead "../cligen.nimble"  #nimble data for YOURPKG not cligen
  clCfg.version = "0.0.1"
  dispatchMultiGen([ "apple" ],
                   [ demo, help = { "verb": "on=chatty, off=quiet" },
                     mergeNames = @["MultiMulti", "apple" ] ],
                   [ show, cmdName="print", short = { "gamma": 'z' },
                     mergeNames = @["MultiMulti", "apple" ] ])
  dispatchMulti([ "multi", usage=clUseMultiPerlish &
                                   "\n\nAUTHOR\n  " & nd.fromNimble("author") ],
                [ whoa, echoResult=true ],
                [ apple, stopWords = @["demo", "show"],
                         doc = "apple/apple help for sub-sub commands",
                         usage = "$doc\n",
                         suppress = @[ "usage", "prefix" ] ],
                [ nelly, noAutoEcho=true ])
