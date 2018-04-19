#This is just a hand-written parseopt3-based parser to guide macro writing.
var foo=2.0
proc demo(alpha: int=1,beta=foo,verb=false,item="", args: seq[string]): int =
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", repr(item)
  for i, arg in args: echo "positional[", i, "]: \"", arg, "\""
  return 42

when isMainModule:
  from os        import commandLineParams
  from argcvt    import argRet, argParse, argHelp, alignTable
  from parseopt3 import getopt, cmdLongOption, cmdShortOption
  proc dispatch_demo(cmdline=commandLineParams(), usage="Explain Me"): int =
    var alphaDisp: int=1                              #1: locals for opt params
    var alphaDfl: int=1                              #1: locals for opt params
    var betaDisp=foo
    var betaDfl=foo
    var verbDisp=false
    var verbDfl=false
    var itemDisp=""
    var itemDfl=""
    var argsDisp: seq[string] = @[]
    var shortNoVal: set[char] = {}                  #only needed for argHelp()
    var longNoVal: seq[string] = @[]
    var tab: seq[array[0..3, string]] = @[          #2: build help
             [ "--help, -?", "", "", "print this help message" ] ]
    argHelp(tab, alphaDisp, "alpha", "a", "meaning of alpha", 0)
    argHelp(tab, betaDisp, "beta", "b", "meaning of beta", 0)
    argHelp(tab, verbDisp, "verb", "v", "meaning of verb", 0)
    argHelp(tab, itemDisp, "item", "i", "meaning of item", 0)
    var help = "Usage:\n  demo [optional-parms] [args]\nOptions:\n" &
               alignTable(tab) & usage
    if help[len(help) - 1] != '\l':                 # ensure newline @end
        help &= "\n"
    for kind, key, val in getopt(cmdline, requireSeparator=true):
      case kind                                     #3: args -> locals updates
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "?": argRet(0, help)
        of "alpha", "a": argParse(alphaDisp, key, alphaDfl, val, help)
        of "beta", "b": argParse(betaDisp, key, betaDfl, val, help)
        of "verb", "v": argParse(verbDisp, key, verbDfl, val, help)
        of "item", "i": argParse(itemDisp, key, itemDfl, val, help)
        else: argRet(1, "bad option: \"" & key & "\"\n" & help)
      else: argsDisp.add(key)                         #4: call wrapped procedure
    return int(demo(alphaDisp, betaDisp, verbDisp, itemDisp, argsDisp))
  quit(dispatch_demo())
