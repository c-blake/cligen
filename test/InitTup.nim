type App* = tuple[
  nim: string,       ## compiler to use
  srcFile: string,   ## script to run
  # non-doc comment: this won't appear in `help`
  show: bool,        ## show informative compiler info
  synth: string ]    ## synthetic inferred from other args

const dfl* = (nim:"nimcc", srcFile: "", show: false, synth: "") #Need all fields

proc logic*(a: var App) =
  a.synth = a.nim & " FOOBAR"

when isMainModule:    #Q: why can one not say {.outputFile: "InitOb".}?
  import cligen
  {.push hint[GlobalVar]: off.}     #Could also put this in a proc
  var app = initFromCL(dfl, cmdName = "InitOb", doc = "do some app",
                       suppress = @[ "synth" ], short = {"show": 'S'},
                       help = { "nim":       "compiler to use",
                                "srcFile":  "script to run",
                                "show": "show informative compiler info" })
  {.pop.} #GlobalVar
  app.logic()
  echo "app: ", app
