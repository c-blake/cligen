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
    var XXalpha: int=1                              #1: locals for opt params
    var XXbeta=foo
    var XXverb=false
    var XXitem=""
    var XXargs: seq[string] = @[]
    var shortNoVal: set[char] = {}                  #only needed for argHelp()
    var longNoVal: seq[string] = @[]
    var tab: seq[array[0..3, string]] = @[          #2: build help
             [ "--help, -?", "", "", "print this help message" ] ]
    argHelp(tab, XXalpha, "alpha", "a", "meaning of alpha")
    argHelp(tab, XXbeta, "beta", "b", "meaning of beta")
    argHelp(tab, XXverb, "verb", "v", "meaning of verb")
    argHelp(tab, XXitem, "item", "i", "meaning of item")
    var help = "Usage:\n  demo [optional-parms] [args]\nOptions:\n" &
               alignTable(tab) & usage
    if help[len(help) - 1] != '\l':                 # ensure newline @end
        help &= "\n"
    for kind, key, val in getopt(cmdline, requireSeparator=true):
      case kind                                     #3: args -> locals updates
      of cmdLongOption, cmdShortOption:
        case key
        of "help", "?": argRet(0, help)
        of "alpha", "a": argParse(XXalpha, key, val, help)
        of "beta", "b": argParse(XXbeta, key, val, help)
        of "verb", "v": argParse(XXverb, key, val, help)
        of "item", "i": argParse(XXitem, key, val, help)
        else: argRet(1, "bad option: \"" & key & "\"\n" & help)
      else: XXargs.add(key)                         #4: call wrapped procedure
    return int(demo(XXalpha, XXbeta, XXverb, XXitem, XXargs))
  quit(dispatch_demo())
