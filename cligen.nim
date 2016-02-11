import macros, tables, parseopt3, strutils, os

proc toString(c: char): string =
  result = newStringOfCap(1)
  if c != '\0': result.add(c)

proc formalParamExpand(fpars: NimNode): NimNode =
  # a,b,..,c:type [maybe=val] --> a:type, b:type, ..., c:type [maybe=val]
  result = newNimNode(nnkFormalParams)
  result.add(fpars[0])                                  # just copy ret value
  for declIx in 1 ..< len(fpars):
    let idefs = fpars[declIx]
    for i in 0 ..< len(idefs) - 3:
      result.add(newIdentDefs(idefs[i], idefs[^2]))
    result.add(newIdentDefs(idefs[^3], idefs[^2], idefs[^1]))

proc formalParams(n: NimNode): NimNode =
  # Extract formal parameter list from the return value of .symbol.getImpl
  for kid in n:
    if kid.kind == nnkFormalParams:
      return formalParamExpand(kid)
  error "formalParams requires a proc argument."
  return nil

proc parseHelps(helps: NimNode): Table[string, string] =
  # Compute a table giving the help text for any parameter
  result = initTable[string, string]()
  for ph in helps:
      let p: string = (ph[1][0]).strVal
      let h: string = (ph[1][1]).strVal
      result[p] = h

proc parseShorts(shorts: NimNode): Table[string, char] =
  # Compute a table giving the user-specified short option for any parameter
  result = initTable[string, char]()
  for losh in shorts:
      let lo: string = (losh[1][0]).strVal
      let sh: char = char((losh[1][1]).intVal)
      result[lo] = sh

proc dupBlock(fpars: NimNode, posIx: int,
              userSpec: Table[string, char]): Table[string, char] =
  # Compute a table giving the short option for any long option, being
  # careful to only allow one such short option if the 1st letters of
  # two or more long options collide.
  result = initTable[string, char]()         # short option for param
  var used: set[char] = {}                   # used shorts; bit vector ok
  for lo, sh in userSpec:
    result[lo] = sh
    used.incl(sh)
  for i in 1 ..< len(fpars):                 # [0] is proc, not desired here
    if i == posIx: continue                  # positionals get no option char
    let parNm = $(fpars[i][0])
    let sh = parNm[0]                        # abbreviation is 1st character
    if sh notin used and parNm notin result: # still available
      result[parNm] = sh
      used.incl(sh)

proc collectComments(buf: var string, n: NimNode, depth: int = 0) =
  if n.len > 1:
    for kid in n: collectComments(buf, kid, depth + 1)
  else:
    if n.kind == nnkCommentStmt and depth < 5:
      if n.strVal != nil:
        buf.add(" ")
        buf.add(n.strVal)

proc isExplicitSeq(typeSlot: NimNode): bool =
  # Test if a proc param typeSlot is explicitly spelled "seq[SOMETHING]" to
  # identify which parameter maps to optional positional arguments.
  result = false
  let lispRep = lispRepr(typeSlot)
  if lispRep.startsWith("BracketExpr(Sym(seq), "):
    return true
  if lispRep.startsWith("Call(OpenSymChoice(Sym([]), "):
    var simplified = typeSlot.copyNimTree()
    simplified[0] = simplified[0][0]
    return lispRepr(simplified).startsWith("Call(Sym([]), Sym(seq), ")

proc postInc*(x: var int): int =
  ## Similar to post-fix `++` in C languages: yield initial val, then increment
  result = x
  inc(x)

