proc demo(al_pha=1, be_ta=2.0, verb=false, item="", args: seq[string]) =
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule:
  import cligen

  const cmdName      = "myCmd"  #First three are tested via --help
  const doc          = "The" & " " & "doc"
  const usage        = "USE:\n\t$command $args\n${doc}Options:\n$options"
  const dispatchName = "demoCL" #This one tested via -d:printDispatch

  #XXX Should add some seq[string] variables as well as accept for `help`
  #`Table[string, string]` or for `short` a `Table[string, char]`.

  dispatch(demo,
           cmdName, doc,
           help = { "al-pha" : "growth constant",
                    "be-ta"  : "shrink target" },
           short = { "a-lpha" : 'z',
                     "b-eta" : '\0' },
           usage, dispatchName=dispatchName)
