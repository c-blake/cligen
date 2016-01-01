import macros, tables, sets

proc toString(c: char): string =
  result = newStringOfCap(1)
  if c != '\0': result.add(c)

proc formalParams(n: NimNode): NimNode =
  ## Extract formal parameter list from the return value of .symbol.getImpl
  for kid in n:
    if kid.kind == nnkFormalParams:
      return kid
  error "formalParams requires a proc argument."
  return nil

proc parseHelps(helps: NimNode): Table[string, string] =
  ## Compute a table giving the help text for any parameter
  result = initTable[string, string]()
  for ph in helps:
      let p: string = (ph[1][0]).strVal
      let h: string = (ph[1][1]).strVal
      result[p] = h

proc parseShorts(shorts: NimNode): Table[string, char] =
  ## Compute a table giving the user-specified short option for any parameter
  result = initTable[string, char]()
  for losh in shorts:
      let lo: string = (losh[1][0]).strVal
      let sh: char = char((losh[1][1]).intVal)
      result[lo] = sh

proc dupBlock(fpars: NimNode, numPars: int,
              userSpec: Table[string, char]): Table[string, char] =
  ## Compute a table giving the short option for any long option, being
  ## careful to only allow one such short option if the 1st letters of
  ## two or more long options collide.
  result = initTable[string, char]()        # short option for param
  var used: set[char] = {}                   # used shorts; bit vector ok
  for lo, sh in userSpec:
    result[lo] = sh
    used.incl(sh)
  for i in 1 ..< numPars:                    # [0] is proc, not desired here
    let parNm = $(fpars[i][0])
    let sh = parNm[0]                        # abbreviation is 1st character
    if sh notin used and parNm notin result: # still available
      result[parNm] = sh
      used.incl(sh)