macro dispatchGen*(pro: typed, cmdName: string="", doc: string="",
                   help: typed= {}, short: typed= {}, usage: string
="Usage:\n  $command $args\n$doc\nOptions (opt&arg sep by :,=,spc):\n$options",
                   requireSeparator: bool = false, sepChars = "=:",
                   stopWords: seq[string] = @[]): untyped =
  ## Generate a command-line dispatcher for proc `pro` with extra help `usage`.
  ## `help` is expected to be seq[(paramNm, string)] of per-parameter help.
  ## `short` is expected to be seq[(paramNm, char)] of per-parameter short opts.
  ##
  ## For a large class of user procs in Nim, anything critical to such dispatch
  ## can be inferred.  User semantics/help round out the info for a nice CLI.
  ## Constraints: 1) only one proc param may be an explicit seq[T] if you want
  ## to receive an unnamed/positional arg list, 2) Every param type has an
  ## argParse/argHelp in scope (argcvt.nim defines argParse/Help for many
  ## types, though).  Non-int return types are discarded since commands can
  ## only return (usually 1-byte) integer codes to the operating system.
  ##
  ## Proc parameters and option keys are normalized so that command users may
  ## spell multi-word option keys flexibly as in ``--dry-Run``|``--dryrun``.
  result = newStmtList()                # The generated dispatch proc
  let helps = parseHelps(help)
  let impl = pro.symbol.getImpl
  let fpars = formalParams(impl)
  var cmtDoc: string = $doc
  if cmtDoc == nil or cmtDoc.len == 0:  # allow caller to override commentDoc
    collectComments(cmtDoc, impl)
  let proNm = $pro                      # Name of wrappred proc
  let disNm = !("dispatch" & $pro)      # Name of dispatch wrapper
  var posIx = -1                        # param slot for positional cmd args|-1
  for i in 1 ..< len(fpars):            #XXX more "type-y" test for seq[T]
    if isExplicitSeq(fpars[i][1]):      #XXX or just let user specify posIx/id?
      if posIx != -1:                   #??? "--" <==> multiple seq[T]s
        error("Currently cligen supports only one seq[T] parameter.")
      posIx = i
  let shOpt = dupBlock(fpars, posIx, parseShorts(short))
  var spars = copyNimTree(fpars)        # Create shadow/safe prefixed params.
  var mandatory = newSeq[int]()
  var mandHelp = ""
  for i in 1 ..< len(fpars):            # No locals/imports begin w/"dispatcher"
    spars[i][0] = ident("dispatcher" & $(fpars[i][0]))
    if fpars[i][2].kind == nnkEmpty:
      if i == posIx:                    # No initializer; Add @[]
        spars[posIx][2] = prefix(newNimNode(nnkBracket), "@")
      else:
        if fpars[i][1].kind == nnkEmpty:
          error("parameter `" & $(fpars[i][0]) &
                "` has neither type nor default value")
        mandatory.add(i)
        mandHelp &= " {" & $fpars[i][0] & ":" & $fpars[i][1] & "}"
  let posNoId = ident("posNo")          # positional arg number
  let docId = ident("doc")              # gen proc parameter
  let usageId = ident("usage")          # gen proc parameter
  let cmdlineId = ident("cmdline")      # gen proc parameter
  let tabId = ident("tab")              # local help table var
  let helpId = ident("help")            # local help table var
  let prefixId = ident("prefix")        # local help prefix param
  let shortBoolId = ident("shortBool")  # local list of arg-free short opts
  let longBoolId = ident("longBool")    # local list of arg-free long opts
  let keyId = ident("key")              # local option key
  var callIt = newNimNode(nnkCall)      # call of wrapped proc in genproc
  callIt.add(pro)
  var preLoop = newStmtList()           # preLoop: init vars & build help str
  preLoop.add(quote do:
    var `tabId`: seq[array[0..3, string]] =
      @[ [ "--help, -?", "", "", "print this help message" ] ]
    var `shortBoolId`: string = "?"     # argHelp(..,bool,..) updates these
    var `longBoolId`: seq[string] = @[ "help" ])
  var args = "[optional-params]" & mandHelp &
             (if posIx != -1: " [" & $(fpars[posIx][0]) & "]" else: "")
  for i in 1 ..< len(fpars):
    let idef = fpars[i]
    let sdef = spars[i]
    preLoop.add(newNimNode(nnkVarSection).add(sdef))    #Init vars
    callIt.add(sdef[0])                                 #Add to call
    if i notin mandatory and i != posIx:
      let parNm = $idef[0]
      let sh = toString(shOpt.getOrDefault(parNm))      #Add to perPar help tab
      let defVal = sdef[0]
      let parHelp = if parNm in helps: helps[parNm] else: "set " & parNm
      preLoop.add(quote do: argHelp(`tabId`, `defVal`, `parNm`, `sh`,`parHelp`))
  preLoop.add(quote do:                 # build one large help string
    let cName = if len(`cmdName`) == 0: `proNm` else: `cmdName`
    var `helpId`=`usageId` % ["doc",`docId`, "command",cName, "args",`args`,
                              "options", alignTable(`tabId`, len(`prefixId`)) ]
    if `helpId`[^1] != '\l':            # ensure newline @end of help
      `helpId` &= "\n"
    if len(`prefixId`) > 0:             # to indent help in a multicmd context
      `helpId` = addPrefix(`prefixId`, `helpId`) )
  preLoop.add(quote do:
    var `posNoId` = 0)
  result.add(quote do:                  # initial parser-dispatcher proc header
    from os        import commandLineParams
    from argcvt    import argRet, argParse, argHelp, alignTable, addPrefix
    from parseopt3 import getopt, cmdLongOption, cmdShortOption, optionNormalize
    import strutils # import join, `%`
    proc `disNm`(`cmdlineId`: seq[string] = commandLineParams(),
                 `docId`: string = `cmtDoc`, `usageId`: string = `usage`,
                 `prefixId`=""): int =
      `preLoop`)
  let sls = result[0][4][^1][0]     # [stlist][4imports+proc][stlist][stlist]
  var nonOpt: NimNode = newNimNode(nnkElse)
  if posIx != -1 or len(mandatory) > 0:     # code to parse non-option args
    nonOpt.add(newNimNode(nnkCaseStmt).add(quote do: postInc(`posNoId`)))
    for i, ix in mandatory:
      let hlp = newStrLitNode("non-option " & $i & " (" & $(fpars[ix][0]) & ")")
      nonOpt[0].add(newNimNode(nnkOfBranch).add(newIntLitNode(i)).add(
        newCall("argParse", spars[ix][0], hlp, keyId, helpId)))
    if posIx != -1:                         # mandatory + optional positionals
      let posId = spars[posIx][0]
      let tmpId = ident("tmp" & $posId)
      nonOpt[0].add(newNimNode(nnkElse).add(quote do:
        var rewind = false                  # Ugly machinery is so tmp=pos[0]..
        if len(`posId`) == 0:               #..type inference works.
          `posId`.setLen(1)
          rewind = true
        var `tmpId` = `posId`[0]
        argParse(`tmpId`, "positional $" & $`posNoId`, key, "positional\n")
        if rewind: `posId`.setLen(0)
        `posId`.add(`tmpId`)))
    else:                                   # only mandatory (no positionals)
      nonOpt[0].add(newNimNode(nnkElse).add(quote do:
        argRet(1, "Optional positional arguments unexpected\n" & `helpId`)))
  else:
    nonOpt.add(quote do:
      argRet(1, `proNm` & " does not expect non-option arguments\n" & `helpId`))
  var optCases = newNimNode(nnkCaseStmt).add(quote do: optionNormalize(`keyId`))
  optCases.add(newNimNode(nnkOfBranch).add(
    newStrLitNode("help"),newStrLitNode("?")).add(quote do: argRet(0,`helpId`)))
  for i in 1 ..< len(fpars):        # build per-param case clauses
    if i == posIx: continue         # skip variable len positionals
    if i in mandatory: continue     # skip mandator arguments
    let idef = fpars[i]
    let sdef = spars[i]
    let lopt = optionNormalize($idef[0])
    if $idef[0] in shOpt:           # both a long and short option
      optCases.add(newNimNode(nnkOfBranch).add(
        newStrLitNode(lopt), newStrLitNode(toString(shOpt[$idef[0]]))).add(
          newCall("argParse", sdef[0], keyId, ident("val"), helpId)))
    else:                           # only a long option
      optCases.add(newNimNode(nnkOfBranch).add(newStrLitNode(lopt)).add(
          newCall("argParse", sdef[0], keyId, ident("val"), helpId)))
  optCases.add(newNimNode(nnkElse).add(quote do:
    argRet(1, "Bad option: \"" & key & "\"\n" & `helpId`)))
  sls.add(                          # set up getopt loop & attach case clauses
    newNimNode(nnkForStmt).add(ident("kind"), keyId, ident("val"),
      newCall("getopt", cmdlineId, shortBoolId, longBoolId,
                        requireSeparator, sepChars, stopWords),
        newStmtList(newNimNode(nnkCaseStmt).add(ident("kind"),
          newNimNode(nnkOfBranch).add(ident("cmdLongOption"),
                                      ident("cmdShortOption"),
                                      newStmtList(optCases)), nonOpt))))
  if fpars[0].kind == nnkEmpty:             # pure proc/no return type
    sls.add(quote do: `callIt`; return 0)
  else:                                     # convertible-to-int return type
    sls.add(quote do:
       when compiles(int(`callIt`)): return `callIt`
       else: discard `callIt`; return 0)

