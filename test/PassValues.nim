proc demo(al_pha=1, be_ta=2.0, verb=false, item="", args: seq[string]) =
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in args: echo "positional[", i, "]: ", arg

when isMainModule:
  import cligen, tables

  const cmdName      = "myCmd"    #These are all tested via --help
  const doc          = "The" & " " & "doc"
  const usage        = "USE:\n\t$command $args\n${doc}Options:\n$options"
  const help         = { "al-pha" : "growth constant",
                        "be-ta"  : "shrink target" }.toTable
  const short        = { "a-lpha" : 'z',
                         "b-eta" : '\0' }.toTable
  const dispatchName = "demoCL"   #This one tested via -d:printDispatch

  #XXX Should add some seq[string] variables as well.
  dispatch(demo, cmdName, doc, help, short, usage, dispatchName=dispatchName)