macro dispatchGen*(pro: typed, cmdName: string="", doc: string="",
                   help: typed= {}, short: typed= {},
usage: string="Usage:\n  $command $optPos\n$doc\nOptions:\n$options\n"): untyped =
  ## Generate a command-line dispatcher for proc `pro` with extra help `usage`.
  ## `help` is expected to be seq[(paramNm, string)] of per-parameter help.
  ## `short` is expected to be seq[(paramNm, char)] of per-parameter short opts.
  ##
  ## For a large class of user procs in Nim, anything critical to such dispatch
  ## can be inferred.  User semantics/help round out the info for a nice CLI.
  ## The only real constraints are 1) the last proc param must be a seq[string]
  ## *if* you want to receive non-option/positional args, 2) no return type or
  ## return is int-like, and 3) Every param type has an argParse/argHelp in
  ## scope.  argcvt.nim defines argParse/Help for many types, though.

  result = newStmtList()                # The generated dispatch proc
  let helps = parseHelps(help)
  let fpars = formalParams(pro.symbol.getImpl)
  let proNm = $pro                      # Name of wrappred proc
  let disNm = !("dispatch" & $pro)      # Name of dispatch wrapper
  let posId: NimNode =                  # id for positional command args|nil
    if lispRepr(fpars[^1][1]) == "BracketExpr(Sym(seq), Sym(string))":
      fpars[^1][0] else: nil            #XXX should have more "type-y" test
  let numPars = len(fpars) - (if posId == nil: 0 else: 1)
  let shOpt = dupBlock(fpars, numPars, parseShorts(short))
  var spars = copyNimTree(fpars)        # Create shadow/safe prefixed params.
  for i in 1 ..< len(fpars):            # No locals/imports begin w/"dispatcher"
    spars[i][0] = ident("dispatcher" & $(fpars[i][0]))
  let docId = ident("doc")              # gen proc parameter
  let usageId = ident("usage")          # gen proc parameter
  let cmdlineId = ident("cmdline")      # gen proc parameter
  let tabId = ident("tab")              # local help table var
  let helpId = ident("help")            # local help table var
  let prefixId = ident("prefix")        # local help prefix param
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  var preLoop = newStmtList()           # preLoop: init vars & build help str
  preLoop.add(quote do:
    var `tabId`: seq[array[0..3, string]] =
      @[ [ "--help, -?", "", "", "print this help message" ] ])
  for i in 1 ..< numPars:
    let idef = fpars[i]
    let sdef = spars[i]
    preLoop.add(newNimNode(nnkVarSection).add(sdef))    #Init vars
    callIt.add(sdef[0])                                 #Add to call
    let parNm = $idef[0]
    let sh = toString(shOpt.getOrDefault(parNm))        #Add to perPar help tab
    let defVal = idef[2]
    let parHelp = if parNm in helps: helps[parNm] else: "set " & parNm
    preLoop.add(quote do: argHelp(`tabId`, `defVal`, `parNm`, `sh`, `parHelp`))
  var optPos: string
  if posId != nil:
    preLoop.add(quote do:
      var `posId`: seq[string] = @[])
    callIt.add(posId)
    optPos = " [optional-params] [" & $posId & "]"
  else:
    optPos = " [optional-params]"
  preLoop.add(quote do:                 # build one large help string
    let cName = if len(`cmdName`) == 0: `proNm` else: `cmdName`
    var `helpId`=`usageId` % ["doc",`docId`, "command",cName, "optPos",`optPos`,
                              "options", alignTable(`tabId`, len(`prefixId`)) ]
    if `helpId`[len(`helpId`) - 1] != '\l':     # ensure newline @end of help
      `helpId` &= "\n"
    if len(`prefixId`) > 0:             # to indent help in a multicmd context
      `helpId` = addPrefix(`prefixId`, `helpId`) )
  result.add(quote do:                  # initial parser-dispatcher proc header
    from os        import commandLineParams
    from argcvt    import argRet, argParse, argHelp, alignTable, addPrefix
    from argcvt    import getopt2, cmdLongOption, cmdShortOption #XXX parseopt2
    import strutils # import join, `%`
    proc `disNm`(`cmdlineId`: seq[string] = commandLineParams(),
                 `docId`: string = `doc`, `usageId`: string = `usage`,
                 `prefixId`=""): int =
      `preLoop`)
  let sls = result[0][4][^1][0]     # [stlist][4imports+proc][stlist][stlist]
  var nonOpt: NimNode
  if posId != nil:                  # Catch non-option arguments in posId
    nonOpt = newNimNode(nnkElse).add(quote do: `posId`.add(key))
  else:
    nonOpt = newNimNode(nnkElse).add(quote do:
      argRet(1, `proNm` & " does not expect non-option arguments\n" & `helpId`))
  var optCases = newNimNode(nnkCaseStmt).add(ident("key"))
  optCases.add(newNimNode(nnkOfBranch).add(
    newStrLitNode("help"),newStrLitNode("?")).add(quote do: argRet(0,`helpId`)))
  for i in 1 ..< numPars:           # build per-param case clauses
    let idef = fpars[i]
    let sdef = spars[i]
    if $idef[0] in shOpt:           # both a long and short option
      optCases.add(newNimNode(nnkOfBranch).add(
        newStrLitNode($idef[0]), newStrLitNode(toString(shOpt[$idef[0]]))).add(
          newCall("argParse", sdef[0], ident("key"), ident("val"), helpId)))
    else:                           # only a long option
      optCases.add(newNimNode(nnkOfBranch).add(newStrLitNode($idef[0])).add(
          newCall("argParse", sdef[0], ident("key"), ident("val"), helpId)))
  optCases.add(newNimNode(nnkElse).add(quote do:
    argRet(1, "Bad option: \"" & key & "\"\n" & `helpId`)))
  sls.add(                          # set up getopt loop & attach case clauses
    newNimNode(nnkForStmt).add(ident("kind"), ident("key"), ident("val"),
      newCall("getopt2", cmdlineId), newStmtList(
        newNimNode(nnkCaseStmt).add(ident("kind"),
          newNimNode(nnkOfBranch).add(ident("cmdLongOption"),
                                      ident("cmdShortOption"),
                                      newStmtList(optCases)), nonOpt))))
  if fpars[0].kind == nnkEmpty:             # pure proc/no return type
    sls.add(quote do: `callIt`; return 0)
  else:                                     # convertible-to-int return type
    sls.add(quote do: return `callIt`)

macro dispatch*(pro: typed, cmdName: string="", doc: string="",
                help: typed = { }, short: typed = { },
usage: string="Usage:\n  $command $optPos\n$doc\nOptions:\n$options"): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call said dispatcher; Usage is the same as the dispatchGen() macro.
  result = newStmtList()
  result.add(newCall("dispatchGen", pro, cmdName, doc, help, short, usage))
  result.add(newCall("quit", newCall("dispatch" & $pro)))