macro dispatch*(pro: typed, cmdName: string="", doc: string="",
                help: typed = { }, short: typed = { }, usage: string
="Usage:\n  $command $args\n$doc\nOptions (opt&arg sep by :,=,spc):\n$options",
                requireSeparator: bool = false, sepChars = "=:",
                stopWords: seq[string] = @[]): untyped =
  ## A convenience wrapper to both generate a command-line dispatcher and then
  ## call quit(said dispatcher); Usage is the same as the dispatchGen() macro.
  result = newStmtList()
  result.add(newCall("dispatchGen", pro, cmdName, doc, help, short, usage,
                                         requireSeparator, sepChars, stopWords))
  result.add(newCall("quit", newCall("dispatch" & $pro)))

macro dispatchMulti*(procBrackets: varargs[untyped]): untyped =
  ## A convenience wrapper to both generate a multi-command dispatcher and then
  ## call quit(said dispatcher); pass []s of argument lists for dispatchGen(),
  ## E.g., dispatchMulti([demo, short={"dryRun":"n"}], [real, cmdName="go"]).
  result = newStmtList()
  for p in procBrackets:
    var c = newCall("dispatchGen")
    copyChildrenTo(p, c)
    result.add(c)
  let arg0Id = ident("arg0")
  let restId = ident("rest")
  let dashHelpId = ident("dashHelp")
  let multiId = ident("multi")
  let subcmdsId = ident("subcmds")
  var multiDef = newStmtList()
  multiDef.add(quote do:
    proc `multiId`(dummy=1, dummy2=2, subcmd: seq[string]) =
      let n = subcmd.len
      let `arg0Id` = if n > 0: subcmd[0] else: "help"
      let `restId`: seq[string] = if n > 1: subcmd[1..<n] else: @[ ])
  var cases = multiDef[0][0][^1].add(newNimNode(nnkCaseStmt).add(arg0Id))
  var helps = (quote do:
        echo "Usage:  This is a multiple-dispatch cmd.  Usage is like\n"
        echo "    $1 subcommand [subcommand-opts & args]\n" % [ paramstr(0) ]
        echo "where subcommand syntaxes are as follows:\n"
        let `dashHelpId` = @[ "--help" ])
  for p in procBrackets:
    let disp = "dispatch_" & $p[0]
    cases[^1].add(newNimNode(nnkOfBranch).add(newStrLitNode($(p[0]))).add(
      newCall("quit", newCall(disp, restId))))
    helps.add(newNimNode(nnkDiscardStmt).add(
      newCall(disp, dashHelpId,
              newNimNode(nnkExprEqExpr).add(ident("prefix"),
                                            newStrLitNode("    ")))))
  cases[^1].add(newNimNode(nnkElse).add(helps))
  result.add(multiDef)
  result.add(quote do:
    var `subcmdsId`: seq[string] = @[ ])
  for p in procBrackets:
    result.add(newCall("add", subcmdsId, newStrLitNode($p[0])))
  result.add(newCall("dispatch", multiId,
                     newNimNode(nnkExprEqExpr).add(ident("stopWords"),
                                                   subcmdsId)))
