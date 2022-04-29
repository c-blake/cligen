proc demo(al_pha=1, be_ta=2.0, verb=false, item="", a1, a2: seq[string]) =
  echo "alpha:", alpha, " beta:", beta, " verb:", verb, " item:", item
  for i, arg in a1: echo "positional[", i, "]: ", arg
  echo "a2: ", a2

when isMainModule:
  import cligen, tables

  const cmdName         = "myCmd"     #These are all tested via --help
  const doc             = "The" & " " & "doc"
  const usage           = "$command $args\n${doc}Options:\n$options"
  const helpA           = "growth " & "constant"
  const paramB1         = "be-" & "ta"
  const paramB2         = "b-" & "eta"
  const help            = { "al-pha" : helpA,
                            paramB1  : "shrink target" }.toTable
  const shortA          = chr(ord('y') + 1) # == 'z'
  const short           = { "a-lpha" : shortA,
                            paramB2 : '\0' }.toTable
  const echoResult      = false
  const noAutoEcho      = true
  const positional      = "a1"
  const suppress        = @[ "verb" ]
  const implicitDefault = @[ "a2" ]
  const dispatchName    = "demoCL"    #This one tested via -d:printDispatch

  dispatch(demo, cmdName, doc, help, short, usage, echoResult, noAutoEcho,
           positional, suppress, implicitDefault, dispatchName)
