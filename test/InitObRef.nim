type App* = ref object
  nim*: string       ## compiler to use
  # non-doc comment: this won't appear in `help`
  show*: bool        ## show informative compiler info
  synth*: string     ## synthetic inferred from other args
  iters*: seq[int]   ## iteration counts

let dfl* = App(nim: "nimcc") #set any defaults != default for type

proc logic*(a: var App) =
  a.synth = a.nim & " FOOBAR"

when isMainModule:    #Q: why can one not say {.outputFile: "InitOb".}?
  import cligen
  {.push hint[GlobalVar]: off.}     #Could also put this in a proc
  var app = initFromCL(dfl, cmdName = "InitOb", doc = "do some app",
                       positional = "iters", suppress = @[ "synth" ],
                       help = { "nim":   "compiler to use",
                                "show":  "show informative compiler info",
                                "iters": "[iters: int (loops per slot)]" })
  #var app = initFromCL(App())  #also works if type defaults are ok
  {.pop.} #GlobalVar
  app.logic()
  echo "app: ", app[]
